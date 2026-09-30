extends "res://tests/vegetation/tree_walk_capture.gd"

## Coste de CPU de la fauna en el bosque del juego real: quieto mientras se llena la población y
## luego andando (altas, reciclado y sustos). Imprime media, p99 y máximo por frame de cada
## etiqueta fauna:* de DebugStats, y el estado de las aves al final de cada fase.
##   godot --path . res://tests/fauna/bird_bench.tscn -- [--still=25] [--walk=30] [--speed=6]

var _sampling := false
var _samples: Dictionary = {}
var _frames := 0
var _stats: DebugStats
var _bird_frames := 0
var _frame_ms: Array = []


class Sampler extends Node:
	var bench

	func _process(_delta: float) -> void:
		bench._sample()


func _run() -> void:
	var still := 25.0
	var walk := 30.0
	var speed := 6.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--still="):
			still = float(arg.substr(8))
		elif arg.begins_with("--walk="):
			walk = float(arg.substr(7))
		elif arg.begins_with("--speed="):
			speed = float(arg.substr(8))
	var walk_dir := WALK_DIR
	if "--save" in OS.get_cmdline_user_args():
		# Donde está la partida guardada del usuario (posición canónica del origen flotante).
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://saves/main_save_player.json"))
		var saved: Dictionary = data.player.data.position
		var canonical := Vector3(saved.x, saved.y, saved.z)
		var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
		var world := fo.from_canonical(canonical) if fo != null else canonical
		walk_dir = (world - _earth_center()).normalized()
		print("BENCH partida guardada: dir=%s altura=%.0f" % [walk_dir, (world - _earth_center()).length()])
	var view := {"dir": walk_dir, "yaw": 0.0, "pitch": -2.0}
	_set_sun_elevation(view, TIMES["afternoon"], false)
	await _place(view)
	await _wait_streaming(90.0)
	GameManager._change_state(GameManager.State.PLAYING)
	DebugStats.profiling = true
	for spawner in get_tree().get_nodes_in_group(AmbientFaunaSpawner.GROUP):
		print("BENCH spawner ", spawner.name)
	var sampler := Sampler.new()
	sampler.bench = self
	# Al principio del frame lee los costes completos del anterior, que DebugStats guarda.
	sampler.process_priority = DebugStats.PROBE_PRIORITY - 1
	var found := get_tree().root.find_children("*", "CanvasLayer", true, false).filter(
		func(n: Node) -> bool: return n is DebugStats)
	_stats = found[0] if not found.is_empty() else null
	print("BENCH DebugStats encontrado: ", _stats != null)
	add_child(sampler)
	var start_up := walk_dir.normalized()
	var frame := _local_frame(start_up)
	var axis := start_up.cross(-frame.z).normalized()
	var radius: float = _earth.get("radius") if _earth.get("radius") != null else 30000.0
	_move_camera(start_up, axis, 0.0, 1.7, deg_to_rad(-2.0), radius)
	await _phase("quieto", still, func(_t: float) -> void: pass)
	await _phase("andando", walk, func(t: float) -> void:
		_move_camera(start_up, axis, t * speed, 1.7, deg_to_rad(-2.0), radius))


func _phase(label: String, duration: float, step: Callable) -> void:
	_samples.clear()
	_frames = 0
	_bird_frames = 0
	_frame_ms.clear()
	_sampling = true
	var elapsed := 0.0
	while elapsed < duration:
		elapsed += get_process_delta_time()
		_frame_ms.append(get_process_delta_time() * 1000.0)
		step.call(elapsed)
		await get_tree().process_frame
	_sampling = false
	var mean_birds := float(_bird_frames) / maxf(_frames, 1.0)
	var bird_total := 0
	for v in _samples.get(&"fauna:birds", []):
		bird_total += v
	print("BENCH %s frames=%d aves_medias=%.1f coste_por_ave=%.2f us/frame" % [label, _frames, mean_birds,
		bird_total / maxf(_bird_frames, 1.0)])
	_frame_ms.sort()
	var frame_total := 0.0
	for ms in _frame_ms:
		frame_total += ms
	print("  frame total: media=%.2f ms  p99=%.2f ms  max=%.2f ms" % [frame_total / maxf(_frame_ms.size(), 1.0),
		_frame_ms[int(_frame_ms.size() * 0.99)], _frame_ms[-1]])
	var keys := _samples.keys()
	keys.sort()
	for key in keys:
		var values: Array = _samples[key]
		while values.size() < _frames:
			values.append(0)
		values.sort()
		var total := 0
		for v in values:
			total += v
		print("  %-32s media=%6.3f ms  p99=%6.3f ms  max=%6.3f ms" % [key,
			total / 1000.0 / maxf(values.size(), 1.0), values[int(values.size() * 0.99)] / 1000.0, values[-1] / 1000.0])
	var states := {}
	var active := 0
	for node in get_tree().get_nodes_in_group(AmbientAnimal.GROUP):
		var bird := node as AmbientBird
		if bird != null and not bird is AmbientWaterBird and bird.active:
			active += 1
			var name: String = AmbientBird.State.keys()[bird.state]
			if bird.state == AmbientBird.State.FLYING and bird._perch.is_empty():
				name = "WANDER"
			states[name] = int(states.get(name, 0)) + 1
	print("  aves activas=%d %s" % [active, states])
	for spawner in get_tree().get_nodes_in_group(AmbientFaunaSpawner.GROUP):
		if spawner.habitat is ForestBirdHabitat:
			print("  árboles con perchas cerca=%d" % (spawner.habitat as ForestBirdHabitat)._trees.size())


func _sample() -> void:
	if not _sampling:
		return
	_frames += 1
	for node in get_tree().get_nodes_in_group(AmbientAnimal.GROUP):
		if node is AmbientBird and (node as AmbientBird).active:
			_bird_frames += 1
	var costs: Dictionary = _stats._previous_costs if _stats != null else {}
	for key in costs:
		if not String(key).begins_with("fauna"):
			continue
		if not _samples.has(key):
			var padded := []
			padded.resize(_frames - 1)
			padded.fill(0)
			_samples[key] = padded
		(_samples[key] as Array).append(int(costs[key]))
	for key in _samples:
		if (_samples[key] as Array).size() < _frames:
			(_samples[key] as Array).append(0)
