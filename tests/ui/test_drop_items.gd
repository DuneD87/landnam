extends Node

## Tirar cosas del inventario al suelo arrastrándolas fuera de las ventanas, y recogerlas.
##   godot --headless --path . res://tests/ui/test_drop_items.tscn

const Config = preload("res://scripts/config.gd")

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	add_child(body)
	body.global_position = pos
	return body


func _settle(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


## Caja de las mallas de [node] en mundo.
func _world_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _run() -> void:
	_box(Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	var dropper := Node3D.new()
	add_child(dropper)
	await get_tree().physics_frame
	var down := Vector3.DOWN

	# Cae delante (mira por +Z) hasta el suelo, tumbada: la espada, con su malla y de plano.
	var sword := DroppedItem.spawn(dropper, Config.get_item(&"iron_sword"), 1, down)
	check(sword.global_position.y > 1.0, "sale de la altura de la mano (%.2f m)" % sword.global_position.y)
	await _settle(1.0)
	check(absf(sword.global_position.y) < 0.01, "cae hasta el suelo (%.3f m)" % sword.global_position.y)
	check(absf(sword.global_position.z - DroppedItem.DROP_AHEAD) < 0.01, "delante de quien la suelta (%.2f m)" % sword.global_position.z)
	var box := _world_aabb(sword)
	check(box.size.y < 0.12 and maxf(box.size.x, box.size.z) > 0.6,
		"la espada queda tumbada (alto %.2f, largo %.2f)" % [box.size.y, maxf(box.size.x, box.size.z)])
	check(absf(box.position.y) < 0.01, "apoyada sobre el suelo, ni hundida ni flotando (%.3f)" % box.position.y)

	# Lo que no tiene malla propia va en un saquito.
	var stones := DroppedItem.spawn(dropper, Config.get_item(&"stone_01"), 30, down)
	await _settle(1.0)
	var sack := _world_aabb(stones)
	check(absf(sack.position.y) < 0.01 and sack.size.y > 0.2, "la piedra va en un saquito en el suelo (%.2f m)" % sack.size.y)

	# Contra una pared no la atraviesa: cae a este lado.
	var wall := _box(Vector3(4, 3, 0.2), Vector3(5, 1.5, 0.5))
	var walled := Node3D.new()
	add_child(walled)
	walled.global_position = Vector3(5, 0, 0)
	await get_tree().physics_frame
	var shield := DroppedItem.spawn(walled, Config.get_item(&"wooden_shield"), 1, down)
	await _settle(1.0)
	check(shield.global_position.z < 0.4 and absf(shield.global_position.y) < 0.01,
		"con una pared delante cae a este lado (z %.2f)" % shield.global_position.z)
	wall.queue_free()

	# Recoger: lo más cercano, o lo que se mira.
	var picker := Node3D.new()
	add_child(picker)
	var eye := Vector3(0, 1.6, -2.0)
	check(DroppedItem.find(picker) != null, "a su alcance hay algo que recoger")
	check(DroppedItem.find(picker, eye, Vector3.BACK.rotated(Vector3.UP, PI)) == null,
		"mirando a otro lado no se coge lo que se mira")
	var to_sword := sword.global_position - eye
	check(DroppedItem.find(picker, eye, to_sword.normalized()) != null, "mirándolo, sí")
	picker.global_position = Vector3(20, 0, 20)
	check(DroppedItem.find(picker) == null, "lejos no hay nada que recoger")
	picker.global_position = Vector3.ZERO

	var inv := Inventory.new()
	add_child(inv)
	check(sword.pick_into(inv) and inv.get_item_count(Config.get_item(&"iron_sword")) == 1, "la espada vuelve al inventario")
	await get_tree().process_frame
	check(not is_instance_valid(sword), "y desaparece del suelo")

	# Con el inventario lleno se queda en el suelo; con un hueco, entra lo que cabe.
	var full := Inventory.new()
	add_child(full)
	var wood := Config.get_item(&"wood_01")
	for i in full.max_slots:
		full.items[i] = InventoryItem.new(wood, wood.max_stack)
	check(not stones.pick_into(full) and stones.quantity == 30, "con el inventario lleno se queda en el suelo")
	var stone := Config.get_item(&"stone_01")
	full.items[0] = InventoryItem.new(stone, stone.max_stack - 9)
	check(stones.pick_into(full) and stones.quantity == 21, "con hueco para 9, entran 9 y quedan %d" % stones.quantity)

	# Desde la ventana: lo cogido de una casilla y soltado fuera de las ventanas sale por
	# drop_requested; soltado sobre la ventana, no.
	var ui: InventoryUI = load("res://scenes/ui/inventory_ui.tscn").instantiate()
	var character_window: CharacterWindow = load("res://scenes/ui/character_window.tscn").instantiate()
	var hotbar: Hotbar = load("res://scenes/ui/hotbar.tscn").instantiate()
	add_child(ui)
	add_child(character_window)
	add_child(hotbar)
	var bag := Inventory.new()
	add_child(bag)
	bag.add_item(stone, 50)
	ui.setup(bag, character_window, hotbar)
	ui.open()
	await _settle(0.2)
	var dropped := []
	# Más allá de la ventana y de la barra (la ventana sin pantalla de headless es diminuta).
	var outside := ui.panel.get_global_rect().merge(hotbar.get_panel().get_global_rect()).end + Vector2(50, 50)
	ui.drop_requested.connect(func(data: ItemData, n: int): dropped.append([data.id, n]))
	ui._on_slot_clicked(ui.slots[0], MOUSE_BUTTON_LEFT)
	_release(ui, ui.panel.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(dropped.is_empty() and ui.floating_item != null, "soltado sobre la ventana sigue en el cursor")
	_click(ui, outside, MOUSE_BUTTON_RIGHT)
	check(dropped == [[&"stone_01", 1]] and ui.floating_item.quantity == 49, "clic derecho fuera: tira una (%s)" % [dropped])
	_click(ui, outside, MOUSE_BUTTON_LEFT)
	check(dropped.size() == 2 and dropped[1] == [&"stone_01", 49] and ui.floating_item == null,
		"clic izquierdo fuera: tira el resto (%s)" % [dropped])
	check(bag.get_item_count(stone) == 0, "y ya no está en el inventario")
	bag.add_item(stone, 10)
	ui._refresh()
	ui._on_slot_clicked(ui.slots[0], MOUSE_BUTTON_LEFT)
	_release(ui, outside, MOUSE_BUTTON_LEFT)
	check(dropped.size() == 3 and dropped[2] == [&"stone_01", 10], "arrastrado fuera y soltado: al suelo (%s)" % [dropped])

	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _release(ui: InventoryUI, at: Vector2, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = false
	ev.position = at
	ev.global_position = at
	ui._input(ev)


func _click(ui: InventoryUI, at: Vector2, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	ui._input(ev)
	_release(ui, at, button)
