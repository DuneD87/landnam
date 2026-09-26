extends Node3D

## Pradera de prueba con el VoxelInstancer real y los items del planeta.
## WASD: moverse; Q/E: bajar/subir; Shift: acelerar; Escape: salir.
## --capture: guardar vistas y recorrido, comparar coste con todos los LOD en full.

var _planet: Planet
var _terrain: VoxelLodTerrain
var _camera: Camera3D
var _light: DirectionalLight3D
var _capture_mode: bool = false
var _understory_mode: bool = false
var _sun := Vector3(0.4, 0.8, 0.3).normalized()


func _ready() -> void:
	_capture_mode = "--capture" in OS.get_cmdline_user_args()
	_understory_mode = "--understory" in OS.get_cmdline_user_args()
	var environment := WorldEnvironment.new()
	environment.environment = _build_environment()
	add_child(environment)
	_light = DirectionalLight3D.new()
	add_child(_light)
	_light.look_at(-_sun)
	# Sombras con los mismos ajustes que scenes/maps/sun.tscn. La hierba no las
	# proyecta (cast_shadow=false en los items) pero sí las recibe.
	_light.shadow_enabled = true
	_light.shadow_normal_bias = 2.627
	_light.shadow_opacity = 0.85
	_light.directional_shadow_split_1 = 0.02
	_light.directional_shadow_split_2 = 0.07
	_light.directional_shadow_blend_splits = true
	_light.directional_shadow_fade_start = 0.761
	_light.directional_shadow_max_distance = 1500.0
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
	_terrain.material = meadow_ground_material()
	_planet = Planet.new(_terrain)
	_planet.radius = 30000.0
	_planet.planet_position = _terrain.position
	_planet.sun_dir = _sun
	_planet.wind_direction = Vector3(1, 0, 0.3).normalized()
	var config := JSON.new()
	config.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	var vegetation: Dictionary = config.data.vegetation_settings
	# TODOS los items de hierba, no solo la variante verde: las variantes amarillas
	# tienen su propio material y su propio color, así que un preview que carga una
	# sola no sirve para juzgar el aspecto de la pradera. Se cargan también las
	# capas lejanas para ver el relevo completo.
	var item_index := 0
	for item in vegetation.items:
		if item.has("grass_lods") or (_understory_mode and item.has("understory_lods")):
			await _planet._load_vegetation_item(item_index, item, vegetation.generators, [])
			item_index += 1
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


## Suelo del bioma verde con la textura y la escala triplanar del terreno del planeta
## (texture_scale 0.5 en planet_biomes.gdshader). Con un color liso, los claros entre
## matas parecían agujeros y no el césped corto que se ve en el juego.
static func meadow_ground_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var folder := "res://textures/terrain/whispy-grass-meadow-bl/"
	material.albedo_texture = load(folder + "wispy-grass-meadow_albedo.png")
	material.normal_enabled = true
	material.normal_texture = load(folder + "wispy-grass-meadow_normal-ogl.png")
	material.roughness = 1.0
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


## Copia del entorno de scenes/maps/sun.tscn. El sombreado de la hierba se juzga
## DESPUÉS del tonemap y del glow, así que un entorno lineal y sin bloom hacía que
## el preview aprobara ajustes que en el juego se queman. Lo único que no se
## reproduce es el cielo: el juego usa el shader de espacio y aquí basta un color
## plano, que además deja la silueta de la mata más legible. El ambiente del juego
## sale del cielo del observador (SkyLighting); aquí se fija el de un mediodía
## despejado, que es con el que se ajusta la hierba.
func _build_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.38, 0.52, 0.67)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.26, 0.35)
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.07
	env.glow_strength = 0.5
	env.glow_bloom = 0.51
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_enabled = true
	env.fog_density = 1.0
	env.fog_depth_begin = 0.0
	env.fog_depth_end = 4000.0
	return env


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
	if _understory_mode:
		DirAccess.make_dir_recursive_absolute("res://build/understory")
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
	await _capture_backlit()
	print("GRASS NATIVE PREVIEW COMPLETE")
	get_tree().quit()


## Sol rasante justo delante de la cámara: es la única vista donde se enciende la
## transmisión de la hoja, así que sin ella el contraluz quedaría sin comprobar.
func _capture_backlit() -> void:
	var low_sun := Vector3(0.0, 0.12, -1.0).normalized()
	_sun = low_sun
	_light.look_at(-low_sun)
	_planet.sun_dir = low_sun
	_planet._update_planet()
	_camera.position.y = 0.55
	_camera.look_at(_camera.position + Vector3(0.0, 0.08, -1.0))
	await get_tree().create_timer(0.5).timeout
	await _save("native_backlit")


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var directory: String = "understory" if _understory_mode else "grass_lods"
	get_viewport().get_texture().get_image().save_png("res://build/%s/%s.png" % [directory, name])
	print("CAPTURE ", name)


func _exit_tree() -> void:
	if is_instance_valid(_planet):
		_planet.free()
