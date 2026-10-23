extends Node3D

## Las herramientas conservan su cantidad entre inventario, equipo y barra al guardar/cargar.
## godot --headless --path . res://tests/player/test_item_save_load.tscn

class GroundedPlayer extends PlayerController:
	func is_ground_ready() -> bool:
		return true


var failures := 0
var _player: PlayerController
var _slot := "test_item_save_load_%d" % Time.get_ticks_usec()


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _count(data: ItemData) -> int:
	var total := _player.inventory.get_item_count(data)
	for slot: EquipmentSlot in _player.character_window.equipment_slots.values():
		if slot.has_item() and slot.equipped_item.data.id == data.id:
			total += slot.equipped_item.quantity
	return total


func _run() -> void:
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
	_player = load("res://scenes/player/third_person_player.tscn").instantiate()
	_player.set_script(GroundedPlayer)
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.main_menu = menu
	add_child(_player)
	GameManager.current_state = GameManager.State.PLAYING

	var pickaxe := ItemCatalog.get_item(&"stone_pickaxe_01")
	var axe := ItemCatalog.get_item(&"stone_axe_01")
	_player.inventory.add_item(pickaxe, 1)
	_player.inventory.add_item(axe, 1)
	_player.hotbar.assign_to_slot(0, pickaxe)
	_player.hotbar.assign_to_slot(1, axe)
	_player.hotbar.select_slot(1)
	check(_count(axe) == 1 and _count(pickaxe) == 1, "antes de guardar hay un hacha y un pico")
	check(await GameManager.save_game(_slot), "se guarda la partida con el hacha equipada")

	# Al arrancar, la barra aún no tiene selección: cargar el equipo y luego elegir el hueco
	# no debe fabricar otra hacha ni mover al inventario la que acaba de restaurarse.
	_player.hotbar.selected_index = -1
	for round in 3:
		check(GameManager.load_game(_slot), "carga %d de la misma partida" % (round + 1))
		await get_tree().create_timer(0.5).timeout
		check(_count(axe) == 1, "carga %d: el hacha equipada no se duplica" % (round + 1))
		check(_count(pickaxe) == 1, "carga %d: activar al jugador no entrega otro pico" % (round + 1))
		check(_player.hotbar.selected_index == 1 and _player._get_right_hand_item() == axe,
			"carga %d: se conservan el hueco seleccionado y el equipo" % (round + 1))
		# La siguiente carga también debe funcionar sobre una selección diferente.
		_player.hotbar.select_slot(0)

	# La partida también puede contener solo el pico equipado y ningún pico en la mochila.
	check(await GameManager.save_game(_slot), "se guarda con el pico equipado")
	_player.hotbar.selected_index = -1
	check(GameManager.load_game(_slot), "se restaura el pico equipado desde una barra sin selección")
	await get_tree().create_timer(0.5).timeout
	check(_count(pickaxe) == 1 and _player.inventory.get_item_count(pickaxe) == 0,
		"el pico permanece solo en la mano, sin copias en la mochila")
	check(_count(axe) == 1, "el hacha de la mochila también conserva su cantidad")
	_player._equip_from_hotbar(null, pickaxe)
	check(_count(pickaxe) == 1, "reequipar el pico que ya está en la mano no crea una copia")
	_player.inventory.remove_item(axe, 1)
	_player.hotbar.select_slot(1)
	check(_count(axe) == 0 and _player._get_right_hand_item() == pickaxe,
		"un acceso al hacha que ya no se posee no crea otra herramienta")

	# Con la mochila llena y sin selección, el equipo no debe volver a ella al cargar.
	_player.hotbar.restore_selection(-1)
	var stone := ItemCatalog.get_item(&"stone_01")
	for i in _player.inventory.max_slots:
		_player.inventory.items[i] = InventoryItem.new(stone, stone.max_stack)
	var torch := ItemCatalog.get_item(&"torch_01")
	var left: EquipmentSlot = _player.character_window.get_slot(ItemData.ArmorSlot.OFFHAND)
	_player.character_window.equip_item(left, InventoryItem.new(torch, 1))
	check(await GameManager.save_game(_slot), "se guarda con la mochila llena y ambas manos ocupadas")
	check(GameManager.load_game(_slot), "se carga sin huecos libres en la mochila")
	await get_tree().create_timer(0.5).timeout
	check(_count(pickaxe) == 1 and _count(torch) == 1 and _player.inventory.is_full(),
		"la mochila llena no pierde ni duplica el equipo de ninguna mano")
	check(_player.hotbar.selected_index == -1 and _player._get_right_hand_item() == pickaxe,
		"sin selección guardada, el pico sigue equipado")

	# Los modos de construcción se restauran sin simular una pulsación de la barra.
	_player.inventory.clear()
	var prop := ItemCatalog.get_item(&"torch_placeable_01")
	_player.inventory.add_item(prop, 1)
	_player.hotbar.assign_to_slot(2, prop)
	_player.hotbar.select_slot(2)
	check(await GameManager.save_game(_slot), "se guarda con un colocable seleccionado")
	_player.building_system.select_placeable(null)
	check(GameManager.load_game(_slot), "se carga el colocable seleccionado")
	await get_tree().create_timer(0.5).timeout
	check(_player.building_system.selected_placeable == prop and _count(prop) == 1,
		"se recupera el modo de colocar sin mover ni duplicar objetos")
	var hammer := ItemCatalog.get_item(&"stone_hammer_01")
	_player.inventory.add_item(hammer, 1)
	_player.hotbar.assign_to_slot(3, hammer)
	_player.hotbar.select_slot(3)
	check(await GameManager.save_game(_slot), "se guarda con el martillo equipado")
	check(GameManager.load_game(_slot), "se carga el martillo equipado")
	await get_tree().create_timer(0.5).timeout
	check(_count(hammer) == 1 and _player.building_system.build_mode
			and not _player.building_system.is_prop_mode(),
		"el martillo conserva su cantidad y permite construir tras cargar")

	GameManager.delete_save(_slot)
	GameManager.player = null
	_player.queue_free()
	await get_tree().process_frame
	print("ITEM SAVE/LOAD: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
