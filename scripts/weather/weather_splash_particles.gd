class_name WeatherSplashParticles
extends GPUParticles3D

## Capa de salpicaduras de lluvia: emite un disco fino de partículas sobre el jugador y el shader las
## posa sobre el terreno (canal G del campo de WeatherOcclusionField), dibujándolas como anillos
## planos que crecen y se desvanecen. No detecta colisión por gota: las reparte estadísticamente
## sobre el suelo visible bajo el jugador, con intensidad ligada a la lluvia. Simula en MUNDO
## (local_coords=false) y sigue al jugador en radial, igual que WeatherParticles. [[weather_particles]]

const DRAW_SHADER := preload("res://shaders/weather/splash_particle.gdshader")

# Salpicaduras compartidas (anillo suave) para no regenerar la textura por instancia.
static var _shared_ring_texture: ImageTexture

## Mitad-extensión tangencial del disco de emisión (m). Debe caber dentro del half_size del campo.
@export var disc_radius: float = 40.0
@export var max_amount: int = 1500
@export var splash_lifetime: float = 0.45
## Tamaño base del quad del anillo (m); scale_min/max + la curva de crecimiento lo modulan.
@export var ring_size: float = 0.9
@export var color: Color = Color(0.85, 0.9, 1.0, 0.6)

var _player: Node3D
var _planet_center: Vector3
var _draw_mat: ShaderMaterial


func setup(player: Node3D, planet_center: Vector3) -> void:
	_player = player
	_planet_center = planet_center
	local_coords = false
	fixed_fps = 0
	amount = maxi(max_amount, 1)
	lifetime = maxf(splash_lifetime, 0.05)
	preprocess = 0.0
	process_material = _build_process_material()
	draw_pass_1 = _build_mesh()
	# AABB amplio: las partículas se reubican en el shader sobre el terreno, lejos del nodo.
	visibility_aabb = AABB(Vector3.ONE * -disc_radius * 2.0, Vector3.ONE * disc_radius * 4.0)
	set_intensity(0.0)
	_follow_player()


## Intensidad 0..1 (la liga WeatherFX a la lluvia): escala el nº de splashes y enciende/apaga.
func set_intensity(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	amount_ratio = v
	var should_emit := v > 0.001
	if should_emit != emitting:
		emitting = should_emit
		if should_emit:
			_follow_player()


func _process(_delta: float) -> void:
	if emitting:
		_follow_player()


## WeatherFX empuja aquí la luz solar (color día/noche + atardecer); el shader la multiplica por
## el albedo del anillo, así las salpicaduras se oscurecen de noche igual que la lluvia.
func set_sun_light(c: Color) -> void:
	if _draw_mat == null:
		return
	_draw_mat.set_shader_parameter("sun_light", Vector3(c.r, c.g, c.b))


## WeatherFX empuja aquí el campo radial (mismo que la lluvia). Con enabled=false el shader oculta
## todo (sin dato de suelo no sabe dónde posar el anillo).
func set_field(field_center: Vector3, field_x: Vector3, field_z: Vector3, field_up: Vector3,
		field_half_size: float, field_span: float, field_below: float,
		field_tex: Texture2D, enabled: bool) -> void:
	if _draw_mat == null:
		return
	_draw_mat.set_shader_parameter("field_enabled", 1.0 if enabled else 0.0)
	if not enabled:
		return
	_draw_mat.set_shader_parameter("field_tex", field_tex)
	_draw_mat.set_shader_parameter("field_center", field_center)
	_draw_mat.set_shader_parameter("field_x", field_x)
	_draw_mat.set_shader_parameter("field_z", field_z)
	_draw_mat.set_shader_parameter("field_up", field_up)
	_draw_mat.set_shader_parameter("field_half_size", field_half_size)
	_draw_mat.set_shader_parameter("field_span", field_span)
	_draw_mat.set_shader_parameter("field_below", field_below)


# ── Construcción ────────────────────────────────────────────────────────────────

func _build_process_material() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	# Disco fino centrado en el jugador: solo importa la posición tangencial (el shader fija la altura).
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(disc_radius, 0.5, disc_radius)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO   # los anillos son estáticos sobre el suelo
	pm.color = color

	# Crecer durante la vida (anillo expansivo).
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.set_param_min(ParticleProcessMaterial.PARAM_SCALE, ring_size * 0.9)
	pm.set_param_max(ParticleProcessMaterial.PARAM_SCALE, ring_size * 1.3)
	pm.set_param_texture(ParticleProcessMaterial.PARAM_SCALE, grow_tex)

	# Aparecer rápido y desvanecer (alfa sobre la vida).
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	return pm


func _build_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE   # el tamaño real lo da scale (ring_size * curva)
	quad.material = _build_draw_material()
	return quad


func _build_draw_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = DRAW_SHADER
	mat.set_shader_parameter("albedo_tex", _get_ring_texture())
	mat.set_shader_parameter("field_enabled", 0.0)   # WeatherFX lo activa al empujar el campo
	_draw_mat = mat
	return mat


# ── Seguimiento radial ───────────────────────────────────────────────────────────

func _follow_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pos := _player.global_position
	var up := pos - _planet_center
	up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD
	if absf(up.dot(ref)) > 0.99:
		ref = Vector3.RIGHT
	var x_axis := ref.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	global_transform = Transform3D(Basis(x_axis, up, z_axis), pos)


static func _get_ring_texture() -> ImageTexture:
	if _shared_ring_texture != null:
		return _shared_ring_texture
	var size := 64
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			# Anillo: alfa máximo cerca del borde (r≈0.8), 0 en el centro y fuera del círculo.
			var d := Vector2(x, y).distance_to(center) / radius
			var a := clampf(1.0 - absf(d - 0.8) / 0.2, 0.0, 1.0)
			a *= clampf((1.0 - d) * 4.0, 0.0, 1.0)   # recorta el filo exterior
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_shared_ring_texture = ImageTexture.create_from_image(img)
	return _shared_ring_texture
