class_name WindGusts
extends RefCounted

## Variación del viento dentro de un mismo evento: la intensidad sube y baja despacio, llegan
## rachas cortas y la dirección gira lentamente. Corre en tiempo real y no en el del calendario:
## es lo que se nota estando quieto, y al dormir no hace falta que el viento gire a 120x.

## Oleaje lento de la intensidad: fracción arriba y abajo, y su periodo aproximado (s).
var swell_amount := 0.25
var swell_period := 45.0
## Racha: subida media sobre la intensidad del evento (0.6 = +60 %), con algo de azar alrededor.
var gust_strength := 0.6
## Segundos entre rachas con un viento de evento de 1.0. Con más viento llegan más seguidas.
var gust_interval_min := 10.0
var gust_interval_max := 28.0
## Forma de la racha (s): subida, meseta (entre min y max) y caída.
var gust_attack := 1.2
var gust_hold_min := 0.5
var gust_hold_max := 2.5
var gust_release := 2.8
## Giro máximo de la dirección respecto a la del planeta (grados) y su periodo aproximado (s).
var veer_degrees := 110.0
var veer_period := 300.0

## Multiplicador resultante sobre la intensidad del evento.
var gain := 1.0
## Giro actual de la dirección, en radianes alrededor de la vertical del jugador.
var veer := 0.0

var _time := 0.0
var _noise := FastNoiseLite.new()
## Tiempo dentro de la racha en curso; negativo sin racha.
var _gust_time := -1.0
var _gust_peak := 0.0
var _gust_hold := 0.0
var _next_gust := 0.0


func _init(seed_value: int = 0) -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = seed_value
	# Arranca a un punto cualquiera de la curva para que dos partidas no empiecen igual.
	_time = float(seed_value % 100000)
	_next_gust = randf_range(gust_interval_min, gust_interval_max) * 0.5


## Ajustes desde weather_settings.wind_variation del planeta. Las claves que falten se quedan.
func configure(config: Dictionary) -> void:
	for key: String in config:
		if key in self and typeof(get(key)) == TYPE_FLOAT:
			set(key, float(config[key]))


## event_wind: wind_multiplier del evento resuelto, que solo decide cada cuánto llegan las rachas.
func step(delta: float, event_wind: float) -> void:
	_time += delta
	var swell := 1.0 + swell_amount * clampf(_noise.get_noise_1d(_time / maxf(swell_period, 0.01)) * 1.6, -1.0, 1.0)
	var veer_noise := _noise.get_noise_2d(_time / maxf(veer_period, 0.01), 517.0)
	veer = deg_to_rad(veer_degrees) * clampf(veer_noise * 1.6, -1.0, 1.0)
	gain = maxf(swell * (1.0 + _gust_envelope(delta, event_wind)), 0.2)


func _gust_envelope(delta: float, event_wind: float) -> float:
	if _gust_time < 0.0:
		# A más viento, rachas más seguidas: el despejado (0.6) sopla una cada ~30 s y el temporal
		# (2.4) una cada ~8.
		_next_gust -= delta * clampf(event_wind, 0.5, 3.5)
		if _next_gust > 0.0:
			return 0.0
		_gust_time = 0.0
		_gust_peak = gust_strength * randf_range(0.6, 1.4)
		_gust_hold = randf_range(gust_hold_min, gust_hold_max)
		_next_gust = randf_range(gust_interval_min, gust_interval_max)
	_gust_time += delta
	var t := _gust_time
	if t < gust_attack:
		return _gust_peak * smoothstep(0.0, gust_attack, t)
	t -= gust_attack
	if t < _gust_hold:
		return _gust_peak
	t -= _gust_hold
	if t < gust_release:
		return _gust_peak * (1.0 - smoothstep(0.0, gust_release, t))
	_gust_time = -1.0
	return 0.0
