class_name FeatherPuff
extends RefCounted

## Plumas que salen de un ave: al morir (AmbientBird) y al desplumarla (FaunaCorpse.pluck, desde
## Butchering). Salen de golpe, frenan en el aire y bajan despacio, girando y meciéndose
## (turbulencia), del color del plumaje con algo de variación. Se encogen al final de su vida. No es
## gore: salen con cualquier nivel.

const LIFETIME := 3.0
## El tamaño de una pluma (m) para un ave de REFERENCE_RADIUS de grueso; crece con el ave, entre
## SIZE_LIMITS.
const SIZE := Vector2(0.03, 0.06)
const REFERENCE_RADIUS := 0.12
const SIZE_LIMITS := Vector2(0.6, 1.5)

static var _mesh: QuadMesh
static var _scale_curve: CurveTexture


## [amount] plumas de [color] desde [point] hacia [up] (y a los lados), para un ave de [radius] m de
## grueso. [target] es de quien salen (sirve para encontrar la escena).
static func spawn(target: Node, point: Vector3, up: Vector3, color: Color, amount: int, radius: float) -> void:
	if amount <= 0 or target == null or not target.is_inside_tree():
		return
	var host := target.get_tree().current_scene
	if host == null:
		return
	var size := clampf(radius / REFERENCE_RADIUS, SIZE_LIMITS.x, SIZE_LIMITS.y)
	var particles := GPUParticles3D.new()
	particles.name = "FeatherPuff"
	particles.amount = amount
	particles.lifetime = LIFETIME
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.randomness = 0.5
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 75.0
	process.initial_velocity_min = 0.6 * size
	process.initial_velocity_max = 1.8 * size
	# El aire las frena enseguida y la gravedad apenas puede con ellas: bajan despacio.
	process.gravity = -up.normalized() * 1.6
	process.damping_min = 1.0
	process.damping_max = 1.6
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_noise_scale = 1.6
	process.turbulence_influence_min = 0.04
	process.turbulence_influence_max = 0.14
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -160.0
	process.angular_velocity_max = 160.0
	process.scale_min = 0.7 * size
	process.scale_max = 1.2 * size
	process.scale_curve = _shrink_curve()
	process.color = color
	var tints := Gradient.new()
	tints.set_color(0, color.darkened(0.3))
	tints.set_color(1, color.lightened(0.25))
	var ramp := GradientTexture1D.new()
	ramp.gradient = tints
	process.color_initial_ramp = ramp
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(radius * 0.6, 0.02)
	particles.process_material = process
	particles.draw_pass_1 = _feather()
	particles.visibility_aabb = AABB(Vector3.ONE * -3.0, Vector3.ONE * 6.0)
	host.add_child(particles)
	# En el marco del emisor, +Y es [up].
	var y := up.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	particles.global_transform = Transform3D(Basis(x, y, x.cross(y)), point)
	particles.add_to_group(&"floating_origin")
	particles.emitting = true
	particles.get_tree().create_timer(LIFETIME * 1.6).timeout.connect(particles.queue_free)


## Una pluma: un cuadro de cara a la cámara con su silueta (el cañón y las barbas) recortada.
static func _feather() -> QuadMesh:
	if _mesh != null:
		return _mesh
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _feather_texture()
	mat.roughness = 0.9
	_mesh = QuadMesh.new()
	_mesh.size = SIZE
	_mesh.material = mat
	return _mesh


## La silueta: la pluma ensanchándose desde el cañón hasta pasada la mitad y redonda en la punta,
## con la raya del cañón más clara y las barbas algo deshilachadas.
static func _feather_texture() -> ImageTexture:
	var w := 32
	var h := 64
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for py in h:
		# t: 0 en la base (abajo), 1 en la punta.
		var t := 1.0 - (float(py) + 0.5) / h
		var half := 0.0
		if t > 0.12:
			var u := (t - 0.12) / 0.88
			half = sin(pow(u, 0.75) * PI) * 0.46
		var frayed := rng.randf_range(0.85, 1.0)
		for px in w:
			var x := (float(px) + 0.5) / w - 0.5
			var shaft := absf(x) < 0.035
			var inside := absf(x) < half * frayed
			if shaft and t < 0.97:
				image.set_pixel(px, py, Color(1.0, 1.0, 1.0, 1.0))
			elif inside:
				var shade := 0.82 + 0.18 * (1.0 - absf(x) / maxf(half, 0.01))
				image.set_pixel(px, py, Color(shade, shade, shade, 1.0))
			else:
				image.set_pixel(px, py, Color(1.0, 1.0, 1.0, 0.0))
	return ImageTexture.create_from_image(image)


## Enteras casi toda su vida y encogiéndose al final.
static func _shrink_curve() -> CurveTexture:
	if _scale_curve != null:
		return _scale_curve
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.8, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_scale_curve = CurveTexture.new()
	_scale_curve.curve = curve
	return _scale_curve
