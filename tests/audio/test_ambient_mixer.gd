extends Node

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var wav := AudioStreamWAV.new()
	wav.mix_rate = 8000
	wav.data = PackedByteArray([0, 1, 2, 3, 4, 3, 2, 1])
	SoundEvent.force_loop(wav)
	check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == 8,
		"El WAV completo se repite aunque el importador no defina un rango")
	wav.loop_begin = 2
	wav.loop_end = 6
	SoundEvent.force_loop(wav)
	check(wav.loop_begin == 2 and wav.loop_end == 6, "Se respeta un rango de bucle existente")
	var event := SoundEvent.new()
	event.streams = [wav]
	event.volume_db = -6.0
	AudioManager._events[&"test_bed"] = event
	AudioManager._events[&"test_missing_bed"] = SoundEvent.new()
	var host := Node.new()
	add_child(host)
	var mixer := AmbientBedMixer.new(host, [&"test_bed", &"test_missing_bed"])
	var voice := host.get_child(0) as AudioStreamPlayer
	check(not voice.playing, "Las pistas nacen en silencio")
	mixer.target[0] = 1.0
	mixer.target[1] = 1.0
	mixer.update(0.5, 1.0, -3.0, 0.001)
	check(voice.playing and is_equal_approx(voice.volume_db, -9.0 + linear_to_db(0.5)),
		"El fundido suma la ganancia lineal, el volumen del evento y el ajuste global")
	check(not (host.get_child(1) as AudioStreamPlayer).playing, "Un evento sin clip queda mudo")
	mixer.target.fill(0.0)
	mixer.update(0.5, 1.0, 0.0, 0.001)
	check(not voice.playing, "Al llegar al silencio se detiene la pista")
	AudioManager._events.erase(&"test_bed")
	AudioManager._events.erase(&"test_missing_bed")
	host.free()
	print("AMBIENT MIXER: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
