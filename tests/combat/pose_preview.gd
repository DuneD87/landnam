extends SceneTree

## Poses de combate y agarre de las armas sobre el cuerpo real del personaje.
##   godot --path . --script res://tests/combat/pose_preview.gd -- --tag=x
## Guarda build/combat/poses_<tag>.png (cuadrícula de casos) y cierra.

const MODEL := "res://scenes/character/character_model.tscn"

var _tag := "preview"

## nombre: {anim, t, pose (dict de CombatPose), weapon, left (arma en mano izq.)}
var CASES := [
	{"name": "idle_sword", "anim": "idle", "t": 0.5, "weapon": "iron_sword"},
	{"name": "h_wind", "anim": "attack_horizontal", "t": 0.62, "weapon": "iron_sword"},
	{"name": "h_hit", "anim": "attack_horizontal", "t": 0.9, "weapon": "iron_sword"},
	{"name": "v_hit", "anim": "attack_vertical", "t": 0.82, "weapon": "battle_axe"},
	{"name": "idle_mace", "anim": "running", "t": 0.3, "weapon": "iron_mace"},
	{"name": "tuck", "anim": "idle", "t": 0.5, "pose": {"tuck": 1.0}},
	{"name": "bow_rest", "anim": "idle", "t": 0.5, "pose": {"aim_weight": 1.0, "aim_style": &"bow", "draw": 0.0}, "bow": true},
	{"name": "bow_full", "anim": "idle", "t": 0.5, "pose": {"aim_weight": 1.0, "aim_style": &"bow", "draw": 1.0}, "bow": true},
	{"name": "sling", "anim": "idle", "t": 0.5, "pose": {"aim_weight": 1.0, "aim_style": &"sling", "draw": 1.0}},
	{"name": "throw", "anim": "idle", "t": 0.5, "pose": {"aim_weight": 1.0, "aim_style": &"throw", "draw": 1.0}, "weapon": "spear"},
	{"name": "release", "anim": "idle", "t": 0.5, "pose": {"aim_weight": 1.0, "aim_style": &"throw", "draw": 1.0, "release": 1.0}, "weapon": "spear"},
	{"name": "death", "anim": "idle", "t": 0.5, "pose": {"death": 1.0}},
]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
	_run.call_deferred()


func _run() -> void:
	var cell := Vector2i(360, 480)
	var cols := 6
	var rows := int(ceil(CASES.size() / float(cols)))
	root.size = Vector2i(cell.x * cols, cell.y * rows)
	var sheet := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGBA8)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.33, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
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
		var player: AnimationPlayer = model.get_node("AnimationPlayer")
		if player.has_animation(c.anim):
			player.play(c.anim)
			player.seek(c.t, true)
			player.pause()
		else:
			push_warning("sin animación " + c.anim)
		var pose := CombatPose.new()
		pose.frame_node = model
		skel.add_child(pose)
		for key in c.get("pose", {}):
			pose.set(key, c.pose[key])
		# Apunta hacia +Z del modelo, un poco hacia abajo.
		pose.aim_dir = (model.global_basis * Vector3(0, -0.05, 1)).normalized()
		if c.has("weapon"):
			var att := BoneAttachment3D.new()
			att.bone_name = "mixamorig_RightHandMiddle2"
			skel.add_child(att)
			var grip := Node3D.new()
			grip.transform = CombatPose.RIGHT_GRIP
			att.add_child(grip)
			grip.add_child(load("res://scenes/items/weapons/combat/%s.tscn" % c.weapon).instantiate())
		if c.get("bow", false):
			var bow: Node3D = load("res://scenes/items/weapons/combat/hunting_bow.tscn").instantiate()
			world.add_child(bow)
			pose.after_pose = func(p: CombatPose) -> void:
				var hand := p.bone_world("mixamorig_LeftHand")
				var z := p.aim_dir
				var y := (model.global_basis.y - z * model.global_basis.y.dot(z)).normalized()
				bow.global_transform = Transform3D(Basis(y.cross(z), y, z), hand + z * 0.02)
				(bow as RangedWeaponVisual).set_draw_point(p.bone_world("mixamorig_RightHandMiddle1") if p.draw > 0.01 else null)
		# Cámara de tres cuartos por delante-derecha.
		var target := model.global_position + Vector3(0, 1.0, 0)
		var eye := target + Vector3(-2.2, 0.35, 2.6) * (0.85 if c.name != "death" else 1.0)
		if c.name in ["bow_rest", "bow_full", "sling", "throw", "release"]:
			eye = target + Vector3(-3.2, 0.5, 0.2)
		cam.look_at_from_position(eye, target)
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((i % cols) * cell.x, (i / cols) * cell.y))
		print("case ", c.name)
		model.queue_free()
		for node in world.get_children():
			if node is RangedWeaponVisual:
				node.queue_free()
		await process_frame
	var path := "res://build/combat/poses_%s.png" % _tag
	sheet.save_png(path)
	print("saved ", path)
	quit()
