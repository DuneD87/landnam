extends SceneTree

## El cuerpo visto en primera persona: la cámara en el ojo que da CharacterAppearanceRig, como
## CameraController, sobre varias animaciones y mirando más o menos abajo; y desde fuera, el
## cuerpo sin cabeza que ve la cámara con la sombra entera.
##   godot --path . --script res://tests/character/first_person_preview.gd -- --tag=x
## Guarda build/character/first_person_<tag>.png (cuadrícula de casos) y cierra. Necesita ventana.

const MODEL := "res://scenes/character/character_model.tscn"
## Lo que se adelanta la cámara del punto entre los ojos (CameraController.fp_eye_forward).
const EYE_FORWARD := -0.1

var _tag := "preview"
## Encara el cuerpo a la vista (FirstPersonSquare), como en el juego; `--loose` lo quita.
var _square := true

## nombre: {anim, t, pitch (grados, negativo hacia abajo), weapon, outside (vista desde fuera)}
var CASES := [
	{"name": "ahead", "anim": "idle", "t": 0.5, "pitch": 0.0, "weapon": "iron_sword"},
	{"name": "down_40", "anim": "idle", "t": 0.5, "pitch": -40.0, "weapon": "iron_sword"},
	{"name": "down_70", "anim": "idle", "t": 0.5, "pitch": -70.0, "weapon": "iron_sword"},
	{"name": "run_down_30", "anim": "running", "t": 0.3, "pitch": -30.0, "weapon": "iron_mace"},
	{"name": "swing", "anim": "attack_horizontal", "t": 0.62, "pitch": -10.0, "weapon": "iron_sword"},
	# El combo de espada y el pesado: la cara se va hasta 70° de la mirada, y el pesado da la vuelta.
	{"name": "combo_1_hit", "anim": "combat/sword_combo", "t": 1.0, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "combo_2_turn", "anim": "combat/sword_combo", "t": 1.45, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "combo_2_hit", "anim": "combat/sword_combo", "t": 2.1, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "combo_3_wind", "anim": "combat/sword_combo", "t": 2.5, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "combo_3_hit", "anim": "combat/sword_combo", "t": 3.1, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "heavy_spin", "anim": "combat/sword_heavy", "t": 0.7, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "heavy_air", "anim": "combat/sword_heavy", "t": 1.0, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "heavy_hit", "anim": "combat/sword_heavy", "t": 1.3, "pitch": -10.0, "weapon": "iron_sword"},
	{"name": "outside", "anim": "idle", "t": 0.5, "pitch": 0.0, "weapon": "iron_sword", "outside": true},
]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg == "--loose":
			_square = false
	_run.call_deferred()


func _run() -> void:
	var cell := Vector2i(640, 360)
	var cols := 3
	var rows := int(ceil(CASES.size() / float(cols)))
	var sheet := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGBA8)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.55, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -150, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.42, 0.4, 0.33)
	ground.material_override = ground_mat
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 75
	cam.near = 0.01
	world.add_child(cam)
	cam.current = true
	root.size = cell
	for i in CASES.size():
		var c: Dictionary = CASES[i]
		var model: Node3D = load(MODEL).instantiate()
		world.add_child(model)
		var skel: Skeleton3D = model.get_node("Armature/Skeleton3D")
		var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
		rig.apply(CharacterAppearance.new())
		rig.set_first_person(true)
		if _square and not c.get("outside", false):
			var square := FirstPersonSquare.new()
			square.frame_node = model
			skel.add_child(square)
		var player: AnimationPlayer = model.get_node("AnimationPlayer")
		if not player.has_animation_library(&"combat"):
			player.add_animation_library(&"combat", load("res://models/player/mixamo/combat_anims.tres"))
		if player.has_animation(c.anim):
			player.play(c.anim)
			player.seek(c.t, true)
			player.pause()
		else:
			push_warning("sin animación " + c.anim)
		if c.has("weapon"):
			var att := BoneAttachment3D.new()
			att.bone_name = "mixamorig_RightHandMiddle2"
			skel.add_child(att)
			var grip := Node3D.new()
			grip.transform = CombatPose.RIGHT_GRIP
			att.add_child(grip)
			grip.add_child(load("res://scenes/items/weapons/combat/%s.tscn" % c.weapon).instantiate())
		# El ojo de la pose final, como CameraController._place_on_head.
		var head := skel.find_bone(CharacterAppearanceRig.HEAD_BONE)
		var eye := [Vector3.ZERO]
		var track := func() -> void:
			eye[0] = skel.global_transform * (skel.get_bone_global_pose(head) * rig.first_person_eye(EYE_FORWARD))
		skel.skeleton_updated.connect(track)
		for f in 3:
			await process_frame
		var forward := model.global_basis.z
		var up := model.global_basis.y
		if c.get("outside", false):
			var target := model.global_position + Vector3(0, 0.9, 0)
			cam.fov = 50
			cam.look_at_from_position(target + Vector3(-2.6, 0.9, 2.4), target)
		else:
			var pitch := deg_to_rad(c.pitch)
			var look := forward * cos(pitch) + up * sin(pitch)
			cam.fov = 75
			cam.look_at_from_position(eye[0], eye[0] + look, up)
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((i % cols) * cell.x, (i / cols) * cell.y))
		print("case ", c.name, " eye ", model.global_transform.affine_inverse() * eye[0])
		skel.skeleton_updated.disconnect(track)
		model.queue_free()
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/character")
	var path := "res://build/character/first_person_%s.png" % _tag
	sheet.save_png(path)
	print("saved ", path)
	quit()
