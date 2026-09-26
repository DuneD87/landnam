class_name WeatherFX
extends Node3D

## Gestiona los efectos de precipitación y su oclusión: un WeatherParticles por efecto más un
## WeatherOcclusionField compartido cuya textura de alturas se pasa cada frame al shader, que
## oculta las gotas bajo techo (no llueve dentro de cuevas, pero sí fuera).

## Si se desactiva, la precipitación se ve en todas partes (incluidas cuevas).
@export var occlusion_enabled: bool = true

## Brillo de la precipitación en plena noche (0..1); sube a 1 de día.
@export_range(0.0, 1.0, 0.01) var night_brightness: float = 0.06

## El WeatherController lo activa para mantener viva la rejilla de oclusión sin precipitación (niebla pura).
var field_force_active: bool = false

var _player: Node3D
var _planet_center: Vector3
var _sun: Node3D
var _effects: Dictionary = {}
var _field: WeatherOcclusionField
var _splash: WeatherSplashParticles
var _submerged: bool = false


func setup(player: Node3D, planet_center: Vector3, sun: Node3D = null) -> void:
	_player = player
	_planet_center = planet_center
	_sun = sun
	_field = WeatherOcclusionField.new()
	_field.name = "OcclusionField"
	add_child(_field)
	_field.setup(player, planet_center)
	register_effect("rain", WeatherParticlePreset.rain())
	register_effect("snow", WeatherParticlePreset.snow())
	_splash = WeatherSplashParticles.new()
	_splash.name = "FX_rain_splash"
	add_child(_splash)
	_splash.setup(player, planet_center)


## Registra (o reemplaza) un efecto con su preset.
func register_effect(effect_name: String, preset: WeatherParticlePreset) -> WeatherParticles:
	if _effects.has(effect_name):
		_effects[effect_name].queue_free()
	var fx := WeatherParticles.new()
	fx.name = "FX_" + effect_name
	add_child(fx)
	fx.setup(_player, _planet_center, preset)
	_effects[effect_name] = fx
	return fx


func set_intensity(effect_name: String, value: float) -> void:
	var fx: WeatherParticles = _effects.get(effect_name)
	if fx != null:
		fx.set_intensity(value)
	if effect_name == "rain" and _splash != null:
		_splash.set_intensity(value)


func get_effect(effect_name: String) -> WeatherParticles:
	return _effects.get(effect_name)


## Acceso a la rejilla de oclusión (puede ser null antes de setup()).
func get_occlusion_field() -> WeatherOcclusionField:
	return _field


## Con la cámara bajo el agua la precipitación se oculta entera: el quad submarino escribe una
## profundidad adelantada (fuga de atmósfera) contra la que las gotas ganan el test de
## profundidad, así que si no se ocultan aquí se ven cayendo dentro del mar.
func set_submerged(value: bool) -> void:
	if value == _submerged:
		return
	_submerged = value
	DebugStats.report_event(&"clima:sumergir" if value else &"clima:emerger")
	visible = not value
	if _submerged:
		return
	# Oculto, el emisor no simula: al emerger se tira el fotograma congelado.
	for effect_name in _effects:
		_effects[effect_name].respawn()
	if _splash != null:
		_splash.respawn()


func _physics_process(delta: float) -> void:
	if _submerged:
		return
	if _field == null or (not _has_active_effect() and not field_force_active):
		return

	# Actualiza el campo primero: así player_occluded refleja la posición de este frame, no la anterior.
	_field.ground_enabled = _splash != null and _splash.emitting
	var _t0 := Time.get_ticks_usec()
	var committed := _field.update(delta)
	DebugStats.report_cost(&"clima:oclusion", Time.get_ticks_usec() - _t0)

	# Al aire libre la precipitación sigue al jugador; bajo techo nace sobre el claro más cercano
	# (la boca de la cueva), y si no hay ninguno en la rejilla vuelve al jugador: allí la oculta
	# entera el shader, pero el emisor se queda al lado y reaparece en cuanto asoma un claro.
	var anchored := _field.player_occluded and _field.has_open_sky
	var anchor := _field.open_sky_pos
	if not anchored and _player != null and is_instance_valid(_player):
		anchor = _player.global_position
	for effect_name in _effects:
		_effects[effect_name].set_emit_anchor(anchor, anchored)
	if _splash != null:
		_splash.set_emit_anchor(anchor, anchored)
		# Los splashes solo nacen en el disco del emisor: el campo se ahorra el rayo de suelo en
		# el resto de la rejilla, que es ~9 de cada 10 celdas.
		_field.set_ground_region(anchor, _splash.disc_radius)

	var sun_light := _compute_sun_light()
	for effect_name in _effects:
		var lit_fx: WeatherParticles = _effects[effect_name]
		if lit_fx.emitting:
			lit_fx.set_sun_light(sun_light)
	if _splash != null and _splash.emitting:
		_splash.set_sun_light(sun_light)

	if not committed:
		return
	DebugStats.report_event(&"clima:textura_oclusion")
	var tex := _field.get_height_texture()
	for effect_name in _effects:
		var fx: WeatherParticles = _effects[effect_name]
		if not fx.emitting:
			continue
		fx.set_occlusion(
			_field.center, _field.x_axis, _field.z_axis, _field.up,
			_field.half_size(), _field.span(), _field.probe_below,
			tex, occlusion_enabled)
	if _splash != null and _splash.emitting:
		_splash.set_field(
			_field.center, _field.x_axis, _field.z_axis, _field.up,
			_field.half_size(), _field.span(), _field.probe_below,
			tex, true)


## Refresca el centro del planeta y reinicia las partículas tras un rebase de origen flotante.
func on_origin_shift(new_center: Vector3) -> void:
	DebugStats.report_event(&"clima:rebase")
	_planet_center = new_center
	if _field != null and _field.has_method("set_planet_center"):
		_field.set_planet_center(new_center)
	for effect_name in _effects:
		_effects[effect_name].shift_origin(new_center)
	if _splash != null:
		if _splash.has_method("shift_origin"):
			_splash.shift_origin(new_center)
		else:
			var was: bool = _splash.emitting
			_splash.restart()
			_splash.emitting = was


func _has_active_effect() -> bool:
	for effect_name in _effects:
		if _effects[effect_name].emitting:
			return true
	return false


## Color de luz que multiplica el albedo de las partículas según día/noche, con tinte cálido en el terminador.
## Con SkyLighting en la escena sale de las mismas luces que el resto (sol, luna, cielo y clima).
func _compute_sun_light() -> Color:
	var sky := get_tree().get_first_node_in_group(SkyLighting.GROUP) as SkyLighting
	if sky != null:
		return sky.get_particle_light()
	if _player == null or not is_instance_valid(_player):
		return Color.WHITE
	var up := _player.global_position - _planet_center
	up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP

	var sun_dir := Vector3.UP
	if _sun != null and is_instance_valid(_sun):
		sun_dir = _sun.global_transform.basis.z.normalized()

	var sun_dot := up.dot(sun_dir)
	var day := smoothstep(-0.15, 0.15, sun_dot)
	var sunset_f := 1.0 - smoothstep(0.0, 0.3, absf(sun_dot))
	var bright := lerpf(night_brightness, 1.0, day)
	var tint := Color.WHITE.lerp(Color(1.3, 0.9, 0.7), sunset_f)
	return Color(bright * tint.r, bright * tint.g, bright * tint.b)
