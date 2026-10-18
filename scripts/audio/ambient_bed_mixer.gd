class_name AmbientBedMixer
extends RefCounted

## Pistas ambientales con ganancias lineales: el mundo decide los objetivos y este mezclador
## lleva los fundidos, el volumen de cada evento y el arranque/parada al entrar o salir del silencio.
var target := PackedFloat32Array()
var _mix := PackedFloat32Array()
var _players: Array[AudioStreamPlayer] = []
var _events: Array[SoundEvent] = []


func _init(host: Node, event_ids: Array[StringName]) -> void:
	target.resize(event_ids.size())
	_mix.resize(event_ids.size())
	for event_id in event_ids:
		var event := AudioManager.get_event(event_id)
		_events.append(event)
		var player := AudioStreamPlayer.new()
		player.name = String(event_id)
		if event != null and event.is_valid():
			player.stream = event.pick_stream()
			player.bus = event.bus
			SoundEvent.force_loop(player.stream)
		player.volume_db = -80.0
		host.add_child(player)
		_players.append(player)


func update(delta: float, blend_speed: float, volume_offset_db: float,
		silence_threshold: float) -> void:
	for i in _players.size():
		var moved := move_toward(_mix[i], target[i], blend_speed * delta)
		if is_equal_approx(moved, _mix[i]):
			continue
		_mix[i] = moved
		var player := _players[i]
		if player.stream == null:
			continue
		if moved <= silence_threshold:
			if player.playing:
				player.stop()
			continue
		var event := _events[i]
		var base := event.volume_db if event != null else 0.0
		player.volume_db = base + volume_offset_db + linear_to_db(moved)
		if not player.playing:
			player.play()
