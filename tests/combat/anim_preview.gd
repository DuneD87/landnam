extends SceneTree

## Animaciones de combate de Mixamo (librería "combat", reorientada al jugador) sobre el cuerpo
## real, fotograma a fotograma. Una fila por animación.
##   godot --path . --audio-driver Dummy --script res://tests/combat/anim_preview.gd -- --tag=x [--background] [--only=roll,death]
## Guarda build/combat/anims_<tag>.png y cierra.

const MODEL := "res://scenes/character/character_model.tscn"
const LIBRARY := "res://models/player/mixamo/combat_anims.tres"
var COLS := 8
const CELL := Vector2i(240, 280)

var _tag := "preview"
var _only: PackedStringArray = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
		elif arg.begins_with("--cols="):
			COLS = int(arg.substr(7))
		elif arg == "--background":
			root.unfocusable = true
			root.position = Vector2i(-4000, -4000)
	_run.call_deferred()


func _run() -> void:
	var library: AnimationLibrary = load(LIBRARY)
	var names: Array = []
	for n in library.get_animation_list():
		if _only.is_empty() or String(n) in _only:
			names.append(n)
	root.size = CELL
	var sheet := Image.create(CELL.x * COLS, CELL.y * names.size(), false, Image.FORMAT_RGBA8)
	var world := Node3D.new()
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.45, 0.30)
	plane.material = gm
	ground.mesh = plane
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 45
	world.add_child(cam)
	cam.current = true
	var model: Node3D = load(MODEL).instantiate()
	world.add_child(model)
	(model.get_node("AppearanceRig") as CharacterAppearanceRig).apply(CharacterAppearance.new())
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	player.add_animation_library(&"combat", library)
	for row in names.size():
		var anim_name := "combat/" + String(names[row])
		var anim := player.get_animation(anim_name)
		player.play(anim_name)
		for c in COLS:
			var t := anim.length * c / float(COLS - 1)
			player.seek(t, true)
			player.pause()
			await process_frame
			cam.look_at_from_position(Vector3(-2.6, 1.5, 2.6), Vector3(0, 0.75, 0.3))
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			# Marca de tiempo en la esquina (en décimas), para elegir tramos.
			var tenth := int(round(t * 10.0))
			for d in range(mini(tenth, 60)):
				img.fill_rect(Rect2i(4 + (d % 30) * 7, 4 + (d / 30) * 7, 5, 5), Color(0.1, 0.1, 0.1) if d % 10 != 9 else Color(0.8, 0.1, 0.1))
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, row * CELL.y))
		print("%s %.2f s" % [anim_name, anim.length])
	var path := "res://build/combat/anims_%s.png" % _tag
	sheet.save_png(path)
	print("saved ", path)
	quit()
