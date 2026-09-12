extends SceneTree

## Run in an isolated Forward+ project with the atmosphere/water shader assets.
## No terrain, autoloads or scene-specific scripts are needed.
var effect: PlanetAtmosphere
var camera: Camera3D
var material: ShaderMaterial
var world: Node3D
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _frame() -> Image:
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)


func _center(image: Image) -> Color:
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)


func _difference(a: Image, b: Image) -> float:
	var difference := 0.0
	var count := 0
	for y in range(a.get_height() / 4, a.get_height() * 3 / 4, 3):
		for x in range(a.get_width() / 4, a.get_width() * 3 / 4, 3):
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			difference += absf(delta.r) + absf(delta.g) + absf(delta.b)
			count += 3
	return difference / count


func _test_surface_projection() -> void:
	# Flat waves and a black scattering source isolate the sky projected on the
	# roof. It must continue past the old critical cone and fade in world metres.
	material.set_shader_parameter("fog_density", 0.0)
	effect.underwater_pass.update_material(material)
	var samples: Array[float] = []
	for angle in [44.0, 48.0, 52.0, 60.0, 65.0]:
		var a := deg_to_rad(angle)
		camera.look_at(camera.position + Vector3(0, cos(a), -sin(a)), Vector3.UP)
		samples.append(_center(await _frame()).b)
	_check(samples[2] > 0.02 and samples[4] > 0.02,
		"Projected sky continues along the surface beyond the old Snell-cone boundary")
	# The boundary has to be VISIBLE: it is what the ripples break into fragments.
	# A transition spread across the whole vault leaves a smooth gradient with no
	# edge for detail to bite on, which is what made the window read as a bubble.
	var sharp := samples[1] - samples[3]
	material.set_shader_parameter("surface_window_sharpness", 0.0)
	effect.underwater_pass.update_material(material)
	var soft_samples: Array[float] = []
	for angle in [48.0, 60.0]:
		var a := deg_to_rad(angle)
		camera.look_at(camera.position + Vector3(0, cos(a), -sin(a)), Vector3.UP)
		soft_samples.append(_center(await _frame()).b)
	var soft := soft_samples[0] - soft_samples[1]
	material.set_shader_parameter("surface_window_sharpness", 0.8)
	effect.underwater_pass.update_material(material)
	_check(sharp > 0.05 and sharp > soft * 1.3,
		"The critical angle leaves a defined window edge (sharp %.3f vs soft %.3f)" % [sharp, soft])
	var distances: Array[float] = []
	for depth in [4.0, 12.0, 25.0, 40.0]:
		camera.position.y = 1000.0 - depth
		var a := deg_to_rad(65.0)
		camera.look_at(camera.position + Vector3(0, cos(a), -sin(a)), Vector3.UP)
		var frame := await _frame()
		frame.save_png("user://surface_projection_%dm.png" % int(depth))
		# Measure transmission directly: the darker look can legitimately put
		# distant sky radiance below the atmosphere's 0.5% early-out threshold.
		material.set_shader_parameter("debug_mode", 6)
		effect.underwater_pass.update_material(material)
		distances.append(_center(await _frame()).g)
		material.set_shader_parameter("debug_mode", 0)
		effect.underwater_pass.update_material(material)
	_check(distances[0] > distances[1] and distances[1] > distances[2] and distances[2] > distances[3],
		"Surface transmission fades progressively at 4/12/25/40 metres depth (%s)" % str(distances))
	material.set_shader_parameter("fog_density", 1.0)
	effect.underwater_pass.update_material(material)
	camera.position = Vector3(0, 998, 0)
	camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)


func _test_oblique_reflection() -> void:
	# Keep exposure, distance and volume fixed. The surface must selectively
	# suppress oblique sky, while preserving the light directly overhead.
	material.set_shader_parameter("debug_mode", 6)
	material.set_shader_parameter("fog_density", 0.0)
	var normal_incidence: Array[float] = []
	var oblique: Array[float] = []
	var strength: float = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "surface_reflection_strength")
	for reflectivity in [0.0, strength]:
		material.set_shader_parameter("surface_reflection_strength", reflectivity)
		effect.underwater_pass.update_material(material)
		camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)
		normal_incidence.append(_center(await _frame()).g)
		var angle := deg_to_rad(65.0)
		camera.look_at(camera.position + Vector3(0, cos(angle), -sin(angle)), Vector3.UP)
		oblique.append(_center(await _frame()).g)
	_check(normal_incidence[1] > 0.7 and absf(normal_incidence[1] - normal_incidence[0]) < 0.005,
		"Stronger surface reflection preserves the overhead light")
	_check(oblique[1] > 0.02 and oblique[1] < oblique[0] * 0.7,
		"Oblique sky gives way to reflection without an opaque angular cutoff (%.3f -> %.3f)" % [oblique[0], oblique[1]])
	material.set_shader_parameter("debug_mode", 0)
	material.set_shader_parameter("fog_density", 1.0)
	effect.underwater_pass.update_material(material)
	camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)


func _test_distant_surface_join() -> void:
	# Keep the same camera, waterline and medium while moving only the roof beyond
	# the trace budget. A faded roof must converge to the no-roof volume response.
	camera.position = Vector3(0, 980, 0)
	var direction := Vector3(0, cos(deg_to_rad(80.0)), -sin(deg_to_rad(80.0)))
	camera.look_at(camera.position + direction, Vector3.UP)
	material.set_shader_parameter("fog_color", Color("6e8073"))
	material.set_shader_parameter("sun_direction", Vector3.UP)
	material.set_shader_parameter("fog_density", 0.15)
	material.set_shader_parameter("water_radius", 1000.0)
	material.set_shader_parameter("debug_mode", 4)
	effect.underwater_pass.update_material(material)
	var hit := _center(await _frame())
	material.set_shader_parameter("water_radius", 1200.0)
	effect.underwater_pass.update_material(material)
	var miss := _center(await _frame())
	_check(hit.r < 0.05 and hit.g > 0.05 and miss.r > 0.95,
		"Distant join regression straddles an actual surface hit and a trace-budget miss")
	material.set_shader_parameter("debug_mode", 0)
	var receiver := MeshInstance3D.new()
	receiver.mesh = BoxMesh.new()
	receiver.scale = Vector3(10, 10, 10)
	receiver.position = camera.position + direction * 145.0
	var receiver_material := StandardMaterial3D.new()
	receiver_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	receiver_material.albedo_color = Color(0.8, 0.6, 0.4)
	receiver.material_override = receiver_material
	world.add_child(receiver)
	for has_receiver in [false, true]:
		receiver.visible = has_receiver
		material.set_shader_parameter("water_radius", 1000.0)
		effect.underwater_pass.update_material(material)
		var roof := _center(await _frame())
		material.set_shader_parameter("water_radius", 1200.0)
		effect.underwater_pass.update_material(material)
		var volume := _center(await _frame())
		var delta := roof - volume
		_check(maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) < 0.003,
			"Distant surface converges to the same water colour without a seam (geometry=%s)" % has_receiver)
	receiver.queue_free()
	material.set_shader_parameter("fog_color", Color.BLACK)
	material.set_shader_parameter("sun_direction", Vector3.RIGHT)
	material.set_shader_parameter("fog_density", 1.0)
	material.set_shader_parameter("water_radius", 1000.0)
	effect.underwater_pass.update_material(material)
	camera.position = Vector3(0, 998, 0)
	camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)


func _test_shallow_precision() -> void:
	# Flat water must have a smooth Fresnel response even at a 30 km radius.
	# Differentiating cached radial heights used to introduce up to 12% jumps
	# here, with no waves or normal maps enabled. Test away from the axis poles.
	var previous_size := root.size
	root.size = Vector2i(1024, 768)
	var up := Vector3(0.4, 0.8, 0.46).normalized()
	var tangent := up.cross(Vector3.RIGHT).normalized()
	material.set_shader_parameter("water_radius", 29950.0)
	material.set_shader_parameter("waterline_point", up * 29950.0)
	material.set_shader_parameter("waterline_normal", up)
	material.set_shader_parameter("wave_amplitude", 0.0)
	material.set_shader_parameter("wave_calm_amplitude", 0.0)
	material.set_shader_parameter("shore_amplitude", 0.0)
	# Ripple detail off too: this test isolates the CACHE GRID, and per-pixel ripples
	# are genuine structure that would mask the artefact it looks for.
	material.set_shader_parameter("surface_ripple_strength", 0.0)
	material.set_shader_parameter("debug_mode", 6)
	for depth in [0.2, 2.0]:
		camera.position = up * (29950.0 - depth)
		camera.look_at(camera.position + up * 0.8 + tangent * 0.6, up)
		effect.underwater_pass.update_material(material)
		var frame := await _frame()
		frame.save_png("user://underwater_shallow_precision_%sm.png" % depth)
		# A cache grid repeats over a broad area; the critical-angle boundary is one
		# thin arc that legitimately carries a step. Peak curvature alone cannot tell
		# them apart, so what is measured is how WIDESPREAD the abrupt pixels are.
		var maximum := 0.0
		var abrupt := 0
		var samples := 0
		for y in range(30, frame.get_height() - 30, 2):
			for x in range(30, frame.get_width() - 30, 2):
				var curvature := absf(frame.get_pixel(x - 4, y).r + frame.get_pixel(x + 4, y).r \
					- 2.0 * frame.get_pixel(x, y).r)
				maximum = maxf(maximum, curvature)
				samples += 1
				if curvature > 0.02:
					abrupt += 1
		var spread := float(abrupt) / maxf(float(samples), 1.0)
		_check(_center(frame).g > 0.5 and spread < 0.01 and maximum < 0.06,
			"Shallow flat water has no cache-grid Fresnel jumps at %sm (%.2f%% abrupto, max %.4f)"
				% [depth, spread * 100.0, maximum])
	material.set_shader_parameter("surface_ripple_strength", 4.0)
	root.size = previous_size


func _test_waterline_partition() -> void:
	# Exercise the raster/compositor boundary on a planet, not just at the origin.
	# The probe executes the ocean's outside-water discard. Every discarded pixel
	# must be wet in the compositor, with neither a gap nor an overlap.
	var probe := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	probe.mesh = quad
	probe.extra_cull_margin = 100000.0
	var probe_material := ShaderMaterial.new()
	probe_material.shader = load("res://shaders/liquid/underwater_waterline_probe.gdshader")
	probe.material_override = probe_material
	world.add_child(probe)
	var location := Vector3(12000, 24000, 14000)
	var up := location.normalized()
	var forward := up.cross(Vector3.RIGHT).normalized()
	var radius := location.length()
	effect.set_planet_data(Vector3.ZERO, radius, radius + 400, up)
	material.set_shader_parameter("water_radius", radius)
	material.set_shader_parameter("waterline_point", location)
	material.set_shader_parameter("waterline_normal", up)
	material.set_shader_parameter("debug_mode", 1)
	probe_material.set_shader_parameter("waterline_point", location)
	probe_material.set_shader_parameter("waterline_normal", up)
	var mismatches := 0
	for elevation in [-0.02, 0.0, 0.02, 0.08]:
		camera.position = location + up * elevation
		camera.look_at(camera.position + forward - up * 0.15, up)
		probe.position = camera.position + forward
		effect.underwater_pass.update_material(null)
		# Read the raster mask directly; atmospheric light can turn discarded
		# background pixels white and makes a colour threshold ambiguous.
		effect.enabled = false
		var exterior := await _frame()
		effect.enabled = true
		effect.underwater_pass.update_material(material)
		var composed := await _frame()
		exterior.save_png("user://waterline_exterior_%s.png" % elevation)
		composed.save_png("user://waterline_composed_%s.png" % elevation)
		for y in composed.get_height():
			for x in composed.get_width():
				var raster := exterior.get_pixel(x, y)
				var outside := raster.r > raster.g + 0.15
				var c := composed.get_pixel(x, y)
				var wet := c.g > 0.95 and c.r < 0.05
				if outside == wet:
					mismatches += 1
	_check(mismatches == 0, "Exterior water and compositor share the exact waterline at planet scale (%d mismatches)" % mismatches)
	probe.queue_free()


func _test_detail_and_caustics(environment: Environment) -> void:
	# Freeze the macro waves: only the animated surface detail may change the sky.
	material.set_shader_parameter("wave_amplitude", 0.0)
	var pattern := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			pattern.set_pixel(x, y, Color(0.5 + 0.45 * sin(x * TAU / 64.0), 0.5 + 0.45 * cos(y * TAU / 64.0), 1.0))
	pattern.generate_mipmaps()
	material.set_shader_parameter("texture_normal", ImageTexture.create_from_image(pattern))
	material.set_shader_parameter("normal_scale1", 4.0)
	material.set_shader_parameter("water_time", 0.0)
	effect.underwater_pass.update_material(material)
	var normal_a := await _frame()
	material.set_shader_parameter("water_time", 3.0)
	effect.underwater_pass.update_material(material)
	var normal_b := await _frame()
	_check(_difference(normal_a, normal_b) > 0.001, "Broad surface detail animates exit normals with a stationary camera and flat macro waves")
	material.set_shader_parameter("debug_mode", 0)
	camera.look_at(camera.position + Vector3(0, 0.8, -0.6), Vector3.UP)
	# Measure the ray itself: changing exposure or tint cannot satisfy this check.
	# The old clamp made 1.5, the new default, and 8.0 produce identical refraction.
	material.set_shader_parameter("debug_mode", 7)
	var refraction_motion: Array[float] = []
	var default_refraction: float = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "underside_refraction")
	for strength in [0.0, 1.5, default_refraction, 8.0]:
		material.set_shader_parameter("underside_refraction", strength)
		material.set_shader_parameter("water_time", 0.0)
		effect.underwater_pass.update_material(material)
		var direction_a := await _frame()
		material.set_shader_parameter("water_time", 3.0)
		effect.underwater_pass.update_material(material)
		var direction_b := await _frame()
		refraction_motion.append(_difference(direction_a, direction_b))
	_check(refraction_motion[0] < 0.001, "Zero refraction disables ripple displacement")
	_check(refraction_motion[1] > 0.001 and refraction_motion[2] > refraction_motion[1] * 2.0,
		"Default refraction increases animated ray displacement beyond the old 1.5 limit (%s)" % str(refraction_motion))
	_check(refraction_motion[3] > refraction_motion[2] * 1.2,
		"Refraction control remains effective above the default intensity (%s)" % str(refraction_motion))
	material.set_shader_parameter("underside_refraction", default_refraction)
	material.set_shader_parameter("debug_mode", 0)
	effect.underwater_pass.update_material(material)
	var sky_a := await _frame()
	material.set_shader_parameter("water_time", 0.0)
	effect.underwater_pass.update_material(material)
	var sky_b := await _frame()
	_check(_difference(sky_a, sky_b) > 0.001, "Animated detail refracts the atmospheric sky")
	sky_a.save_png("user://underwater_detail_t3.png")
	sky_b.save_png("user://underwater_detail_t0.png")
	# Isolate refraction: a constant input stays constant when facet reflection
	# is disabled. With reflection enabled, the air and water have different
	# radiance, so changing the facets SHOULD change their mixture.
	var reflection_strength: float = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "surface_reflection_strength")
	material.set_shader_parameter("surface_reflection_strength", 0.0)
	var saved_sun := effect.sun_intensity
	var saved_background := environment.background_color
	effect.sun_intensity = 0.0
	environment.background_color = Color(0.35, 0.45, 0.55)
	material.set_shader_parameter("fog_color", Color("6e8073"))
	material.set_shader_parameter("sun_direction", Vector3.UP)
	effect.underwater_pass.update_material(material)
	var constant_a := await _frame()
	material.set_shader_parameter("water_time", 3.0)
	effect.underwater_pass.update_material(material)
	var constant_b := await _frame()
	_check(_difference(constant_a, constant_b) < 0.001,
		"Refraction alone does not paint colour or opacity patches over a uniform sky")
	material.set_shader_parameter("surface_reflection_strength", reflection_strength)
	material.set_shader_parameter("water_time", 0.0)
	effect.underwater_pass.update_material(material)
	var facets_a := await _frame()
	material.set_shader_parameter("water_time", 3.0)
	effect.underwater_pass.update_material(material)
	var facets_b := await _frame()
	_check(_difference(facets_a, facets_b) > 0.002,
		"Resolved wave facets change the mixture of bright air and reflected water")
	facets_a.save_png("user://underwater_facets_t0.png")
	facets_b.save_png("user://underwater_facets_t3.png")
	effect.sun_intensity = saved_sun
	environment.background_color = saved_background
	material.set_shader_parameter("fog_color", Color.BLACK)
	material.set_shader_parameter("sun_direction", Vector3.RIGHT)
	material.set_shader_parameter("water_time", 0.0)
	material.set_shader_parameter("texture_normal", null)
	material.set_shader_parameter("normal_scale1", 8.0)

	# The same world point must receive the same caustic under camera translation
	# and rotation. Disable the medium to isolate projection from path attenuation.
	var original_size := root.size
	root.size = Vector2i(321, 181)
	var receiver := MeshInstance3D.new()
	receiver.mesh = PlaneMesh.new()
	receiver.scale = Vector3(100, 1, 100)
	receiver.position.y = 992.0
	var receiver_material := StandardMaterial3D.new()
	receiver_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	receiver_material.albedo_color = Color(0.2, 0.2, 0.2)
	receiver.material_override = receiver_material
	world.add_child(receiver)
	material.set_shader_parameter("fog_density", 0.0)
	material.set_shader_parameter("sun_direction", Vector3.UP)
	material.set_shader_parameter("caustics_texture", ImageTexture.create_from_image(pattern))
	material.set_shader_parameter("caustics_scale", 0.15)
	material.set_shader_parameter("caustics_depth_fade", 0.0)
	material.set_shader_parameter("caustics_intensity", 1.5)
	var target := Vector3(3.27, 992, 5.13)
	camera.look_at(target)
	effect.underwater_pass.update_material(material)
	var caustic_a := _center(await _frame())
	camera.position = Vector3(15, 997, -7)
	camera.look_at(target)
	var caustic_image := await _frame()
	caustic_image.save_png("user://underwater_caustics_receiver.png")
	var caustic_b := _center(caustic_image)
	_check(absf(caustic_a.g - caustic_b.g) < 0.015, "Caustics stay on the same world point when the camera translates and rotates")
	material.set_shader_parameter("caustics_intensity", 0.0)
	effect.underwater_pass.update_material(material)
	_check(caustic_b.g > _center(await _frame()).g + 0.02, "Caustics illuminate the submerged receiver")
	material.set_shader_parameter("caustics_intensity", 1.5)
	receiver_material.albedo_color = Color.BLACK
	effect.underwater_pass.update_material(material)
	_check(_center(await _frame()).g < 0.005, "Caustics modulate receiver colour instead of painting an additive screen glow")

	# Everything above runs on values chosen to make the mechanism observable. The
	# shipped ones have to light a receiver at a depth a diver actually swims at:
	# a depth fade of 0.7 extinguished the pattern within about three metres, so
	# the effect was wired correctly and still invisible in the game.
	receiver_material.albedo_color = Color(0.2, 0.2, 0.2)
	receiver.position.y = 992.0
	camera.position = Vector3(0, 996, 0)
	camera.look_at(Vector3(2.0, 992, 3.0))
	for name in ["caustics_intensity", "caustics_depth_fade", "caustics_near_fade"]:
		material.set_shader_parameter(name, RenderingServer.shader_get_parameter_default(material.shader.get_rid(), name))
	effect.underwater_pass.update_material(material)
	var shipped := _center(await _frame())
	material.set_shader_parameter("caustics_intensity", 0.0)
	effect.underwater_pass.update_material(material)
	var unlit := _center(await _frame())
	_check(shipped.g > unlit.g * 1.05, "Shipped caustics defaults still light a receiver eight metres down (%.4f vs %.4f)" % [shipped.g, unlit.g])

	receiver.queue_free()
	material.set_shader_parameter("caustics_texture", null)
	material.set_shader_parameter("caustics_intensity", 0.0)
	material.set_shader_parameter("caustics_scale", 2.0)
	material.set_shader_parameter("caustics_depth_fade", 0.7)
	material.set_shader_parameter("fog_density", 1.0)
	material.set_shader_parameter("sun_direction", Vector3.RIGHT)
	camera.position = Vector3(0, 998, 0)
	camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)
	root.size = original_size


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	effect = PlanetAtmosphere.new()
	effect.clouds_enabled = false
	effect.god_rays_enabled = false
	effect.purkinje_strength = 0.0
	effect.set_planet_data(Vector3.ZERO, 1000.0, 1400.0, Vector3(0.2, 1.0, 0.1).normalized())
	var compositor := Compositor.new()
	compositor.compositor_effects = [effect]
	environment.compositor = compositor
	world.add_child(environment)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 998, 0)
	camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)
	camera.current = true
	camera.far = 10000.0
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/liquid/underwater.gdshader")
	var settings := {"water_radius": 1000.0, "planet_center": Vector3.ZERO,
		"waterline_point": Vector3(0, 1000, 0), "waterline_normal": Vector3.UP,
		"wave_amplitude": 0.0, "wave_calm_amplitude": 0.0, "shore_amplitude": 0.0,
		"godray_intensity": 0.0, "caustics_intensity": 0.0, "meniscus_strength": 0.0,
		"fog_color": Color.BLACK, "deep_fog_color": Color.BLACK, "abyss_fog_color": Color.BLACK,
		"absorption_coefficients": Vector3(0.45, 0.18, 0.06)}
	for key in settings:
		material.set_shader_parameter(key, settings[key])
	effect.underwater_pass.update_material(material)
	var shallow := await _frame()
	shallow.save_png("user://underwater_shallow.png")
	var shallow_color := _center(shallow)
	_check(shallow_color.b > 0.02, "Actual atmospheric sky is visible through two metres of water")
	material.set_shader_parameter("godray_intensity", 8.0)
	effect.underwater_pass.update_material(material)
	_check(absf(_center(await _frame()).b - shallow_color.b) < 0.002, "Missing caustics texture cannot create a uniform blue glow")
	material.set_shader_parameter("godray_intensity", 0.0)
	effect.underwater_pass.update_material(material)
	effect.sun_intensity = 0.0
	var dark := _center(await _frame())
	_check(shallow_color.b > dark.b + 0.01, "Underwater sky responds to the atmospheric sun, not a synthetic sky")
	effect.sun_intensity = 20.0
	camera.position.y = 1000.1
	var dry := _center(await _frame())
	_check(dry.b > shallow_color.b, "Dry sky is brighter than the water-attenuated sky")
	camera.position.y = 980.0
	var deep_image := await _frame()
	deep_image.save_png("user://underwater_deep.png")
	var deep := _center(deep_image)
	_check(deep.b < shallow_color.b, "Longer water paths attenuate the real sky")

	# Opaque submerged foreground must block the sky even when it lies above the camera.
	camera.position.y = 998.0
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.scale = Vector3(2.0, 0.2, 2.0)
	blocker.position = Vector3(0, 999, 0)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	blocker.material_override = black
	world.add_child(blocker)
	_check(_center(await _frame()).b < 0.01, "Submerged foreground blocks atmospheric scattering")
	material.set_shader_parameter("fog_color", Color("6e8073"))
	effect.underwater_pass.update_material(material)
	blocker.position.y = 998.3
	var near_fog := _center(await _frame())
	blocker.position.y = 999.7
	var far_fog := _center(await _frame())
	_check(near_fog.b < 0.08 and near_fog.g < 0.08, "Short water paths retain foreground contrast without a coloured veil")
	_check(far_fog.g > near_fog.g + 0.003, "Scattered light builds gradually with water path length")
	material.set_shader_parameter("fog_color", Color.BLACK)
	effect.underwater_pass.update_material(material)
	blocker.queue_free()
	await process_frame
	var glass := MeshInstance3D.new()
	glass.mesh = BoxMesh.new()
	glass.scale = Vector3(2.0, 0.1, 2.0)
	glass.position = Vector3(0, 999, 0)
	var glass_material := ShaderMaterial.new()
	glass_material.shader = load("res://shaders/materials/glass_block.gdshader")
	for key in ["water_radius", "planet_center", "waterline_point", "waterline_normal"]:
		glass_material.set_shader_parameter(key, settings[key])
	glass_material.set_shader_parameter("sky_influence", 0.0)
	glass.material_override = glass_material
	world.add_child(glass)
	var through_glass := _center(await _frame())
	_check(absf(through_glass.b - shallow_color.b) < 0.025, "Submerged glass preserves depth and does not apply water absorption twice")
	glass.queue_free()
	await process_frame

	await _test_surface_projection()
	await _test_oblique_reflection()
	await _test_distant_surface_join()
	effect.clouds_enabled = true
	effect.cloud_min_height = 80.0
	effect.cloud_max_height = 180.0
	effect.cloud_coverage = 0.95
	effect.cloud_density = 2.0
	effect.god_rays_enabled = true
	var clouds := await _frame()
	_check(clouds.get_data() != shallow.get_data(), "Clouds and atmospheric shafts participate in the underwater composition")
	effect.clouds_enabled = false
	effect.god_rays_enabled = false
	material.set_shader_parameter("wave_amplitude", 2.0)
	material.set_shader_parameter("debug_mode", 3)
	effect.underwater_pass.update_material(material)
	var wave_normal := _center(await _frame())
	_check(wave_normal.r > 0.05 and wave_normal.b > 0.05, "Shared Gerstner surface produces valid exit normals in compute")
	material.set_shader_parameter("wave_amplitude", 0.0)
	await _test_detail_and_caustics(environment.environment)

	material.set_shader_parameter("debug_mode", 1)
	camera.position.y = 1000.0
	camera.look_at(camera.position + Vector3.FORWARD, Vector3.UP)
	effect.underwater_pass.update_material(material)
	var split := await _frame()
	split.save_png("user://underwater_waterline.png")
	var upper := split.get_pixel(split.get_width() / 2, split.get_height() / 4)
	var lower := split.get_pixel(split.get_width() / 2, split.get_height() * 3 / 4)
	_check(lower.g > 0.9 and upper.g < 0.9, "The near-plane waterline classifies pixels independently")

	# Resize recreates all per-view resources, including a non-multiple-of-eight edge.
	root.size = Vector2i(257, 145)
	var resized := await _frame()
	_check(resized.get_width() == 257, "Resize and partial workgroups render successfully")
	# Estas dos comprueban la composición normal, no una vista de depuración: el modo
	# seguía en 1 desde la prueba del waterline, y los píxeles secos de una vista de
	# depuración se pintan aparte para que "no cambia nada" no sea ambiguo.
	material.set_shader_parameter("debug_mode", 0)
	material.set_shader_parameter("interior_count", 1)
	material.set_shader_parameter("interior_center", PackedVector4Array([Vector4(0, 1000, 0, 0)]))
	material.set_shader_parameter("interior_axis_x", PackedVector4Array([Vector4(1, 0, 0, 10)]))
	material.set_shader_parameter("interior_axis_y", PackedVector4Array([Vector4(0, 1, 0, 10)]))
	material.set_shader_parameter("interior_axis_z", PackedVector4Array([Vector4(0, 0, 1, 10)]))
	effect.underwater_pass.update_material(material)
	var interior := _center(await _frame())
	_check(interior.g < 0.9, "A dry ship interior excludes the underwater pass")
	effect.underwater_pass.update_material(null)
	var no_water := _center(await _frame())
	_check(absf(no_water.g - interior.g) < 0.01, "No-water fallback preserves the atmosphere")
	material.set_shader_parameter("interior_count", 0)
	material.set_shader_parameter("debug_mode", 0)
	effect.underwater_pass.update_material(material)
	camera.position.y = 1020.0
	camera.look_at(camera.position + Vector3.UP, Vector3.FORWARD)
	_check(_center(await _frame()).b > 0.01, "Above-water fast path preserves the sky without full-frame water dispatches")
	await _test_shallow_precision()
	await _test_waterline_partition()
	print("UNDERWATER_RESULT failures=", failures)
	compositor.compositor_effects = []
	effect = null
	world.queue_free()
	await process_frame
	await process_frame
	quit(failures)
