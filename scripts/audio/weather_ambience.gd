class_name WeatherAmbience
extends Node

## Lecho sonoro del clima: lluvia, viento y truenos. Misma idea que WaterAmbience — todas las camas
## suenan a la vez y lo que cambia son sus volúmenes— y las mismas fuentes: lo que suena sale del
## estado que el WeatherController está aplicando de verdad este frame (ya interpolado), no del
## evento de destino, que llega antes que el mundo.
##
## Bajo techo la lluvia se agacha y, si hay clip para ello, cede el sitio al de interior. Eso lo
## decide el MISMO barrido de oclusión que decide si te caen gotas encima, así que el sonido y las
## partículas entran y salen de la cueva a la vez.

const BED_RAIN_LIGHT := 0
const BED_RAIN_HEAVY := 1
const BED_RAIN_INDOOR := 2
const BED_WIND_LIGHT := 3
const BED_WIND_STRONG := 4
const EVENTS: Array[StringName] = [
	&"rain_light", &"rain_heavy", &"rain_indoor", &"wind_light", &"wind_strong",
]

const UPDATE_INTERVAL := 0.1

@export_group("Lluvia")
## Lluvia a la que se cruza de la cama suave a la fuerte. rain_rate va de 0 a 1 en el catálogo.
@export_range(0.0, 1.0) var rain_heavy_at: float = 0.6
## Cuánto se agacha la lluvia de fuera estando bajo techo. Si hay clip de interior, además cede.
@export_range(0.0, 1.0) var sheltered_outdoor_gain: float = 0.25

@export_group("Viento")
## Valores de wind_multiplier que se toman por calma y por vendaval. Salen del catálogo de eventos:
## 0.5 en niebla, 3.2 en el evento de viento.
@export var wind_calm: float = 0.6
@export var wind_full: float = 3.2
## Brisa de fondo al aire libre. Sin esto, con el parte tendido no se oye absolutamente nada.
@export_range(0.0, 1.0) var wind_floor: float = 0.15
## Altitud (m) a la que el viento ya suena a pleno aunque el clima esté tendido: en una cima sopla.
@export var wind_altitude_full: float = 1200.0
## Cuánto puede subir la altitud el factor de viento, sumado.
@export_range(0.0, 1.0) var wind_altitude_boost: float = 0.35

@export_group("Truenos")
## Segundos de retardo entre el destello y el trueno, de un rayo pegado a uno lejano. Es la
## distancia fingida: no hace falta saber dónde cayó, y la sensación es la misma.
@export var thunder_delay_near: float = 0.4
@export var thunder_delay_far: float = 9.0
## Retardo a partir del cual el trueno usa la cama lejana en vez de la cercana.
@export var thunder_far_after: float = 3.0
## Atenuación del trueno más lejano respecto al más cercano, en dB.
@export var thunder_far_db: float = -12.0

@export_group("Mezcla")
@export var blend_speed: float = 0.5
@export_range(-24.0, 12.0) var volume_offset_db: float = 0.0
@export var silence_threshold: float = 0.001

var _players: Array[AudioStreamPlayer] = []
var _events: Array[SoundEvent] = []
var _mix := PackedFloat32Array()
var _target := PackedFloat32Array()
var _update_timer: float = 0.0
## Retardos que quedan para cada trueno pendiente, y el que se le sorteo al caer el rayo.
var _pending_thunder: PackedFloat32Array = PackedFloat32Array()
var _thunder_rolled: PackedFloat32Array = PackedFloat32Array()

var _weather: WeatherController

## Diagnóstico, para el comando 'audio' de la consola.
var last_rain: float = 0.0
var last_wind: float = 0.0
var last_sheltered: bool = false


## Lo llama el WeatherController cuando termina de montarse.
func setup(weather: WeatherController) -> void:
	_weather = weather
	if weather != null and not weather.lightning_struck.is_connected(_on_lightning):
		weather.lightning_struck.connect(_on_lightning)


func _ready() -> void:
	_mix.resize(EVENTS.size())
	_target.resize(EVENTS.size())
	for event_id in EVENTS:
		var ev := AudioManager.get_event(event_id)
		_events.append(ev)
		var player := AudioStreamPlayer.new()
		player.name = String(event_id)
		if ev != null and ev.is_valid():
			player.stream = ev.pick_stream()
			player.bus = ev.bus
			_force_loop(player.stream)
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


func _process(delta: float) -> void:
	_tick_thunder(delta)
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_compute_target()

	var step := blend_speed * delta
	for i in _players.size():
		var moved := move_toward(_mix[i], _target[i], step)
		if not is_equal_approx(moved, _mix[i]):
			_mix[i] = moved
			_apply(i)


func _compute_target() -> void:
	_target.fill(0.0)
	if _weather == null or not is_instance_valid(_weather):
		return
	var st := _weather.get_resolved_state()
	if st == null:
		return

	last_rain = clampf(st.rain_rate, 0.0, 1.0)
	last_wind = _wind_factor(st)
	last_sheltered = _weather.is_sheltered()

	# Lluvia: cruce suave→fuerte, y bajo techo se agacha entera. Si hay cama de interior, lo que
	# pierde la de fuera lo gana ella; si no la hay, simplemente se oye menos, que es lo honesto.
	var heavy := smoothstep(0.0, maxf(rain_heavy_at, 0.001), last_rain)
	var outdoor := last_rain * (sheltered_outdoor_gain if last_sheltered else 1.0)
	_target[BED_RAIN_LIGHT] = outdoor * (1.0 - heavy)
	_target[BED_RAIN_HEAVY] = outdoor * heavy
	if last_sheltered:
		_target[BED_RAIN_INDOOR] = last_rain

	var strong := last_wind
	_target[BED_WIND_LIGHT] = last_wind * (1.0 - strong)
	_target[BED_WIND_STRONG] = last_wind * strong


## Fuerza del viento en [0,1]: la del clima, subida por la altitud. En una cima sopla aunque el
## parte esté tendido.
func _wind_factor(st: WeatherState) -> float:
	var from_weather := clampf(
		inverse_lerp(wind_calm, maxf(wind_full, wind_calm + 0.001), st.wind_multiplier), 0.0, 1.0)
	var altitude := _weather.get_player_altitude()
	var from_altitude := clampf(altitude / maxf(wind_altitude_full, 1.0), 0.0, 1.0)
	return clampf(maxf(from_weather, wind_floor) + from_altitude * wind_altitude_boost,
		0.0, 1.0)


## Un rayo acaba de caer. El trueno llega con retardo, y ese retardo ES la distancia: no hace falta
## saber dónde cayó para que suene lejos o encima.
func _on_lightning() -> void:
	var delay := randf_range(thunder_delay_near, thunder_delay_far)
	_pending_thunder.append(delay)
	_thunder_rolled.append(delay)


## Suelta los truenos que ya han llegado. Va por cola y no por await: una corrutina dormida
## despierta sobre el nodo aunque lo hayan liberado entretanto.
func _tick_thunder(delta: float) -> void:
	var i := _pending_thunder.size() - 1
	while i >= 0:
		var left: float = _pending_thunder[i] - delta
		if left > 0.0:
			_pending_thunder[i] = left
			i -= 1
			continue
		# El retardo sorteado, no el que queda: la cuenta atras ya se lo ha comido.
		var delay: float = _thunder_rolled[i]
		_pending_thunder.remove_at(i)
		_thunder_rolled.remove_at(i)
		i -= 1
		var event: StringName = &"thunder_far" if delay >= thunder_far_after else &"thunder_near"
		var distance := clampf(
			inverse_lerp(thunder_delay_near, thunder_delay_far, delay), 0.0, 1.0)
		AudioManager.play_ui(event,
			{"volume_offset_db": volume_offset_db + lerpf(0.0, thunder_far_db, distance)})


func _apply(index: int) -> void:
	var player := _players[index]
	if player.stream == null:
		return
	var mix := _mix[index]
	if mix <= silence_threshold:
		if player.playing:
			player.stop()
		return
	var ev := _events[index]
	var base: float = ev.volume_db if ev != null else 0.0
	player.volume_db = base + volume_offset_db + linear_to_db(mix)
	if not player.playing:
		player.play()


## Mismo motivo que en EntityAudio: el bucle se declara aquí y no en el .import de cada clip.
func _force_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav != null:
		if wav.loop_end <= wav.loop_begin:
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return
	if "loop" in stream:
		stream.set(&"loop", true)
