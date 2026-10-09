extends SceneTree

## Mide un clip de ataque para su CreatureAttack: cuánto adelanta (y a qué altura va) cada hueso que
## golpea a lo largo del clip, en metros del modelo tal cual (escala 1, hacia +Z como los del pack).
## Lo más adelantado marca la ventana del golpe (from/to, cuando pasa del --share de su recorrido) y
## el alcance; el avance del cuerpo (lunge) se suma aparte en el ataque.
##   godot --headless --path . --script res://tools/fauna/measure_attack.gd -- \
##       --source=res://models/_pack/puma/puma.fbx --clip=attack_close_lft --bones=LeftHand,Head \
##       [--share=0.8] [--fps=30]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	for key in ["source", "clip", "bones"]:
		if not args.has(key):
			push_error("Falta --%s" % key)
			quit(1)
			return
	var model: Node3D = (load(args.source) as PackedScene).instantiate()
	root.add_child(model)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var take := StringName()
	for clip in player.get_animation_list():
		if String(clip).get_slice("|", String(clip).get_slice_count("|") - 1) == args.clip:
			take = clip
	if take == StringName():
		push_error("No hay clip %s" % args.clip)
		quit(1)
		return
	var to_model := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != model:
		if node is Node3D:
			to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	var bones: Array[int] = []
	for bone_name in String(args.bones).split(","):
		var bone := skeleton.find_bone(bone_name.strip_edges())
		if bone < 0:
			push_error("No hay hueso %s" % bone_name)
			quit(1)
			return
		bones.append(bone)
	var fps := float(args.get("fps", "30"))
	var share := float(args.get("share", "0.8"))
	var anim := player.get_animation(take)
	player.play(take)
	player.pause()
	var samples := []
	var t := 0.0
	while t <= anim.length + 0.0001:
		player.seek(t, true)
		var best := -INF
		var height := 0.0
		for bone in bones:
			var at := to_model * skeleton.get_bone_global_pose(bone).origin
			if at.z > best:
				best = at.z
				height = at.y
		samples.append([t, best, height])
		t += 1.0 / fps
	var low: float = samples.map(func(s: Array) -> float: return s[1]).min()
	var high: float = samples.map(func(s: Array) -> float: return s[1]).max()
	var from := -1.0
	var to := -1.0
	for s in samples:
		var marker := ""
		if s[1] >= low + (high - low) * share:
			marker = " ←"
			if from < 0.0:
				from = s[0]
			to = s[0]
		print("  %.2f s  adelante %5.2f m  altura %5.2f m%s" % [s[0], s[1], s[2], marker])
	print("%s: %.2f s, alcance %.2f m (de %.2f en reposo del clip), ventana %.2f–%.2f s (%.0f–%.0f %%)" % [args.clip,
		anim.length, high, samples[0][1], from, to, 100.0 * from / anim.length, 100.0 * to / anim.length])
	quit(0)
