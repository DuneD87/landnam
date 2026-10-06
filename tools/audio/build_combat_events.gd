extends SceneTree

## Un SoundEvent por carpeta de audio/combat/ (los clips que deja build_combat_sounds.py), en
## data/audio/events/combat_<evento>.tres, con su mezcla. CombatFx los pide por "combat_<id>" y,
## si un evento no está, suena su versión sintetizada.
##   godot --headless --path . --script res://tools/audio/build_combat_events.gd
## (tras importar los clips: godot --headless --editor --quit --path .)

const CLIPS := "res://audio/combat"
const EVENTS := "res://data/audio/events"

## Mezcla de cada evento: bus, volumen (dB), tono, variación de tono, alcance (m), radio sin
## atenuar (m), voces a la vez y cooldown (s). "clips": otra carpeta de la que tomar los clips.
const MIX := {
	&"swing_light": {"volume": -6.0, "pitch_jitter": 0.06, "max": 30.0, "unit": 3.0, "voices": 4, "cooldown": 0.03},
	&"swing_heavy": {"volume": -4.0, "pitch": 0.82, "pitch_jitter": 0.05, "max": 35.0, "unit": 3.0, "voices": 4, "cooldown": 0.03},
	# El zarpazo de las fieras: los silbidos pesados, más graves.
	&"claw_swipe": {"clips": &"swing_heavy", "volume": -2.0, "pitch": 0.68, "pitch_jitter": 0.06, "max": 50.0, "unit": 4.0, "voices": 3, "cooldown": 0.05},
	&"hit_slash": {"volume": -1.0, "pitch_jitter": 0.06, "max": 40.0, "unit": 4.0, "voices": 6, "cooldown": 0.02},
	&"hit_pierce": {"volume": -2.0, "pitch_jitter": 0.06, "max": 40.0, "unit": 4.0, "voices": 6, "cooldown": 0.02},
	&"hit_blunt": {"volume": 0.0, "pitch_jitter": 0.06, "max": 40.0, "unit": 4.0, "voices": 6, "cooldown": 0.02},
	&"hit_world": {"volume": -6.0, "pitch_jitter": 0.08, "max": 30.0, "unit": 3.0, "voices": 4, "cooldown": 0.03},
	&"bow_release": {"volume": -4.0, "pitch_jitter": 0.04, "max": 40.0, "unit": 3.0, "voices": 3, "cooldown": 0.05},
	&"throw": {"volume": -5.0, "pitch_jitter": 0.06, "max": 30.0, "unit": 3.0, "voices": 3, "cooldown": 0.05},
	&"player_hurt": {"bus": "Voice", "volume": -3.0, "pitch_jitter": 0.04, "max": 30.0, "unit": 3.0, "voices": 2, "cooldown": 0.2},
	&"player_death": {"bus": "Voice", "volume": 0.0, "pitch_jitter": 0.03, "max": 40.0, "unit": 4.0, "voices": 1, "cooldown": 1.0},
	&"player_hurt_female": {"bus": "Voice", "volume": -3.0, "pitch_jitter": 0.04, "max": 30.0, "unit": 3.0, "voices": 2, "cooldown": 0.2},
	&"player_death_female": {"bus": "Voice", "volume": 0.0, "pitch_jitter": 0.03, "max": 40.0, "unit": 4.0, "voices": 1, "cooldown": 1.0},
	&"bear_growl": {"volume": -2.0, "pitch_jitter": 0.06, "max": 60.0, "unit": 6.0, "voices": 3, "cooldown": 0.5},
	&"bear_roar": {"volume": 2.0, "pitch_jitter": 0.05, "max": 90.0, "unit": 8.0, "voices": 2, "cooldown": 1.0},
	&"bear_huff": {"volume": -2.0, "pitch_jitter": 0.06, "max": 40.0, "unit": 5.0, "voices": 2, "cooldown": 0.3},
	&"bear_hurt": {"volume": -1.0, "pitch": 1.15, "pitch_jitter": 0.06, "max": 50.0, "unit": 5.0, "voices": 2, "cooldown": 0.35},
	&"bear_death": {"volume": 0.0, "pitch": 0.9, "pitch_jitter": 0.04, "max": 70.0, "unit": 6.0, "voices": 2, "cooldown": 1.0},
	&"lion_roar": {"volume": 3.0, "pitch_jitter": 0.04, "max": 120.0, "unit": 8.0, "voices": 2, "cooldown": 1.0},
	&"lion_growl": {"volume": -2.0, "pitch_jitter": 0.06, "max": 60.0, "unit": 6.0, "voices": 3, "cooldown": 0.5},
	&"lion_hurt": {"volume": -1.0, "pitch": 1.1, "pitch_jitter": 0.06, "max": 50.0, "unit": 5.0, "voices": 2, "cooldown": 0.35},
	&"lion_death": {"volume": 0.0, "pitch": 0.92, "pitch_jitter": 0.04, "max": 70.0, "unit": 6.0, "voices": 2, "cooldown": 1.0},
}


func _initialize() -> void:
	var made := 0
	for id in MIX:
		var mix: Dictionary = MIX[id]
		var folder := "%s/%s" % [CLIPS, mix.get("clips", id)]
		var streams: Array[AudioStream] = []
		for file in DirAccess.get_files_at(folder):
			var clean := file.trim_suffix(".import")
			if clean.ends_with(".ogg") and not streams.any(func(s): return s.resource_path.ends_with(clean)):
				var stream := load("%s/%s" % [folder, clean]) as AudioStream
				if stream != null:
					streams.append(stream)
		if streams.is_empty():
			push_error("Sin clips en %s (¿importados?)" % folder)
			continue
		var ev := SoundEvent.new()
		ev.event_id = StringName("combat_" + String(id))
		ev.streams = streams
		ev.bus = mix.get("bus", "SFX")
		ev.volume_db = mix.get("volume", 0.0)
		ev.volume_jitter_db = 1.5
		ev.pitch = mix.get("pitch", 1.0)
		ev.pitch_jitter = mix.get("pitch_jitter", 0.05)
		ev.max_distance = mix.get("max", 40.0)
		ev.unit_size = mix.get("unit", 4.0)
		ev.max_voices = mix.get("voices", 4)
		ev.cooldown = mix.get("cooldown", 0.05)
		var path := "%s/combat_%s.tres" % [EVENTS, id]
		if ResourceSaver.save(ev, path) == OK:
			made += 1
		print("combat_%s: %d clips" % [id, streams.size()])
	print("%d eventos de combate" % made)
	quit()
