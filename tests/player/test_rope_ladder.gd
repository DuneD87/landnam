extends Node3D

## Escala de cuerda (RopeLadder) colgada de una plataforma sin pared debajo: lo que cuelga (hasta el
## suelo, hasta meterse en el mar o el máximo), su marco, cuándo se agarra con USAR, que corona arriba
## y que de pie arriba baja a ella con coronar al revés. Y un recorrido entero con ticks: subir hasta
## quedar de pie encima, bajar a ella y bajar hasta el suelo. Puesta en una construcción, no choca
## con nada, también en un barco, y guardar y cargar conserva su largo.
##   godot --headless --path . res://tests/player/test_rope_ladder.tscn

class SeaData extends RefCounted:
	var has_water := false
	var radius := 1000.0
	var water_radius := 0.0

class TestPlanet extends Node3D:
	var global_pos := Vector3.ZERO
	var gravity_strength := 0.0
	var planet := SeaData.new()
	var water_sphere: OceanSystem
	var voxel_terrain: VoxelLodTerrain

## La cara de la plataforma, mirando a -Z, y su cima.
const FACE_Z := 1.0
const TOP_Y := 3.0
const TICK := 1.0 / 60.0

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var basis := RopeLadder.hanging_basis(Vector3.FORWARD)
	check(basis.y.is_equal_approx(Vector3.DOWN) and basis.z.is_equal_approx(Vector3.FORWARD)
		and basis.determinant() > 0.99, "el marco cuelga: +Y abajo y +Z fuera de la cara")

	# Suelo y una plataforma de 1 m de canto en el aire: debajo no hay pared.
	_box(Vector3(0.0, -0.25, 0.0), Vector3(20.0, 0.5, 20.0))
	_box(Vector3(0.0, TOP_Y - 0.5, FACE_Z + 1.5), Vector3(3.0, 1.0, 3.0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_world_3d().direct_space_state
	var top := Vector3(0.0, TOP_Y, FACE_Z)
	check(is_equal_approx(RopeLadder.measure_length(space, top, Vector3.DOWN, Vector3.FORWARD, Vector3.ZERO, 0.0),
		TOP_Y), "cuelga hasta el suelo")
	var sea := RopeLadder.measure_length(space, top, Vector3.DOWN, Vector3.FORWARD,
		Vector3(0.0, -1000.0, 0.0), 1001.5)
	check(is_equal_approx(sea, 1.5 + RopeLadder.WATER_DEPTH), "sobre el mar, hasta un poco por debajo (%.2f)" % sea)
	check(is_equal_approx(RopeLadder.measure_length(space, Vector3(0.0, 50.0, FACE_Z), Vector3.DOWN,
		Vector3.FORWARD, Vector3.ZERO, 0.0), RopeLadder.MAX_LENGTH), "sin nada debajo, el máximo")

	# Colgada del canto como la pondría el martillo: el ancla lleva prop_key. El fantasma no.
	var anchor := Node3D.new()
	anchor.set_meta(&"prop_key", "test")
	anchor.transform = Transform3D(basis, top)
	add_child(anchor)
	var ladder: RopeLadder = load("res://scenes/items/rope_ladder/rope_ladder_placed.tscn").instantiate()
	anchor.add_child(ladder)
	ladder.restore_prop_state({"length": TOP_Y})
	var ghost: RopeLadder = load("res://scenes/items/rope_ladder/rope_ladder_placed.tscn").instantiate()
	add_child(ghost)
	check(ladder.is_in_group(RopeLadder.GROUP) and not ghost.is_in_group(RopeLadder.GROUP),
		"se trepa la puesta, no el fantasma")
	ghost.free()
	check(ladder.top().is_equal_approx(top) and ladder.down().is_equal_approx(Vector3.DOWN)
		and ladder.out().is_equal_approx(Vector3.FORWARD), "en mundo: canto, abajo y fuera")

	var menu := Control.new()
	add_child(menu)
	var save_button := Button.new()
	save_button.name = "btnSaveGame"
	menu.add_child(save_button)
	save_button.owner = menu
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	# Parado, pero en el espacio de física: los ticks de la escalada lo mueven con move_and_slide.
	player.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	player.main_menu = menu
	add_child(player)
	player.gravity_direction = Vector3.DOWN
	var climb := player.climb

	# Desde el suelo, delante y mirándola.
	player.global_position = Vector3(0.0, 0.0, FACE_Z - 0.8)
	_look(player, Vector3.BACK)
	check(climb._ladder_in_reach() == ladder, "se agarra mirándola desde el suelo")
	_look(player, Vector3.FORWARD)
	check(climb._ladder_in_reach() == null, "no de espaldas")
	_look(player, Vector3.BACK)
	player.global_position = Vector3(0.0, 0.0, FACE_Z - 2.0)
	check(climb._ladder_in_reach() == null, "no lejos")

	# Colgado arriba corona y acaba de pie encima de la plataforma.
	climb._start_ladder(ladder)
	check(climb.mode == ClimbController.Mode.LADDER, "agarrado desde el suelo")
	player.global_position = climb._ladder_body(climb._ladder_low())
	check(climb._start_top(Vector3.UP), "arriba corona")
	check(absf(climb._top_frame.origin.y - TOP_Y) < 0.05 and climb._top_frame.origin.z > FACE_Z + 0.3,
		"y acaba de pie encima (%s)" % climb._top_frame.origin)

	# De pie arriba, junto al canto y mirándolo: baja a ella con coronar al revés.
	climb.cancel()
	var stand := Vector3(0.0, TOP_Y, FACE_Z + 0.5)
	player.global_position = stand
	_look(player, Vector3.FORWARD)
	check(climb._ladder_in_reach() == ladder, "de pie arriba se agarra mirando al canto")
	climb._start_ladder(ladder)
	check(climb.mode == ClimbController.Mode.TOP and climb._top_down, "baja a ella coronando al revés")
	check(climb._top_body(climb._top_end).distance_to(stand) < 0.06, "empieza de pie donde está")
	check(climb._top_body(0.0).distance_to(climb._ladder_body(climb._ladder_low())) < 0.02,
		"y acaba colgado en lo alto de la escala")

	# Con ticks: de abajo hasta quedar de pie encima.
	climb.cancel()
	player.global_position = ladder.rung_top() + Vector3.DOWN * (TOP_Y - 0.5) + ladder.out() * climb._radius()
	climb._start_ladder(ladder)
	Input.action_press(&"move_forward")
	var crowned := await _tick_until(climb, func() -> bool: return climb.mode == ClimbController.Mode.NONE, 900)
	Input.action_release(&"move_forward")
	check(crowned and absf(player.global_position.y - TOP_Y) < 0.1 and player.global_position.z > FACE_Z,
		"sube por ella hasta quedar de pie encima (%s)" % player.global_position)

	# Y de vuelta: baja a ella y por ella hasta el suelo.
	_look(player, Vector3.FORWARD)
	climb._cooldown = 0.0
	climb._start_ladder(ladder)
	var hung := await _tick_until(climb, func() -> bool: return climb.mode == ClimbController.Mode.LADDER, 600)
	check(hung, "bajando desde arriba queda colgado de ella")
	Input.action_press(&"move_back")
	var landed := await _tick_until(climb, func() -> bool: return climb.mode == ClimbController.Mode.NONE, 900)
	Input.action_release(&"move_back")
	check(landed and absf(player.global_position.y) < 0.1 and player.global_position.z < FACE_Z,
		"y baja hasta el suelo, delante de ella (%s)" % player.global_position)
	await _check_grids()
	_finish()


## Colgada de un bloque de una construcción, como la pone el martillo.
func _check_grids() -> void:
	var planet := TestPlanet.new()
	add_child(planet)
	var grid := GridManager.create_grid_exact(planet, Vector3(0, 500, 0), Basis.IDENTITY, 1.0)
	grid.place_block(Vector3i.ZERO, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
		grid.get_grid_world_transform(), "wood")
	var local := Transform3D(RopeLadder.hanging_basis(Vector3.FORWARD), Vector3(0.5, 1.0, 0.0))
	check(grid.place_prop(Vector3i.ZERO, Vector3i.FORWARD, RopeLadder.ITEM, local, {"length": 4.0}),
		"se cuelga de la cara de un bloque")
	var anchor: StaticBody3D = grid.get_all_props().values()[0]["node"]
	var ladder := _ladder_of(anchor)
	check(anchor.collision_layer == PhysicsLayers.CLIMBABLE and anchor.collision_mask == 0,
		"en una construcción no choca con nada")
	check(ladder != null and is_equal_approx(ladder.length, 4.0) and ladder.is_in_group(RopeLadder.GROUP)
		and ladder.top().is_equal_approx(Vector3(0.5, 501.0, 0.0)), "cuelga del canto lo que dice su estado")
	check(is_equal_approx(_box_of(anchor).size.y, 4.0) and _box_of(anchor).size.z < 0.2,
		"y se apunta en todo su largo")

	var dynamic: DynamicPlanetGrid = GridManager.convert_to_dynamic(grid.grid_id)[0]
	var body := dynamic._body
	body.set_physics_process(false)
	anchor = dynamic.get_all_props().values()[0]["node"] as StaticBody3D
	check(anchor != null and anchor.get_parent() == body and anchor.collision_layer == PhysicsLayers.CLIMBABLE
		and anchor.collision_mask == 0, "en un barco va en un cuerpo propio colgado del casco, que no choca")
	check(ClimbController._carrier_of(anchor) == body, "y trepándola se va con el barco")
	check(is_equal_approx(_ladder_of(anchor).length, 4.0), "convertirla en dinámica conserva su largo")

	var id := dynamic.grid_id
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GridManager.get_save_data()))
	GridManager.restore_save_data(saved)
	await get_tree().process_frame
	dynamic = GridManager.get_grid(id) as DynamicPlanetGrid
	var restored: Node3D = dynamic.get_all_props().values()[0]["node"] if dynamic != null else null
	check(restored != null and is_equal_approx(_ladder_of(restored).length, 4.0), "guardar y cargar conserva su largo")
	GridManager.clear_all()
	planet.queue_free()


func _ladder_of(anchor: Node) -> RopeLadder:
	for child in anchor.get_children():
		if child is RopeLadder:
			return child
	return null


func _box_of(anchor: Node) -> BoxShape3D:
	for child in anchor.get_children():
		if child is CollisionShape3D:
			return child.shape
	return null


## Ticks de la escalada (dentro del paso de física) hasta [done] o [limit]. true si se cumple.
func _tick_until(climb: ClimbController, done: Callable, limit: int) -> bool:
	for i in limit:
		await get_tree().physics_frame
		climb.physics_update(TICK)
		if done.call():
			return true
	return false


## La cámara mirando hacia [dir].
func _look(player: PlayerController, dir: Vector3) -> void:
	player.camera.global_basis = Basis.looking_at(dir)


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	body.position = center
	add_child(body)


func _finish() -> void:
	GameManager.player = null
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)
