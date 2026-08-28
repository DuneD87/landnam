class_name OceanAmbience
extends Node

## Lecho sonoro del océano: cuatro loops (costa/alta mar × calma/temporal) sonando a la vez, con
## los volúmenes cruzados por dos factores continuos. No hay saltos entre "estados" porque no hay
## estados: la mezcla es el producto de la cercanía a la costa por el estado de mar.
##
## Los dos factores salen de lo que el juego ya sabe, no de medidas nuevas. La distancia al litoral
## la da el campo de orilla horneado, el mismo que decide dónde dibuja el shader la rompiente; el
## estado de mar sale de WaterHeightSampler.get_sea_state(), la misma medida con la que la física
## resuelve la corriente. Si audio y agua discrepasen sobre cuánto sopla, se notaría antes aquí.
##
## Va sin posicionar y en el bus Ambient: el mar es un fondo difuso, y el filtro de sumergido del
## AudioManager ya lo apaga al meter la cabeza.

## Eventos del catálogo, en el orden en que se mezclan: costa calma, costa temporal, mar abierto
## calma, mar abierto temporal.
const EVENTS: Array[StringName] = [
	&"ocean_shore_calm", &"ocean_shore_storm", &"ocean_calm", &"ocean_storm",
]

## Cada cuánto se reevalúa la mezcla. El mar no cambia de humor en un frame, y cada evaluación
## muestrea el campo de orilla: a 10 Hz sobra y no aparece en el perfil.
const UPDATE_INTERVAL := 0.1

## Metros tierra adentro en los que el mar se apaga. El campo de orilla solo cubre
## PlanetWorldMap.SHORE_RANGE (300 m), así que subir de ahí no hace nada sin rehornear el mapa.
@export var inland_range: float = 250.0
## Altitudes (m sobre el nivel del mar) entre las que el mar se apaga por altura. Sin esto, un
## acantilado a pie de costa sonaría igual de fuerte que la playa.
@export var altitude_quiet_start: float = 80.0
@export var altitude_quiet_full: float = 300.0
## Velocidad de los cruces, en unidades de mezcla por segundo. Baja = transiciones largas, que es
## justo lo que se quiere aquí.
@export var blend_speed: float = 0.35
## Desplazamiento de volumen del conjunto, para cuadrarlo con el resto de la mezcla.
@export_range(-24.0, 12.0) var volume_offset_db: float = 0.0
## Por debajo de esta mezcla la voz se para, en vez de quedarse sonando a nada.
@export var silence_threshold: float = 0.001

var _players: Array[AudioStreamPlayer] = []
var _events: Array[SoundEvent] = []
var _mix := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _target := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _update_timer: float = 0.0

var _world_map: PlanetWorldMap
var _sampler: WaterHeightSampler

## Diagnóstico, para el comando 'ocean' de la consola.
var last_shore: float = 0.0
var last_storm: float = 0.0
var last_gain: float = 0.0


## Lo llama planet_loader cuando el mapa del planeta está listo.
func setup(map: PlanetWorldMap, water_material: ShaderMaterial) -> void:
	_world_map = map
	if _sampler == null:
		_sampler = WaterHeightSampler.new()
		add_child(_sampler)
	_sampler.setup(water_material, map)


func _ready() -> void:
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
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_target = _compute_target()

	var step := blend_speed * delta
	for i in _players.size():
		var moved := move_toward(_mix[i], _target[i], step)
		if not is_equal_approx(moved, _mix[i]):
			_mix[i] = moved
			_apply(i)


## Mezcla que pide el mundo: cercanía a la costa por estado de mar, escalado por cuánto mar se oye
## desde donde están los oídos.
func _compute_target() -> PackedFloat32Array:
	var silent := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if _world_map == null or not _world_map.is_ready():
		return silent
	var listener := _listener()
	if listener == null:
		return silent

	var ears := listener.global_position
	last_gain = _water_gain(ears)
	last_shore = _shore_factor(ears)
	last_storm = _sampler.get_sea_state() if _sampler != null else 0.0
	if last_gain <= 0.0:
		return silent

	return PackedFloat32Array([
		last_gain * last_shore * (1.0 - last_storm),
		last_gain * last_shore * last_storm,
		last_gain * (1.0 - last_shore) * (1.0 - last_storm),
		last_gain * (1.0 - last_shore) * last_storm,
	])


## Cuánto mar se oye desde [ears]: pleno sobre el agua, apagándose tierra adentro y con la altura.
func _water_gain(ears: Vector3) -> float:
	var gain := 1.0
	if not _world_map.is_water_at(ears):
		gain = 1.0 - smoothstep(0.0, inland_range, _shore_distance(ears))
	gain *= 1.0 - smoothstep(altitude_quiet_start, altitude_quiet_full,
		_world_map.get_altitude(ears))
	return clampf(gain, 0.0, 1.0)


## 1 pegado a la rompiente, 0 en mar abierto.
func _shore_factor(ears: Vector3) -> float:
	if not _world_map.has_shore_field():
		return 0.0
	return 1.0 - smoothstep(0.0, _world_map.map.shore_range, _shore_distance(ears))


## Distancia al litoral en metros. El campo la da con signo (a qué lado de la costa), y aquí solo
## importa cuánto.
func _shore_distance(ears: Vector3) -> float:
	if not _world_map.has_shore_field():
		return INF
	# El centro vivo lo da el propio mapa, que es lo que hace que el origen flotante no descuadre.
	return absf(_world_map.shore_sample_local(ears - _world_map.get_planet_center()).w)


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


func _listener() -> Node3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var listener := viewport.get_audio_listener_3d()
	return listener if listener != null else viewport.get_camera_3d()


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
