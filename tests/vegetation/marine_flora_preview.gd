extends Node3D

## Revisión de la flora sumergida: las cuatro especies a escala, con el vaivén de corriente.
## `--capture` guarda una vista de conjunto y una por especie en build/vegetation/.

const IDS := ["seagrass", "kelp", "sea_fan", "coral"]
const HEIGHTS := {"seagrass": 0.85, "kelp": 4.2, "sea_fan": 1.15, "coral": 0.95}

## Ejemplares por especie: la variación de color solo se juzga en grupo.
const CLUSTER := 9

var _plants: Array[Node3D] = []
var _camera: Camera3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("1b4a58")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("9fd2dc")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62, -35, 0)
	light.light_energy = 1.7
	add_child(light)
	var seabed := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	seabed.mesh = plane
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("6b6a4c")
	seabed.material_override = sand
	add_child(seabed)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	_rng.seed = 9
	for index in IDS.size():
		var id: String = IDS[index]
		var mesh: ArrayMesh = load("res://data/vegetation/marine/%s.res" % id)
		var group := Node3D.new()
		group.position = Vector3((index - 1.5) * 4.5, 0, 0)
		add_child(group)
		var spread: float = 1.1 if id == "seagrass" else 1.6
		for copy in CLUSTER:
			var plant := MeshInstance3D.new()
			plant.mesh = mesh
			# Sin material_override: el material va dentro de la malla, como en el juego,
			# y el tinte por instancia sale de la posición de cada copia.
			plant.position = Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
			plant.rotate_y(_rng.randf_range(0.0, TAU))
			plant.scale = Vector3.ONE * _rng.randf_range(0.7, 1.35)
			group.add_child(plant)
		_plants.append(group)
	_frame(Vector3(0, 1.8, 0), 12.0)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()


func _frame(target: Vector3, extent: float) -> void:
	_camera.position = target + Vector3(0.6, 0.35, 1.0).normalized() * extent
	_camera.look_at(target)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/vegetation")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/vegetation/marine_flora.png")
	for index in _plants.size():
		for other in _plants.size():
			_plants[other].visible = other == index
		var height: float = HEIGHTS[IDS[index]]
		_frame(_plants[index].position + Vector3.UP * height * 0.45, height * 2.6)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/vegetation/%s.png" % IDS[index])
	get_tree().quit()
