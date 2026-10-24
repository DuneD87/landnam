extends Node3D

## Capacidad, restricciones, transferencias y cursor entre inventarios; guardado real del mundo.
## godot --headless --path . res://tests/items/test_storage.tscn
## Con ventana: -- --background --capture=/tmp/storage.png

class WoodRules extends InventoryRules:
	func accepts(_slot: int, data: ItemData) -> bool:
		return data.id == &"wood_01"

	func capacity(_slot: int, _data: ItemData) -> int:
		return 2


class StorageActions extends SurvivalActions:
	# Solo se omite el raycast continuo de la vista previa; se usan colocación e interacción reales.
	func _update_ghost() -> void:
		pass


class SaveProbe extends Node:
	var entity_id := "storage_test_player"
	var save_category := "player"
	var inventory: Inventory
	var ui: InventoryUI

	func prepare_save() -> void:
		ui._cancel_floating_item()

	func prepare_restore() -> void:
		ui.close()

	func get_save_data() -> Dictionary:
		return inventory.get_save_data()

	func restore_save_data(data: Dictionary) -> void:
		inventory.restore_save_data(data)


var failures := 0
var checks := 0
var stone: ItemData
var wood: ItemData
var bag: Inventory
var ui: InventoryUI
var chest: Storage


func _ready() -> void:
	if "--background" in OS.get_cmdline_user_args():
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _chest() -> Storage:
	var storage: Storage = load("res://scenes/world/wooden_chest.tscn").instantiate()
	add_child(storage)
	return storage


func _run() -> void:
	stone = ItemCatalog.get_item(&"stone_01")
	wood = ItemCatalog.get_item(&"wood_01")
	_test_model()
	_test_rules()
	_test_serialization()
	bag = Inventory.new(3)
	add_child(bag)
	ui = InventoryUI.new()
	add_child(ui)
	ui.inventory = bag
	bag.inventory_changed.connect(ui._refresh)
	ui._create_slots()
	chest = _chest()
	await _test_ui()
	await _test_placement()
	await _test_save_load()
	ui.close()
	ui.free()
	bag.free()
	chest.free()
	await get_tree().process_frame
	print("STORAGE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _test_model() -> void:
	var source := Inventory.new(2)
	var target := Inventory.new(1)
	check(source.items.size() == 2, "el constructor configura la capacidad")
	source.max_slots = 4
	check(source.items.size() == 4, "cambiar max_slots redimensiona el contenido")
	source.add_item_at(stone, 7, 3)
	check(not source.resize_slots(2) and source.max_slots == 4 and source.items[3].quantity == 7,
		"reducir la capacidad no elimina huecos ocupados")
	source.move_item(3, 0)
	check(source.resize_slots(2) and source.items[0].quantity == 7, "se pueden recortar huecos vacíos")
	target.add_item(stone, stone.max_stack - 2)
	var notifications := []
	source.inventory_changed.connect(func() -> void:
		notifications.append(["source", source.get_item_count(stone), target.get_item_count(stone)]))
	target.inventory_changed.connect(func() -> void:
		notifications.append(["target", source.get_item_count(stone), target.get_item_count(stone)]))
	check(source.transfer_to(target, 0) == 2 and source.items[0].quantity == 5,
		"un inventario lleno recibe solo lo que cabe en su montón")
	check(notifications == [["source", 5, stone.max_stack], ["target", 5, stone.max_stack]],
		"cada inventario se notifica una vez y ambos ya tienen el resultado final")
	notifications.clear()
	var original := source.items[0]
	check(source.transfer_to(target, 0) == 0 and source.items[0] == original and notifications.is_empty(),
		"sin sitio no cambia ni la identidad del montón ni se emiten señales")
	check(source.transfer_to(target, 0, 2, -2) == 0 and source.items[0].quantity == 5,
		"un destino inválido devuelve la parte retirada al origen")
	target.clear()
	check(source.transfer_to(target, 0, 3) == 3 and source.items[0].quantity == 2 \
		and target.items[0].quantity == 3, "se pueden transferir cantidades parciales")
	check(target.transfer_to(source, 0) == 3 and source.get_item_count(stone) == 5,
		"la misma operación sirve en ambos sentidos")
	check(not source.move_item(0, 0) and not source.move_item(0, 1, 0), "los movimientos vacíos no cambian nada")
	check(source.put_at(1, source.items[0]) == source.items[0] and source.items[1] == null,
		"insertar un montón aún poseído no crea otra referencia al mismo objeto")
	source.free()
	target.free()


func _test_rules() -> void:
	var restricted := Inventory.new(2)
	restricted.rules = WoodRules.new()
	check(restricted.add_item(stone, 3) == 3 and restricted.get_free_slots() == 2,
		"las restricciones se aplican al insertar por código")
	check(restricted.add_item(wood, 7) == 3 and restricted.items[0].quantity == 2 \
		and restricted.items[1].quantity == 2, "se respeta la capacidad de cada hueco")
	var source := Inventory.new(1)
	source.add_item(stone, 5)
	check(source.transfer_to(restricted, 0) == 0 and source.items[0].quantity == 5,
		"una transferencia rechazada conserva todo en origen")
	restricted.clear()
	var held := InventoryItem.new(wood, 5)
	held = restricted.put_at(0, held)
	check(held.quantity == 3 and restricted.items[0].quantity == 2,
		"también el cursor respeta el límite del hueco")
	var fire := Campfire.new()
	var raw := ItemCatalog.get_item(&"raw_meat")
	check(fire.inventory.add_item(stone, 1) == 1, "la hoguera rechaza piedra desde el modelo")
	check(fire.inventory.add_item(raw, 3) == 0 and fire.inventory.items[1].quantity == 1 \
		and fire.inventory.items[2].quantity == 1 and fire.inventory.items[3].quantity == 1,
		"el modelo de la hoguera reparte la comida de una en una")
	check(fire.inventory.items[0] == null and fire.inventory.add_item(wood, 3) == 0 \
		and fire.inventory.items[0].quantity == 3, "el combustible va solo a su hueco")
	# La hoguera aún no ha entrado al árbol: su inventario no tiene padre.
	fire.inventory.free()
	fire.free()
	restricted.free()
	source.free()


func _test_serialization() -> void:
	var source := Inventory.new(8)
	source.add_item_at(stone, 17, 7)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(source.get_save_data()))
	var target := Inventory.new()
	check(target.restore_save_data(saved) and target.max_slots == 8 and target.items[7].quantity == 17,
		"el guardado común conserva capacidad, cantidades y posición tras pasar por JSON")
	check(target.restore_save_data([{"item_id": "wood_01", "quantity": 3, "slot_index": 2}]) \
		and target.items[2].quantity == 3 and target.items[7] == null,
		"se siguen leyendo las listas de inventario de partidas anteriores")
	check(not target.restore_save_data({"items": [{"item_id": "stone_01", "quantity": 0, "slot_index": 0}]}) \
		and target.get_item_count(wood) == 3, "un contenido inválido no sustituye el inventario actual")
	source.free()
	target.free()


func _test_ui() -> void:
	var other := _chest()
	check(chest.inventory.max_slots == 24 and other.inventory != chest.inventory,
		"dos cofres comparten configuración y tienen inventarios independientes")
	other.free()
	ui.open_storage(chest)
	check(ui._loot_slots.size() == 24 and ui.open_storage_node() == chest,
		"un cofre vacío se abre con todos sus huecos y permanece abierto")
	bag.add_item(stone, 7)
	ui._pickup_from_inventory(ui.slots[0])
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_LEFT)
	check(bag.get_item_count(stone) == 0 and chest.inventory.items[0].quantity == 7 and ui.floating_item == null,
		"el mismo índice en dos inventarios distintos permite depositar el montón")
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_RIGHT)
	check(ui.floating_item.quantity == 4 and ui._loot_slots[0].item.quantity == 3,
		"coger la mitad deja visible la cantidad restante en el cofre")
	ui._drop_single_to_inventory(ui.slots[0])
	check(bag.items[0].quantity == 1 and ui.floating_item.quantity == 3,
		"desde el cofre se puede depositar de uno en uno en el jugador")
	ui.close()
	check(chest.inventory.get_item_count(stone) == 6 and bag.get_item_count(stone) == 1,
		"cerrar devuelve al cofre exactamente lo que quedaba en el cursor")
	ui.open_storage(chest)
	bag.add_item_at(wood, 3, 1)
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_RIGHT)
	ui._drop_to_inventory(ui.slots[1])
	check(ui.floating_item == null and chest.inventory.get_item_count(wood) == 3 \
		and bag.get_item_count(stone) + chest.inventory.get_item_count(stone) == 7,
		"intercambiar desde medio montón conserva ambos objetos y coloca el desplazado")
	bag.clear()
	chest.inventory.clear()
	bag.add_item(stone, 8)
	ui._pickup_from_inventory(ui.slots[0])
	ui._on_loot_slot_clicked(ui._loot_slots[5], MOUSE_BUTTON_RIGHT)
	ui.close_loot()
	check(bag.get_item_count(stone) == 0 and chest.inventory.items[5].quantity == 1 \
		and ui.floating_item.quantity == 7, "cerrar el cofre conserva un cursor cuyo origen es el jugador")
	ui.close()
	check(ui.floating_item == null and bag.get_item_count(stone) == 7,
		"cerrar toda la interfaz termina ese movimiento sin perder el resto")
	ui.open_storage(chest)
	ui._take_all_loot()
	check(chest.inventory.get_free_slots() == 24 and bag.get_item_count(stone) == 8 \
		and ui.open_storage_node() == chest, "cogerlo todo vacía el cofre sin cerrarlo")
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	ui._on_slot_clicked(ui.slots[0], MOUSE_BUTTON_LEFT)
	var release := InputEventKey.new()
	release.keycode = KEY_SHIFT
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	check(bag.get_item_count(stone) == 0 and chest.inventory.get_item_count(stone) == 8,
		"Mayús+clic transfiere directamente al cofre")
	var temporary := _chest()
	temporary.inventory.add_item(wood, 4)
	ui.open_storage(temporary)
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_LEFT)
	temporary.free()
	check(ui.floating_item == null and bag.get_item_count(wood) == 4 and ui.open_storage_node() == null,
		"si desaparece el contenedor se recupera en el jugador lo que tenía en el cursor")
	bag.clear()
	bag.max_slots = 1
	bag.add_item(stone, stone.max_stack)
	var drops := []
	var record_drop := func(data: ItemData, amount: int) -> void: drops.append([data.id, amount])
	ui.drop_requested.connect(record_drop)
	temporary = _chest()
	temporary.inventory.add_item(wood, 4)
	ui.open_storage(temporary)
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_LEFT)
	temporary.free()
	check(ui.floating_item == null and drops == [[wood.id, 4]] and bag.get_item_count(stone) == stone.max_stack,
		"con el jugador lleno se suelta el sobrante sin sobrescribir ningún objeto")
	ui.drop_requested.disconnect(record_drop)
	bag.clear()
	chest.inventory.clear()
	bag.max_slots = 20
	var character: CharacterWindow = load("res://scenes/ui/character_window.tscn").instantiate()
	add_child(character)
	ui.character_window = character
	var spear := ItemCatalog.get_item(&"spear")
	var sword := ItemCatalog.get_item(&"iron_sword")
	chest.inventory.add_item(spear, 3)
	ui.open_storage(chest)
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_LEFT)
	ui._drop_to_equipment(character.get_slot(ItemData.ArmorSlot.RIGHT_HAND))
	check(ui.floating_item == null and chest.inventory.get_item_count(spear) == 2 \
		and character.get_equipped_item(ItemData.ArmorSlot.RIGHT_HAND).quantity == 1,
		"equipar desde el cofre consume una pieza y devuelve el resto al cofre")
	chest.inventory.add_item_at(sword, 1, 1)
	ui._on_loot_slot_clicked(ui._loot_slots[1], MOUSE_BUTTON_LEFT)
	ui._drop_to_equipment(character.get_slot(ItemData.ArmorSlot.RIGHT_HAND))
	ui.close()
	check(bag.get_item_count(spear) == 1 and chest.inventory.get_item_count(spear) == 2 \
		and character.get_equipped_item(ItemData.ArmorSlot.RIGHT_HAND).data == sword,
		"sustituir equipo desde un cofre conserva el arma desplazada al cerrar")
	ui.character_window = null
	character.free()
	bag.clear()
	chest.inventory.clear()
	bag.add_item(stone, 42)
	bag.add_item(wood, 18)
	chest.inventory.add_item(ItemCatalog.get_item(&"raw_hide"), 6)
	chest.inventory.add_item(ItemCatalog.get_item(&"bone"), 9)
	ui.open_storage(chest)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await _capture(arg.trim_prefix("--capture="))
	ui.close()


func _test_placement() -> void:
	var data := ItemCatalog.get_item(&"wooden_chest")
	var recipe: RecipeData = load("res://data/recipes/stone/hand/wooden_chest.tres")
	var materials := Inventory.new()
	materials.add_item(wood, 12)
	materials.add_item(ItemCatalog.get_item(&"raw_hide"), 2)
	check(Recipes.craft(recipe, materials) == 0 and materials.get_item_count(data) == 1 \
		and materials.get_item_count(wood) == 0, "la receta fabrica el cofre y consume sus materiales")
	var body := CharacterBody3D.new()
	add_child(body)
	body.set_script(PlayerController)
	var player := body as PlayerController
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.inventory = materials
	player.inventory_ui = ui
	player.add_child(materials)
	var actions := StorageActions.new()
	player.add_child(actions)
	actions.set_process(false)
	actions._player = player
	var ground := data.get_trait(GroundPlaceableTrait) as GroundPlaceableTrait
	actions._make_ghost(ground.preview_scene)
	var ghost_mesh := actions._ghost.get_node("Mesh") as MeshInstance3D
	check(ghost_mesh.material_override != null and not actions._ghost is Storage,
		"la vista previa usa el material fantasma sin crear un almacenamiento real")
	actions._place_ok = true
	actions._place_xform = Transform3D(Basis.IDENTITY, Vector3(12, 0, 1))
	actions._place(data, ground)
	var placed := Storage.nearest(get_tree(), Vector3(12, 0, 1))
	check(placed != null and materials.get_item_count(data) == 0,
		"colocar consume el cofre del jugador y crea un contenedor en el mundo")
	player.position = Vector3(12, 0, 1.5)
	check(actions.open_nearby_storage() and ui.open_storage_node() == placed,
		"la interacción cercana abre el almacenamiento colocado")
	placed.inventory.add_item(wood, 3)
	ui._on_loot_slot_clicked(ui._loot_slots[0], MOUSE_BUTTON_LEFT)
	player.position = Vector3(20, 0, 1)
	actions._process(0.1)
	check(ui.open_storage_node() == null and ui.floating_item == null \
		and placed.inventory.get_item_count(wood) == 3, "alejarse cierra el contenedor y devuelve el cursor")
	check(not actions.open_nearby_storage(), "la interacción no abre un cofre fuera de alcance")
	ui.open_storage(placed)
	ui._dismantle_storage()
	check(not placed.is_queued_for_deletion() and ui._dismantle_storage_button.disabled,
		"un contenedor con objetos no se puede desmontar")
	placed.inventory.clear()
	ui._dismantle_storage()
	check(placed.is_queued_for_deletion() and bag.get_item_count(data) == 1,
		"desmontar un cofre vacío lo devuelve una sola vez al inventario")
	ui.close()
	body.free()
	await get_tree().process_frame


func _test_save_load() -> void:
	# El cofre se registra antes que el jugador para comprobar la preparación de todos antes
	# de capturar/restaurar cualquiera. Se usa el GameManager real y archivos JSON temporales.
	var probe := SaveProbe.new()
	probe.inventory = bag
	probe.ui = ui
	add_child(probe)
	probe.add_to_group(GameManager.SAVEABLE_GROUP)
	var slot := "test_storage_%d" % Time.get_ticks_usec()
	bag.clear()
	chest.inventory.clear()
	chest.position = Vector3(1.0, 0.0, 1.5)
	chest.rotation.y = 0.4
	chest.inventory.add_item_at(stone, 17, 23)
	ui.open_storage(chest)
	ui._on_loot_slot_clicked(ui._loot_slots[23], MOUSE_BUTTON_LEFT)
	check(await GameManager.save_game(slot), "se guarda la partida con un montón del cofre en el cursor")
	check(ui.floating_item == null and chest.inventory.items[23].quantity == 17,
		"guardar termina el movimiento antes de serializar el cofre")
	ui._on_loot_slot_clicked(ui._loot_slots[23], MOUSE_BUTTON_LEFT)
	var newer := _chest()
	var id := chest.entity_id
	for round in 2:
		check(GameManager.load_game(slot), "se carga la partida %d" % (round + 1))
		await get_tree().process_frame
		check(ui.floating_item == null and chest.inventory.get_item_count(stone) == 17 \
			and bag.get_item_count(stone) == 0, "cargar no reinserta el cursor antiguo sobre el contenido restaurado")
	check(not is_instance_valid(newer), "cargar retira los cofres colocados después de guardar")
	chest.free()
	check(GameManager.load_game(slot), "se restaura también un cofre que ya no existe en el mundo")
	chest = Storage.nearest(get_tree(), Vector3(1, 0, 1.5))
	check(chest != null and chest.entity_id == id and chest.inventory.items[23].quantity == 17 \
		and chest.position.is_equal_approx(Vector3(1, 0, 1.5)) and is_equal_approx(chest.rotation.y, 0.4),
		"el cofre se recrea con identidad, transformación y contenido en el último hueco")
	GameManager.delete_save(slot)
	probe.free()


func _capture(path: String) -> void:
	get_window().size = Vector2i(1600, 1000)
	TranslationServer.set_locale("es")
	var camera := Camera3D.new()
	camera.position = Vector3(2.0, 1.6, 2.3)
	add_child(camera)
	camera.look_at(Vector3(0, 0.28, 0))
	camera.current = true
	IconStudio.light(self)
	for frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	camera.free()
