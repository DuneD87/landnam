extends SceneTree

## Primera persona sobre el cuerpo real: FirstPersonSquare encara el pecho al frente del modelo
## en los golpes de espada, que sin él lo tuercen hasta dar la vuelta.
##   godot --headless --path . --script res://tests/character/test_first_person.gd

const MODEL := "res://scenes/character/character_model.tscn"
## Animación y tiempos donde el pecho más se aparta del frente.
const FRAMES := [
	["combat/sword_combo", [0.2, 1.0, 1.45, 2.5, 3.1]],
	["combat/sword_heavy", [0.6, 0.7, 0.8, 1.0]],
]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var loose := await _chest_yaws(false)
	var square := await _chest_yaws(true)
	var widest := 0.0
	var worst := 0.0
	for yaw in loose:
		widest = maxf(widest, absf(yaw))
	for yaw in square:
		worst = maxf(worst, absf(yaw))
	check(widest > 60.0, "the sword moves twist the chest away from the front (%.0f°)" % widest)
	check(worst < 1.0, "FirstPersonSquare keeps the chest to the front through them (%.2f°)" % worst)
	print("FIRST PERSON TESTS: %d failures" % failures)
	quit(1 if failures else 0)


## Giro del pecho (grados, marco del modelo) en cada fotograma de FRAMES, por la línea de los
## hombros de la pose final.
func _chest_yaws(square: bool) -> Array[float]:
	var model: Node3D = load(MODEL).instantiate()
	root.add_child(model)
	var skel: Skeleton3D = model.get_node("Armature/Skeleton3D")
	(model.get_node("AppearanceRig") as CharacterAppearanceRig).apply(CharacterAppearance.new())
	if square:
		var modifier := FirstPersonSquare.new()
		modifier.frame_node = model
		skel.add_child(modifier)
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	player.add_animation_library(&"combat", load("res://models/player/mixamo/combat_anims.tres"))
	var left := skel.find_bone(&"mixamorig_LeftArm")
	var right := skel.find_bone(&"mixamorig_RightArm")
	var yaw := [0.0]
	var measure := func() -> void:
		var to_model := model.global_transform.affine_inverse() * skel.global_transform
		var across := to_model * skel.get_bone_global_pose(left).origin - to_model * skel.get_bone_global_pose(right).origin
		var forward := across.cross(Vector3.UP)
		yaw[0] = rad_to_deg(atan2(forward.x, forward.z))
	skel.skeleton_updated.connect(measure)
	var yaws: Array[float] = []
	for frames in FRAMES:
		player.play(frames[0])
		player.pause()
		for t in frames[1]:
			player.seek(t, true)
			await process_frame
			await process_frame
			yaws.append(yaw[0])
	model.queue_free()
	return yaws
