extends Node3D

## Render fixture: runs independently of the large planet scene.
## Add -- --capture to save the model and blood stages under build/fauna/ and quit.
class PreviewWater extends WaterFaunaHabitat:
	func surface_radius(_point: Vector3) -> float:
		return 10000.0

var _water: PreviewWater


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("123b49")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c7e9ed")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 1.4
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 8)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.2
	add_child(camera)
	camera.current = true
	for i in SimpleFishMesh.TYPES.size():
		var fish := MeshInstance3D.new()
		fish.mesh = SimpleFishMesh.mesh(i)
		fish.material_override = SimpleFishMesh.material()
		fish.position = Vector3((i % 3 - 1) * 1.8, 1.0 - float(i / 3) * 1.6, 0)
		fish.rotation_degrees = Vector3(0, 72, -3 + i)
		add_child(fish)
		fish.set_instance_shader_parameter("fish_type", i)
		fish.set_instance_shader_parameter("swim_phase", float(i))
		var label := Label3D.new()
		label.text = SimpleFishMesh.TYPES[i].name
		label.position = fish.position + Vector3(0, -0.64, 0.1)
		label.font_size = 42
		label.pixel_size = 0.003
		label.modulate = Color("c4dde0")
		label.outline_size = 0
		add_child(label)
	var terrain := VoxelLodTerrain.new()
	add_child(terrain)
	_water = PreviewWater.new()
	_water.terrain = terrain
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://build/fauna")
		await get_tree().create_timer(0.5).timeout
		await _capture("fish_species")
		_water.burst_blood(Vector3(0, -1.65, 0))
		await get_tree().create_timer(0.6).timeout
		await _capture("blood_early")
		await get_tree().create_timer(1.0).timeout
		await _capture("blood_dispersing")
		await get_tree().create_timer(1.8).timeout
		await _capture("blood_dissipated")
		get_tree().quit()
	else:
		while is_inside_tree():
			_water.burst_blood(Vector3(0, -1.65, 0))
			await get_tree().create_timer(4.0).timeout


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var file := "res://build/fauna/%s.png" % label
	var error := get_viewport().get_texture().get_image().save_png(file)
	print("FAUNA PREVIEW: ", file, " result=", error)
