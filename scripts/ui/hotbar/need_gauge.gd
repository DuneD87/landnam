class_name NeedGauge
extends Control

## Medidor de una necesidad en la consola de la barra rápida (Hotbar): un arco por el canal tallado
## alrededor de un engaste, que arranca del medallón de su icono y se llena desde él en el sentido
## de las agujas del reloj. El medallón late cuando el valor está bajo. La temperatura no se llena:
## un rombo marca dónde está entre el frío (junto al icono) y el calor (la punta), sobre el
## degradado de uno a otro. Dibuja en las coordenadas de la capa: se coloca con place().

enum Mode {FILL, BIPOLAR}

const COLD := Color(0.45, 0.72, 0.98)
const MILD := Color(0.86, 0.82, 0.72)
const HOT := Color(0.95, 0.42, 0.2)

var mode := Mode.FILL
var color := Color.WHITE
## De 0 a 1, o de -1 a 1 en BIPOLAR.
var value := 1.0
var critical := false

var _centre := Vector2.ZERO
var _radius := 0.0
var _width := 0.0
var _base := 0.0
var _tip := 0.0
var _medallion := Vector2.ZERO
var _medallion_radius := 0.0
var _scale := 1.0
var _time := 0.0


func _init(gauge_mode: Mode, gauge_color: Color) -> void:
	mode = gauge_mode
	color = gauge_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## [base_deg] y [tip_deg] son grados desde lo alto del engaste en el sentido de las agujas del
## reloj (como en tools/ui/bake_hotbar_console.py); el medallón, igual, a [medallion_distance].
func place(centre: Vector2, radius: float, width: float, base_deg: float, tip_deg: float,
		medallion_deg: float, medallion_distance: float, medallion_radius: float, ui_scale: float) -> void:
	_centre = centre
	_radius = radius
	_width = width
	_base = deg_to_rad(base_deg - 90.0)
	_tip = deg_to_rad(tip_deg - 90.0)
	_medallion = centre + Vector2.from_angle(deg_to_rad(medallion_deg - 90.0)) * medallion_distance
	_medallion_radius = medallion_radius
	_scale = ui_scale
	queue_redraw()


func set_value(new_value: float, is_critical: bool, delta: float) -> void:
	_time += delta
	if is_equal_approx(new_value, value) and is_critical == critical and not critical:
		return
	value = new_value
	critical = is_critical
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 6.0) if critical else 0.0
	if mode == Mode.FILL:
		_draw_fill(pulse)
	else:
		_draw_bipolar()
	if critical:
		draw_arc(_medallion, _medallion_radius + 2.5 * _scale, 0.0, TAU, 48,
			Color(GameTheme.BLOOD.lightened(0.2), 0.35 + 0.5 * pulse), 2.0 * _scale, true)


func _angle_at(t: float) -> float:
	return lerpf(_base, _tip, t)


func _draw_fill(pulse: float) -> void:
	var t := clampf(value, 0.0, 1.0)
	if t <= 0.002:
		return
	var tint := color.lerp(GameTheme.BLOOD.lightened(0.15), pulse * 0.5) if critical else color
	var points := maxi(4, int(48 * t))
	draw_arc(_centre, _radius, _base, _angle_at(t), points, tint.darkened(0.25), _width, true)
	# Brillo por el lado de fuera, como el del líquido de las orbes.
	draw_arc(_centre, _radius + _width * 0.22, _base, _angle_at(t), points, Color(tint.lightened(0.25), 0.8),
		_width * 0.32, true)


func _draw_bipolar() -> void:
	var segments := 24
	for i in segments:
		var a := float(i) / segments
		var b := float(i + 1) / segments
		draw_arc(_centre, _radius, _angle_at(a), _angle_at(b), 3, Color(_temperature_color(a), 0.32), _width, true)
	# Del medio al valor, vivo.
	var t := clampf(value * 0.5 + 0.5, 0.0, 1.0)
	var lo := minf(t, 0.5)
	var hi := maxf(t, 0.5)
	var steps := maxi(1, int((hi - lo) * segments))
	for i in steps:
		var a := lerpf(lo, hi, float(i) / steps)
		var b := lerpf(lo, hi, float(i + 1) / steps)
		draw_arc(_centre, _radius, _angle_at(a), _angle_at(b), 3, _temperature_color((a + b) * 0.5), _width * 0.7, true)
	var at := _centre + Vector2.from_angle(_angle_at(t)) * _radius
	draw_colored_polygon(SagaFrame.diamond(at, 6.5 * _scale), GameTheme.INK)
	draw_colored_polygon(SagaFrame.diamond(at, 5.0 * _scale), GameTheme.BONE if not critical else _temperature_color(t))
	draw_colored_polygon(SagaFrame.diamond(at, 2.0 * _scale), GameTheme.INK)


## Del frío (0) al calor (1), pasando por templado en el medio.
static func _temperature_color(t: float) -> Color:
	return COLD.lerp(MILD, t * 2.0) if t < 0.5 else MILD.lerp(HOT, t * 2.0 - 1.0)
