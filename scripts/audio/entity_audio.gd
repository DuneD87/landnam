class_name EntityAudio
extends Node

## Componente de audio de una entidad: mantiene su sonido continuo (fuego, motor, chapoteo) en un
## AudioStreamPlayer3D propio con fundido de entrada y salida, y traduce señales de su nodo padre
## a one-shots del AudioManager. Con él, ningún script de gameplay llama al audio: se cuelga en la
## escena y se configura desde el inspector.
## El loop se apaga solo cuando los oídos se alejan; lo decide el barrido del AudioManager, para
## no pagar un _process por cada antorcha del mundo.

## Evento continuo mientras la entidad exista. Vacío = sin loop.
@export var loop_event: StringName = &""
## Si false, el loop no arranca solo: lo enciende quien quiera con set_loop_active().
@export var loop_autostart: bool = true
## Señales del nodo padre → evento one-shot a disparar en la posición de la entidad.
@export var signal_events: Dictionary[StringName, StringName] = {}
## Nodo cuya posición sigue el sonido. Vacío = el primer Node3D subiendo desde este componente.
@export var target_path: NodePath

## Margen sobre el alcance del evento a partir del cual el loop se apaga. Solo sirve para que un
## sonido en la frontera no se encienda y se apague en cada barrido.
const CULL_HYSTERESIS := 1.25

var _target: Node3D
var _loop_player: AudioStreamPlayer3D
var _loop_tween: Tween
var _loop_event_res: SoundEvent
## Lo que pide el juego, y lo que permite la distancia. El loop suena solo si ambos son true.
var _loop_wanted: bool = false
var _loop_audible: bool = true


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		_target = _find_target()
	_connect_signal_events()
	if loop_event == &"":
		return
	_loop_event_res = AudioManager.get_event(loop_event)
	if _loop_event_res == null or not _loop_event_res.is_valid():
		return
	AudioManager.register_loop(self)
	if not loop_autostart:
		return
	_loop_wanted = true
	# La voz se cuelga del objetivo, y add_child falla si el padre sigue inicializándose: es
	# exactamente lo que pasa cuando la escena se instancia en runtime (equiparse la antorcha),
	# porque este _ready corre dentro del add_child del subárbol entero. Diferirlo lo saca de
	# esa ventana.
	_refresh_loop.call_deferred()


## Enciende o apaga el sonido continuo. El fundido y el alcance salen de su SoundEvent.
func set_loop_active(active: bool) -> void:
	_loop_wanted = active
	_refresh_loop()


## Reevalúa el loop contra la posición de los oídos. La llama el barrido del AudioManager.
func update_distance_cull(ears: Vector3) -> void:
	if _loop_event_res == null or _target == null or not is_instance_valid(_target):
		return
	# Un objeto de equipo desequipado sale del árbol pero sigue vivo (equip_item hace
	# remove_child sin liberar). Fuera del árbol no hay global_position que valga.
	if not _target.is_inside_tree():
		return
	var reach: float = _loop_event_res.max_distance
	if _loop_audible:
		reach *= CULL_HYSTERESIS
	var audible := _target.global_position.distance_squared_to(ears) <= reach * reach
	if audible == _loop_audible:
		# Reintento: si debería sonar y aún no tiene voz, es que no se pudo crear cuando tocaba.
		if _loop_wanted and _loop_audible and _loop_player == null:
			_refresh_loop()
		return
	_loop_audible = audible
	_refresh_loop()


## Dispara un one-shot en la posición de la entidad. Útil desde código cuando el disparador no
## es una señal (una animación, una máquina de estados).
func fire(event_id: StringName, opts: Dictionary = {}) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		return
	AudioManager.play_3d(event_id, _target.global_position, opts)


func _refresh_loop() -> void:
	var active := _loop_wanted and _loop_audible
	if not is_instance_valid(_loop_player):
		_loop_player = null
	if active and _loop_player == null:
		_loop_player = _make_loop_player(_loop_event_res)
	if _loop_player == null:
		return

	if _loop_tween != null and _loop_tween.is_valid():
		_loop_tween.kill()
	_loop_tween = create_tween()
	if active:
		if not _loop_player.playing:
			_loop_player.volume_db = -60.0
			_loop_player.play()
		_loop_tween.tween_property(_loop_player, "volume_db", _loop_event_res.volume_db,
			_loop_event_res.fade_time)
	else:
		_loop_tween.tween_property(_loop_player, "volume_db", -60.0, _loop_event_res.fade_time)
		_loop_tween.tween_callback(_loop_player.stop)


func _make_loop_player(ev: SoundEvent) -> AudioStreamPlayer3D:
	var stream := ev.pick_stream()
	if stream == null:
		return null
	_force_loop(stream)
	var player := AudioStreamPlayer3D.new()
	player.name = "LoopVoice"
	player.stream = stream
	player.bus = ev.bus
	player.max_distance = ev.max_distance
	player.unit_size = ev.unit_size
	player.attenuation_model = ev.attenuation
	player.pitch_scale = ev.roll_pitch()
	player.volume_db = -60.0
	# Cuelga del objetivo para heredar su transform: así viaja con la entidad y con los rebases
	# del origen flotante sin depender del grupo.
	var host: Node = _target if _target != null else self
	if not host.is_inside_tree():
		player.free()
		return null
	host.add_child(player)
	return player


## Fuerza el bucle del clip. Cada formato lo expone a su manera —el WAV por loop_mode y por
## rango en frames, el resto por una propiedad "loop"—, y olvidarlo en el .import deja un
## sonido continuo que suena una vez y calla.
func _force_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav != null:
		if wav.loop_end <= wav.loop_begin:
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return
	if "loop" in stream:
		stream.set(&"loop", true)


## Conecta cada señal declarada. La aridad se lee del nodo padre porque connect() exige que el
## handler la respete, y aquí no se sabe de antemano.
func _connect_signal_events() -> void:
	if signal_events.is_empty():
		return
	var host := get_parent()
	if host == null:
		return
	var arity: Dictionary = {}
	for s in host.get_signal_list():
		arity[StringName(s["name"])] = (s["args"] as Array).size()

	for sig in signal_events:
		if not arity.has(sig):
			push_warning("[EntityAudio] %s no declara la señal %s." % [host.name, sig])
			continue
		var handler := _handler_for(int(arity[sig]))
		if handler.is_null():
			push_warning("[EntityAudio] Señal %s con demasiados argumentos." % sig)
			continue
		host.connect(sig, handler.bind(signal_events[sig]))


func _handler_for(argc: int) -> Callable:
	match argc:
		0: return _on_signal_0
		1: return _on_signal_1
		2: return _on_signal_2
		3: return _on_signal_3
	return Callable()


func _on_signal_0(event_id: StringName) -> void:
	fire(event_id)


func _on_signal_1(_a: Variant, event_id: StringName) -> void:
	fire(event_id)


func _on_signal_2(_a: Variant, _b: Variant, event_id: StringName) -> void:
	fire(event_id)


func _on_signal_3(_a: Variant, _b: Variant, _c: Variant, event_id: StringName) -> void:
	fire(event_id)


## Primer Node3D subiendo por la jerarquía: el componente puede colgar de un Node plano.
func _find_target() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is Node3D:
			return n
		n = n.get_parent()
	return null
