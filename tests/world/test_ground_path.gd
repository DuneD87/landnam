extends Node3D

## godot --headless --path . res://tests/world/test_ground_path.tscn
## Caminos a pie (GroundPath, Companion.steer) para salir de una casa de 6×6 m con la puerta en -Z y una
## ventana (pared hasta 1 m, hueco hasta 2 m) en +Z, que es hacia donde queda lo que se busca.
var failures := 0
var checks := 0

const HALF := 3.0
const THICK := 0.3
const DOOR_HALF := 0.6
const WINDOW_HALF := 1.0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	add_child(body)


func _house() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	# Paredes este y oeste, enteras.
	for side in [-1.0, 1.0]:
		_box(Vector3(side * HALF, 1.5, 0), Vector3(THICK, 3, HALF * 2 + THICK))
	# Norte (+Z): la ventana.
	var piece := HALF - WINDOW_HALF
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (WINDOW_HALF + piece * 0.5), 1.5, HALF), Vector3(piece, 3, THICK))
	_box(Vector3(0, 0.5, HALF), Vector3(WINDOW_HALF * 2, 1, THICK))
	_box(Vector3(0, 2.5, HALF), Vector3(WINDOW_HALF * 2, 1, THICK))
	# Sur (-Z): la puerta, un hueco entero.
	piece = HALF - DOOR_HALF
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (DOOR_HALF + piece * 0.5), 1.5, -HALF), Vector3(piece, 3, THICK))
	_box(Vector3(0, 2.6, -HALF), Vector3(DOOR_HALF * 2, 0.8, THICK))
	# Tejado.
	_box(Vector3(0, 3.1, 0), Vector3(HALF * 2 + THICK, 0.2, HALF * 2 + THICK))


## Si el camino cruza la pared norte (z = HALF) por dentro de la casa: por la ventana.
func _through_window(path: PackedVector3Array) -> bool:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		if (a.z - HALF) * (b.z - HALF) < 0.0:
			var t := (HALF - a.z) / (b.z - a.z)
			if absf(lerpf(a.x, b.x, t)) < HALF + THICK:
				return true
	return false


func _run() -> void:
	_house()
	var walker := CharacterBody3D.new()
	add_child(walker)
	walker.position = Vector3(0, 0.05, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start := Vector3(0, 0.05, 0)

	# Lejos (más que MAX_RANGE): antes no había camino y se quedaba empujando la ventana.
	var far := GroundPath.find(walker, start, Vector3(0, 0, 60), Vector3.UP, 1.0)
	check(not far.is_empty(), "hacia algo lejano hay camino (parcial)")
	check(GroundPath.last_stats.get("partial", false), "y es parcial")
	check(not _through_window(far), "no sale por la ventana")
	var out_door := false
	for p in far:
		if p.z < -HALF:
			out_door = true
	check(out_door, "sale por la puerta")
	check(far.size() > 0 and far[far.size() - 1].z > HALF + 1.0, "y acaba fuera, del lado de lo que busca")

	# Cerca (dentro de MAX_RANGE): el camino entero, también por la puerta.
	var near := GroundPath.find(walker, start, Vector3(0, 0, 10), Vector3.UP, 1.0)
	check(not near.is_empty() and not GroundPath.last_stats.get("partial", true), "hacia algo cerca hay camino entero")
	check(not _through_window(near), "tampoco por la ventana")
	check(near.size() > 0 and Vector2(near[near.size() - 1].x, near[near.size() - 1].z).distance_to(Vector2(0, 10)) <= 1.0 + GroundPath.CELL,
		"y llega")

	# Sin ganar nada (encerrado del todo) no hay camino parcial.
	var shut := GroundPath.find(walker, Vector3(0, 0.05, 0), Vector3(0, 0, -60), Vector3.UP, 1.0)
	check(not shut.is_empty(), "hacia el lado de la puerta, por la puerta")

	# Companion: ve la ventana delante (y no la ladera ni el aire libre).
	var terrain := Node3D.new()
	add_child(terrain)
	terrain.position = Vector3(0.0, -10000.0, 0.0)
	var player := Node3D.new()
	add_child(player)
	var who := {"id": "path_test", "name": "Colono", "sex": &"male", "look": 102}
	var c := Companion.new()
	c.setup(who, 0, "Prueba", null, Villager.build_model(who, []), terrain, player, Vector3(0, 0.05, 2.0))
	add_child(c)
	c.set_physics_process(false)
	c.global_position = Vector3(0, 0.05, 2.0)
	c.up_direction = Vector3.UP
	await get_tree().physics_frame
	check(c._blocked_ahead(Vector3(0, 0, 60), 58.0, Vector3.UP), "el colono ve la ventana delante")
	check(not c._blocked_ahead(Vector3(0, 0, -60), 62.0, Vector3.UP), "y hacia la puerta, nada")

	print("GROUND PATH: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
