extends Node3D

var birds: Array[SimpleBirdModel] = []
var elapsed := 0.0


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("243e4c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("dbe8eb")
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.3
	add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.position = Vector3(0, 1.65, 3.5)
	add_child(camera)
	camera.look_at(Vector3(0, 0.15, 0))
	camera.current = true
	for i in 2:
		var bird := SimpleBirdModel.new()
		bird.position = Vector3((i - 0.5) * 1.8, -0.08, 0)
		bird.rotation_degrees.y = -130
		add_child(bird)
		bird.set_species(i + 3)
		birds.append(bird)
		var label := Label3D.new()
		label.text = SimpleBirdModel.NAMES[i + 3]
		label.font_size = 48
		label.pixel_size = 0.0025
		label.outline_size = 0
		label.position = Vector3(bird.position.x, 0.1, 1.2)
		add_child(label)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("2d7083")
	material.roughness = 0.3
	plane.material = material
	water.mesh = plane
	add_child(water)
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://build/fauna")
		await get_tree().create_timer(0.5).timeout
		await capture("water_birds_resting")
		set_process(false)
		for bird in birds:
			bird.position.y = 0.25
			bird.animate(0.0, true, 1.0)
		await capture("water_birds_flying")
		get_tree().quit()


func _process(delta: float) -> void:
	elapsed += delta
	for bird in birds:
		bird.animate(elapsed, false, delta)


func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	print("WATER BIRD PREVIEW: ", get_viewport().get_texture().get_image().save_png("res://build/fauna/%s.png" % name))
