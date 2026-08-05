class_name DebugStats
extends CanvasLayer

## Overlay de depuración fijo arriba a la izquierda con el coste del frame: FPS, tiempo total y
## su desglose en física y render (CPU/GPU), más el recuento de draw calls.
## Ojo con 'cpu tot' (TIME_PROCESS): mide el paso idle completo, incluida la sincronización y el
## envío de comandos a la GPU, así que no es el coste de los scripts (ese sale en el profiler).
## Los valores se suavizan con una media móvil para que sean legibles y se refrescan a intervalo
## fijo, no cada frame. Se muestra/oculta con F3.

const UPDATE_INTERVAL := 0.25
const SMOOTHING := 0.1

# --- Detector de picos ---------------------------------------------------------------------
# Un pico es un frame que se sale de la línea base reciente. Al detectarlo se vuelca una línea con
# todo lo atribuible EN ESE MISMO FRAME, para no tener que averiguar el culpable por descarte.
# Funciona con el overlay oculto: solo el volcado a consola importa.

## Cuántas veces la línea base tiene que durar un frame para considerarse pico.
const SPIKE_FACTOR := 2.5
## Suelo absoluto: por debajo de esto no es un pico aunque multiplique la base.
const SPIKE_MIN_MS := 12.0
## Segundos entre volcados, para que un tramo malo no inunde la consola.
const SPIKE_COOLDOWN := 0.25
## Peso de cada frame en la línea base. Solo aprende de frames normales: si aprendiese de los picos,
## un tramo malo se convertiría en "lo normal" y dejaría de detectar nada.
const BASELINE_RATE := 0.05

var _label: Label
var _time_since_update := 0.0

var _frame_ms := 0.0
var _process_ms := 0.0
var _physics_ms := 0.0
var _render_cpu_ms := 0.0
var _render_gpu_ms := 0.0

var _baseline_ms := 0.0
var _spike_count := 0
var _worst_ms := 0.0
var _last_dump := 0.0
var _prev_nodes := 0
var _prev_memory := 0.0
var _prev_drops := Vector2i.ZERO
var _prev_offset := Vector3.ZERO
var _terrains: Array[VoxelLodTerrain] = []
var _origin: Node = null
var _refs_resolved := false
var _prev_pipelines := 0

## Costes del frame que reportan otros sistemas, en microsegundos. Es estático para que cualquiera
## pueda alimentarlo sin cablear una referencia, y se vacía al final de cada frame. Este nodo corre
## con process_priority alto justo para leerlo DESPUÉS de que todos hayan reportado.
static var _frame_costs: Dictionary = {}


## Apunta el coste de un tramo de código en el frame actual, para que el volcado de picos lo atribuya.
static func report_cost(label: StringName, usec: int) -> void:
	_frame_costs[label] = int(_frame_costs.get(label, 0)) + usec


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Se procesa el último del frame: así lee los costes que los demás nodos acaban de reportar.
	process_priority = 500
	_build_ui()
	# Sin esto los tiempos de render del viewport se quedan siempre a cero.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func toggle() -> void:
	visible = !visible
	if visible:
		# Abrir el overlay reinicia el recuento: sirve para acotar "los picos de ESTE vuelo".
		_spike_count = 0
		_worst_ms = 0.0


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.6)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	panel.add_child(_label)


func _process(delta: float) -> void:
	# El detector va SIEMPRE, con el overlay oculto también: lo que interesa es el volcado.
	_detect_spike(delta)
	if not visible:
		return

	_frame_ms = lerp(_frame_ms, delta * 1000.0, SMOOTHING)
	_process_ms = lerp(_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, SMOOTHING)
	_physics_ms = lerp(_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, SMOOTHING)

	var vp_rid := get_viewport().get_viewport_rid()
	_render_cpu_ms = lerp(_render_cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(vp_rid), SMOOTHING)
	_render_gpu_ms = lerp(_render_gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(vp_rid), SMOOTHING)

	_time_since_update += delta
	if _time_since_update < UPDATE_INTERVAL:
		return
	_time_since_update = 0.0
	_refresh_label()


## Vuelca los tiempos acumulados al label y tiñe el texto según los FPS.
func _refresh_label() -> void:
	var fps := Engine.get_frames_per_second()
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

	_label.text = "\n".join([
		"FPS      %d  (%.2f ms)" % [fps, _frame_ms],
		"cpu tot  %.2f ms" % _process_ms,
		"physics  %.2f ms" % _physics_ms,
		"gpu      %.2f ms" % _render_gpu_ms,
		"rend cpu %.2f ms" % _render_cpu_ms,
		"draws    %d" % draw_calls,
		"picos    %d  (peor %.0f ms, base %.1f)" % [_spike_count, _worst_ms, _baseline_ms],
	])

	var color := Color(0.6, 1.0, 0.6)
	if fps < 30:
		color = Color(1.0, 0.5, 0.5)
	elif fps < 55:
		color = Color(1.0, 0.9, 0.5)
	_label.add_theme_color_override("font_color", color)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------------------------
#  Detector de picos
# --------------------------------------------------------------------------------------------

## Compara el frame contra la línea base y, si se dispara, vuelca su desglose.
func _detect_spike(delta: float) -> void:
	if not _refs_resolved:
		_resolve_refs()

	var frame_ms := delta * 1000.0
	if _baseline_ms <= 0.0:
		_baseline_ms = frame_ms

	var is_spike := frame_ms > maxf(SPIKE_MIN_MS, _baseline_ms * SPIKE_FACTOR)
	if not is_spike:
		_baseline_ms = lerpf(_baseline_ms, frame_ms, BASELINE_RATE)

	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var drops := _terrain_drops()
	var pipelines := _pipeline_compilations()
	var rebased := _consume_rebase()

	if is_spike:
		_spike_count += 1
		_worst_ms = maxf(_worst_ms, frame_ms)
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_dump >= SPIKE_COOLDOWN:
			_last_dump = now
			_dump_spike(frame_ms, nodes - _prev_nodes, memory - _prev_memory,
				drops - _prev_drops, pipelines - _prev_pipelines, rebased)

	_prev_nodes = nodes
	_prev_memory = memory
	_prev_drops = drops
	_prev_pipelines = pipelines
	_frame_costs.clear()


## Una línea por pico con todo lo que se puede atribuir. Cómo leerla:
##   gpu alto            -> límite de GPU (draw calls / fill), no de CPU
##   rendCPU alto        -> envío de comandos: demasiados objetos visibles
##   nodos +N grande     -> alguien está creando nodos ese frame (colisiones del terreno, vegetación)
##   terreno update alto -> el VoxelLodTerrain está subiendo mallas/colisión en el hilo principal
##   drops +N            -> el streaming no da abasto y descarta trabajo: vas demasiado rápido para él
##   pipelines +N        -> Godot está compilando variantes de shader al entrar material nuevo en cuadro
##   REBASE              -> ese frame el origen flotante movió el mundo entero
##   la cola de '·'      -> costes que los propios sistemas han reportado (ver report_cost)
##
## OJO con 'cpu' y 'phys': NO son de este frame. Los monitores TIME_* de Godot publican el máximo
## de la última ventana de un segundo, y por eso se repiten idénticos en picos seguidos. Sirven
## para saber si el paso idle llega a esos valores, no para atribuir el frame concreto.
func _dump_spike(frame_ms: float, node_delta: int, mem_delta: float,
		drop_delta: Vector2i, pipeline_delta: int, rebased: bool) -> void:
	var vp_rid := get_viewport().get_viewport_rid()
	var parts := PackedStringArray([
		"[pico] %6.1f ms (base %.1f)" % [frame_ms, _baseline_ms],
		"cpu(max1s) %.1f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		"phys(max1s) %.1f" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"rendCPU %.1f" % RenderingServer.viewport_get_measured_render_time_cpu(vp_rid),
		"gpu %.1f" % RenderingServer.viewport_get_measured_render_time_gpu(vp_rid),
		"draws %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodos %+d" % node_delta,
		"mem %+.1f MB" % mem_delta,
	])
	parts.append(_terrain_report())
	if drop_delta.x != 0 or drop_delta.y != 0:
		parts.append("drops carga %+d malla %+d" % [drop_delta.x, drop_delta.y])
	if pipeline_delta > 0:
		parts.append("pipelines +%d" % pipeline_delta)
	if rebased:
		parts.append("REBASE")
	var costs := _costs_report()
	if costs != "":
		parts.append(costs)
	print("  ".join(parts))


## Lo que han reportado los propios sistemas este frame, de mayor a menor. Es la atribución fiable:
## a diferencia de los monitores TIME_*, esto sí es de este frame y sí dice quién.
func _costs_report() -> String:
	if _frame_costs.is_empty():
		return ""
	var labels := _frame_costs.keys()
	labels.sort_custom(func(a, b) -> bool: return _frame_costs[a] > _frame_costs[b])
	var parts := PackedStringArray()
	for label in labels:
		parts.append("%s %.1f ms" % [label, int(_frame_costs[label]) / 1000.0])
	return "· " + "  ".join(parts)


## Variantes de shader compiladas hasta ahora. Cuando esto sube en un pico, el tirón es de Godot
## compilando pipelines al entrar en cuadro material que no había usado todavía.
func _pipeline_compilations() -> int:
	return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)) \
		+ int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)) \
		+ int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)) \
		+ int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) \
		+ int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))


## Tiempos del propio VoxelLodTerrain, sumados si hay varios planetas. Vienen en microsegundos.
func _terrain_report() -> String:
	if _terrains.is_empty():
		return "terreno n/d"
	var detect := 0
	var io := 0
	var mesh := 0
	var update := 0
	for terrain in _terrains:
		if not is_instance_valid(terrain):
			continue
		var s: Dictionary = terrain.get_statistics()
		detect += int(s.get("time_detect_required_blocks", 0))
		io += int(s.get("time_io_requests", 0))
		mesh += int(s.get("time_mesh_requests", 0))
		update += int(s.get("time_update_task", 0))
	return "terreno[detect %.1f io %.1f mesh %.1f update %.1f ms]" % [
		detect / 1000.0, io / 1000.0, mesh / 1000.0, update / 1000.0]


## Contadores acumulados de trabajo descartado por el streaming (carga, mallado).
func _terrain_drops() -> Vector2i:
	var out := Vector2i.ZERO
	for terrain in _terrains:
		if not is_instance_valid(terrain):
			continue
		var s: Dictionary = terrain.get_statistics()
		out.x += int(s.get("dropped_block_loads", 0))
		out.y += int(s.get("dropped_block_meshs", 0))
	return out


## True si el origen flotante movió el mundo desde la última comprobación.
func _consume_rebase() -> bool:
	if _origin == null:
		return false
	var offset: Vector3 = _origin.get("total_offset")
	if offset == _prev_offset:
		return false
	_prev_offset = offset
	return true


## Busca terrenos y origen flotante una vez, cuando el mundo ya está montado.
func _resolve_refs() -> void:
	_origin = get_tree().get_first_node_in_group("floating_origin_manager")
	_terrains.clear()
	_collect_terrains(get_tree().root)
	if _origin != null:
		_prev_offset = _origin.get("total_offset")
	# Sin terreno todavía no merece la pena fijar las referencias: se reintenta al frame siguiente.
	_refs_resolved = not _terrains.is_empty()
	if _refs_resolved:
		print("[pico] detector activo: %d terreno(s), origen flotante %s"
			% [_terrains.size(), "sí" if _origin != null else "no"])


func _collect_terrains(node: Node) -> void:
	if node is VoxelLodTerrain:
		_terrains.append(node)
	for child in node.get_children():
		_collect_terrains(child)
