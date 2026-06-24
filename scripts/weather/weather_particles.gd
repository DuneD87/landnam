class_name WeatherParticles
extends GPUParticles3D

## Emisor de precipitación genérico: apply_preset() construye cualquier efecto desde un preset.
## Simula en MUNDO (local_coords=false), así el jugador atraviesa la precipitación en vez de
## arrastrarla. La gravedad apunta al CENTRO del planeta: cada frame se fija al "abajo radial"
## del jugador (en mundo la gravedad del material es global).

# Textura compartida (punto suave radial) para presets sin textura propia.
static var _shared_dot_texture: ImageTexture

const DRAW_SHADER := preload("res://shaders/weather/weather_particle.gdshader")

var _preset: WeatherParticlePreset
var _player: Node3D
var _planet_center: Vector3
var _proc: ParticleProcessMaterial   # para reescribir la gravedad radial cada frame
var _draw_mat: ShaderMaterial


func setup(player: Node3D, planet_center: Vector3, preset: WeatherParticlePreset) -> void:
	_player = player
	_planet_center = planet_center
	local_coords = false
	fixed_fps = 0
	apply_preset(preset)
	set_intensity(0.0)
	_follow_player()


func apply_preset(preset: WeatherParticlePreset) -> void:
	_preset = preset
	amount = maxi(preset.amount, 1)
	lifetime = maxf(preset.lifetime, 0.05)
	preprocess = preset.lifetime   # arranca con el volumen lleno, sin "cielo vacío" inicial
	_proc = _build_process_material(preset)
	process_material = _proc
	draw_pass_1 = _build_mesh(preset)
	# AABB generoso (caja + alcance de caída) para que no se culee al mirar lejos.
	var reach := preset.box_extents + Vector3.ONE * (preset.initial_velocity_max \
		+ preset.gravity_strength * preset.lifetime) * preset.lifetime
	visibility_aabb = AABB(-reach, reach * 2.0)


## Intensidad 0..1 (rate del clima): escala el nº de partículas y enciende/apaga la emisión.
func set_intensity(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	amount_ratio = v
	var should_emit := v > 0.001
	if should_emit != emitting:
		emitting = should_emit
		if should_emit:
			_follow_player()   # recoloca el volumen antes de emitir tras estar inactivo


func _process(_delta: float) -> void:
	# Solo el efecto que emite necesita seguir al jugador y reorientar su gravedad radial. El
	# inactivo (p.ej. nieve mientras llueve) no dibuja nada, así que nos lo saltamos.
	if emitting:
		_follow_player()


# ── Construcción ────────────────────────────────────────────────────────────────

func _build_process_material(preset: WeatherParticlePreset) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = preset.box_extents
	pm.direction = Vector3(0.0, -1.0, 0.0)   # -Y local; el nodo se orienta radial cada frame
	pm.spread = preset.spread
	pm.initial_velocity_min = preset.initial_velocity_min
	pm.initial_velocity_max = preset.initial_velocity_max
	pm.gravity = Vector3(0.0, -preset.gravity_strength, 0.0)   # _follow_player lo reescribe a radial
	pm.damping_min = preset.damping_min
	pm.damping_max = preset.damping_max
	pm.scale_min = preset.scale_min
	pm.scale_max = preset.scale_max
	pm.color = preset.color
	if preset.turbulence_strength > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = preset.turbulence_strength
		pm.turbulence_noise_scale = preset.turbulence_scale
	return pm


func _build_mesh(preset: WeatherParticlePreset) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = preset.mesh_size
	quad.material = _build_draw_material(preset)
	return quad


func _build_draw_material(preset: WeatherParticlePreset) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = DRAW_SHADER
	mat.set_shader_parameter("albedo_tex",
		preset.texture if preset.texture != null else _get_dot_texture())
	mat.set_shader_parameter("occ_enabled", 0.0)   # WeatherFX lo activa al empujar el campo
	_draw_mat = mat
	return mat


## WeatherFX empuja aquí la luz solar (color día/noche + atardecer); el shader la multiplica por
## el albedo de cada gota, así la precipitación se oscurece de noche en vez de ir a brillo pleno.
func set_sun_light(c: Color) -> void:
	if _draw_mat == null:
		return
	_draw_mat.set_shader_parameter("sun_light", Vector3(c.r, c.g, c.b))


## WeatherFX empuja aquí la rejilla de oclusión. Con enabled=false el shader solo billboardea.
func set_occlusion(field_center: Vector3, field_x: Vector3, field_z: Vector3, field_up: Vector3,
		field_half_size: float, field_span: float, field_below: float,
		height_tex: Texture2D, enabled: bool) -> void:
	if _draw_mat == null:
		return
	_draw_mat.set_shader_parameter("occ_enabled", 1.0 if enabled else 0.0)
	if not enabled:
		return
	_draw_mat.set_shader_parameter("occ_height_tex", height_tex)
	_draw_mat.set_shader_parameter("occ_center", field_center)
	_draw_mat.set_shader_parameter("occ_x", field_x)
	_draw_mat.set_shader_parameter("occ_z", field_z)
	_draw_mat.set_shader_parameter("occ_up", field_up)
	_draw_mat.set_shader_parameter("occ_half_size", field_half_size)
	_draw_mat.set_shader_parameter("occ_span", field_span)
	_draw_mat.set_shader_parameter("occ_below", field_below)


static func _get_dot_texture() -> ImageTexture:
	if _shared_dot_texture != null:
		return _shared_dot_texture
	var size := 32
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var a := clampf(1.0 - Vector2(x, y).distance_to(center) / radius, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_shared_dot_texture = ImageTexture.create_from_image(img)
	return _shared_dot_texture


# ── Seguimiento + orientación radial ─────────────────────────────────────────────

## Recoloca el volumen sobre el jugador (solo dónde nacen; las emitidas viven en mundo) y orienta
## la gravedad/velocidad hacia el centro del planeta con el "abajo radial" actual.
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
	global_transform = Transform3D(Basis(x_axis, up, z_axis), pos + up * _preset.volume_offset)
	if _proc != null:
		_proc.gravity = -up * _preset.gravity_strength
