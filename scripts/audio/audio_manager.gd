extends Node

## AudioManager (autoload): catálogo de SoundEvent + pool de voces.
## Los one-shot se piden aquí (play_3d / play_ui) y salen de un pool prewarmeado — crear
## AudioStreamPlayer3D por evento es asignación y trasiego de árbol en el peor momento. Aplica
## los topes del evento (voces, cooldown) y el descarte por distancia ANTES de coger voz, y
## filtra los buses cuando los oídos se sumergen. Registrar como autoload "AudioManager".

## Carpeta que se escanea al arrancar. Cada .tres de SoundEvent que caiga ahí entra al catálogo.
const EVENTS_DIR := "res://data/audio/events/"
const POOL_3D_SIZE := 24
const POOL_2D_SIZE := 8

## Buses que se apagan al sumergirse, y la frecuencia de corte del filtro cuando lo están.
const FILTERED_BUSES: Array[StringName] = [&"SFX", &"Ambient", &"Voice"]
const OPEN_AIR_CUTOFF_HZ := 20500.0
const UNDERWATER_CUTOFF_HZ := 480.0
## Segundos que tarda el filtro en abrirse o cerrarse al cruzar la superficie.
const UNDERWATER_FADE_TIME := 0.35

## Cada cuánto se revisa qué sonidos continuos siguen al alcance del oyente. Un barrido
## central sale mucho más barato que un _process por cada antorcha del mundo.
const LOOP_CULL_INTERVAL := 0.4

var _events: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
## event_id -> voces sonando ahora mismo.
var _active_voices: Dictionary = {}
## event_id -> ticks_msec a partir del cual el evento vuelve a poder sonar.
var _next_allowed: Dictionary = {}
var _missing_warned: Dictionary = {}

var _underwater: bool = false
var _underwater_blend: float = 0.0
## Índices [bus, efecto] de cada filtro paso bajo encontrado en FILTERED_BUSES.
var _filters: Array[Vector2i] = []

## Sonidos continuos registrados. Las entradas muertas se limpian en el propio barrido.
var _loops: Array[EntityAudio] = []
var _loop_cull_timer: float = 0.0

## Diagnóstico: one-shots que no llegaron a sonar, por motivo.
var dropped_no_voice: int = 0
var dropped_budget: int = 0
var dropped_distance: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_catalog()
	_build_pools()
	_find_filters()
	_apply_underwater_filter(0.0)


func _process(delta: float) -> void:
	_loop_cull_timer -= delta
	if _loop_cull_timer <= 0.0:
		_loop_cull_timer = LOOP_CULL_INTERVAL
		_cull_loops()

	var target := 1.0 if _underwater else 0.0
	if is_equal_approx(_underwater_blend, target):
		return
	var step := delta / maxf(UNDERWATER_FADE_TIME, 0.001)
	_underwater_blend = move_toward(_underwater_blend, target, step)
	_apply_underwater_filter(_underwater_blend)


## Dispara [event_id] en [world_pos]. Devuelve el player usado, o null si se descartó (evento
## desconocido o mudo, fuera de alcance, en cooldown o sin voces libres).
## [opts] admite "bus", "pitch", "volume_db" (sustituye al del .tres) y "volume_offset_db"
## (lo desplaza, para intensidades que dependen del gameplay).
func play_3d(event_id: StringName, world_pos: Vector3, opts: Dictionary = {}) -> AudioStreamPlayer3D:
	var ev := get_event(event_id)
	if ev == null or not ev.is_valid():
		return null
	var listener := _get_listener()
	if listener != null:
		var reach: float = ev.max_distance
		if listener.global_position.distance_squared_to(world_pos) > reach * reach:
			dropped_distance += 1
			return null
	if not _budget_allows(ev):
		dropped_budget += 1
		return null

	var player := _acquire_3d()
	if player == null:
		dropped_no_voice += 1
		return null

	player.stream = ev.pick_stream()
	player.bus = opts.get("bus", ev.bus)
	player.volume_db = opts.get("volume_db", ev.roll_volume_db()) + opts.get("volume_offset_db", 0.0)
	player.pitch_scale = opts.get("pitch", ev.roll_pitch())
	player.max_distance = ev.max_distance
	player.unit_size = ev.unit_size
	player.attenuation_model = ev.attenuation
	player.global_position = world_pos
	player.set_meta(&"event_id", ev.event_id)
	# El origen flotante desplaza el mundo bajo los pies: una voz que dure más que un rebase se
	# quedaría a 4 km de donde suena si no viajase con él (ver FloatingOrigin._rebase).
	player.add_to_group(&"floating_origin")
	_active_voices[ev.event_id] = int(_active_voices.get(ev.event_id, 0)) + 1
	player.play()
	return player


## Dispara la variante de [prefix] para la familia de material [sound_material], cayendo al evento
## genérico si esa familia no tiene sonido propio. Es lo que permite añadir un material nuevo sin
## tocar código: basta con dejar caer "<prefix>_<familia>.tres" en el catálogo.
func play_material(prefix: StringName, sound_material: StringName, world_pos: Vector3,
		opts: Dictionary = {}) -> AudioStreamPlayer3D:
	if sound_material != &"":
		var specific := StringName("%s_%s" % [prefix, sound_material])
		# Declarado PERO sin clip cuenta como no declarado: un .tres preparado por adelantado,
		# esperando a que lleguen los audios, no puede dejar mudo al evento genérico.
		var ev: SoundEvent = _events.get(specific)
		if ev != null and ev.is_valid():
			return play_3d(specific, world_pos, opts)
	return play_3d(prefix, world_pos, opts)


## Dispara [event_id] sin posición (UI, notificaciones, narración).
func play_ui(event_id: StringName, opts: Dictionary = {}) -> AudioStreamPlayer:
	var ev := get_event(event_id)
	if ev == null or not ev.is_valid():
		return null
	if not _budget_allows(ev):
		dropped_budget += 1
		return null

	var player := _acquire_2d()
	if player == null:
		dropped_no_voice += 1
		return null

	player.stream = ev.pick_stream()
	player.bus = opts.get("bus", ev.bus)
	player.volume_db = opts.get("volume_db", ev.roll_volume_db()) + opts.get("volume_offset_db", 0.0)
	player.pitch_scale = opts.get("pitch", ev.roll_pitch())
	player.set_meta(&"event_id", ev.event_id)
	_active_voices[ev.event_id] = int(_active_voices.get(ev.event_id, 0)) + 1
	player.play()
	return player


func get_event(event_id: StringName) -> SoundEvent:
	var ev: SoundEvent = _events.get(event_id)
	if ev == null and not _missing_warned.has(event_id):
		_missing_warned[event_id] = true
		push_warning("[AudioManager] Evento de audio desconocido: %s" % event_id)
	return ev


## Da de alta un sonido continuo en el barrido de distancia. No hace falta darse de baja.
func register_loop(entity: EntityAudio) -> void:
	if _loops.has(entity):
		return
	_loops.append(entity)
	var listener := _get_listener()
	if listener != null:
		entity.update_distance_cull(listener.global_position)


func has_event(event_id: StringName) -> bool:
	return _events.has(event_id)


## Cierra o abre el filtro de los buses espaciales. Lo llama quien sepa dónde están los oídos
## (el jugador, con la cámara y el radio de la superficie del agua).
func set_underwater(active: bool) -> void:
	_underwater = active


## Volumen de un bus en lineal [0..1], para el menú de opciones.
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


func get_bus_volume(bus_name: StringName) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


## Estado del pool y descartes acumulados, para la consola de depuración.
func get_debug_stats() -> Dictionary:
	var busy_3d := 0
	for p in _pool_3d:
		if p.playing:
			busy_3d += 1
	return {
		"events": _events.size(),
		"voices_3d": "%d/%d" % [busy_3d, _pool_3d.size()],
		"dropped_no_voice": dropped_no_voice,
		"dropped_budget": dropped_budget,
		"dropped_distance": dropped_distance,
		"loops": _loops.size(),
		"underwater": _underwater,
	}


## Carga los SoundEvent de EVENTS_DIR. La clave es event_id, o el nombre del archivo si está vacío.
func _load_catalog() -> void:
	var dir := DirAccess.open(EVENTS_DIR)
	if dir == null:
		push_warning("[AudioManager] No existe %s; catálogo vacío." % EVENTS_DIR)
		return
	for file_name in dir.get_files():
		# En un build exportado los recursos llegan con sufijo .remap.
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres") and not clean.ends_with(".res"):
			continue
		var ev := load(EVENTS_DIR + clean) as SoundEvent
		if ev == null:
			continue
		if ev.event_id == &"":
			ev.event_id = StringName(clean.get_basename())
		if _events.has(ev.event_id):
			push_warning("[AudioManager] Evento duplicado: %s" % ev.event_id)
		_events[ev.event_id] = ev
	print("[AudioManager] Catálogo: %d eventos." % _events.size())


func _build_pools() -> void:
	for i in POOL_3D_SIZE:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Voice3D_%d" % i
		p3.bus = "SFX"
		p3.finished.connect(_on_voice_finished.bind(p3))
		add_child(p3)
		_pool_3d.append(p3)
	for i in POOL_2D_SIZE:
		var p2 := AudioStreamPlayer.new()
		p2.name = "Voice2D_%d" % i
		p2.bus = "UI"
		p2.finished.connect(_on_voice_finished.bind(p2))
		add_child(p2)
		_pool_2d.append(p2)


## Localiza el paso bajo de cada bus filtrado. Sin él (layout sin efectos) el sumergido
## simplemente no filtra, en vez de reventar.
func _find_filters() -> void:
	for bus_name in FILTERED_BUSES:
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			continue
		for effect_index in AudioServer.get_bus_effect_count(bus_index):
			if AudioServer.get_bus_effect(bus_index, effect_index) is AudioEffectLowPassFilter:
				_filters.append(Vector2i(bus_index, effect_index))
				break


func _apply_underwater_filter(blend: float) -> void:
	var cutoff := lerpf(OPEN_AIR_CUTOFF_HZ, UNDERWATER_CUTOFF_HZ, blend)
	var enabled := blend > 0.001
	for f in _filters:
		var effect := AudioServer.get_bus_effect(f.x, f.y) as AudioEffectLowPassFilter
		if effect == null:
			continue
		effect.cutoff_hz = cutoff
		AudioServer.set_bus_effect_enabled(f.x, f.y, enabled)


## Apaga los loops fuera de alcance y aprovecha para soltar los de entidades ya liberadas.
func _cull_loops() -> void:
	if _loops.is_empty():
		return
	var listener := _get_listener()
	if listener == null:
		return
	var ears := listener.global_position
	var alive: Array[EntityAudio] = []
	for entity in _loops:
		if not is_instance_valid(entity):
			continue
		alive.append(entity)
		entity.update_distance_cull(ears)
	_loops = alive


func _budget_allows(ev: SoundEvent) -> bool:
	if int(_active_voices.get(ev.event_id, 0)) >= ev.max_voices:
		return false
	if ev.cooldown > 0.0:
		var now := Time.get_ticks_msec()
		if now < int(_next_allowed.get(ev.event_id, 0)):
			return false
		_next_allowed[ev.event_id] = now + int(ev.cooldown * 1000.0)
	return true


func _acquire_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	return null


func _acquire_2d() -> AudioStreamPlayer:
	for p in _pool_2d:
		if not p.playing:
			return p
	return null


func _on_voice_finished(player: Node) -> void:
	var event_id: StringName = player.get_meta(&"event_id", &"")
	if event_id != &"":
		_active_voices[event_id] = maxi(0, int(_active_voices.get(event_id, 0)) - 1)
		player.remove_meta(&"event_id")
	if player is AudioStreamPlayer3D:
		player.remove_from_group(&"floating_origin")


## Los oídos están en la cámara activa, no en el jugador (la tercera persona los separa metros).
func _get_listener() -> Node3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var listener := viewport.get_audio_listener_3d()
	if listener != null:
		return listener
	return viewport.get_camera_3d()
