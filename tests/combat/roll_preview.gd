extends SceneTree

## Voltereta de esquiva, fotograma a fotograma, sobre un suelo plano: fila de arriba la versión
## anterior (ovillo fijo que gira como una rueda), fila de abajo la actual (posturas clave de
## RollMotion). Con --gif guarda además una animación de cada una. Debajo
## corre la animación de correr, que es con la que se suele rodar. Imprime cuánto se hunde el
## cuerpo en el suelo en cada fase (negativo = atraviesa).
##   godot --path . --audio-driver Dummy --script res://tests/combat/roll_preview.gd -- --tag=x [--background]
## Guarda build/combat/roll_<tag>.png y cierra.

const MODEL := "res://scenes/character/character_model.tscn"
var PHASES := 12
## Con --frames=N guarda N fotogramas sueltos por versión (para montar una animación).
var _save_frames := false
var CELL := Vector2i(230, 300)
## Distancia que recorre la voltereta, para verla avanzar en la tira.
const DISTANCE := 4.4

var _tag := "preview"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--frames="):
			PHASES = int(arg.substr(9))
			_save_frames = true
			CELL = Vector2i(480, 400)
		elif arg == "--background":
			root.unfocusable = true
			root.position = Vector2i(-4000, -4000)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(CELL.x * PHASES, CELL.y * 2)
	var sheet := Image.create(CELL.x * PHASES, CELL.y * 2, false, Image.FORMAT_RGBA8)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.42, 0.52, 0.60)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -60, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.55, 0.45, 0.30)
	# Cuadros de 1 m para que se vea el avance.
	var checker := Image.create(2, 2, false, Image.FORMAT_RGB8)
	checker.set_pixel(0, 0, Color(1, 1, 1))
	checker.set_pixel(1, 1, Color(1, 1, 1))
	checker.set_pixel(1, 0, Color(0.82, 0.82, 0.82))
	checker.set_pixel(0, 1, Color(0.82, 0.82, 0.82))
	ground_mat.albedo_texture = ImageTexture.create_from_image(checker)
	ground_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground_mat.uv1_scale = Vector3(20, 20, 1)
	plane.material = ground_mat
	ground.mesh = plane
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.9
	world.add_child(cam)
	cam.current = true
	root.size = CELL
	# Aquí el cuerpo se mueve fuera del paso de física: sin interpolar, o el render iría un
	# giro por detrás de lo que se mide.
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	for row in 2:
		var old := row == 0
		var worst := INF
		var line := ""
		for i in PHASES:
			var x := float(i) / float(PHASES - 1)
			var model: Node3D = load(MODEL).instantiate()
			world.add_child(model)
			(model.get_node("AppearanceRig") as CharacterAppearanceRig).apply(CharacterAppearance.new())
			var skel: Skeleton3D = model.get_node("Armature/Skeleton3D")
			var anim: AnimationPlayer = model.get_node("AnimationPlayer")
			anim.play("running")
			anim.seek(0.1 + x * 0.6, true)
			anim.pause()
			var body := Node3D.new()
			world.add_child(body)
			model.reparent(body, false)
			body.position = Vector3(0, 0, 0)
			var cache := {}
			var pose := CombatPose.new()
			pose.frame_node = model
			skel.add_child(pose)
			pose.sample_contacts = true
			if old:
				pose.tuck = RollMotion.tuck(x)
			else:
				pose.roll_x = x
			for f in 4:
				await process_frame
				var s: Dictionary = pose.contact_sample
				if not s.is_empty():
					model.transform = RollMotion.model_transform(x, s.points, s.radii, s.pivot)
			await process_frame
			# Hundimiento: el punto más bajo de la carne respecto al suelo (pose ya modificada).
			var s2: Dictionary = {}
			s2 = pose.contact_sample
			var lowest := INF
			for k in s2.points.size():
				lowest = minf(lowest, (model.transform * s2.points[k]).y - s2.radii[k])
			worst = minf(worst, lowest)
			line += "%+.2f " % lowest
			# De lado (desde la derecha del personaje), algo por encima del suelo; en modo
			# animación, de tres cuartos y siguiendo el avance de la voltereta.
			var center := body.global_position + Vector3(0, 0.75, 0)
			if _save_frames:
				# Avanza lo que avanza la voltereta y la cámara lo sigue de tres cuartos.
				body.position.z = DISTANCE * (1.0 - pow(1.0 - x, 2.2))
				center = body.global_position + Vector3(0, 0.6, 0)
				cam.look_at_from_position(center + Vector3(-3.0, 1.1, -1.4), center)
			else:
				cam.look_at_from_position(center + Vector3(-6.0, 1.1, 0.0), center)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, row * CELL.y))
			if _save_frames:
				DirAccess.make_dir_recursive_absolute("res://build/combat/roll_frames")
				img.save_png("res://build/combat/roll_frames/%s_%s_%03d.png" % [_tag, "static" if old else "keys", i])
			body.queue_free()
			await process_frame
		print("%s hundimiento por fase (m): %s  peor %+.2f" % ["ESTÁTICA" if old else "CLAVES  ", line, worst])
	var path := "res://build/combat/roll_%s.png" % _tag
	sheet.save_png(path)
	print("saved ", path)
	quit()
