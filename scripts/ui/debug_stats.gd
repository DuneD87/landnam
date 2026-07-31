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

var _label: Label
var _time_since_update := 0.0

var _frame_ms := 0.0
var _process_ms := 0.0
var _physics_ms := 0.0
var _render_cpu_ms := 0.0
var _render_gpu_ms := 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	# Sin esto los tiempos de render del viewport se quedan siempre a cero.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func toggle() -> void:
	visible = !visible


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
