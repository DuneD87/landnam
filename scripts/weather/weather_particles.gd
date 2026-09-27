class_name WeatherParticles
extends GPUParticles3D

## Emisor de precipitación genérico construido desde un preset. Simula en mundo
## (local_coords=false), así el jugador atraviesa la precipitación; la gravedad se reorienta
## cada frame hacia el centro del planeta (abajo radial del jugador).

static var _shared_dot_texture: ImageTexture
## Fracción de preset.amount que se emite, según las opciones gráficas (SettingsManager).
static var amount_scale: float = 1.0

const DRAW_SHADER := preload("res://shaders/weather/weather_particle.gdshader")
# Salto (m) del volumen de emisión a partir del cual se considera teletransporte, no seguimiento.
const TELEPORT_DISTANCE := 4.0

var _preset: WeatherParticlePreset
var _player: Node3D
var _planet_center: Vector3
var _proc: ParticleProcessMaterial
var _draw_mat: ShaderMaterial
# Punto donde nace la precipitación bajo techo (cielo abierto más cercano); si no es válido, el jugador.
var _anchor: Vector3
var _anchor_valid: bool = false
var _last_placed: Vector3 = Vector3.INF


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
	amount = maxi(roundi(preset.amount * amount_scale), 1)
	lifetime = maxf(preset.lifetime, 0.05)
	preprocess = preset.lifetime
	_proc = _build_process_material(preset)
	process_material = _proc
	draw_pass_1 = _build_mesh(preset)
	var reach := preset.box_extents + Vector3.ONE * (preset.initial_velocity_max \
		+ preset.gravity_strength * preset.lifetime) * preset.lifetime
	visibility_aabb = AABB(-reach, reach * 2.0)


## Recalcula el nº de partículas tras cambiar amount_scale. Cambiar amount reinicia el emisor.
func refresh_amount() -> void:
	if _preset != null:
		amount = maxi(roundi(_preset.amount * amount_scale), 1)


## Intensidad 0..1 (rate del clima): escala el nº de partículas y enciende/apaga la emisión.
func set_intensity(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	amount_ratio = v
	var should_emit := v > 0.001
	if should_emit != emitting:
		emitting = should_emit
		if should_emit:
			_follow_player()


## WeatherFX empuja aquí dónde debe nacer la precipitación: al aire libre (valid=false) sobre el
## jugador; bajo techo, sobre el cielo abierto más cercano de la rejilla si lo hay.
func set_emit_anchor(pos: Vector3, valid: bool) -> void:
	_anchor = pos
	_anchor_valid = valid


func _process(_delta: float) -> void:
	if emitting:
		_follow_player()


func _build_process_material(preset: WeatherParticlePreset) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = preset.box_extents
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = preset.spread
	pm.initial_velocity_min = preset.initial_velocity_min
	pm.initial_velocity_max = preset.initial_velocity_max
	pm.gravity = Vector3(0.0, -preset.gravity_strength, 0.0)
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
	mat.set_shader_parameter("occ_enabled", 0.0)
	_draw_mat = mat
	return mat


## Empuja al shader la luz solar (color día/noche), que multiplica el albedo de cada gota.
func set_sun_light(c: Color) -> void:
	if _draw_mat == null:
		return
	_draw_mat.set_shader_parameter("sun_light", Vector3(c.r, c.g, c.b))


## Empuja la rejilla de oclusión al shader. Con enabled=false el shader solo billboardea.
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


## Recoloca el volumen de emisión sobre el ancla (o el jugador) y orienta la gravedad hacia el
## centro del planeta. Al saltar entre ancla y jugador corta la interpolación, para que las gotas
## no nazcan repartidas por el camino durante un frame.
func _follow_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pos := _anchor if _anchor_valid else _player.global_position
	var jumped := pos.distance_squared_to(_last_placed) > TELEPORT_DISTANCE * TELEPORT_DISTANCE
	_last_placed = pos
	var up := pos - _planet_center
	up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD
	if absf(up.dot(ref)) > 0.99:
		ref = Vector3.RIGHT
	var x_axis := ref.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	global_transform = Transform3D(Basis(x_axis, up, z_axis), pos + up * _preset.volume_offset)
	if jumped:
		reset_physics_interpolation()
	if _proc != null:
		_proc.gravity = -up * _preset.gravity_strength


## Rehace las partículas conservando el estado de emisión. Al ocultarse el emisor la simulación
## queda congelada, así que al volver a mostrarlo hay que tirar el fotograma viejo.
func respawn() -> void:
	DebugStats.report_event(&"clima:reinicio_activo" if emitting else &"clima:reinicio_inactivo")
	_follow_player()
	var was := emitting
	restart()
	emitting = was


## Reinicia las partículas tras un rebase de origen flotante (viven en mundo y quedarían desplazadas).
func shift_origin(new_center: Vector3) -> void:
	_planet_center = new_center
	_anchor_valid = false   # el ancla vieja está en el marco anterior; la rejilla republica una nueva
	_follow_player()
	var was := emitting
	restart()
	emitting = was
