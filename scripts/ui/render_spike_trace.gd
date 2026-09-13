extends RefCounted

## Native renderer timestamps arrive several frames late. Match their absolute CPU times
## to the saved pre/post-draw window; never assign the latest GPU reading to today's spike.
var enabled: bool = false
var last_match: Dictionary = {}
var _owns_profiler: bool = false
var _generation: int = 0
var _read_pending: bool = false
var _windows: Array[Dictionary] = []


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	_generation += 1
	_windows.clear()
	_read_pending = false
	last_match.clear()
	enabled = value
	if value:
		if EngineDebugger.has_profiler(&"visual"):
			_owns_profiler = not EngineDebugger.is_profiling(&"visual")
			if _owns_profiler:
				EngineDebugger.profiler_enable(&"visual", true)
			print("[perf render] Traza nativa activa; cada lectura se empareja con su pico.")
		else:
			print("[perf render] Sin profiler visual: lanza desde el editor o con --debug para obtener las etapas internas.")
	elif _owns_profiler:
		EngineDebugger.profiler_enable(&"visual", false)
		_owns_profiler = false


func record_spike(id: int, begin: int, end: int) -> void:
	if not enabled or end <= begin:
		return
	_windows.append({"id": id, "begin": begin, "end": end,
		"expires": Engine.get_process_frames() + 30})


## Called after draw, but reads the RenderingDevice on its owning thread without a sync.
func poll() -> void:
	if not enabled or _windows.is_empty() or _read_pending:
		return
	for i in range(_windows.size() - 1, -1, -1):
		if Engine.get_process_frames() > int(_windows[i].expires):
			print("[pico render #%d] Sin timestamps correspondientes; no se atribuye otra lectura GPU." % int(_windows[i].id))
			_windows.remove_at(i)
	if _windows.is_empty():
		return
	_read_pending = true
	RenderingServer.call_on_render_thread(_read.bind(_generation))


func _read(generation: int) -> void:
	var data: Dictionary = {}
	var rd := RenderingServer.get_rendering_device()
	if rd != null and rd.get_captured_timestamps_count() >= 2:
		var count := rd.get_captured_timestamps_count()
		var spans: Array[Dictionary] = []
		for i in count - 1:
			spans.append({"name": rd.get_captured_timestamp_name(i),
				"end_name": rd.get_captured_timestamp_name(i + 1),
				"cpu": maxf(0.0, (rd.get_captured_timestamp_cpu_time(i + 1) - rd.get_captured_timestamp_cpu_time(i)) / 1000.0),
				"gpu": maxf(0.0, (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1000000.0)})
		data = {"frame": rd.get_captured_timestamps_frame(), "spans": spans,
			"first": rd.get_captured_timestamp_cpu_time(0),
			"last": rd.get_captured_timestamp_cpu_time(count - 1),
			"gpu": (rd.get_captured_timestamp_gpu_time(count - 1) - rd.get_captured_timestamp_gpu_time(0)) / 1000000.0}
	# Only the render thread touches RD. All state and report formatting stay on main.
	_deliver.call_deferred(data, generation)


func _deliver(data: Dictionary, generation: int) -> void:
	if generation != _generation or not enabled:
		return
	_read_pending = false
	if data.is_empty():
		return
	for i in _windows.size():
		var window := _windows[i]
		if int(data.first) < int(window.begin) or int(data.last) > int(window.end):
			continue
		last_match = {"id": window.id, "frame": data.frame,
			"before_ms": (int(data.first) - int(window.begin)) / 1000.0,
			"inside_ms": (int(data.last) - int(data.first)) / 1000.0,
			"after_ms": (int(window.end) - int(data.last)) / 1000.0,
			"gpu_ms": data.gpu}
		print("[pico render #%d] frameRD %d CPU[antes %.1f | entre marcas %.1f | despues %.1f] GPU entre marcas %.1f ms  CPU %s  GPU %s" % [
			int(window.id), int(data.frame), last_match.before_ms, last_match.inside_ms,
			last_match.after_ms, float(data.gpu), _top_spans(data.spans, "cpu"), _top_spans(data.spans, "gpu")])
		_windows.remove_at(i)
		return


func _top_spans(spans: Array, field: String) -> String:
	var ordered := spans.duplicate()
	ordered.sort_custom(func(a, b): return float(a[field]) > float(b[field]))
	var parts := PackedStringArray()
	for i in mini(4, ordered.size()):
		var label: String = ordered[i].name
		# The last directional split is followed by general scene culling and worker
		# waits before the next marker. It is not a duration of that cascade alone.
		if label.begins_with("Cull DirectionalLight3D"):
			label += " -> " + str(ordered[i].get("end_name", "?"))
		parts.append("%s %.2f" % [label, float(ordered[i][field])])
	return "[" + " | ".join(parts) + "]"
