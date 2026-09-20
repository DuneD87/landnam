extends Node3D

## Pradera de prueba con el VoxelInstancer real y los items del planeta.
## WASD: moverse; Q/E: bajar/subir; Shift: acelerar; Escape: salir.
## --capture: guardar vistas y recorrido, comparar coste con todos los LOD en full.

var _planet: Planet
var _terrain: VoxelLodTerrain
var _camera: Camera3D
var _capture_mode: bool = false
var _sun := Vector3(0.4, 0.8, 0.3).normalized()


func _ready() -> void:
	_capture_mode = "--capture" in OS.get_cmdline_user_args()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.38, 0.52, 0.67)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.65, 0.72, 0.8)
	environment.environment.ambient_light_energy = 0.2
	add_child(environment)
	var light := DirectionalLight3D.new()
	add_child(light)
	light.look_at(-_sun)
	_terrain = VoxelLodTerrain.new()
	_terrain.name = "GrassTestTerrain"
	_terrain.position.y = -30000.0
	_terrain.lod_count = 5
	_terrain.secondary_lod_distance = 32.0
	_terrain.view_distance = 512
	_terrain.streaming_system = 1
	_terrain.generate_collisions = false
	var generator := VoxelGeneratorFlat.new()
	generator.height = 30000.0
	_terrain.generator = generator
	_terrain.mesher = VoxelMesherTransvoxel.new()
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.16, 0.23, 0.09)
	_terrain.material = ground_material
	_planet = Planet.new(_terrain)
	_planet.radius = 30000.0
	_planet.planet_position = _terrain.position
	_planet.sun_dir = _sun
	_planet.wind_direction = Vector3(1, 0, 0.3).normalized()
	var config := JSON.new()
	config.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	var vegetation: Dictionary = config.data.vegetation_settings
	for item in vegetation.items:
		if item.has("grass_lods") and item.scene.ends_with("/low_poly_grass.tscn"):
			await _planet._load_vegetation_item(0, item, vegetation.generators, [])
	add_child(_terrain)
	_camera = Camera3D.new()
	_camera.far = 1200.0
	add_child(_camera)
	_camera.position = Vector3(8, 1.7, 8)
	_camera.look_at(Vector3(8, 0.8, -100))
	_camera.current = true
	var viewer := VoxelViewer.new()
	viewer.view_distance = 512
	viewer.requires_collisions = false
	_camera.add_child(viewer)
	_planet._update_planet()
	if _capture_mode:
		await _capture()


func _process(delta: float) -> void:
	if _planet != null:
		_planet._update_planet()
	if _camera == null or _capture_mode:
		return
	var direction := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	_camera.position += direction * delta * (35.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0)
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().quit()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/grass_lods")
	# Dejar que el generador y el streaming nativos terminen las bandas iniciales.
	await get_tree().create_timer(6.0).timeout
	await _save("native_ground")
	_camera.position.y = 14.0
	_camera.look_at(Vector3(8, 0, -100))
	await get_tree().create_timer(1.0).timeout
	await _save("native_elevated")
	var lod_triangles: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	# Comparación de carga con idéntica distribución y materiales, todas las mallas full.
	var originals: Array = []
	for id in _planet._next_library_id:
		var item = _planet.voxel_instancer.library.get_item(id)
		var meshes: Array = []
		for lod in 4:
			meshes.append(item.get_mesh(lod))
		originals.append(meshes)
		for lod in 4:
			item.set_mesh(meshes[0], lod)
	await get_tree().create_timer(1.0).timeout
	await _save("native_full_reference")
	var full_triangles: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	print("GRASS DRAW PRIMITIVES lod=", lod_triangles, " full=", full_triangles)
	for id in _planet._next_library_id:
		var item = _planet.voxel_instancer.library.get_item(id)
		for lod in 4:
			item.set_mesh(originals[id][lod], lod)
	_camera.position.y = 1.7
	_camera.look_at(_camera.position + Vector3(0, -0.01, -1))
	# Avanzar cruzando bloques: valida el relevo en movimiento y la actualización de viento.
	for step in 8:
		_camera.position.z -= 6.0
		await get_tree().create_timer(0.35).timeout
		await _save("walk_%02d" % step)
	print("GRASS NATIVE PREVIEW COMPLETE")
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/grass_lods/%s.png" % name)
	print("CAPTURE ", name)


func _exit_tree() -> void:
	if is_instance_valid(_planet):
		_planet.free()
