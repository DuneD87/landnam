extends Node3D

## Coronar y subirse a paredes bajas, contra cajas como las de una construcción de bloques: dónde
## acaba de pie (encima de un muro fino, no al otro lado; donde lleva el clip en una cima ancha), por
## dónde empieza el clip en una pared baja, lo que no se sube y que el marco del clip sale de la
## cadera del personaje y acaba en el suelo.
##   godot --headless --path . res://tests/player/test_climb.tscn

## La cara de las paredes, mirando a -Z; el jugador delante, a su radio.
const FACE_Z := 1.0

var failures := 0
var _boxes: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var menu := Control.new()
	add_child(menu)
	var save_button := Button.new()
	save_button.name = "btnSaveGame"
	menu.add_child(save_button)
	save_button.owner = menu
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	player.gravity_direction = Vector3.DOWN
	var climb := player.climb
	climb._sample_hips_path()
	check(not climb._hips_path.is_empty(), "climb_top tiene el recorrido de la cadera")
	if climb._hips_path.is_empty():
		_finish()
		return
	check(climb._top_end > 2.5 and climb._top_end < climb._hips_path.size() / ClimbController.PATH_FPS,
		"coronar acaba al quedarse de pie (%.2f s), no al final del clip" % climb._top_end)

	# Colgado en lo alto de un muro de 0,5 m de grueso y 2,6 m de alto.
	await _build([[Vector3(0.0, 1.3, FACE_Z + 0.25), Vector3(4.0, 2.6, 0.5)]])
	var stand: Variant = _crown(player, 2.6 - 1.75, true)
	check(stand != null, "corona un muro fino")
	if stand != null:
		check(absf(stand.y - 2.6) < 0.05 and stand.z > FACE_Z and stand.z < FACE_Z + 0.5,
			"acaba de pie encima del muro fino (%s)" % stand)
		_check_frame(player, "muro fino")

	# Lo mismo en un bloque de 3 m de fondo: donde lleva el clip.
	await _build([[Vector3(0.0, 1.3, FACE_Z + 1.5), Vector3(4.0, 2.6, 3.0)]])
	stand = _crown(player, 2.6 - 1.75, true)
	check(stand != null and absf(stand.y - 2.6) < 0.05 and stand.z > FACE_Z + 0.8,
		"en una cima ancha acaba donde lleva el clip (%s)" % stand)

	# Desde el suelo, una cornisa de 1,3 m: sin colgarse, con el clip empezado a esa altura.
	await _build([[Vector3(0.0, 0.65, FACE_Z + 1.5), Vector3(4.0, 1.3, 3.0)]])
	stand = _crown(player, 0.0, false)
	check(stand != null and absf(stand.y - 1.3) < 0.05, "se sube a una cornisa de 1,3 m (%s)" % stand)
	if stand != null:
		var start := roundi(climb._top_t * ClimbController.PATH_FPS)
		check(start > 0, "el clip no empieza colgado (%.2f s)" % climb._top_t)
		check(absf(climb._hips_path[start].y - (climb._hips_world().y - 1.3)) < 0.1,
			"y empieza con la cadera a su altura sobre el borde")
		_check_frame(player, "cornisa baja")

	# Un muro de 1,3 m y 0,25 m con suelo detrás: encima del muro, no al otro lado.
	await _build([[Vector3(0.0, 0.65, FACE_Z + 0.125), Vector3(4.0, 1.3, 0.25)]])
	stand = _crown(player, 0.0, false)
	check(stand != null and absf(stand.y - 1.3) < 0.05 and stand.z < FACE_Z + 0.25,
		"en un muro bajo y fino acaba encima (%s)" % stand)

	# Lo que no: un escalón y una cornisa sin sitio para ponerse de pie (el techo encima no es dónde
	# ponerse: desde el borde no se llega).
	await _build([[Vector3(0.0, 0.2, FACE_Z + 1.5), Vector3(4.0, 0.4, 3.0)]])
	check(_crown(player, 0.0, false) == null, "un escalón no se trepa (lo sube StepUpSystem)")
	await _build([[Vector3(0.0, 0.65, FACE_Z + 1.5), Vector3(4.0, 1.3, 3.0)],
		[Vector3(0.0, 2.3, FACE_Z + 1.5), Vector3(4.0, 0.4, 3.0)]])
	check(_crown(player, 0.0, false) == null, "sin sitio encima no se sube")
	_finish()


## Corona desde [feet_y], colgado o desde el suelo, contra la pared de cara FACE_Z. Devuelve dónde
## acaba de pie, o null si no corona.
func _crown(player: PlayerController, feet_y: float, hanging: bool) -> Variant:
	var climb := player.climb
	climb.cancel()
	player.global_position = Vector3(0.0, feet_y, FACE_Z - climb._radius())
	climb._normal = Vector3.FORWARD
	climb._contact = Vector3(0.0, feet_y + 0.9, FACE_Z)
	climb.mode = ClimbController.Mode.CLIMB if hanging else ClimbController.Mode.NONE
	if not climb._start_top(Vector3.UP):
		climb.mode = ClimbController.Mode.NONE
		return null
	return climb._top_frame.origin


## El marco del clip sale de la cadera del personaje y acaba donde se pone de pie.
func _check_frame(player: PlayerController, what: String) -> void:
	var climb := player.climb
	var t0 := climb._top_t
	var hips := climb._frame_at(t0) * climb._hips_at(t0)
	check(hips.distance_to(climb._hips_world()) < 0.02, "%s: el clip sale de la cadera del personaje" % what)
	var feet := climb._top_body(climb._top_end)
	check(feet.distance_to(climb._top_frame.origin) < 0.06, "%s: y acaba de pie donde toca" % what)


## Deja solo estas cajas estáticas ([centro, tamaño]) y un suelo, y espera a que la física las vea.
func _build(boxes: Array) -> void:
	for body in _boxes:
		body.queue_free()
	_boxes.clear()
	for box in [[Vector3(0.0, -0.25, 0.0), Vector3(20.0, 0.5, 20.0)]] + boxes:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		(shape.shape as BoxShape3D).size = box[1]
		body.add_child(shape)
		body.position = box[0]
		add_child(body)
		_boxes.append(body)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _finish() -> void:
	GameManager.player = null
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)
