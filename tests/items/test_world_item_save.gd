extends Node3D

## Conservación entre mochila, objetos del suelo y colocables con el GameManager real.
## godot --headless --path . res://tests/items/test_world_item_save.tscn

class SaveProbe extends CharacterBody3D:
	var entity_id := "world_items_player"
	var save_category := "player"
	var inventory := Inventory.new()

	func _ready() -> void:
		add_child(inventory)
		add_to_group(GameManager.SAVEABLE_GROUP)

	func get_save_data() -> Dictionary:
		return inventory.get_save_data()

	func restore_save_data(data: Dictionary) -> void:
		inventory.restore_save_data(data)


var failures := 0
var checks := 0
var _player: SaveProbe
var _slot := "test_world_items_%d" % Time.get_ticks_usec()


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _drops() -> Array[Node]:
	return get_tree().get_nodes_in_group(DroppedItem.GROUP).filter(
		func(node: Node) -> bool: return not node.is_queued_for_deletion())


func _world_count(data: ItemData) -> int:
	var count := _player.inventory.get_item_count(data)
	for node: DroppedItem in _drops():
		if node.item_data.id == data.id:
			count += node.quantity
	return count


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	add_child(floor_body)
	var marker := Marker3D.new()
	marker.name = "SpawnPoint"
	add_child(marker)
	_player = SaveProbe.new()
	add_child(_player)
	GameManager.register_player(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _test_future_drop()
	await _test_saved_drop()
	_test_coordinates_and_ship()
	await _test_spears_and_transients()
	await _test_future_placeables()
	await _test_dismantle_save()
	await _test_legacy_slot()
	GameManager.delete_save(_slot)
	GameManager.player = null
	print("WORLD ITEM SAVE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _test_future_drop() -> void:
	var axe := ItemCatalog.get_item(&"stone_axe_01")
	_player.inventory.add_item(axe, 1)
	check(await GameManager.save_game(_slot), "se guarda el hacha en la mochila")
	_player.inventory.remove_item(axe, 1)
	DroppedItem.spawn(_player, axe, 1, Vector3.DOWN)
	check(GameManager.load_game(_slot), "se carga después de tirar el hacha")
	check(_world_count(axe) == 1 and _drops().is_empty(),
		"cargar no deja una copia del hacha tirada después del guardado")
	for node in _drops():
		node.free()
	_player.inventory.clear()


func _test_saved_drop() -> void:
	var wood := ItemCatalog.get_item(&"wood_01")
	var pile := TreeLog.pile(12, 0.25, null)
	var drop := DroppedItem.spawn_at(_player, wood, 12, Vector3(2, 1, 0), Vector3.DOWN, pile)
	var mesh_count := pile.get_child_count()
	check(await GameManager.save_game(_slot), "se guarda un montón de leña en el suelo")
	check(drop.pick_into(_player.inventory), "se recoge la leña después de guardar")
	check(GameManager.load_game(_slot), "se carga inmediatamente después de recoger")
	check(_world_count(wood) == 12 and _player.inventory.get_item_count(wood) == 0 \
		and _drops().size() == 1, "cargar devuelve exactamente la leña guardada al suelo")
	# Simula otra sesión: se liberan todos los objetos antes de restaurar el archivo.
	for node in _drops():
		node.free()
	check(GameManager.load_game(_slot), "se recrea el montón que ya no está en la escena")
	check(_drops().size() == 1 and _world_count(wood) == 12,
		"el objeto guardado sobrevive también sin su instancia original")
	if _drops().size() == 1:
		var restored := _drops()[0] as DroppedItem
		check(restored.find_children("*", "MeshInstance3D", true, false).size() == mesh_count,
			"la leña recupera sus mallas, además de su cantidad")
		check(is_equal_approx(restored._fall_left, 1.0), "se conserva la distancia que le quedaba por caer")
	for round in 3:
		check(GameManager.load_game(_slot) and _drops().size() == 1 and _world_count(wood) == 12,
			"carga repetida %d: un solo montón con la cantidad guardada" % (round + 1))
	for node in _drops():
		node.free()
	await get_tree().process_frame


func _test_coordinates_and_ship() -> void:
	var data := ItemCatalog.get_item(&"stone_01")
	var origin := FloatingOrigin.new()
	add_child(origin)
	origin.total_offset = Vector3(1024, 512, -2048)
	var drop := DroppedItem.spawn_at(_player, data, 9, Vector3(3, 1, 4), Vector3.DOWN)
	var canonical := origin.to_canonical(drop.global_position)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(DroppedItem.capture_all(get_tree())))
	DroppedItem.clear_all(get_tree())
	origin.total_offset = Vector3(512, 256, -1024)
	DroppedItem.restore_all(get_tree(), saved)
	check(_drops().size() == 1 and origin.to_canonical((_drops()[0] as Node3D).global_position).is_equal_approx(canonical),
		"el objeto conserva su posición canónica aunque cambie el origen flotante")
	DroppedItem.clear_all(get_tree())
	origin.free()

	var ship := DynamicGridBody.new()
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	ship.set_meta("grid_id", "world_item_test_ship")
	add_child(ship)
	ship.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(7, 2, 3))
	var grid := DynamicPlanetGrid.new()
	grid._body = ship
	GridManager._grids["world_item_test_ship"] = grid
	drop = DroppedItem.new()
	drop.item_data = data
	drop.quantity = 9
	ship.add_child(drop)
	drop.remove_from_group("floating_origin")
	drop.transform = Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(1, 0, 2))
	var local := drop.transform
	saved = JSON.parse_string(JSON.stringify(DroppedItem.capture_all(get_tree())))
	DroppedItem.clear_all(get_tree())
	ship.free()
	ship = DynamicGridBody.new()
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	ship.set_meta("grid_id", "world_item_test_ship")
	add_child(ship)
	grid._body = ship
	DroppedItem.restore_all(get_tree(), saved)
	check(_drops().size() == 1 and _drops()[0].get_parent() == ship \
		and (_drops()[0] as Node3D).transform.is_equal_approx(local)
		and not _drops()[0].is_in_group("floating_origin"),
		"el objeto vuelve al barco recreado usando su id y transformación local")
	DroppedItem.clear_all(get_tree())
	GridManager._grids.erase("world_item_test_ship")
	grid._body = null
	grid = null
	ship.free()


func _test_spears_and_transients() -> void:
	var spear := CombatProjectile.new()
	spear.kind = CombatProjectile.Kind.SPEAR
	spear.item_data = ItemCatalog.get_item(&"spear")
	spear._stuck = true
	add_child(spear)
	spear.add_to_group(CombatProjectile.PICKUP_GROUP)
	check(await GameManager.save_game(_slot), "se guarda la lanza clavada en el suelo")
	var future := CombatProjectile.new()
	add_child(future)
	var corpse := Node3D.new()
	add_child(corpse)
	corpse.add_to_group(GameManager.RESET_ON_LOAD_GROUP)
	check(GameManager.load_game(_slot), "se carga con proyectiles y restos de sesión presentes")
	check(not future.is_inside_tree() and not corpse.is_inside_tree(),
		"los objetos de sesión se retiran inmediatamente, antes de que se puedan recoger")
	check(_world_count(ItemCatalog.get_item(&"spear")) == 1 and _drops().size() == 1 \
		and get_tree().get_nodes_in_group(CombatProjectile.PICKUP_GROUP).is_empty(),
		"la lanza guardada se recupera una sola vez, sin conservar también el proyectil antiguo")
	DroppedItem.clear_all(get_tree())
	await get_tree().process_frame


func _test_future_placeables() -> void:
	var fire_data := ItemCatalog.get_item(Campfire.ITEM_ID)
	var station_data := ItemCatalog.get_item(&"stone_workbench")
	_player.inventory.add_item(fire_data, 1)
	_player.inventory.add_item(station_data, 1)
	check(await GameManager.save_game(_slot), "se guardan la hoguera y el banco sin colocar")
	var fire := load("res://scenes/world/campfire.tscn").instantiate() as Campfire
	var station := load("res://scenes/world/stone_workbench.tscn").instantiate() as Workstation
	add_child(fire)
	add_child(station)
	_player.inventory.remove_item(fire_data, 1)
	_player.inventory.remove_item(station_data, 1)
	check(GameManager.load_game(_slot), "se carga después de colocar hoguera y banco")
	check(fire.is_queued_for_deletion() and station.is_queued_for_deletion(),
		"los colocables del futuro se retiran al restaurar la mochila")
	await get_tree().process_frame
	if is_instance_valid(fire):
		fire.free()
	if is_instance_valid(station):
		station.free()
	_player.inventory.clear()


func _test_dismantle_save() -> void:
	var chest := load("res://scenes/world/wooden_chest.tscn").instantiate() as Storage
	add_child(chest)
	var ui := InventoryUI.new()
	add_child(ui)
	ui.inventory = _player.inventory
	ui._create_slots()
	ui.open_storage(chest)
	ui._dismantle_storage()
	check(await GameManager.save_game(_slot), "se guarda en el mismo fotograma que se desmonta un cofre")
	await get_tree().process_frame
	check(GameManager.load_game(_slot), "se carga el guardado del desmontaje")
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group(Storage.GROUP).is_empty() \
		and _player.inventory.get_item_count(ItemCatalog.get_item(&"wooden_chest")) == 1,
		"el cofre desmontado no reaparece junto a su objeto en la mochila")
	ui.free()


func _test_legacy_slot() -> void:
	check(await GameManager.save_game(_slot), "se prepara una partida sin objetos del mundo")
	DirAccess.remove_absolute(GameManager._save_file_path(_slot, "world_items"))
	DroppedItem.spawn(_player, ItemCatalog.get_item(&"wood_01"), 4, Vector3.DOWN)
	check(GameManager.load_game(_slot) and _drops().is_empty(),
		"una partida antigua sin archivo de objetos del mundo también elimina los drops posteriores")
