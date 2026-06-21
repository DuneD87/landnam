class_name WeatherFX
extends Node3D

## Gestiona los efectos de precipitación y su oclusión: un WeatherParticles por efecto + un
## WeatherOcclusionField compartido cuya textura de alturas se pasa cada frame al shader, que
## oculta las gotas bajo techo → no llueve dentro de cuevas, pero sí fuera.

## Si se desactiva, la precipitación se ve en todas partes (incluidas cuevas).
@export var occlusion_enabled: bool = true

var _player: Node3D
var _planet_center: Vector3
var _effects: Dictionary = {}   # nombre -> WeatherParticles
var _field: WeatherOcclusionField


func setup(player: Node3D, planet_center: Vector3) -> void:
	_player = player
	_planet_center = planet_center
	_field = WeatherOcclusionField.new()
	_field.name = "OcclusionField"
	add_child(_field)
	_field.setup(player, planet_center)
	register_effect("rain", WeatherParticlePreset.rain())
	register_effect("snow", WeatherParticlePreset.snow())


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


func get_effect(effect_name: String) -> WeatherParticles:
	return _effects.get(effect_name)


func _physics_process(delta: float) -> void:
	if _field == null or not _has_active_effect():
		return   # sin precipitación no reconstruimos la rejilla (ahorra raycasts)
	# Reconstruir ANTES de empujar: centro/ejes/textura del mismo frame (si no, parpadea).
	# Solo empujamos los uniforms el frame en que la rejilla cambió (centro/ejes/textura nuevos);
	# entre reconstrucciones siguen vigentes los del último push.
	if not _field.update(delta):
		return
	var tex := _field.get_height_texture()
	for effect_name in _effects:
		var fx: WeatherParticles = _effects[effect_name]
		if not fx.emitting:
			continue   # el efecto inactivo no dibuja nada: no hace falta actualizar su oclusión
		fx.set_occlusion(
			_field.center, _field.x_axis, _field.z_axis, _field.up,
			_field.half_size(), _field.span(), _field.probe_below,
			tex, occlusion_enabled)


func _has_active_effect() -> bool:
	for effect_name in _effects:
		if _effects[effect_name].emitting:
			return true
	return false
