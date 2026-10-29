extends Node

## Clima local, audio y continuidad de las transiciones sin cargar el planeta.
## godot --headless --path . res://tests/weather/test_weather.tscn

class LocalWeather extends WeatherController:
	var altitude := 0.0
	var cold := 0.0
	var sheltered := false

	func _current_altitude() -> float:
		return altitude

	func _cold_precipitation() -> float:
		return cold

	func is_sheltered() -> bool:
		return sheltered


class CPUAtmosphere extends PlanetAtmosphere:
	func _initialize_compute() -> void:
		pass


class LocalFX extends WeatherFX:
	var rain := 0.0

	func set_intensity(effect_name: String, value: float) -> void:
		if effect_name == "rain":
			rain = value


var failures := 0
var checks := 0
var weather: LocalWeather
var atmosphere: PlanetAtmosphere
var ambience: WeatherAmbience
var player: Node3D


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	atmosphere = CPUAtmosphere.new()
	atmosphere.cloud_group_strength = 1.0
	atmosphere._group_image = Image.create_empty(4, 2, false, Image.FORMAT_RG8)
	atmosphere._group_image.fill(Color.WHITE)
	player = Node3D.new()
	add_child(player)
	player.position = Vector3.RIGHT * 30000.0
	weather = LocalWeather.new()
	weather._player = player
	weather._atmosphere = atmosphere
	weather._read_base_values()
	weather._build_events({})
	weather._fx = LocalFX.new()
	weather.add_child(weather._fx)
	weather._ready_to_run = true
	add_child(weather)
	weather.set_process(false)
	ambience = WeatherAmbience.new()
	add_child(ambience)
	ambience.setup(weather)
	ambience.set_process(false)

	_test_local_audio()
	_test_cloud_group()
	_test_transitions()
	_test_group_sampling()
	_test_wind()
	_test_sailing_wind()
	_test_gusts()
	_test_save_ignores_force()

	weather.free()
	ambience.free()
	player.free()
	atmosphere = null
	await get_tree().process_frame
	print("WEATHER: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _set_event(event: String, envelope := 1.0, altitude := 0.0, cold := 0.0, sheltered := false) -> void:
	atmosphere._group_image.fill(Color(envelope, 0.5, 0.0))
	weather.altitude = altitude
	weather.cold = cold
	weather.sheltered = sheltered
	weather.enabled = true
	weather._apply_state(weather._events[event])
	ambience._compute_target()
	check(is_equal_approx(ambience.last_rain, (weather._fx as LocalFX).rain),
		"Audio y partículas reciben la misma lluvia local: %s" % event)


func _rain_target() -> float:
	return ambience._mixer.target[WeatherAmbience.BED_RAIN_LIGHT] \
		+ ambience._mixer.target[WeatherAmbience.BED_RAIN_HEAVY] \
		+ ambience._mixer.target[WeatherAmbience.BED_RAIN_INDOOR]


func _test_local_audio() -> void:
	_set_event("storm")
	check(is_equal_approx(ambience.last_rain, 1.0) and _rain_target() > 0.99,
		"El temporal suena con toda la lluvia local bajo la celda")
	_set_event("storm", 0.0)
	check(weather.get_local_precipitation() == Vector2.ZERO and is_zero_approx(_rain_target()),
		"En un claro del temporal no hay gotas ni audio de lluvia")
	_set_event("storm", 1.0, 1200.0)
	check(is_zero_approx(_rain_target()), "Por encima de las nubes no suena lluvia")
	weather._shade = -1.0
	weather._update_sky_light(0.0, weather.get_resolved_state())
	check(is_zero_approx(weather._shade), "Por encima de las nubes no se oscurece la luz del observador")
	_set_event("storm", 1.0, 0.0, 1.0)
	check(weather.get_local_precipitation().y > 0.99 and is_zero_approx(_rain_target()),
		"El temporal que se convierte en nieve no suena a lluvia")
	_set_event("storm", 1.0, 0.0, 0.5)
	check(is_equal_approx(ambience.last_rain, 0.5), "La mezcla de agua y nieve solo hace sonar su parte de lluvia")
	_set_event("storm", 1.0, 0.0, 0.0, true)
	check(ambience._mixer.target[WeatherAmbience.BED_RAIN_INDOOR] > 0.99
		and is_equal_approx(ambience._mixer.target[WeatherAmbience.BED_RAIN_HEAVY], ambience.sheltered_outdoor_gain),
		"Bajo techo la lluvia exterior cede al sonido interior")
	_set_event("storm", 0.0, 0.0, 0.0, true)
	check(is_zero_approx(_rain_target()), "Estar bajo techo en una zona seca tampoco activa la lluvia interior")
	_set_event("clear")
	check(is_zero_approx(_rain_target()), "Despejado queda sin lluvia")
	_set_event("snow")
	check(is_zero_approx(_rain_target()), "La nevada queda sin audio de lluvia")
	_set_event("storm")
	weather.enabled = false
	ambience._compute_target()
	check(is_zero_approx(_rain_target()) and is_zero_approx(ambience.last_wind),
		"Desactivar el clima silencia sus pistas y limpia el diagnóstico")
	weather.enabled = true


func _test_cloud_group() -> void:
	_set_event("clear", 0.5)
	var clear_cov := weather._local_cloud_coverage(weather.get_resolved_state())
	_set_event("storm", 0.5)
	var storm_cov := weather._local_cloud_coverage(weather.get_resolved_state())
	check(storm_cov > clear_cov * 2.0 and storm_cov >= 0.74,
		"El temporal extiende el manto a las zonas intermedias de la agrupación")
	check(weather.get_local_precipitation().is_zero_approx(), "La extensión de nubes no obliga a llover entre las celdas")
	weather._apply_state(weather._events.storm)
	check(is_equal_approx(atmosphere.cloud_group_strength, 0.5), "Reaplicar el clima conserva la agrupación sin acumular escalas")
	_set_event("clear")
	check(is_equal_approx(atmosphere.cloud_group_strength, 1.0), "Despejado recupera la agrupación del planeta")


func _test_transitions() -> void:
	_set_event("clear")
	weather._from = weather._events.clear
	weather._to = weather._events.storm
	weather._blend = 0.4
	var visible := WeatherState.blend(weather._from, weather._to, 0.4)
	weather._apply_state(visible)
	weather.force_weather("snow")
	for field in WeatherState.FIELDS:
		check(is_equal_approx(float(weather._from.get(field)), float(visible.get(field))),
			"Una transición interrumpida parte del valor visible: %s" % field)
	weather.restore_save_data({"current": "storm", "forced": true})
	check(weather.get_resolved_state() == weather._events.storm,
		"Restaurar una partida actualiza inmediatamente el estado para audio y consumidores")
	_set_event("clear")
	weather._apply_state(WeatherState.blend(weather._events.clear, weather._events.storm, 0.25))
	ambience._compute_target()
	check(is_zero_approx(_rain_target()), "La transición no hace sonar lluvia antes de que se cierre el cielo")


func _test_group_sampling() -> void:
	atmosphere.cloud_group_strength = 1.0
	atmosphere._group_image.fill(Color.BLACK)
	atmosphere._group_image.set_pixel(1, 0, Color.WHITE)
	# u=0.5, v=0.25 cae a medio camino entre los texels 1 y 2 de la fila 0.
	var middle := Vector3(sqrt(0.5), sqrt(0.5), 0.0)
	check(is_equal_approx(atmosphere.get_cloud_group_envelope(middle), 0.5),
		"La consulta CPU interpola entre texels igual que el sampler GPU")
	atmosphere._group_image.fill(Color.BLACK)
	atmosphere._group_image.set_pixel(3, 0, Color.WHITE)
	check(is_equal_approx(atmosphere.get_cloud_group_envelope(Vector3(-sqrt(0.5), sqrt(0.5), 0.0)), 0.5),
		"La consulta CPU interpola a través de la costura de longitud")
	atmosphere._group_image.fill(Color.BLACK)
	for x in 4:
		atmosphere._group_image.set_pixel(x, 0, Color.WHITE)
	check(is_equal_approx(atmosphere.get_cloud_group_envelope(Vector3.UP), 1.0)
		and is_zero_approx(atmosphere.get_cloud_group_envelope(Vector3.DOWN)),
		"El filtrado conserva separados los polos norte y sur")


func _test_wind() -> void:
	# Una hora de partida no debe convertirse en un desplazamiento extra al cambiar de velocidad.
	atmosphere._wind_last_usec = 0
	atmosphere._cloud_wind_offset = 0.0
	atmosphere._fog_wind_offset = 0.0
	atmosphere.cloud_wind_speed = 0.025
	atmosphere.fog_wind_speed = 0.03
	atmosphere._advance_wind(3600000000)
	var cloud_phase := atmosphere._cloud_wind_offset
	var fog_phase := atmosphere._fog_wind_offset
	atmosphere.cloud_wind_speed = 0.06
	atmosphere.fog_wind_speed = 0.05
	atmosphere._advance_wind(3601000000)
	check(is_equal_approx(atmosphere._cloud_wind_offset - cloud_phase, 0.06),
		"Cambiar el viento desplaza las nubes solo el segundo transcurrido, sin saltar")
	check(is_equal_approx(atmosphere._fog_wind_offset - fog_phase, 0.05),
		"Cambiar el viento de niebla conserva su posición acumulada")


func _test_sailing_wind() -> void:
	var legacy := WeatherState.new()
	legacy.apply_overrides({"wind_multiplier": 0.6})
	check(is_equal_approx(legacy.wind_speed_multiplier, 0.6),
		"Los catálogos anteriores conservan su velocidad física de viento")
	legacy.wind_multiplier = 1.3
	check(is_equal_approx(legacy.wind_speed_multiplier, 1.3),
		"Sin ajuste físico explícito, el viento sigue al evento antiguo")
	legacy.apply_overrides({"wind_speed_multiplier": 0.0})
	check(is_zero_approx(legacy.wind_speed_multiplier), "Un ajuste explícito de calma elimina el viento físico")
	var clear: WeatherState = weather._events.clear
	var wind: WeatherState = weather._events.wind
	var middle := WeatherState.blend(clear, wind, 0.5)
	check(is_equal_approx(middle.wind_speed_multiplier, 2.4) and is_equal_approx(middle.wind_multiplier, 1.9),
		"La transición interpola por separado navegación y animación, sin saltos de velocidad")
	check(is_equal_approx((weather._builtin_events().clear as WeatherState).wind_speed_multiplier, 1.6),
		"El clima interno conserva la brisa navegable si falta el catálogo")
	var legacy_controller := LocalWeather.new()
	legacy_controller._build_events({"presets": {"clear": {"wind_multiplier": 0.8}}})
	check(is_equal_approx((legacy_controller._events.clear as WeatherState).wind_speed_multiplier, 0.8),
		"Un override antiguo del planeta no hereda por accidente el ajuste físico del catálogo")
	legacy_controller.free()
	var terrain := VoxelLodTerrain.new()
	var planet := Planet.new(terrain)
	planet.wind_direction = Vector3.RIGHT
	planet.wind_speed_mps = 8.0
	var loader = load("res://scripts/planet/planet_loader.gd").new()
	loader.planet = planet
	loader.global_pos = Vector3.ZERO
	weather._planet = planet
	weather.restore_save_data({"current": "clear", "forced": true})
	var local_up := Vector3(0.626, 0.490, -0.607).normalized()
	var air: Vector3 = loader.get_wind_velocity(local_up * 30000.0)
	check(air.length() > 9.5 and air.length() < 10.5 and absf(air.dot(local_up)) < 0.0001,
		"Al cargar clear el planeta entrega unos 10 m/s tangentes para las velas")
	check(is_equal_approx(planet.weather_wind_multiplier, 0.6) and clear.water_wave_multiplier == 0.4,
		"Clear conserva la animación de la vegetación y el oleaje tranquilo")
	weather._apply_state(wind)
	check(is_equal_approx(planet.weather_wind_speed_multiplier, 3.2)
		and (loader.get_wind_velocity(local_up * 30000.0) as Vector3).length() > 19.0,
		"Weather wind conserva su velocidad física anterior")
	weather._apply_state(legacy)
	check((loader.get_wind_velocity(local_up * 30000.0) as Vector3).is_zero_approx(),
		"La calma explícita llega al consumidor físico del planeta")
	weather._planet = null
	loader.free()
	planet.free()
	terrain.free()


func _test_gusts() -> void:
	var gusts := WindGusts.new(1234)
	var low := INF
	var high := 0.0
	var veer_low := INF
	var veer_high := -INF
	var max_step := 0.0
	var last := gusts.gain
	# Diez minutos a 30 fps con viento de temporal.
	for i in 18000:
		gusts.step(1.0 / 30.0, 2.4)
		low = minf(low, gusts.gain)
		high = maxf(high, gusts.gain)
		veer_low = minf(veer_low, gusts.veer)
		veer_high = maxf(veer_high, gusts.veer)
		if i > 0:
			max_step = maxf(max_step, absf(gusts.gain - last))
		last = gusts.gain
	check(high > 1.5 and low < 0.95 and low >= 0.2,
		"Las rachas suben y bajan el viento del evento (%.2f..%.2f)" % [low, high])
	check(max_step < 0.05, "Las rachas suben y bajan sin saltos entre frames (%.3f)" % max_step)
	check(veer_high - veer_low > deg_to_rad(40.0) and absf(veer_high) <= deg_to_rad(110.0) + 0.001
		and absf(veer_low) <= deg_to_rad(110.0) + 0.001,
		"La dirección gira con el tiempo dentro de su margen (%.0f..%.0f grados)" % [rad_to_deg(veer_low), rad_to_deg(veer_high)])
	gusts.configure({"veer_degrees": 0.0, "_comment": "x"})
	gusts.step(1.0, 1.0)
	check(is_zero_approx(gusts.veer), "La variación del viento se ajusta desde el JSON del planeta")

	var terrain := VoxelLodTerrain.new()
	var planet := Planet.new(terrain)
	planet.wind_direction = Vector3(2.0, 0.0, 0.0)
	weather._planet = planet
	weather._planet_center = Vector3.ZERO
	weather._wind_base_direction = planet.wind_direction
	weather._wind_pushed_veer = INF
	player.position = Vector3.UP * 30000.0
	weather._gusts = WindGusts.new(99)
	weather._update_wind(1.0 / 30.0, weather._events.storm)
	var storm: WeatherState = weather._events.storm
	check(is_equal_approx(planet.weather_wind_speed_multiplier, storm.wind_speed_multiplier * weather.get_wind_gust())
		and is_equal_approx(planet.weather_wind_multiplier, storm.wind_multiplier * weather.get_wind_gust()),
		"La racha escala el viento físico y el de la vegetación sobre el evento, sin acumularse")
	var expected := Vector3(2.0, 0.0, 0.0).rotated(Vector3.UP, weather._gusts.veer)
	check(planet.wind_direction.is_equal_approx(expected) and is_equal_approx(planet.wind_direction.length(), 2.0),
		"La dirección gira alrededor de la vertical del jugador y conserva su módulo")
	weather._planet = null
	player.position = Vector3.RIGHT * 30000.0
	planet.free()
	terrain.free()


func _test_save_ignores_force() -> void:
	weather._forced = false
	weather.restore_save_data({"current": "fog", "forced": true})
	check(not weather._forced and weather.get_current_weather_name() == "fog",
		"Una partida guardada con el clima forzado vuelve a cambiar sola")
	check(not weather.get_save_data().has("forced"), "El forzado de depuración no se guarda")

