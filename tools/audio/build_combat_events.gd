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
	&"block_wood": {"volume": -1.0, "pitch_jitter": 0.07, "max": 40.0, "unit": 4.0, "voices": 4, "cooldown": 0.03},
	&"block_metal": {"volume": -3.0, "pitch_jitter": 0.06, "max": 45.0, "unit": 4.0, "voices": 4, "cooldown": 0.03},
	&"parry": {"volume": 0.0, "pitch_jitter": 0.04, "max": 50.0, "unit": 5.0, "voices": 3, "cooldown": 0.05},
	&"guard_break": {"volume": 1.0, "pitch": 0.85, "pitch_jitter": 0.05, "max": 45.0, "unit": 4.0, "voices": 2, "cooldown": 0.1},
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
	# Los de perro, algo más graves: un lobo pesa el doble que un perro grande. El aullido se oye
	# lejos (en el bosque, a kilómetros).
	&"wolf_growl": {"volume": -3.0, "pitch": 0.88, "pitch_jitter": 0.06, "max": 45.0, "unit": 4.0, "voices": 4, "cooldown": 0.4},
	&"wolf_snarl": {"volume": -1.0, "pitch": 0.9, "pitch_jitter": 0.05, "max": 50.0, "unit": 5.0, "voices": 3, "cooldown": 0.4},
	&"wolf_hurt": {"volume": -2.0, "pitch": 0.85, "pitch_jitter": 0.06, "max": 45.0, "unit": 4.0, "voices": 3, "cooldown": 0.3},
	&"wolf_death": {"volume": -1.0, "pitch": 0.85, "pitch_jitter": 0.04, "max": 55.0, "unit": 5.0, "voices": 2, "cooldown": 1.0},
	&"wolf_howl": {"volume": 2.0, "pitch_jitter": 0.04, "max": 400.0, "unit": 20.0, "voices": 2, "cooldown": 2.0},
	# Perros (labrador, sabueso): los gañidos y gemidos de perro del lobo, a su tono de perro.
	&"dog_hurt": {"clips": &"wolf_hurt", "volume": -2.0, "pitch_jitter": 0.06, "max": 45.0, "unit": 4.0, "voices": 3, "cooldown": 0.3},
	&"dog_death": {"clips": &"wolf_death", "volume": -1.0, "pitch_jitter": 0.04, "max": 50.0, "unit": 5.0, "voices": 2, "cooldown": 1.0},
	# Especies del pack. Las muertes, algo más graves que los quejidos de la misma voz.
	&"deer_hurt": {"volume": -2.0, "pitch_jitter": 0.06, "max": 50.0, "unit": 4.0, "voices": 3, "cooldown": 0.3},
	&"deer_death": {"volume": -1.0, "pitch": 0.85, "pitch_jitter": 0.04, "max": 60.0, "unit": 5.0, "voices": 2, "cooldown": 1.0},
	&"goat_hurt": {"volume": -3.0, "pitch_jitter": 0.06, "max": 45.0, "unit": 3.0, "voices": 3, "cooldown": 0.3},
	&"goat_death": {"volume": -2.0, "pitch": 0.92, "pitch_jitter": 0.04, "max": 50.0, "unit": 4.0, "voices": 2, "cooldown": 1.0},
	# El muflón es un carnero salvaje: más grave que la oveja de granja.
	&"sheep_hurt": {"volume": -3.0, "pitch": 0.88, "pitch_jitter": 0.06, "max": 45.0, "unit": 3.0, "voices": 3, "cooldown": 0.3},
	&"sheep_death": {"volume": -2.0, "pitch": 0.82, "pitch_jitter": 0.04, "max": 50.0, "unit": 4.0, "voices": 2, "cooldown": 1.0},
	&"cow_hurt": {"volume": -1.0, "pitch_jitter": 0.05, "max": 80.0, "unit": 6.0, "voices": 3, "cooldown": 0.4},
	&"cow_death": {"volume": 0.0, "pitch": 0.94, "pitch_jitter": 0.04, "max": 90.0, "unit": 6.0, "voices": 2, "cooldown": 1.0},
	&"calf_hurt": {"volume": -2.0, "pitch_jitter": 0.06, "max": 60.0, "unit": 4.0, "voices": 3, "cooldown": 0.35},
	&"calf_death": {"volume": -1.0, "pitch": 0.95, "pitch_jitter": 0.04, "max": 70.0, "unit": 5.0, "voices": 2, "cooldown": 1.0},
	&"horse_hurt": {"volume": -1.0, "pitch_jitter": 0.05, "max": 90.0, "unit": 6.0, "voices": 3, "cooldown": 0.4},
	&"horse_death": {"volume": 0.0, "pitch": 0.9, "pitch_jitter": 0.04, "max": 90.0, "unit": 6.0, "voices": 2, "cooldown": 1.0},
	# Un rebuzno se oye desde muy lejos.
	&"donkey_hurt": {"volume": -1.0, "pitch_jitter": 0.05, "max": 120.0, "unit": 7.0, "voices": 2, "cooldown": 0.5},
	&"donkey_death": {"volume": 0.0, "pitch": 0.92, "pitch_jitter": 0.04, "max": 120.0, "unit": 7.0, "voices": 2, "cooldown": 1.0},
	# Bramidos de bisonte: el búfalo tal cual; el alce, algo más agudo; el ñu, aún más.
	&"bison_bellow": {"volume": 1.0, "pitch_jitter": 0.05, "max": 120.0, "unit": 8.0, "voices": 2, "cooldown": 1.0},
	&"buffalo_hurt": {"clips": &"bison_bellow", "volume": 0.0, "pitch": 1.12, "pitch_jitter": 0.05, "max": 100.0, "unit": 7.0, "voices": 2, "cooldown": 0.4},
	&"moose_bellow": {"clips": &"bison_bellow", "volume": 0.0, "pitch": 1.08, "pitch_jitter": 0.05, "max": 110.0, "unit": 8.0, "voices": 2, "cooldown": 0.6},
	&"moose_hurt": {"clips": &"bison_bellow", "volume": -1.0, "pitch": 1.2, "pitch_jitter": 0.05, "max": 90.0, "unit": 7.0, "voices": 2, "cooldown": 0.4},
	&"moose_death": {"clips": &"bison_bellow", "volume": 1.0, "pitch": 0.95, "pitch_jitter": 0.04, "max": 110.0, "unit": 8.0, "voices": 2, "cooldown": 1.0},
	&"wildebeest_hurt": {"clips": &"bison_bellow", "volume": -2.0, "pitch": 1.35, "pitch_jitter": 0.06, "max": 80.0, "unit": 6.0, "voices": 3, "cooldown": 0.4},
	&"wildebeest_death": {"clips": &"bison_bellow", "volume": -1.0, "pitch": 1.22, "pitch_jitter": 0.04, "max": 90.0, "unit": 6.0, "voices": 2, "cooldown": 1.0},
	&"boar_grunt": {"volume": -2.0, "pitch": 0.9, "pitch_jitter": 0.06, "max": 45.0, "unit": 4.0, "voices": 3, "cooldown": 0.3},
	&"boar_squeal": {"volume": -1.0, "pitch_jitter": 0.06, "max": 70.0, "unit": 5.0, "voices": 3, "cooldown": 0.3},
	&"boar_death": {"volume": 0.0, "pitch": 0.92, "pitch_jitter": 0.04, "max": 70.0, "unit": 5.0, "voices": 2, "cooldown": 1.0},
	# La trompa del elefante se oye a kilómetros; el mamut, con la misma, más grave y más lento.
	&"elephant_trumpet": {"volume": 3.0, "pitch_jitter": 0.04, "max": 250.0, "unit": 12.0, "voices": 2, "cooldown": 1.0},
	&"elephant_hurt": {"clips": &"elephant_trumpet", "volume": 1.0, "pitch": 1.12, "pitch_jitter": 0.05, "max": 180.0, "unit": 10.0, "voices": 2, "cooldown": 0.4},
	&"elephant_death": {"clips": &"elephant_trumpet", "volume": 2.0, "pitch": 0.82, "pitch_jitter": 0.04, "max": 220.0, "unit": 12.0, "voices": 2, "cooldown": 1.0},
	&"mammoth_trumpet": {"clips": &"elephant_trumpet", "volume": 4.0, "pitch": 0.76, "pitch_jitter": 0.04, "max": 280.0, "unit": 14.0, "voices": 2, "cooldown": 1.0},
	&"mammoth_hurt": {"clips": &"elephant_trumpet", "volume": 2.0, "pitch": 0.86, "pitch_jitter": 0.05, "max": 200.0, "unit": 12.0, "voices": 2, "cooldown": 0.4},
	&"mammoth_death": {"clips": &"elephant_trumpet", "volume": 3.0, "pitch": 0.64, "pitch_jitter": 0.04, "max": 240.0, "unit": 14.0, "voices": 2, "cooldown": 1.0},
	&"rhino_grunt": {"volume": -1.0, "pitch_jitter": 0.06, "max": 60.0, "unit": 6.0, "voices": 3, "cooldown": 0.4},
	&"rhino_squeal": {"volume": -1.0, "pitch_jitter": 0.06, "max": 60.0, "unit": 5.0, "voices": 2, "cooldown": 0.35},
	&"rhino_death": {"clips": &"rhino_grunt", "volume": 0.0, "pitch": 0.85, "pitch_jitter": 0.04, "max": 70.0, "unit": 6.0, "voices": 2, "cooldown": 1.0},
	&"alligator_growl": {"volume": 0.0, "pitch_jitter": 0.05, "max": 70.0, "unit": 6.0, "voices": 2, "cooldown": 0.6},
	&"alligator_hiss": {"volume": -1.0, "pitch_jitter": 0.05, "max": 40.0, "unit": 5.0, "voices": 2, "cooldown": 0.5},
	# La cría de cocodrilo, mucho más grave: la de un caimán adulto.
	&"alligator_hurt": {"volume": -2.0, "pitch": 0.55, "pitch_jitter": 0.05, "max": 45.0, "unit": 4.0, "voices": 2, "cooldown": 0.35},
	&"alligator_death": {"clips": &"alligator_growl", "volume": 0.0, "pitch": 0.85, "pitch_jitter": 0.04, "max": 70.0, "unit": 6.0, "voices": 2, "cooldown": 1.0},
	# Felinos: el lince, algo más grave que un gato; el puma, mucho más (sisea y gruñe, no ruge).
	&"lynx_hurt": {"clips": &"cat_hurt", "volume": -2.0, "pitch": 0.8, "pitch_jitter": 0.06, "max": 45.0, "unit": 4.0, "voices": 2, "cooldown": 0.35},
	&"lynx_death": {"clips": &"cat_growl", "volume": -1.0, "pitch": 0.72, "pitch_jitter": 0.04, "max": 50.0, "unit": 4.0, "voices": 2, "cooldown": 1.0},
	&"puma_hiss": {"clips": &"cat_hiss", "volume": 0.0, "pitch": 0.6, "pitch_jitter": 0.05, "max": 50.0, "unit": 5.0, "voices": 2, "cooldown": 0.5},
	&"puma_growl": {"clips": &"cat_growl", "volume": 0.0, "pitch": 0.62, "pitch_jitter": 0.05, "max": 55.0, "unit": 5.0, "voices": 3, "cooldown": 0.5},
	&"puma_hurt": {"clips": &"cat_hurt", "volume": 0.0, "pitch": 0.62, "pitch_jitter": 0.05, "max": 50.0, "unit": 5.0, "voices": 2, "cooldown": 0.35},
	&"puma_death": {"clips": &"cat_growl", "volume": 1.0, "pitch": 0.55, "pitch_jitter": 0.04, "max": 60.0, "unit": 5.0, "voices": 2, "cooldown": 1.0},
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
