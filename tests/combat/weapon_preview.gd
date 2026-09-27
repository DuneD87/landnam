extends SceneTree

## Galería de las armas de combate (mallas de WeaponMeshes) con luz de estudio.
##   godot --path . --script res://tests/combat/weapon_preview.gd -- --tag=x
## Guarda build/combat/weapons_<tag>.png y cierra.

var _tag := "preview"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1800, 1000)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.20, 0.22, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	scene.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.8
	scene.add_child(rim)
	var items := [
		["sword", WeaponMeshes.sword()],
		["axe", WeaponMeshes.battle_axe()],
		["mace", WeaponMeshes.mace()],
		["spear", WeaponMeshes.spear()],
		["bow", WeaponMeshes.bow()],
		["sling", WeaponMeshes.slingshot()],
		["arrow", WeaponMeshes.arrow()],
		["pebble", WeaponMeshes.pebble()],
	]
	var x := -2.1
	for entry in items:
		var mi := MeshInstance3D.new()
		mi.mesh = entry[1]
		scene.add_child(mi)
		var scale := 1.0
		if entry[0] == "spear":
			scale = 0.55
		elif entry[0] == "sling":
			scale = 3.0
		elif entry[0] == "pebble":
			scale = 6.0
		elif entry[0] == "arrow":
			scale = 1.2
		# Filo hacia la cámara ladeado para ver volumen.
		mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-65)).scaled(Vector3.ONE * scale), Vector3(x, -0.1, 0))
		x += 0.6
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.1, 3.4)
	cam.fov = 45
	scene.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://build/combat/weapons_%s.png" % _tag
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	# Primer plano de la espada y el hacha.
	cam.position = Vector3(-1.8, 0.25, 1.1)
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/combat/weapons_%s_close.png" % _tag)
	quit()
