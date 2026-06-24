class_name WeatherFX
extends Node3D

## Gestiona los efectos de precipitación y su oclusión: un WeatherParticles por efecto + un
## WeatherOcclusionField compartido cuya textura de alturas se pasa cada frame al shader, que
## oculta las gotas bajo techo → no llueve dentro de cuevas, pero sí fuera.

## Si se desactiva, la precipitación se ve en todas partes (incluidas cuevas).
@export var occlusion_enabled: bool = true

## Brillo de la precipitación en plena noche (0..1). Las gotas/copos se atenúan hasta este valor
## en el lado nocturno y suben a 1 de día, replicando el día/noche de la niebla/nubes.
@export_range(0.0, 1.0, 0.01) var night_brightness: float = 0.06

## Lo pone el WeatherController para mantener la rejilla de oclusión reconstruyéndose aunque no
## haya precipitación (p. ej. evento de niebla pura): así el shader de atmósfera puede ocultar la
## niebla dentro de las cuevas. Sin esto, la rejilla solo vive durante lluvia/nieve.
var field_force_active: bool = false

var _player: Node3D
var _planet_center: Vector3
var _sun: Node3D                # fuente de la dirección del sol (DirectionalLight3D)
var _effects: Dictionary = {}   # nombre -> WeatherParticles
var _field: WeatherOcclusionField
var _splash: WeatherSplashParticles   # salpicaduras de lluvia sobre el terreno


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
		_splash.set_intensity(value)   # las salpicaduras siguen el ritmo de la lluvia


func get_effect(effect_name: String) -> WeatherParticles:
	return _effects.get(effect_name)


## Acceso a la rejilla de oclusión (la usa el WeatherController para empujarla al shader de
## atmósfera y ocultar la niebla en cuevas). Puede ser null antes de setup().
func get_occlusion_field() -> WeatherOcclusionField:
	return _field


func _physics_process(delta: float) -> void:
	# Reconstruimos la rejilla si hay precipitación O si el controller la fuerza para la niebla;
	# sin ninguna de las dos no gastamos raycasts.
	if _field == null or (not _has_active_effect() and not field_force_active):
		return

	# Luz solar (día/noche + tinte de atardecer): se empuja CADA frame porque el sol se mueve
	# continuamente, y ANTES del posible early-return del campo de oclusión (que sí se salta
	# frames). Así la lluvia/nieve/salpicaduras se atenúan de noche como la niebla y las nubes.
	var sun_light := _compute_sun_light()
	for effect_name in _effects:
		var lit_fx: WeatherParticles = _effects[effect_name]
		if lit_fx.emitting:
			lit_fx.set_sun_light(sun_light)
	if _splash != null and _splash.emitting:
		_splash.set_sun_light(sun_light)

	# El rayo de suelo (canal G) solo se lanza si hay splashes activos (lluvia): evita duplicar
	# raycasts cuando solo nieva. Se fija ANTES de update() porque update() reconstruye la rejilla.
	_field.ground_enabled = _splash != null and _splash.emitting
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
	if _splash != null and _splash.emitting:
		# Las salpicaduras necesitan el campo SIEMPRE (canal G = suelo donde posarse), no solo en cuevas.
		_splash.set_field(
			_field.center, _field.x_axis, _field.z_axis, _field.up,
			_field.half_size(), _field.span(), _field.probe_below,
			tex, true)


func _has_active_effect() -> bool:
	for effect_name in _effects:
		if _effects[effect_name].emitting:
			return true
	return false


## Color de luz que multiplica el albedo de las partículas. Brillo por día/noche según el ángulo
## entre el "arriba" radial del jugador y la dirección del sol (mismo criterio que niebla/nubes en
## el shader de atmósfera), con un suelo nocturno (night_brightness) y un tinte cálido suave en el
## terminador. Sin sol asignado → blanco (sin modular), así el efecto degrada con seguridad.
func _compute_sun_light() -> Color:
	if _player == null or not is_instance_valid(_player):
		return Color.WHITE
	var up := _player.global_position - _planet_center
	up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP

	var sun_dir := Vector3.UP
	if _sun != null and is_instance_valid(_sun):
		# basis.z = del planeta hacia el sol (igual que PlanetAtmosphereController).
		sun_dir = _sun.global_transform.basis.z.normalized()

	var sun_dot := up.dot(sun_dir)
	var day := smoothstep(-0.15, 0.15, sun_dot)            # 0 = noche, 1 = día
	var sunset_f := 1.0 - smoothstep(0.0, 0.3, absf(sun_dot))
	var bright := lerpf(night_brightness, 1.0, day)
	var tint := Color.WHITE.lerp(Color(1.3, 0.9, 0.7), sunset_f)  # cálido suave en el terminador
	return Color(bright * tint.r, bright * tint.g, bright * tint.b)
