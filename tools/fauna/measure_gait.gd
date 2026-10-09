extends SceneTree

## Mide a qué velocidad avanza cada clip de marcha de un modelo, para los gait_speeds de
## FaunaModelData y los run_clip_speed / sprint_clip_speed de las criaturas: con el clip en su sitio,
## un pie apoyado va hacia atrás a la velocidad del suelo. Para cada pie (los huesos de pie, mano, dedo,
## pezuña o tobillo, o los de --feet), la velocidad hacia atrás mientras está en su punto más bajo;
## la mediana de todos. Si el clip además avanza con la raíz, lo suma. En metros por segundo del
## modelo tal cual (escala 1), hacia donde mira (+Z, como los del pack).
##   godot --headless --path . --script res://tools/fauna/measure_gait.gd -- \
##       --source=res://models/animals/fox/fox.fbx --clips=Walk,Trot,Run,Sprint [--feet=a,b] [--fps=60]
## Sin --clips, todos los que se llamen algo como walk, trot, run, sprint, gallop o hop.

const GAIT_WORDS := ["walk", "trot", "run", "sprint", "gallop", "hop", "canter", "sneak"]
const FOOT_WORDS := ["foot", "toe", "hoof", "paw", "ankle", "hand", "finger", "digit"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if not args.has("source"):
		push_error("Falta --source")
		quit(1)
		return
	var model: Node3D = (load(args.source) as PackedScene).instantiate()
	root.add_child(model)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var fps := float(args.get("fps", "60"))
	var to_model := _to_model(model, skeleton)
	var feet := _feet(skeleton, String(args.get("feet", "")))
	print("Pies: %s" % ", ".join(feet.map(func(bone: int) -> String: return skeleton.get_bone_name(bone))))
	var takes := {}
	for take in player.get_animation_list():
		takes[String(take).get_slice("|", String(take).get_slice_count("|") - 1)] = take
	var wanted: PackedStringArray = String(args.get("clips", "")).split(",", false)
	if wanted.is_empty():
		for clip in takes:
			var lower := String(clip).to_lower()
			if GAIT_WORDS.any(func(word: String) -> bool: return lower.contains(word)):
				wanted.append(clip)
	for clip in wanted:
		if not takes.has(clip):
			print("%-28s no está" % clip)
			continue
		var anim := player.get_animation(takes[clip])
		var samples := []
		var t := 0.0
		player.play(takes[clip])
		player.pause()
		while t <= anim.length + 0.0001:
			player.seek(t, true)
			var at := []
			for bone in feet:
				at.append(to_model * skeleton.get_bone_global_pose(bone).origin)
			samples.append({"feet": at, "root": to_model * skeleton.get_bone_global_pose(0).origin})
			t += 1.0 / fps
		var speeds := []
		for f in feet.size():
			var low := INF
			var high := -INF
			for sample in samples:
				low = minf(low, sample.feet[f].y)
				high = maxf(high, sample.feet[f].y)
			var stance := low + maxf((high - low) * 0.12, 0.003)
			for i in range(1, samples.size()):
				var a: Vector3 = samples[i - 1].feet[f]
				var b: Vector3 = samples[i].feet[f]
				if a.y <= stance and b.y <= stance:
					speeds.append((a.z - b.z) * fps)
		speeds.sort()
		var stance_speed: float = speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
		var root_speed: float = (samples.back().root.z - samples.front().root.z) / maxf(anim.length, 0.001)
		print("%-28s %5.2f s  pies %6.2f m/s  raíz %5.2f m/s  → %6.2f m/s" % [clip, anim.length, stance_speed,
			root_speed, stance_speed + root_speed])
	quit(0)


## Del esqueleto al espacio del modelo (la raíz de la escena importada).
func _to_model(model: Node3D, skeleton: Skeleton3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != model:
		if node is Node3D:
			xform = (node as Node3D).transform * xform
		node = node.get_parent()
	return xform


## Los pies: los de [wanted], o los huesos con nombre de pie (sin los de IK). Todos: cada uno se mide
## en su propio apoyo (en lo más bajo de su recorrido), así que da igual que el tobillo vaya más alto
## que el dedo.
func _feet(skeleton: Skeleton3D, wanted: String) -> Array[int]:
	var result: Array[int] = []
	if wanted != "":
		for bone_name in wanted.split(","):
			var bone := skeleton.find_bone(bone_name.strip_edges())
			if bone >= 0:
				result.append(bone)
		return result
	for bone in skeleton.get_bone_count():
		var lower := skeleton.get_bone_name(bone).to_lower()
		if lower.contains("ik") or lower.contains("target") or lower.contains("nub"):
			continue
		if FOOT_WORDS.any(func(word: String) -> bool: return lower.contains(word)):
			result.append(bone)
	return result
