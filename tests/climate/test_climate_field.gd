extends SceneTree

## El campo de frío de CPU (ClimateField) y el de los shaders (climate.gdshaderinc) tienen que dar
## lo mismo: la nieve del suelo y dónde crece la taiga salen de uno y otro. Pinta el frío de N
## puntos en una SubViewport HDR y lo compara con la CPU. Necesita renderer (no --headless).
##   godot --path . -s res://tests/climate/test_climate_field.gd

const CONFIG := "res://data/planet/planet_earth.json"
const POINTS := 256

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var radius: float = config.terrain_settings.radius
	var climate := ClimateField.new(config.climate_settings, radius)
	climate.push_shader_globals()
	_check(climate.enabled, "clima activo")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var points: Array[Vector3] = []
	for i in POINTS:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		points.append(dir * (radius + rng.randf_range(-60.0, 700.0)))

	var viewport := SubViewport.new()
	viewport.size = Vector2i(POINTS, 1)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(POINTS, 1)
	var material := ShaderMaterial.new()
	material.shader = load("res://tests/climate/climate_probe.gdshader")
	var image := Image.create(POINTS, 1, false, Image.FORMAT_RGBF)
	for i in POINTS:
		image.set_pixel(i, 0, Color(points[i].x, points[i].y, points[i].z))
	material.set_shader_parameter("points", ImageTexture.create_from_image(image))
	material.set_shader_parameter("count", POINTS)
	rect.material = material
	viewport.add_child(rect)
	for _i in 4:
		await process_frame
	var result := viewport.get_texture().get_image()
	result.convert(Image.FORMAT_RGBAF)

	var worst := 0.0
	var worst_ice := 0.0
	for i in POINTS:
		var p := points[i]
		var cpu_noise := climate.coldness(p) - ClimateField.abs_latitude(p) \
			- climate.lapse * maxf(p.length() - radius - climate.lapse_base, 0.0)
		var c := result.get_pixel(i, 0)
		var gpu_noise := (c.r - 0.5) * 20.0
		worst = maxf(worst, absf(gpu_noise - cpu_noise))
		var shore := float(i % 5) * 80.0 - 1.0
		worst_ice = maxf(worst_ice, absf(c.g - climate.sea_ice(p, shore)))
	print("frío: diferencia máxima CPU/GPU del ruido %.4f grados" % worst)
	print("hielo marino: diferencia máxima %.4f" % worst_ice)
	_check(worst < 0.02, "ruido del frío igual en CPU y GPU")
	_check(worst_ice < 0.01, "hielo marino igual en CPU y GPU")
	print("CLIMATE FIELD: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FALLO: " + what)
	else:
		print("ok: ", what)
