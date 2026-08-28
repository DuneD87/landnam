class_name WaterAmbience
extends Node

## Lecho sonoro del agua del planeta: mar, lagos y ríos. Todas las camas suenan a la vez y lo que
## cambia son sus volúmenes, cruzados por factores continuos. No hay estados ni transiciones que
## programar: navegar de la rompiente a alta mar mientras arrecia es un deslizamiento de la mezcla.
##
## Ningún factor es una medida nueva. La distancia al litoral la da el campo de orilla horneado, el
## mismo que decide dónde dibuja el shader la rompiente. El estado de mar sale de
## WaterHeightSampler.get_sea_state(), la misma medida con la que la física resuelve la corriente.
## Y los ríos salen de la red de cauces de RiverField, la misma que talló el terreno: por eso el
## rumor del agua está donde está el cauce y no donde lo pondría una aproximación aparte.
##
## Va sin posicionar y en el bus Ambient: el agua es un fondo difuso, y el filtro de sumergido del
## AudioManager ya lo apaga al meter la cabeza.

## Camas, en el orden en que se mezclan. Cualquiera puede faltar del catálogo: esa se queda muda y
## las demás siguen.
const BED_SHORE_CALM := 0
const BED_SHORE_STORM := 1
const BED_OPEN_CALM := 2
const BED_OPEN_STORM := 3
const BED_LAKE_CALM := 4
const BED_LAKE_STORM := 5
const BED_RIVER := 6
const EVENTS: Array[StringName] = [
	&"ocean_shore_calm", &"ocean_shore_storm", &"ocean_calm", &"ocean_storm",
	&"lake_calm", &"lake_storm", &"river",
]

## Cada cuánto se reevalúa la mezcla. El agua no cambia de humor en un frame y cada evaluación
## barre la red de cauces: a 10 Hz sobra y no aparece en el perfil.
const UPDATE_INTERVAL := 0.1
## Margen sobre el alcance audible con el que se descartan tramos de río sin hacer la cuenta buena.
## Un tramo mide una celda de hidrología (~180 m en la Tierra), así que con esto no se escapa uno
## que pase cerca aunque sus dos extremos queden lejos.
const RIVER_CULL_MARGIN := 400.0

@export_group("Mar y lagos")
## Metros tierra adentro en los que el agua se apaga. El campo de orilla solo cubre
## PlanetWorldMap.SHORE_RANGE (300 m), así que subir de ahí no hace nada sin rehornear el mapa.
@export var inland_range: float = 250.0
## Altitudes (m sobre el nivel del mar) entre las que el agua se apaga por altura. Sin esto, un
## acantilado a pie de costa sonaría igual de fuerte que la playa.
@export var altitude_quiet_start: float = 80.0
@export var altitude_quiet_full: float = 300.0

@export_group("Ríos")
## Metros desde la orilla del cauce a los que se deja de oír el río.
@export var river_range: float = 120.0
## Volumen relativo del cauce más estrecho frente al más ancho. La red guarda la semianchura de
## cada tramo, así que un arroyo no tiene por qué sonar como un río grande.
@export_range(0.0, 1.0) var river_narrow_gain: float = 0.6

@export_group("Mezcla")
## Velocidad de los cruces, en unidades de mezcla por segundo. Baja = transiciones largas, que es
## justo lo que se quiere aquí.
@export var blend_speed: float = 0.35
@export_range(-24.0, 12.0) var volume_offset_db: float = 0.0
## Por debajo de esta mezcla la voz se para, en vez de quedarse sonando a nada.
@export var silence_threshold: float = 0.001

var _players: Array[AudioStreamPlayer] = []
var _events: Array[SoundEvent] = []
var _mix := PackedFloat32Array()
var _target := PackedFloat32Array()
var _update_timer: float = 0.0

var _world_map: PlanetWorldMap
var _sampler: WaterHeightSampler
## Extremos de cada tramo de río en metros desde el centro del planeta, y su semianchura. Se
## precalculan una vez: la red es estática y reconstruirla por consulta sería el grueso del coste.
var _river_a: PackedVector3Array = PackedVector3Array()
var _river_b: PackedVector3Array = PackedVector3Array()
var _river_half: PackedVector2Array = PackedVector2Array()
var _planet_radius: float = 0.0
## Semianchura mayor de la red, para normalizar el volumen por anchura de cauce.
var _river_max_half: float = 1.0

## Diagnóstico, para el comando 'ocean' de la consola.
var last_shore: float = 0.0
var last_storm: float = 0.0
var last_gain: float = 0.0
var last_river: float = 0.0
var last_is_lake: bool = false


## Lo llama planet_loader cuando el mapa del planeta está listo.
func setup(map: PlanetWorldMap, water_material: ShaderMaterial, planet: Planet) -> void:
	_world_map = map
	if _sampler == null:
		_sampler = WaterHeightSampler.new()
		add_child(_sampler)
	_sampler.setup(water_material, map)
	if planet != null:
		_planet_radius = planet.radius
		_build_river_cache(planet.get_river_network())


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


## Rellena la mezcla que pide el mundo ahora mismo.
func _compute_target() -> void:
	_target.fill(0.0)
	last_gain = 0.0
	last_river = 0.0
	if _world_map == null or not _world_map.is_ready():
		return
	var listener := _listener()
	if listener == null:
		return
	var ears := listener.global_position

	last_storm = _sampler.get_sea_state() if _sampler != null else 0.0
	_target[BED_RIVER] = _river_mix(ears)
	last_river = _target[BED_RIVER]

	last_gain = _standing_water_gain(ears)
	last_shore = _shore_factor(ears)
	if last_gain <= 0.0:
		return

	# Lago y mar se reparten la misma ganancia: o estás junto a uno o junto al otro.
	if last_is_lake:
		_target[BED_LAKE_CALM] = last_gain * (1.0 - last_storm)
		_target[BED_LAKE_STORM] = last_gain * last_storm
		return
	_target[BED_SHORE_CALM] = last_gain * last_shore * (1.0 - last_storm)
	_target[BED_SHORE_STORM] = last_gain * last_shore * last_storm
	_target[BED_OPEN_CALM] = last_gain * (1.0 - last_shore) * (1.0 - last_storm)
	_target[BED_OPEN_STORM] = last_gain * (1.0 - last_shore) * last_storm


## Cuánta agua quieta se oye desde [ears], y de paso si la más cercana es un lago o el mar. Pleno
## sobre el agua, apagándose tierra adentro y con la altura.
func _standing_water_gain(ears: Vector3) -> float:
	var body := _world_map.get_water_body_at(ears)
	var gain := 1.0
	if body.is_empty():
		# Tierra adentro: el cuerpo que se oye es el que hay al otro lado de la línea de costa, y
		# la dirección a tierra que trae el campo dice hacia dónde queda.
		var dist := _shore_distance(ears)
		gain = 1.0 - smoothstep(0.0, inland_range, dist)
		if gain > 0.0:
			body = _world_map.get_water_body_at(_water_side_of_shore(ears, dist))
	last_is_lake = not body.is_empty() and int(body.get("type", 0)) >= WorldMapData.WaterType.LAKE
	gain *= 1.0 - smoothstep(altitude_quiet_start, altitude_quiet_full,
		_world_map.get_altitude(ears))
	return clampf(gain, 0.0, 1.0)


## Punto al otro lado del litoral, en el agua. El campo de orilla da la dirección a TIERRA, así que
## se camina en contra. Un pelo de más para no caer justo en la línea, que es ambigua.
func _water_side_of_shore(ears: Vector3, dist: float) -> Vector3:
	var field := _world_map.shore_sample_local(ears - _world_map.get_planet_center())
	var to_land := Vector3(field.x, field.y, field.z)
	if to_land.length_squared() < 0.0001:
		return ears
	return ears - to_land.normalized() * (dist + 1.0)


## 1 pegado a la rompiente, 0 en mar abierto.
func _shore_factor(ears: Vector3) -> float:
	if not _world_map.has_shore_field():
		return 0.0
	return 1.0 - smoothstep(0.0, _world_map.map.shore_range, _shore_distance(ears))


## Distancia al litoral en metros. El campo la da con signo (a qué lado queda la costa) y aquí solo
## importa cuánto.
func _shore_distance(ears: Vector3) -> float:
	if not _world_map.has_shore_field():
		return INF
	return absf(_world_map.shore_sample_local(ears - _world_map.get_planet_center()).w)


## Mezcla del río: cercanía a la orilla del cauce más próximo, escalada por lo ancho que sea.
func _river_mix(ears: Vector3) -> float:
	if _river_a.is_empty():
		return 0.0
	var p := ears - _world_map.get_planet_center()
	var cull := river_range + RIVER_CULL_MARGIN
	var cull2 := cull * cull
	var best := INF
	var best_half := 0.0

	for i in _river_a.size():
		var pa := _river_a[i]
		var pb := _river_b[i]
		if pa.distance_squared_to(p) > cull2 and pb.distance_squared_to(p) > cull2:
			continue
		var ab := pb - pa
		var ab2 := ab.length_squared()
		var t := 0.0 if ab2 < 0.0001 else clampf((p - pa).dot(ab) / ab2, 0.0, 1.0)
		var half: float = lerpf(_river_half[i].x, _river_half[i].y, t)
		# Distancia a la ORILLA, no al eje: es la misma cuenta que hace RiverField al rasterizar.
		var edge := p.distance_to(pa + ab * t) - half
		if edge < best:
			best = edge
			best_half = half

	if best >= river_range:
		return 0.0
	var proximity := 1.0 - smoothstep(0.0, river_range, maxf(best, 0.0))
	# Un arroyo no suena como un río grande. El rango de semianchuras lo fija el propio planeta.
	var width := clampf(best_half / maxf(_river_max_half, 0.001), 0.0, 1.0)
	return proximity * lerpf(river_narrow_gain, 1.0, width)


## Pasa la sopa de segmentos a posiciones en metros. Vienen en coordenadas del mapa de hidrología,
## que usa la convención acos igual que WorldMapData (ver RiverField.hydro_dir).
func _build_river_cache(field: Dictionary) -> void:
	_river_a.clear()
	_river_b.clear()
	_river_half.clear()
	var count := int(field.get("segments", 0))
	if count <= 0:
		return
	var seg = field.get("seg", PackedFloat32Array())
	var hydro: Vector2i = field.get("hydro_size", Vector2i.ZERO)
	var radius := float(field.get("radius", _planet_radius))
	if seg.size() < count * 8 or hydro.x <= 0 or radius <= 0.0:
		return

	_river_max_half = 0.001
	for k in count:
		var o := k * 8
		_river_a.append(RiverField.hydro_dir(seg[o], seg[o + 1], hydro.x, hydro.y) * radius)
		_river_b.append(RiverField.hydro_dir(seg[o + 2], seg[o + 3], hydro.x, hydro.y) * radius)
		_river_half.append(Vector2(seg[o + 6], seg[o + 7]))
		_river_max_half = maxf(_river_max_half, maxf(seg[o + 6], seg[o + 7]))
	print("[WaterAmbience] %d tramos de rio en la mezcla." % count)


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
