extends SceneTree

var effect: PlanetAtmosphere
var camera: Camera3D
var water: ShaderMaterial
var world: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _measure(label: String) -> void:
	for i in 24:
		await process_frame
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	for i in 90:
		var start := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("BENCHMARK %s median_ms=%.3f p95_ms=%.3f resolution=%s" % [label, samples[45], samples[85], root.size])
	root.get_texture().get_image().save_png("user://benchmark_" + label + ".png")

func _run() -> void:
	root.size = Vector2i(2560, 1440)
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.008, 0.012, 0.025)
	effect = PlanetAtmosphere.new()
	effect.clouds_enabled = true
	effect.cloud_min_height = 400.0
	effect.cloud_max_height = 700.0
	effect.cloud_coverage = 0.6
	effect.god_rays_enabled = true
	effect.set_planet_data(Vector3.ZERO, 30000.0, 33000.0, Vector3(0.2, 1.0, -0.3).normalized())
	var compositor := Compositor.new()
	compositor.compositor_effects = [effect]
	environment.compositor = compositor
	world.add_child(environment)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 29946, 0)
	camera.current = true
	camera.far = 10000.0
	water = ShaderMaterial.new()
	water.shader = load("res://shaders/liquid/underwater.gdshader")
	var settings := {"water_radius": 29950.0, "planet_center": Vector3.ZERO,
		"waterline_point": Vector3(0, 29950, 0), "waterline_normal": Vector3.UP,
		"wave_amplitude": 2.5, "wave_calm_amplitude": 2.5, "wave_base_length": 60.0,
		"wave_steepness": 0.5, "shore_amplitude": 0.0,
		"godray_intensity": 1.0, "godray_samples": 24, "godray_surface_focus": 4.0,
		"godray_pattern_scale": 0.15, "godray_sharpness": 6.0,
		# Sin esta textura el bloque de haces está capado y la medida no incluía
		# lo más caro del efecto: 24 pasos con una consulta al caché cada uno.
		"caustics_texture": load("res://textures/planet/water/caust00.png"),
		"caustics_scale": 0.5, "caustics_intensity": 0.8,
		"fog_color": Color("245661"), "deep_fog_color": Color("0f303f"),
		"abyss_fog_color": Color("030c16"),
		"absorption_coefficients": Vector3(0.45, 0.18, 0.06),
		"sun_direction": Vector3(0.35, 0.9, 0.0).normalized()}
	for key in settings:
		water.set_shader_parameter(key, settings[key])
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.scale = Vector3(1000, 1, 1000)
	floor_mesh.position.y = 29925
	var floor_material := StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.albedo_color = Color(0.35, 0.28, 0.17)
	floor_mesh.material_override = floor_material
	world.add_child(floor_mesh)
	# Match the two procedural normal textures in WaterSphere_material.tres.
	var detail_maps: Array[NoiseTexture2D] = []
	for seed_value in [0, 1337]:
		var map := NoiseTexture2D.new()
		var noise := FastNoiseLite.new()
		noise.seed = seed_value
		map.noise = noise
		map.seamless = true
		map.as_normal_map = true
		map.bump_strength = 4.0
		map.seamless_blend_skirt = 1.0
		map.normalize = seed_value != 0
		await map.changed
		detail_maps.append(map)
	for label in ["up", "horizon"]:
		camera.look_at(camera.position + (Vector3(0, 0.8, -0.6) if label == "up" else Vector3(0, 0.1, -1.0)), Vector3.UP)
		effect.underwater_pass.update_material(null)
		await _measure(label + "_air")
		effect.underwater_pass.update_material(water)
		await _measure(label + "_water")
		water.set_shader_parameter("texture_normal", detail_maps[0])
		water.set_shader_parameter("texture_normal2", detail_maps[1])
		effect.underwater_pass.update_material(water)
		await _measure(label + "_water_detail")
		# Los haces son lo único opcional caro que queda: 24 pasos con una consulta al
		# caché cada uno. Se mide encendido contra apagado, con todo lo demás igual.
		# OJO: hoy este escenario mide lo MISMO que el anterior (1.59 vs 1.59, 0.90 vs 0.91).
		# Comparando los dos fotogramas píxel a píxel la diferencia es ~0.00001, o sea que
		# los haces no llegan a ejecutarse en este banco aunque la textura de cáusticas y
		# sun_direction estén puestas. La sonda de shaders/liquid SÍ los dibuja con la misma
		# configuración, así que el coste de los 24 pasos queda SIN MEDIR: no es cero, es
		# desconocido. Antes de fiarse de este número hay que averiguar por qué no disparan.
		water.set_shader_parameter("godray_intensity", 0.0)
		effect.underwater_pass.update_material(water)
		await _measure(label + "_water_detail_nogodray")
		water.set_shader_parameter("godray_intensity", 1.0)
		effect.underwater_pass.update_material(water)
		water.set_shader_parameter("texture_normal", null)
		water.set_shader_parameter("texture_normal2", null)
	compositor.compositor_effects = []
	effect = null
	world.queue_free()
	await process_frame
	await process_frame
	print("UNDERWATER_BENCHMARK_DONE")
	quit()
