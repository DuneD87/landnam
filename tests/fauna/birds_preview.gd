extends Node3D

## Run with -- --capture to save the gallery and an actual branch close-up.
var models: Array[SimpleBirdModel] = []
var elapsed := 0.0


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("233b36")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e5eadb")
	world.environment.ambient_light_energy = 0.75
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.2
	add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(0, 0.55, 3)
	add_child(camera)
	camera.look_at(Vector3(0, 0.13, 0))
	camera.current = true
	var gallery := Node3D.new()
	add_child(gallery)
	for i in 3:
		var bird := SimpleBirdModel.new()
		bird.position.x = (i - 1) * 0.8
		bird.rotation_degrees.y = -130
		gallery.add_child(bird)
		bird.set_species(i)
		models.append(bird)
		var branch := MeshInstance3D.new()
		var wood := CylinderMesh.new()
		wood.top_radius = 0.035
		wood.bottom_radius = 0.05
		wood.height = 0.52
		wood.radial_segments = 7
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("795a3d")
		wood.material = mat
		branch.mesh = wood
		branch.rotation.z = PI / 2
		branch.position = bird.position + Vector3(0, -0.033, 0)
		gallery.add_child(branch)
		var label := Label3D.new()
		label.text = SimpleBirdModel.NAMES[i]
		label.font_size = 44
		label.pixel_size = 0.0017
		label.outline_size = 0
		label.position = bird.position + Vector3(0, -0.16, 0.1)
		gallery.add_child(label)
	if "--capture" not in OS.get_cmdline_user_args():
		return
	DirAccess.make_dir_recursive_absolute("res://build/fauna")
	await get_tree().create_timer(0.5).timeout
	await _capture("bird_species")
	for bird in models:
		bird.animate(0.12, true, 1.0)
	set_process(false)
	await _capture("bird_wings")
	gallery.hide()
	await _branch_preview(camera)
	get_tree().quit()


func _process(delta: float) -> void:
	elapsed += delta
	for bird in models:
		bird.animate(elapsed, false, delta)


func _branch_preview(camera: Camera3D) -> void:
	var source: Node3D = load("res://scenes/planet/planet_items/vegetation/trees/olive_01.tscn").instantiate()
	var meshes: Array = source.get_child(0).bake_lods()
	var data := TreePerchBaker.bake(meshes[0])
	var tree := MeshInstance3D.new()
	tree.mesh = meshes[0]
	tree.position = Vector3(0, 1000, 0)
	tree.scale = Vector3.ONE * 2.0
	add_child(tree)
	for surface in tree.mesh.get_surface_count():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("80634a") if surface == 0 else Color("729156")
		mat.roughness = 1.0
		if surface > 0:
			var old := tree.mesh.surface_get_material(surface) as ShaderMaterial
			if old != null:
				mat.albedo_texture = old.get_shader_parameter("texture_albedo")
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		tree.set_surface_override_material(surface, mat)
	var observer := Node3D.new()
	observer.position = Vector3(0, 1003, 10)
	add_child(observer)
	var habitat := ForestBirdHabitat.new()
	habitat.setup(self, observer)
	habitat.register_tree(tree, data)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var perch := habitat.reserve(get_instance_id(), Vector3(0, 1003, 0), rng)
	assert(not perch.is_empty(), "Preview needs a supported branch")
	var bird := SimpleBirdModel.new()
	add_child(bird)
	bird.set_species(1)
	bird.global_transform = Transform3D(perch.basis, perch.point)
	camera.size = 1.15
	camera.global_position = perch.point + (perch.basis as Basis) * Vector3(1.0, 0.65, -1.5)
	camera.look_at(perch.point + perch.up * 0.15, perch.up)
	await _capture("bird_branch")
	source.free()


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var file := "res://build/fauna/%s.png" % label
	print("BIRD PREVIEW: ", file, " result=", get_viewport().get_texture().get_image().save_png(file))
