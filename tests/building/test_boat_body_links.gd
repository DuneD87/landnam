extends Node3D

## godot --headless --path . res://tests/building/test_boat_body_links.tscn
## El casco, el aparejo y los mandos deben compartir cuerpo también después de cargar.
class SeaData extends RefCounted:
	var has_water := false
	var radius := 1000.0
	var water_radius := 0.0

class TestPlanet extends Node3D:
	var global_pos := Vector3.ZERO
	var gravity_strength := 0.0
	var planet := SeaData.new()
	var water_sphere: OceanSystem
	func get_wind_velocity(_position: Vector3) -> Vector3:
		return Vector3.BACK * 8.0

var _planet: TestPlanet
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_planet = TestPlanet.new()
	add_child(_planet)
	_check_repair_filters()
	await _check_shared_ship()
	GridManager.clear_all()
	_planet.queue_free()
	await get_tree().process_frame
	print("BOAT BODY LINKS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _place(grid: GridBase, cell: Vector3i) -> void:
	grid.place_block(cell, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
		Transform3D(Basis.IDENTITY, grid.grid_to_world(cell)), "wood")


func _check_shared_ship() -> void:
	var hull := GridManager.create_grid_exact(_planet, Vector3(0, 999.9, 0), Basis.IDENTITY, 1.0)
	_place(hull, Vector3i.ZERO)
	_place(hull, Vector3i.RIGHT)
	var deck := GridManager.create_grid_aligned(_planet, hull, 1.0)
	_place(deck, Vector3i(2, 0, 0))
	deck.place_prop(Vector3i(2, 0, 0), Vector3i.UP, &"hide_sail",
		Transform3D(Basis.IDENTITY, Vector3(2.5, 1, 0.5)), {"level": 0, "deployment": 0.0})
	var hull_id := hull.grid_id
	var deck_id := deck.grid_id
	# Apuntar a la segunda grid reproducía ids distintos dentro de un mismo cuerpo.
	var converted := GridManager.convert_to_dynamic(deck_id)
	var first: DynamicPlanetGrid = converted[0]
	var second: DynamicPlanetGrid = converted[1]
	var body := first._body
	body.set_physics_process(false)
	body.freeze = true
	check(first._body == second._body and first.body_id == deck_id and second.body_id == deck_id,
		"convertir desde la segunda rejilla asigna un único id físico a todo el barco")
	first.body_id = "stale_id"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GridManager.get_save_data()))
	check(saved.grids[hull_id].body_id == deck_id and saved.grids[deck_id].body_id == deck_id,
		"el guardado toma el id del cuerpo compartido aunque una rejilla conserve un id obsoleto")
	check(saved.grids[hull_id].body_link_version == 1,
		"el guardado identifica los cuerpos que ya utilizan enlaces corregidos")
	GridManager.restore_save_data(saved)
	var restored_hull := GridManager.get_grid(hull_id) as DynamicPlanetGrid
	var restored_deck := GridManager.get_grid(deck_id) as DynamicPlanetGrid
	body = restored_hull._body
	body.set_physics_process(false)
	body.freeze = true
	body.refresh_sails()
	check(body == restored_deck._body and body._grids.size() == 2 and body.sailing.sails.size() == 1,
		"guardar y cargar mantiene casco y vela en un solo cuerpo")
	check(str(body.get_meta("grid_id")) == deck_id and restored_hull.body_id == deck_id,
		"al cargar, el propietario recupera el id común aunque su id de rejilla sea otro")
	# Snapshot con el fallo exacto de las partidas anteriores.
	var legacy: Dictionary = saved.duplicate(true)
	for id: String in legacy.grids:
		legacy.grids[id].erase("body_link_version")
		legacy.grids[id].body_id = id
	var original_json := JSON.stringify(legacy)
	GridManager.restore_save_data(legacy)
	restored_hull = GridManager.get_grid(hull_id) as DynamicPlanetGrid
	restored_deck = GridManager.get_grid(deck_id) as DynamicPlanetGrid
	body = restored_hull._body
	body.set_physics_process(false)
	body.freeze = true
	body.refresh_sails()
	check(body == restored_deck._body and body._grids.size() == 2,
		"la carga repara el barco antiguo que tenía dos ids para la misma estructura")
	check(restored_hull.get_block_count() == 2 and restored_deck.get_block_count() == 1
		and body.sailing.sails.size() == 1 and is_equal_approx(body.mass, 750.0),
		"la recuperación conserva bloques, masa y aparejo")
	check(JSON.stringify(legacy) == original_json, "recuperar la unión no modifica el snapshot de entrada")
	var repaired: Dictionary = JSON.parse_string(JSON.stringify(GridManager.get_save_data()))
	GridManager.restore_save_data(repaired)
	restored_hull = GridManager.get_grid(hull_id) as DynamicPlanetGrid
	restored_deck = GridManager.get_grid(deck_id) as DynamicPlanetGrid
	body = restored_hull._body
	body.set_physics_process(false)
	body.freeze = true
	check(body == restored_deck._body, "volver a guardar y cargar conserva la reparación")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var player := _new_player()
	player.global_position = body.global_transform * Vector3(0.5, 1.05, 0.5)
	player.gravity_direction = Vector3.DOWN
	player._update_platform_tracking(1.0 / 60.0)
	check(player._platform_body == body and body._is_being_controlled,
		"el raycast de cubierta detecta el cuerpo completo desde la rejilla sin vela")
	Input.action_press("boat_sail_raise")
	Input.action_press("boat_steer_left")
	player.sailing._physics_process(1.0 / 60.0)
	Input.action_release("boat_sail_raise")
	Input.action_release("boat_steer_left")
	check(body.sailing.gear() == 1 and body.steering_input > 0,
		"los mandos desde el casco actúan sobre la marcha y el timón (marcha %d, giro %.1f, control %s)"
		% [body.sailing.gear(), body.steering_input, player.sailing.can_control()])
	player.free()
	GameManager.player = null
	GridManager.clear_all()
	await get_tree().process_frame


func _new_player() -> PlayerController:
	var menu := Control.new()
	add_child(menu)
	var button := Button.new()
	button.name = "btnSaveGame"
	menu.add_child(button)
	button.owner = menu
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	player.free_flight_enabled = false
	player.input_enabled = true
	player.mouse_captured = true
	player.visible = true
	player.building_system.set_build_mode(false)
	GameManager.current_state = GameManager.State.PLAYING
	return player


func _groups(cells_a: Array, cells_b: Array, size_a := 1.0, size_b := 1.0) -> Dictionary:
	var groups := {}
	for index in 2:
		var id := "part_%d" % index
		var blocks := {}
		for key: String in [cells_a, cells_b][index]:
			blocks[key] = {"block_id": 0, "material_id": "wood"}
		groups[id] = [{"grid_id": id, "data": {
			"body_id": id, "planet_path": "/root/planet", "cell_size": [size_a, size_b][index],
			"body_transform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 999, 0], "blocks": blocks,
		}}]
	return groups


func _check_repair_filters() -> void:
	var groups := _groups(["0,0,0"], ["0,0,0"])
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 1, "recupera rejillas antiguas superpuestas del casco y sus rellenos")
	groups = _groups(["0,0,0"], ["1,0,0"])
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 1, "recupera rejillas antiguas adyacentes")
	groups = _groups(["0,0,0"], ["3,0,0"])
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 2, "conserva separados los fragmentos desconectados con la misma pose")
	groups = _groups(["0,0,0"], ["1,1,0"])
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 2, "el contacto diagonal no une cuerpos antiguos")
	groups = _groups(["0,0,0"], ["1,0,0"])
	groups.part_1[0].data.body_transform[9] = 1
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 2, "la recuperación exige una pose idéntica")
	groups = _groups(["0,0,0"], ["1,0,0"])
	groups.part_1[0].data.planet_path = "/root/other_planet"
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 2, "la recuperación no une cuerpos de planetas distintos")
	groups = _groups(["0,0,0"], ["0,0,0"])
	groups.part_0[0].data.body_link_version = 1
	groups.part_1[0].data.body_link_version = 1
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 2, "el formato nuevo conserva los cuerpos independientes aunque coincidan")
	groups = _groups(["0,0,0"], ["2,0,0"], 1.0, 0.5)
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 1, "recupera el contacto entre rejillas de distinta resolución")
	groups = _groups(["-1,0,0"], ["-3,0,0"], 1.0, 0.5)
	GridManager._repair_legacy_body_groups(groups)
	check(groups.size() == 1, "recupera rejillas de distinta resolución con coordenadas negativas")
