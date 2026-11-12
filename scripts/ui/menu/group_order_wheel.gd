class_name GroupOrderWheel
extends CanvasLayer

## Rueda de órdenes al grupo que acompaña al jugador (GroupCommand). Se abre al pulsar su tecla
## (group_orders); se apunta a una orden moviendo el ratón y se da al soltar la tecla, o con el clic
## izquierdo. Un toque corto sin apuntar a nada la deja abierta hasta el siguiente clic o toque. El
## clic derecho, esquivar o Escape la cierran sin dar nada. Como la rueda del martillo
## (BuildRadialMenu), el ratón sigue capturado: su movimiento lleva un cursor virtual desde el centro
## y la vista no gira mientras está abierta.

signal order_chosen(order: Order)

enum Order { FOLLOW, WAIT, ATTACK, RETREAT, HOME, FORMATION }

## En el sentido de las agujas del reloj, empezando arriba: moverse a la derecha (seguid, esperad,
## a casa) y pelear a la izquierda (retirada, atacad), con la formación entre medias.
const ORDERS: Array[Order] = [Order.FOLLOW, Order.WAIT, Order.HOME, Order.FORMATION, Order.RETREAT,
	Order.ATTACK]
const LABELS := {
	Order.FOLLOW: "GROUP_ORDER_FOLLOW",
	Order.WAIT: "GROUP_ORDER_WAIT",
	Order.ATTACK: "GROUP_ORDER_ATTACK",
	Order.RETREAT: "GROUP_ORDER_RETREAT",
	Order.HOME: "GROUP_ORDER_HOME",
	Order.FORMATION: "GROUP_ORDER_FORMATION",
}
const HINTS := {
	Order.FOLLOW: "GROUP_HINT_FOLLOW",
	Order.WAIT: "GROUP_HINT_WAIT",
	Order.RETREAT: "GROUP_HINT_RETREAT",
	Order.HOME: "GROUP_HINT_HOME",
}
const ACTION := &"group_orders"
## Medidas en la escala base de 1440 px de alto (las de la rueda del martillo).
const OUTER_RADIUS := 220.0
const INNER_RADIUS := 92.0
const ICON_SIZE := 64.0
const GAP_DEG := 2.5
const FONT_SIZE := 22
const DEAD_ZONE := 36.0
## Un toque más corto que esto (s), sin apuntar a nada, deja la rueda abierta.
const TAP_TIME := 0.25

var _canvas: Control
var _cursor := Vector2.ZERO
var _hovered := -1
var _sticky := false
var _opened_at := 0
var _ui_scale := 1.0
## Lo que se ve en el centro sin apuntar a nada (cuántos van) y la formación de ahora (su nombre ya
## traducido), que sale bajo su orden.
var _summary := ""
var _formation := ""
## La fiera a la que irían (su nombre), o "": sin ella, atacar sale apagado.
var _prey := ""


func _ready() -> void:
	layer = 11
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_wheel)
	add_child(_canvas)
	visible = false


## Abre la rueda centrada, sin nada apuntado. [summary]: lo que dice el centro; [formation]: el
## nombre de la formación de ahora; [prey]: el de la fiera a la que apunta el jugador, o "".
func open(summary: String, formation: String, prey: String) -> void:
	_summary = summary
	_formation = formation
	_prey = prey
	_ui_scale = GameTheme.scale_for(get_viewport())
	_cursor = Vector2.ZERO
	_hovered = -1
	_sticky = false
	_opened_at = Time.get_ticks_msec()
	visible = true
	_canvas.queue_redraw()


func close() -> void:
	visible = false
	_sticky = false


func is_open() -> bool:
	return visible


## Hueco de la rueda hacia el que apunta [cursor] (desplazamiento desde el centro, en píxeles de
## pantalla, con y hacia abajo), o -1 dentro de la zona muerta.
static func sector_at(cursor: Vector2, dead_zone: float) -> int:
	if cursor.length() < dead_zone:
		return -1
	var step := TAU / ORDERS.size()
	var angle := atan2(cursor.x, -cursor.y)
	return int(fposmod(angle + step * 0.5, TAU) / step) % ORDERS.size()


func _process(_delta: float) -> void:
	# Si otra cosa suelta el ratón (inventario, consola), la rueda sobra.
	if visible and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge") or event.is_action_pressed("attack_2"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		_point(look * OUTER_RADIUS * _ui_scale)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_point((_cursor + event.relative).limit_length(OUTER_RADIUS * _ui_scale))
		get_viewport().set_input_as_handled()
	elif event.is_action(ACTION):
		get_viewport().set_input_as_handled()
		if event.is_echo():
			return
		if event.is_pressed():
			if _sticky:
				_finish()
		elif not _sticky:
			var held := (Time.get_ticks_msec() - _opened_at) / 1000.0
			if _hovered < 0 and held < TAP_TIME:
				_sticky = true
			else:
				_finish()
	elif event.is_action("attack_1"):
		get_viewport().set_input_as_handled()
		if event.is_pressed():
			_finish()
	elif event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _point(cursor: Vector2) -> void:
	_cursor = cursor
	var hovered := sector_at(_cursor, DEAD_ZONE * _ui_scale)
	if hovered != _hovered:
		_hovered = hovered
		_canvas.queue_redraw()


## Cierra y da lo apuntado, si hay algo (atacar, solo con una fiera a la vista).
func _finish() -> void:
	var chosen := _hovered
	close()
	if chosen >= 0 and _enabled(ORDERS[chosen]):
		order_chosen.emit(ORDERS[chosen])


func _enabled(order: Order) -> bool:
	return order != Order.ATTACK or _prey != ""


func _draw_wheel() -> void:
	var s := _ui_scale
	var center := _canvas.size * 0.5
	var outer := OUTER_RADIUS * s
	var inner := INNER_RADIUS * s
	var step := TAU / ORDERS.size()
	var gap := deg_to_rad(GAP_DEG)
	var font := GameTheme.medium_font()
	var font_size := roundi(FONT_SIZE * s)

	for i in ORDERS.size():
		var order := ORDERS[i]
		var a0 := i * step - step * 0.5 + gap
		var a1 := i * step + step * 0.5 - gap
		var enabled := _enabled(order)
		var hovered := i == _hovered and enabled
		var ring := _sector(center, inner, outer, a0, a1)
		_canvas.draw_colored_polygon(ring, GameTheme.LEATHER_LIGHT if hovered else GameTheme.IRON)
		var outline := ring.duplicate()
		outline.append(ring[0])
		_canvas.draw_polyline(outline, GameTheme.BRONZE if hovered else GameTheme.BRONZE_LINE,
			maxf(1.0, (2.0 if hovered else 1.0) * s), true)
		var mid := center + _dir(i * step) * (inner + outer) * 0.5
		var tint := GameTheme.BONE if hovered else GameTheme.MUTED
		if not enabled:
			tint.a *= 0.4
		_draw_glyph(order, mid - Vector2(0.0, 12.0 * s), ICON_SIZE * s, tint)
		var label := tr(LABELS[order])
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		_canvas.draw_string(font, mid + Vector2(-width * 0.5, ICON_SIZE * 0.5 * s + 14.0 * s), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, tint)

	# Centro: lo apuntado y lo que hará o, sin nada, cuántos van.
	_canvas.draw_circle(center, inner - 8.0 * s, GameTheme.IRON_DEEP)
	_canvas.draw_arc(center, inner - 8.0 * s, 0.0, TAU, 48, GameTheme.BRONZE_LINE, maxf(1.0, s), true)
	var lines: Array[String] = []
	if _hovered >= 0:
		var order := ORDERS[_hovered]
		lines.append(tr(LABELS[order]))
		match order:
			Order.FORMATION:
				lines.append(_formation)
			Order.ATTACK:
				lines.append(_prey if _prey != "" else tr("GROUP_HINT_NO_PREY"))
			_:
				lines.append(tr(HINTS[order]))
	else:
		lines.append(tr("GROUP_WHEEL_TITLE"))
		lines.append(_summary)
	var box := (inner - 22.0 * s) * 2.0
	var sizes := [font_size, roundi(font_size * 0.82)]
	var heights: Array[float] = []
	var total := 0.0
	for k in lines.size():
		var h := font.get_multiline_string_size(lines[k], HORIZONTAL_ALIGNMENT_CENTER, box, sizes[k], 3).y
		heights.append(h)
		total += h
	var y := center.y - total * 0.5
	for k in lines.size():
		_canvas.draw_multiline_string(font, Vector2(center.x - box * 0.5, y + font.get_ascent(sizes[k])),
			lines[k], HORIZONTAL_ALIGNMENT_CENTER, box, sizes[k], 3, GameTheme.BONE if k == 0 else GameTheme.MUTED)
		y += heights[k]

	if _cursor.length() >= DEAD_ZONE * s:
		var tip := center + _cursor.normalized() * (inner - 8.0 * s)
		var d := 7.0 * s
		_canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -d), tip + Vector2(d, 0),
			tip + Vector2(0, d), tip + Vector2(-d, 0)]), GameTheme.BRONZE)


## Dibujo de cada orden, en un cuadrado de [size] centrado en [at].
func _draw_glyph(order: Order, at: Vector2, size: float, color: Color) -> void:
	var w := maxf(2.0, size * 0.07)
	var h := size * 0.32
	match order:
		Order.FOLLOW:
			# Una flecha hacia arriba con dos puntos detrás: los que siguen.
			_arrow(at + Vector2(0, h * 0.5), at + Vector2(0, -h), color, w)
			for side in [-1.0, 1.0]:
				_canvas.draw_circle(at + Vector2(side * h * 0.8, h * 0.8), w * 1.1, color)
		Order.WAIT:
			# Una mano en alto: un palmo y cuatro dedos.
			_canvas.draw_line(at + Vector2(-h * 0.7, h), at + Vector2(h * 0.7, h), color, w, true)
			for k in 4:
				var x := lerpf(-h * 0.6, h * 0.6, k / 3.0)
				var top := -h * (0.95 if k == 1 or k == 2 else 0.7)
				_canvas.draw_line(at + Vector2(x, h), at + Vector2(x, top), color, w, true)
		Order.ATTACK:
			# Dos hojas cruzadas.
			_canvas.draw_line(at + Vector2(-h, h), at + Vector2(h, -h), color, w, true)
			_canvas.draw_line(at + Vector2(h, h), at + Vector2(-h, -h), color, w, true)
			for side in [-1.0, 1.0]:
				var hilt := at + Vector2(side * h * 0.55, h * 0.55)
				var across := Vector2(side, 1.0).normalized() * h * 0.3
				_canvas.draw_line(hilt - Vector2(across.x, -across.y), hilt + Vector2(across.x, -across.y), color,
					w * 0.8, true)
		Order.RETREAT:
			# Una flecha que da la vuelta.
			_canvas.draw_arc(at + Vector2(0, -h * 0.1), h * 0.75, -PI * 0.5, PI * 0.75, 20, color, w, true)
			var tip := at + Vector2(0, -h * 0.1) + Vector2(cos(PI * 0.75), sin(PI * 0.75)) * h * 0.75
			_canvas.draw_line(tip, tip + Vector2(h * 0.55, -h * 0.05), color, w, true)
			_canvas.draw_line(tip, tip + Vector2(-h * 0.1, -h * 0.55), color, w, true)
		Order.HOME:
			# Una casa: el tejado y las paredes.
			_canvas.draw_polyline(PackedVector2Array([at + Vector2(-h, -h * 0.1), at + Vector2(0, -h),
				at + Vector2(h, -h * 0.1)]), color, w, true)
			_canvas.draw_polyline(PackedVector2Array([at + Vector2(-h * 0.7, -h * 0.1), at + Vector2(-h * 0.7, h),
				at + Vector2(h * 0.7, h), at + Vector2(h * 0.7, -h * 0.1)]), color, w, true)
		Order.FORMATION:
			# La cuña: uno delante y dos filas detrás.
			_canvas.draw_circle(at + Vector2(0, -h * 0.9), w * 1.3, color)
			for row in [1, 2]:
				for side in [-1.0, 1.0]:
					_canvas.draw_circle(at + Vector2(side * h * 0.5 * row, -h * 0.9 + h * 0.85 * row), w * 1.1, color)


func _arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	_canvas.draw_line(from, to, color, width, true)
	var back := (from - to).normalized() * width * 4.0
	_canvas.draw_line(to, to + back.rotated(0.6), color, width, true)
	_canvas.draw_line(to, to + back.rotated(-0.6), color, width, true)


## Corona entre [inner] y [outer] de [a0] a [a1] (radianes desde arriba, en el sentido de las agujas).
func _sector(center: Vector2, inner: float, outer: float, a0: float, a1: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 16
	for k in steps + 1:
		points.append(center + _dir(lerpf(a0, a1, float(k) / steps)) * outer)
	for k in range(steps, -1, -1):
		points.append(center + _dir(lerpf(a0, a1, float(k) / steps)) * inner)
	return points


static func _dir(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))
