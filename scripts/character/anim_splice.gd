class_name AnimSplice extends RefCounted

## Clips de cuerpo entero hechos de dos, para quien no tiene AnimationTree (los aldeanos y compañeros
## van con un AnimationPlayer solo): la cadera y las piernas de uno y, del tronco para arriba, otro.
## Es lo que el jugador hace con su canal de tronco y brazos (PlayerCombat.play_task, filtrado desde
## HumanRig.SPINE) sobre la locomoción, horneado en un clip. Ver docs/villagers.md (Colonos).

## La librería de AnimationPlayer con los clips empalmados ("work/..."): se hace una vez, con el
## esqueleto del primero que la pide, y la comparten todos (los humanos tienen el mismo esqueleto).
const LIBRARY := &"work"
## Despiezar: los tajos del jugador (combat/butcher) sobre el agachado quieto (loco/crouch_idle).
const BUTCHER := &"work/butcher"

static var _library: AnimationLibrary


## La librería LIBRARY, hecha con [skeleton] si aún no lo está; o null si faltan los clips.
static func library(skeleton: Skeleton3D) -> AnimationLibrary:
	if _library != null:
		return _library
	if not ResourceLoader.exists(Locomotion.LIBRARY) or not ResourceLoader.exists(PlayerCombat.COMBAT_LIBRARY):
		return null
	var loco := load(Locomotion.LIBRARY) as AnimationLibrary
	var combat := load(PlayerCombat.COMBAT_LIBRARY) as AnimationLibrary
	if loco == null or combat == null or not loco.has_animation(&"crouch_idle") or not combat.has_animation(&"butcher"):
		return null
	_library = AnimationLibrary.new()
	_library.add_animation(&"butcher", splice(loco.get_animation(&"crouch_idle"), combat.get_animation(&"butcher"),
		skeleton, HumanRig.SPINE))
	return _library


## Pone la librería en [player] (con el esqueleto [skeleton]) si no la tiene.
static func attach(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	if player.has_animation_library(LIBRARY):
		return
	var lib := library(skeleton)
	if lib != null:
		player.add_animation_library(LIBRARY, lib)


## Un clip en bucle tan largo como [upper]: de [upper], los huesos que cuelgan de [root_bone] (él
## incluido); de [lower], todo lo demás (la cadera, con su altura, y las piernas), repetido si es más
## corto.
static func splice(lower: Animation, upper: Animation, skeleton: Skeleton3D, root_bone: String) -> Animation:
	var above := {}
	var root := skeleton.find_bone(root_bone)
	for bone in skeleton.get_bone_count():
		var parent := bone
		while parent >= 0 and parent != root:
			parent = skeleton.get_bone_parent(parent)
		if parent == root:
			above[skeleton.get_bone_name(bone)] = true
	var out := Animation.new()
	out.length = upper.length
	out.loop_mode = Animation.LOOP_LINEAR
	for source: Animation in [lower, upper]:
		var top := source == upper
		var repeats := 1 if top else ceili(out.length / maxf(source.length, 0.01))
		for t in source.get_track_count():
			var path := source.track_get_path(t)
			if above.has(String(path.get_concatenated_subnames())) != top:
				continue
			var track := out.add_track(source.track_get_type(t))
			out.track_set_path(track, path)
			out.track_set_interpolation_type(track, source.track_get_interpolation_type(t))
			for r in repeats:
				for k in source.track_get_key_count(t):
					var time := source.track_get_key_time(t, k) + r * source.length
					if time > out.length:
						break
					out.track_insert_key(track, time, source.track_get_key_value(t, k))
	return out
