extends Node3D

## Mochilas: cambios atómicos de capacidad, cursor entre contenedores y persistencia real.
## godot --headless --path . res://tests/items/test_backpacks.tscn
## Con render: -- --background --capture=/tmp/backpack.png

class GroundedPlayer extends PlayerController:
	func is_ground_ready() -> bool:
		return true


var failures := 0
var checks := 0
var pack: ItemData
var large: ItemData
var stone: ItemData
var single: ItemData


func _ready() -> void:
	if "--background" in OS.get_cmdline_user_args():
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	pack = ItemCatalog.get_item(&"hide_backpack")
	large = ItemData.clone(pack)
	large.id = &"test_large_backpack"
	var expansion := InventoryExpansionTrait.new()
	expansion.extra_slots = 16
	large.traits = [expansion]
	stone = ItemCatalog.get_item(&"stone_01")
	single = ItemCatalog.get_item(&"iron_sword")
	_test_repack()
	_test_equipment()
	await _test_cursor()
	await _test_player()
	await get_tree().process_frame
	print("BACKPACKS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _test_repack() -> void:
	var inv := Inventory.new(4)
	inv.add_item_at(stone, 7, 0)
	inv.add_item_at(stone, 9, 1)
	inv.add_item_at(single, 1, 3)
	var original := inv.items[0]
	check(inv.can_repack(2) and inv.items[0].quantity == 7 and inv.items[1].quantity == 9 \
		and inv.items[3] != null, "comprobar la compactación no mueve ni modifica los montones")
	check(inv.repack_slots(2) and inv.max_slots == 2 and inv.items[0] == original \
		and original.quantity == 16 and inv.items[1].data == single,
		"compactar une montones compatibles, conserva su identidad y recoloca el hueco alto")
	var saved := inv.get_save_data()
	check(not inv.repack_slots(1) and inv.get_save_data() == saved,
		"una reducción imposible deja intactos contenido y capacidad")
	check(not inv.can_repack(2, [InventoryItem.new(pack)]) and inv.can_repack(3, [InventoryItem.new(pack)]),
		"se puede reservar espacio para la mochila retirada sin insertarla")
	inv.free()


func _test_equipment() -> void:
	var inv := Inventory.new(4)
	add_child(inv)
	var equipment := CharacterWindow.new()
	add_child(equipment)
	equipment.bind_inventory(inv)
	var back := equipment.get_slot(ItemData.ArmorSlot.BACK)
	check(back != null and int(ItemData.ArmorSlot.OFFHAND) == 8,
		"Espalda tiene su hueco y se conservan los valores anteriores del equipo")
	check(equipment.equip_item(back, InventoryItem.new(pack)) == null and inv.max_slots == 12,
		"equipar aporta ocho huecos sobre la capacidad base")
	var displaced := equipment.equip_item(back, InventoryItem.new(pack))
	check(displaced != null and inv.max_slots == 12, "sustituir por la misma capacidad no acumula el bono")
	for i in inv.max_slots:
		inv.add_item_at(stone, 1, i)
	displaced = equipment.equip_item(back, InventoryItem.new(pack))
	check(inv.get_item_count(stone) == 12 and inv.insert(displaced) == null,
		"al sustituir por igual capacidad se compactan montones para alojar la mochila saliente")
	inv.clear()
	for i in inv.max_slots:
		inv.add_item_at(single, 1, i)
	var notifications := []
	equipment.equipment_changed.connect(func(slot, _item, _equip) -> void:
		if slot == ItemData.ArmorSlot.BACK:
			notifications.append(inv.max_slots))
	var before := inv.get_save_data()
	check(equipment.unequip_item(back) == null and inv.get_save_data() == before and back.has_item() \
		and notifications.is_empty(), "no se retira una mochila llena ni se emite un cambio intermedio")
	displaced = equipment.equip_item(back, InventoryItem.new(large))
	check(displaced.data == pack and inv.max_slots == 20 and notifications == [20, 20],
		"cambiar a una mochila mayor usa la capacidad final incluso con el inventario lleno")
	for i in range(12, 20):
		inv.add_item_at(single, 1, i)
	var incoming := InventoryItem.new(pack)
	notifications.clear()
	before = inv.get_save_data()
	check(equipment.equip_item(back, incoming) == incoming and back.equipped_item.data == large \
		and inv.get_save_data() == before and notifications.is_empty(),
		"una mochila menor se rechaza antes de retirar la anterior")
	inv.clear()
	for i in range(9, 20):
		inv.add_item_at(single, 1, i)
	displaced = equipment.equip_item(back, incoming)
	check(displaced.data == large and inv.max_slots == 12 and inv.get_item_count(single) == 11,
		"la mochila menor compacta los objetos si caben y reserva el hueco de la saliente")
	inv.clear()
	inv.add_item_at(single, 1, 11)
	inv.add_item_at(stone, 3, 9)
	displaced = equipment.unequip_item(back)
	check(displaced.data == pack and inv.max_slots == 4 and inv.get_item_count(single) == 1 \
		and inv.get_item_count(stone) == 3, "quitar la mochila recoloca los objetos de los huecos adicionales")
	check(inv.insert(displaced) == null, "la mochila retirada cabe en el espacio reservado")
	equipment.free()
	inv.free()


func _test_cursor() -> void:
	var inv := Inventory.new(4)
	add_child(inv)
	var equipment := CharacterWindow.new()
	var hotbar: Hotbar = load("res://scenes/ui/hotbar.tscn").instantiate()
	var ui := InventoryUI.new()
	add_child(equipment)
	add_child(hotbar)
	add_child(ui)
	ui.setup(inv, equipment, hotbar)
	var drops := []
	ui.drop_requested.connect(func(data: ItemData, amount: int) -> void: drops.append([data.id, amount]))
	var back := equipment.get_slot(ItemData.ArmorSlot.BACK)
	inv.add_item(pack)
	ui.open()
	ui._pickup_from_inventory(ui.slots[0])
	ui._drop_to_equipment(back)
	check(inv.max_slots == 12 and ui.slots.size() == 12 and ui.floating_item == null \
		and inv.get_item_count(pack) == 0, "equipar desde el cursor consume una mochila y amplía la cuadrícula")
	inv.add_item_at(stone, 5, 11)
	ui._pickup_from_equipment(back)
	check(inv.max_slots == 4 and ui.slots.size() == 4 and ui.floating_item.data == pack,
		"al quitarla el cursor conserva la mochila y la cuadrícula se reduce")
	ui.close()
	check(inv.get_item_count(pack) == 1 and inv.get_item_count(stone) == 5 and drops.is_empty(),
		"cerrar devuelve la mochila sin perder su contenido ni soltar objetos")
	inv.clear()
	inv.add_item(pack)
	ui._pickup_from_inventory(ui.slots[0])
	ui._drop_to_equipment(back)
	for i in inv.max_slots:
		inv.add_item_at(single, 1, i)
	ui._pickup_from_equipment(back)
	check(ui.floating_item == null and back.has_item() and inv.max_slots == 12 \
		and hotbar._notice.text == tr("INV_BACKPACK_FULL"), "quitar sin espacio conserva el equipo y muestra el aviso")
	var chest: Storage = load("res://scenes/world/wooden_chest.tscn").instantiate()
	add_child(chest)
	chest.inventory.add_item(large)
	ui.open_storage(chest)
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_LEFT)
	ui._drop_to_equipment(back)
	ui.close()
	check(inv.max_slots == 20 and back.equipped_item.data == large and inv.get_item_count(pack) == 1 \
		and inv.get_item_count(single) == 12 and drops.is_empty(),
		"se equipa una mochila mayor desde un cofre y se conserva la que sale")
	chest.inventory.add_item(pack)
	ui.open_storage(chest)
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_LEFT)
	ui._drop_to_equipment(back)
	check(ui.floating_item != null and ui.floating_item.data == pack and back.equipped_item.data == large,
		"un cambio rechazado mantiene la mochila entrante en el cursor")
	ui.close()
	check(chest.inventory.get_item_count(pack) == 1 and inv.get_item_count(pack) == 1 \
		and inv.max_slots == 20 and drops.is_empty(), "cancelar el cambio devuelve la entrante al cofre sin duplicados")
	ui.free()
	equipment.free()
	hotbar.free()
	chest.free()
	inv.free()
	await get_tree().process_frame


func _test_player() -> void:
	var menu := Control.new()
	add_child(menu)
	for button_name in ["btnSaveGame", "btnStartGame"]:
		var button := Button.new()
		button.name = button_name
		menu.add_child(button)
		button.owner = menu
	var spawn_point := Marker3D.new()
	spawn_point.name = "SpawnPoint"
	add_child(spawn_point)
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.set_script(GroundedPlayer)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	GameManager.current_state = GameManager.State.PLAYING
	var ui := player.inventory_ui
	var back := player.character_window.get_slot(ItemData.ArmorSlot.BACK)
	player.inventory.add_item(pack)
	ui.open()
	ui._pickup_from_inventory(ui.slots[0])
	ui._drop_to_equipment(back)
	ui.close()
	player.inventory.add_item_at(stone, 17, 27)
	var slot := "test_backpacks_%d" % Time.get_ticks_usec()
	check(await GameManager.save_game(slot), "se guarda el jugador con mochila equipada y el último hueco ocupado")
	for round in 3:
		check(GameManager.load_game(slot), "se carga la partida %d" % (round + 1))
		await get_tree().process_frame
		check(player.inventory.max_slots == 28 and ui.slots.size() == 28 \
			and player.character_window.inventory_capacity.base_slots == 20,
			"la capacidad se deriva una sola vez al cargar")
		check(back.has_item() and back.equipped_item.data == pack and player.inventory.items[27].quantity == 17 \
			and player.inventory.get_item_count(pack) == 0, "se conserva mochila equipada y contenido en su posición")
	var skeleton := player.player_model.get_node("Armature/Skeleton3D") as Skeleton3D
	var attachments := skeleton.get_children().filter(func(node: Node) -> bool: return node is BackEquipment)
	check(attachments.size() == 1, "las cargas repetidas mantienen una sola mochila visible")
	var attachment: BackEquipment = attachments[0]
	var mesh := attachment.visual.get_node("Mesh") as MeshInstance3D
	var box := mesh.global_transform * mesh.get_aabb()
	check(box.size.x > 0.2 and box.size.x < 0.8 and box.size.y > 0.25 and box.size.y < 0.9,
		"la mochila visible conserva su tamaño en metros sobre el esqueleto importado")
	var recipe: RecipeData = load("res://data/recipes/stone/stone_workbench/hide_backpack.tres")
	check(recipe.result == pack.id and recipe.station == &"stone_workbench" and pack.icon != null,
		"la mochila tiene icono y receta en el banco de trabajo")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await _capture(player, arg.trim_prefix("--capture="))
	var legacy := player.get_save_data().duplicate(true)
	legacy.equipment.erase(str(int(ItemData.ArmorSlot.BACK)))
	legacy.inventory = [{"item_id": "stone_01", "quantity": 3, "slot_index": 2}]
	legacy.erase("inventory_base_slots")
	player.restore_save_data(legacy)
	await get_tree().process_frame
	check(player.inventory.max_slots == 20 and not back.has_item() and player.inventory.get_item_count(stone) == 3,
		"las partidas antiguas sin mochila ni capacidad base conservan los veinte huecos")
	check(skeleton.get_children().filter(func(node: Node) -> bool: return node is BackEquipment).is_empty(),
		"cargar sin mochila retira también su modelo")
	player.character_window.inventory_capacity.base_slots = 12
	player.character_window.inventory_capacity.sync()
	var custom := player.get_save_data()
	player.restore_save_data(custom)
	check(player.inventory.max_slots == 12, "se conserva una capacidad base configurada y guardada")
	player.restore_save_data(legacy)
	check(player.inventory.max_slots == 20, "una partida antigua usa la base de la escena y no la de la última partida cargada")
	GameManager.delete_save(slot)
	GameManager.player = null
	player.queue_free()
	await get_tree().process_frame
	menu.free()
	spawn_point.free()


func _capture(player: PlayerController, path: String) -> void:
	get_window().size = Vector2i(1900, 1100)
	TranslationServer.set_locale("es")
	player.debug_stats.visible = false
	player.character_window.preview.process_mode = Node.PROCESS_MODE_ALWAYS
	for id in [&"hide_tunic", &"hide_trousers"]:
		var data := ItemCatalog.get_item(id)
		player.character_window.equip_item(player.character_window.get_slot(data.armor_slot), InventoryItem.new(data))
	player.inventory_ui.open(InventoryUI.View.CHARACTER)
	player.character_window.preview._model.rotation.y = PI - 0.4
	player.character_window.refresh()
	for frame in 12:
		await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 6000
	while player.character_window.preview.rig.is_dressing() and Time.get_ticks_msec() < deadline:
		player.character_window.preview.rig._process(0.0)
		await get_tree().process_frame
	player.character_window.preview._place_camera()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	player.inventory_ui.close()
