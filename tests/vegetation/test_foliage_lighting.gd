extends SceneTree

## Ejecutar con renderer gráfico: comprueba ambas caras con el shader de producción.
## Una hoja invertida debe recibir la misma luz frontal, y oscurecerse al quedar
## a espaldas de la luz. No utiliza normales/colores de un shader de diagnóstico.
var _failures: int = 0
var _sample_index: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 2, 1)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var sun := DirectionalLight3D.new()
	viewport.add_child(sun)
	sun.look_at(-Vector3(0, 1, 0.2).normalized())
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/grass_wind.gdshader")
	if "--normal-debug" in OS.get_cmdline_user_args():
		var debug_shader := Shader.new()
		debug_shader.code = "shader_type spatial; render_mode cull_disabled, unshaded; void fragment() { ALBEDO = NORMAL * 0.5 + 0.5; }"
		material.shader = debug_shader
	for key in ["wind_speed", "base_occlusion", "ground_tint_amount", "variation_value",
		"variation_hue", "blade_variation", "dry_amount", "blade_curvature",
		"near_normal_strength", "distant_normal_strength", "ambient_intensity",
		"diffuse_wrap", "transmission_strength", "specular_strength", "fade_start", "fade_end"]:
		material.set_shader_parameter(key, 0.0)
	material.set_shader_parameter("base_color", Color(0.5, 0.5, 0.5))
	material.set_shader_parameter("tip_color", Color(0.5, 0.5, 0.5))
	material.set_shader_parameter("planet_position", Vector3(0, -30000, 0))
	material.set_shader_parameter("light_direction", Vector3.UP)
	var leaf := MeshInstance3D.new()
	leaf.mesh = PlaneMesh.new()
	leaf.material_override = material
	viewport.add_child(leaf)
	var front: float = await _luminance(viewport)
	leaf.rotation.x = PI
	var back: float = await _luminance(viewport)
	_check(front > 0.15, "La cara frontal recibe luz")
	_check(absf(front - back) < 0.03, "El reverso se orienta una sola vez: frente=%f reverso=%f" % [front, back])
	sun.look_at(Vector3(0, 1, -0.2).normalized())
	var unlit: float = await _luminance(viewport)
	_check(unlit < front * 0.10, "La normal opuesta a la luz no se ilumina: %f" % unlit)
	sun.light_energy = 0.0
	var dark: float = await _luminance(viewport)
	_check(dark < 0.01, "Sin luz ni relleno, la hoja queda oscura")
	print("FOLIAGE LIGHTING front=", front, " back=", back, " unlit=", unlit, " dark=", dark)
	viewport.queue_free()
	await process_frame
	print("FOLIAGE LIGHTING TESTS: %d failures" % _failures)
	quit(1 if _failures else 0)


func _luminance(viewport: SubViewport) -> float:
	await create_timer(0.3).timeout
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if "--normal-debug" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://build/understory_normals")
		image.save_png("res://build/understory_normals/normal_%d.png" % _sample_index)
		print("NORMAL SAMPLE ", _sample_index, " ", image.get_pixel(64, 64))
		_sample_index += 1
	var total: float = 0.0
	for y in range(56, 72):
		for x in range(56, 72):
			var color: Color = image.get_pixel(x, y)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return total / 256.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
