class_name DebugStats
extends CanvasLayer

## Overlay de depuración (F3) y detector de picos de frame. Mide con Time.get_ticks_usec() y una
## sonda hija que corre la primera del frame, así que parte el frame en fases enteras en vez de
## fiarse del delta de _process (Godot lo suaviza y lo cuantiza al refresco) o de los monitores
## TIME_*, que publican el máximo de la última ventana de un segundo. El registro de picos va solo.

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
const SPIKE_COOLDOWN := 0.5
## Peso de cada frame en la línea base. Solo aprende de frames normales: si aprendiese de los picos,
## un tramo malo se convertiría en "lo normal" y dejaría de detectar nada.
const BASELINE_RATE := 0.05

## Prioridades extremas: la sonda corre la primera del frame y este nodo el último.
const PROBE_PRIORITY := -1000000
const STATS_PRIORITY := 1000000


## Sonda que marca el arranque de cada fase. Va como hija de DebugStats con prioridad mínima,
## así sus callbacks son los primeros del frame y los de DebugStats los últimos: restando salen
## las fases enteras, no solo lo que cuesta este nodo.
class FrameProbe extends Node:
	var stats: DebugStats

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = DebugStats.PROBE_PRIORITY
		process_physics_priority = DebugStats.PROBE_PRIORITY

	func _process(_delta: float) -> void:
		stats._idle_first = Time.get_ticks_usec()

	func _physics_process(_delta: float) -> void:
		stats._phys_first.append(Time.get_ticks_usec())


var _label: Label
var _time_since_update := 0.0

var _frame_ms := 0.0
var _render_cpu_ms := 0.0
var _render_gpu_ms := 0.0

# Marcas del frame en curso (usec). Las escribe la sonda; las cierra este nodo.
var _idle_first := 0
var _prev_idle_last := 0
var _phys_first: PackedInt64Array = PackedInt64Array()
var _phys_last: PackedInt64Array = PackedInt64Array()
var _pre_draw := 0
var _post_draw := 0

# Fases del último frame cerrado, en ms.
var _ph := {}
var _ph_smooth := {}

# Ventana de 1 s para distinguir un pico suelto de una caída sostenida: la línea base solo
# aprende de frames normales, así que con la mitad de los frames malos sigue marcando 7 ms y
# cada frame malo sale como "pico" sin que se vea que son constantes.
var _win_start := 0
var _win_frames := 0
var _win_spikes := 0
var _win_time := 0.0
var _win_report := ""

var _baseline_ms := 0.0
var _spike_count := 0
var _worst_ms := 0.0
var _last_dump := 0.0
var _last_spike_time := 0.0
var _last_spike_pos := Vector3.ZERO
var _has_last_spike := false
var _prev_nodes := 0
var _prev_memory := 0.0
var _prev_drops := Vector2i.ZERO
var _prev_offset := Vector3.ZERO
var _prev_pipelines := 0
var _terrains: Array[VoxelLodTerrain] = []
var _instancers: Array[Node] = []
var _prev_bodies := 0
var _bodies := 0
var _bodies_delta := 0
var _origin: Node = null
var _refs_resolved := false
var _threads_schema_dumped := false

## Interruptor global del perfilado. Apagado, ni se detectan picos ni se acumulan costes: el
## detector pediría get_statistics() a cada terreno EN CADA FRAME, que no es gratis. Se enciende
## en caliente con el comando de consola 'perf'.
static var profiling := false

## Costes del frame que reportan otros sistemas, en microsegundos. Es estático para que cualquiera
## pueda alimentarlo sin cablear una referencia, y se vacía al final de cada frame.
static var _frame_costs: Dictionary = {}


## Apunta el coste de un tramo de código en el frame actual, para que el volcado de picos lo
## atribuya. Con el perfilado apagado no hace nada: los envoltorios que la llaman se quedan en
## dos lecturas de reloj, que sí son gratis.
static func report_cost(label: StringName, usec: int) -> void:
	if not profiling:
		return
	_frame_costs[label] = int(_frame_costs.get(label, 0)) + usec


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = STATS_PRIORITY
	process_physics_priority = STATS_PRIORITY

	var probe := FrameProbe.new()
	probe.name = "FrameProbe"
	probe.stats = self
	add_child(probe)

	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

	_build_ui()
	# Sin esto los tiempos de render del viewport se quedan siempre a cero.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func toggle() -> void:
	visible = !visible
	if visible:
		# Abrir el overlay reinicia el recuento: sirve para acotar "los picos de ESTE vuelo".
		_spike_count = 0
		_worst_ms = 0.0


func _on_pre_draw() -> void:
	_pre_draw = Time.get_ticks_usec()


func _on_post_draw() -> void:
	_post_draw = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	_phys_last.append(Time.get_ticks_usec())


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
	# Con el overlay oculto y el perfilado apagado no hay nada que medir: ni siquiera se trocea
	# el frame, que aunque es aritmética construye un diccionario por frame.
	if not visible and not profiling:
		_prev_idle_last = Time.get_ticks_usec()
		_phys_first.clear()
		_phys_last.clear()
		return

	var idle_last := Time.get_ticks_usec()
	var total_ms := _close_frame(idle_last)

	# El detector va con el overlay oculto también: lo que interesa es el volcado a consola.
	if profiling and total_ms > 0.0:
		_detect_spike(total_ms)

	if not visible:
		return

	_frame_ms = lerp(_frame_ms, total_ms, SMOOTHING)
	for k in _ph:
		_ph_smooth[k] = lerp(float(_ph_smooth.get(k, 0.0)), float(_ph[k]), SMOOTHING)

	var vp_rid := get_viewport().get_viewport_rid()
	_render_cpu_ms = lerp(_render_cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(vp_rid), SMOOTHING)
	_render_gpu_ms = lerp(_render_gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(vp_rid), SMOOTHING)

	_time_since_update += delta
	if _time_since_update < UPDATE_INTERVAL:
		return
	_time_since_update = 0.0
	_refresh_label()


# --------------------------------------------------------------------------------------------
#  Troceado del frame
# --------------------------------------------------------------------------------------------

## Cierra la ventana [fin de _process anterior -> fin de _process de ahora] y la reparte en fases.
## La ventana está rotada respecto al frame de Godot (dibujo primero, luego física, luego idle),
## pero contiene un dibujo, una tanda de física y un idle enteros, y suma el tiempo real de frame.
## Devuelve el total en ms, o 0 el primer frame.
func _close_frame(idle_last: int) -> float:
	var total_us := 0
	if _prev_idle_last > 0:
		total_us = idle_last - _prev_idle_last
		_split_phases(idle_last, total_us)
	_prev_idle_last = idle_last
	_phys_first.clear()
	_phys_last.clear()
	return total_us / 1000.0


## Reparte la ventana en proc | callbk | sim | difer | dibujo | resto. La partición es exacta:
## las seis suman el total, así que un hueco inesperado aparece en 'resto' en vez de perderse.
func _split_phases(idle_last: int, total_us: int) -> void:
	# Sin dibujo dentro de la ventana (ventana minimizada, frame saltado) las marcas son viejas.
	if _pre_draw <= _prev_idle_last or _post_draw < _pre_draw:
		_ph = {"total": total_us / 1000.0}
		return

	var callbk_us := 0
	var ticks: int = mini(_phys_first.size(), _phys_last.size())
	for i in ticks:
		callbk_us += maxi(0, int(_phys_last[i]) - int(_phys_first[i]))

	var anchor: int = int(_phys_first[0]) if ticks > 0 else _idle_first
	var sim_us := 0
	if ticks > 0:
		sim_us = maxi(0, (_idle_first - int(_phys_first[0])) - callbk_us)

	_ph = {
		"total": total_us / 1000.0,
		"difer": (_pre_draw - _prev_idle_last) / 1000.0,
		"dibujo": (_post_draw - _pre_draw) / 1000.0,
		"resto": (anchor - _post_draw) / 1000.0,
		"callbk": callbk_us / 1000.0,
		"sim": sim_us / 1000.0,
		"proc": (idle_last - _idle_first) / 1000.0,
		"ticks": ticks,
	}


## Las fases en una línea, de la más cara a la más barata. 'n/d' si el frame no llegó a dibujar.
func _phases_line(src: Dictionary) -> String:
	if not src.has("dibujo"):
		return "fases n/d"
	var keys := ["proc", "callbk", "sim", "difer", "dibujo", "resto"]
	keys.sort_custom(func(a, b) -> bool: return float(src.get(a, 0.0)) > float(src.get(b, 0.0)))
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s %.1f" % [k, float(src.get(k, 0.0))])
	# 'callbk' y 'sim' son la SUMA de los ticks de física del frame, y un frame largo arrastra
	# varios ticks de recuperación: sin saber cuántos no se distingue causa de consecuencia.
	return "[" + " | ".join(parts) + "] x%d" % int(src.get("ticks", 0))


## Vuelca los tiempos acumulados al label y tiñe el texto según los FPS.
func _refresh_label() -> void:
	var fps := Engine.get_frames_per_second()
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

	var lines := PackedStringArray([
		"FPS      %d  (%.2f ms real)" % [fps, _frame_ms],
		"fases    %s" % _phases_line(_ph_smooth),
		"gpu      %.2f ms" % _render_gpu_ms,
		"rend cpu %.2f ms" % _render_cpu_ms,
		"draws    %d" % draw_calls,
	])
	if profiling:
		lines.append("cuerpos  %d  (%+d)" % [_bodies, _bodies_delta])
		lines.append("picos    %d  (peor %.0f ms, base %.1f)" % [_spike_count, _worst_ms, _baseline_ms])
	else:
		lines.append("perf     OFF  (consola: perf on)")
	_label.text = "\n".join(lines)

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
func _detect_spike(frame_ms: float) -> void:
	if not _refs_resolved:
		_resolve_refs()

	if _baseline_ms <= 0.0:
		_baseline_ms = frame_ms

	var is_spike := frame_ms > maxf(SPIKE_MIN_MS, _baseline_ms * SPIKE_FACTOR)
	if not is_spike:
		_baseline_ms = lerpf(_baseline_ms, frame_ms, BASELINE_RATE)

	_accumulate_window(frame_ms, is_spike)

	_sample_bodies()
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
##   dibujo alto         -> el main thread está BLOQUEADO esperando al hilo de render. Si además
##                          rendCPU y gpu son bajos, ese hilo no está ocupado: no consigue CPU
##                          (mirar hilos[] y voxel/threads/count en project.godot)
##   proc / callbk altos -> es GDScript: mirar la cola de '·' para saber quién
##   sim alto            -> PhysicsServer3D::step (cuerpos, colisiones del terreno)
##   difer alto          -> envío de comandos de render: demasiados objetos visibles
##   gpu alto            -> límite de GPU (draw calls / fill), no de CPU
##   nodos +N grande     -> alguien crea nodos ese frame (colisiones del terreno, vegetación)
##   drops +N            -> el streaming no da abasto y descarta trabajo: vas más rápido que él
##   pipelines +N        -> Godot compila variantes de shader al entrar material nuevo en cuadro
##   REBASE              -> ese frame el origen flotante movió el mundo entero
##   d= y t=             -> metros y segundos desde el pico anterior: distingue un disparo por
##                          distancia recorrida (streaming) de uno por reloj (tarea periódica)
func _dump_spike(frame_ms: float, node_delta: int, mem_delta: float,
		drop_delta: Vector2i, pipeline_delta: int, rebased: bool) -> void:
	var vp_rid := get_viewport().get_viewport_rid()
	# Dos líneas: la consola corta por ancho y lo decisivo (fases, hilos, costes) tiene que ir en
	# la primera. La segunda es el inventario del mundo alrededor del pico.
	var head := PackedStringArray([
		"[pico] %6.1f ms (base %.1f)" % [frame_ms, _baseline_ms],
		_phases_line(_ph),
		_since_last_spike(),
	])
	if _win_report != "":
		head.append(_win_report)
	var threads := _threads_report()
	if threads != "":
		head.append(threads)
	var costs := _costs_report()
	if costs != "":
		head.append(costs)
	head.append("rendCPU %.1f" % RenderingServer.viewport_get_measured_render_time_cpu(vp_rid))
	head.append("gpu %.1f" % RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))
	head.append("nodos %+d" % node_delta)
	if rebased:
		head.append("REBASE")
	print("  ".join(head))

	var tail := PackedStringArray([
		"[pico+] draws %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"mem %+.1f MB" % mem_delta,
		_terrain_report(),
		_instancer_report(),
	])
	for extra in [_item_counts_report(), _grids_report(), _physics_nodes_report()]:
		if extra != "":
			tail.append(extra)
	if drop_delta.x != 0 or drop_delta.y != 0:
		tail.append("drops carga %+d malla %+d" % [drop_delta.x, drop_delta.y])
	if pipeline_delta > 0:
		tail.append("pipelines +%d" % pipeline_delta)
	print("  ".join(tail))


## Acumula el último segundo y publica FPS reales, media y qué fracción de frames se salió. Es lo
## que separa "un tirón cada 10 s" de "la mitad de los frames van mal", que el detector de picos
## por sí solo no distingue.
func _accumulate_window(frame_ms: float, is_spike: bool) -> void:
	var now := Time.get_ticks_usec()
	if _win_start == 0:
		_win_start = now
	_win_frames += 1
	_win_time += frame_ms
	if is_spike:
		_win_spikes += 1
	if now - _win_start < 1000000:
		return
	var pct: int = int(round(100.0 * float(_win_spikes) / float(maxi(_win_frames, 1))))
	_win_report = "1s[%d fps, medio %.1f ms, malos %d%%]" % [
		_win_frames, _win_time / float(maxi(_win_frames, 1)), pct]
	_win_start = now
	_win_frames = 0
	_win_spikes = 0
	_win_time = 0.0


## Metros y segundos recorridos desde el pico anterior, en marco canónico (inmune al rebase).
func _since_last_spike() -> String:
	var pos := _canonical_pos()
	var now := Time.get_ticks_msec() / 1000.0
	var out := "d= --     t= -- "
	if _has_last_spike:
		out = "d=%5.1fm t=%4.1fs" % [pos.distance_to(_last_spike_pos), now - _last_spike_time]
	_last_spike_pos = pos
	_last_spike_time = now
	_has_last_spike = true
	return out


## Posición de cámara en el marco canónico: sumarle el offset acumulado del origen flotante
## evita que un rebase se cuele como cientos de metros recorridos.
func _canonical_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var p := cam.global_position
	if _origin != null and is_instance_valid(_origin):
		p += _origin.get("total_offset") as Vector3
	return p


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


## Tiempos del propio VoxelLodTerrain, sumados si hay varios planetas. Vienen en MICROsegundos.
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


## Ocupación de los hilos del VoxelEngine. Si 'activos' == 'hilos' de forma permanente con la cola
## llena, el terreno tiene la máquina saturada y el hilo de render se queda sin turno.
func _threads_report() -> String:
	if not Engine.has_singleton("VoxelEngine"):
		return ""
	var ve = Engine.get_singleton("VoxelEngine")
	if ve == null or not ve.has_method("get_stats"):
		return ""
	var s: Dictionary = ve.get_stats()
	# El esquema del dict cambia entre versiones del módulo: se vuelca crudo una vez para poder
	# afinar las claves de abajo sin adivinar.
	if not _threads_schema_dumped:
		_threads_schema_dumped = true
		print("[pico] esquema VoxelEngine.get_stats(): ", s)
	var pools = s.get("thread_pools", s)
	var parts := PackedStringArray()
	if pools is Dictionary:
		for pool_name in pools:
			var p = pools[pool_name]
			if p is Dictionary and p.has("active_threads"):
				parts.append("%s %d/%d cola %d" % [pool_name,
					int(p.get("active_threads", 0)), int(p.get("thread_count", 0)),
					int(p.get("tasks", 0))])
	if parts.is_empty():
		return ""
	return "hilos[" + "  ".join(parts) + "]"


## Cuerpos de colisión vivos del VoxelInstancer (los crea como hijos suyos, uno por instancia con
## colisión). El delta es del frame, para poder compararlo con el de 'nodos'.
func _instancer_report() -> String:
	if _instancers.is_empty():
		return "instancer n/d"
	return "instancer[cuerpos %d %+d]" % [_bodies, _bodies_delta]


## Las instancias vivas por item de la librería, de mayor a menor (solo las 5 primeras). Dice QUÉ
## item hay que recortar en vez de estimarlo por área y densidad. El id es el orden de registro:
## los items del JSON en orden, uno por cada entrada de su lod_index.
func _item_counts_report() -> String:
	for inst in _instancers:
		if not is_instance_valid(inst) or not inst.has_method("debug_get_instance_counts"):
			continue
		var counts: Dictionary = inst.debug_get_instance_counts()
		if counts.is_empty():
			continue
		var ids := counts.keys()
		ids.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
		var parts := PackedStringArray()
		for i in mini(5, ids.size()):
			parts.append("%s:%d" % [ids[i], int(counts[ids[i]])])
		return "items[" + " ".join(parts) + "]"
	return ""


## Qué scripts tienen _physics_process activo y cuántas instancias de cada uno, de mayor a menor.
## No da milisegundos, pero da la MULTIPLICIDAD: un coste de 20 ms por tick repartido entre cientos
## de nodos del mismo script se ve aquí sin tener que instrumentar cada sistema a ciegas.
func _physics_nodes_report() -> String:
	var counts: Dictionary = {}
	_walk_physics_nodes(get_tree().root, counts)
	if counts.is_empty():
		return ""
	var names := counts.keys()
	names.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	var parts := PackedStringArray()
	for i in mini(5, names.size()):
		parts.append("%s:%d" % [names[i], int(counts[names[i]])])
	return "fisica[" + " ".join(parts) + "]"


## Los subárboles del instancer y del terreno se saltan enteros: son decenas de miles de cuerpos
## sin script y recorrerlos costaría más que el pico que se está midiendo.
func _walk_physics_nodes(node: Node, counts: Dictionary) -> void:
	if node is VoxelInstancer or node is VoxelLodTerrain:
		return
	if node.is_physics_processing():
		var scr : Variant = node.get_script()
		var key: String = scr.resource_path.get_file().get_basename() if scr != null else node.get_class()
		counts[key] = int(counts.get(key, 0)) + 1
	for child in node.get_children():
		_walk_physics_nodes(child, counts)


## Grids dinámicas vivas y cuántas son restos de una rotura. Cada una integra en TODOS los ticks
## (can_sleep está desactivado), así que su coste va con el recuento.
func _grids_report() -> String:
	var grids := get_tree().get_nodes_in_group("dynamic_grid_body")
	if grids.is_empty():
		return ""
	var wrecks := 0
	for g in grids:
		if g.get("spawned_from_split"):
			wrecks += 1
	return "grids[%d de rotura %d]" % [grids.size(), wrecks]


## Recuenta los cuerpos del instancer. Se llama cada frame: sumar get_child_count() es O(1).
func _sample_bodies() -> void:
	var bodies := 0
	for inst in _instancers:
		if is_instance_valid(inst):
			bodies += inst.get_child_count()
	_bodies = bodies
	_bodies_delta = bodies - _prev_bodies
	_prev_bodies = bodies


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
	_instancers.clear()
	_collect_terrains(get_tree().root)
	if _origin != null:
		_prev_offset = _origin.get("total_offset")
	# Sin terreno todavía no merece la pena fijar las referencias: se reintenta al frame siguiente.
	_refs_resolved = not _terrains.is_empty()
	if _refs_resolved:
		print("[pico] detector activo: %d terreno(s), %d instancer(s), origen flotante %s"
			% [_terrains.size(), _instancers.size(), "sí" if _origin != null else "no"])


func _collect_terrains(node: Node) -> void:
	if node is VoxelLodTerrain:
		_terrains.append(node)
	elif node is VoxelInstancer:
		_instancers.append(node)
		return  # sus hijos son los cuerpos de colisión: recorrerlos cuesta miles de nodos
	for child in node.get_children():
		_collect_terrains(child)
