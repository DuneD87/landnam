extends SceneTree

## Presta clips de una especie a otra con un esqueleto de los mismos nombres (los de comer del león a
## la leona, que no los tiene), y los guarda en una AnimationLibrary aparte para el perfil de la que
## los recibe (CreatureCombatProfile.feed_library). Cada hueso lleva el giro relativo a su reposo:
## igual que en el original si los dos esqueletos reposan igual (león y leona); si no, lo más
## parecido (el puma). Los sitios (la pelvis) van a la escala de la que los recibe, por la altura de
## su pelvis. Lo que no tiene la que los recibe (los dientes del león), fuera.
##   godot --headless --path . --script res://tools/fauna/borrow_clips.gd -- \
##       --from=res://scenes/animals/Lion.tscn --to=res://scenes/animals/Lioness.tscn \
##       --clips=lion_idle_eat_01,lion_idle_eat_02 --out=res://models/animals/lioness/lioness_feed.res


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	for key in ["from", "to", "clips", "out"]:
		if not args.has(key):
			push_error("Falta --%s" % key)
			quit(1)
			return
	var source = load(args.from).instantiate()
	var target = load(args.to).instantiate()
	root.add_child(source)
	root.add_child(target)
	var source_player: AnimationPlayer = source.animation_controller.animator
	var target_player: AnimationPlayer = target.animation_controller.animator
	var source_skel: Skeleton3D = source.get_skeleton()
	var target_skel: Skeleton3D = target.get_skeleton()
	var source_prefix := String(source_player.get_node(source_player.root_node).get_path_to(source_skel))
	var target_prefix := String(target_player.get_node(target_player.root_node).get_path_to(target_skel))
	var hips := _root_bone(source_skel)
	var scale := 1.0
	var target_hips := target_skel.find_bone(source_skel.get_bone_name(hips))
	if hips >= 0 and target_hips >= 0 and absf(source_skel.get_bone_rest(hips).origin.y) > 1e-4:
		scale = target_skel.get_bone_rest(target_hips).origin.y / source_skel.get_bone_rest(hips).origin.y
	var library := AnimationLibrary.new()
	for clip in String(args.clips).split(",", false):
		var original := source_player.get_animation(clip)
		if original == null:
			push_error("%s no tiene el clip '%s'" % [args.from, clip])
			continue
		var copy := Animation.new()
		copy.length = original.length
		copy.loop_mode = original.loop_mode
		copy.step = original.step
		var dropped := 0
		for t in original.get_track_count():
			var path := String(original.track_get_path(t))
			var bone_name := path.get_slice(":", 1)
			if not path.begins_with(source_prefix + ":"):
				continue
			var from_bone := source_skel.find_bone(bone_name)
			var to_bone := target_skel.find_bone(bone_name)
			if from_bone < 0 or to_bone < 0:
				dropped += 1
				continue
			var type := original.track_get_type(t)
			var track := copy.add_track(type)
			copy.track_set_path(track, NodePath(target_prefix + ":" + bone_name))
			copy.track_set_interpolation_type(track, original.track_get_interpolation_type(t))
			var from_rest := source_skel.get_bone_rest(from_bone)
			var to_rest := target_skel.get_bone_rest(to_bone)
			for k in original.track_get_key_count(t):
				var value: Variant = original.track_get_key_value(t, k)
				match type:
					Animation.TYPE_ROTATION_3D:
						var relative: Quaternion = from_rest.basis.get_rotation_quaternion().inverse() * (value as Quaternion)
						value = to_rest.basis.get_rotation_quaternion() * relative
					Animation.TYPE_POSITION_3D:
						value = to_rest.origin + ((value as Vector3) - from_rest.origin) * scale
				copy.track_insert_key(track, original.track_get_key_time(t, k), value, original.track_get_key_transition(t, k))
		library.add_animation(clip, copy)
		print("%s: %d pistas (%d sin hueso en la que los recibe)" % [clip, copy.get_track_count(), dropped])
	var error := ResourceSaver.save(library, args.out)
	print("Guardado %s (%s)" % [args.out, error_string(error)])
	quit(0 if error == OK else 1)


static func _root_bone(skel: Skeleton3D) -> int:
	for b in skel.get_bone_count():
		if String(skel.get_bone_name(b)).to_lower() == "hips":
			return b
	return 0
