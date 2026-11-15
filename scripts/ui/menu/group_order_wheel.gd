class_name GroupOrderWheel
extends CanvasLayer

## Rueda de órdenes al grupo que acompaña al jugador (GroupCommand). Se abre al pulsar su tecla
## (group_orders); se apunta a una orden moviendo el ratón y se da al soltar la tecla, o con el clic
## izquierdo. Un toque corto sin apuntar a nada la deja abierta hasta el siguiente clic o toque. El
## clic derecho, esquivar o Escape la cierran sin dar nada. Como la rueda del martillo
## (BuildRadialMenu), el ratón sigue capturado: su movimiento lleva un cursor virtual desde el centro
## y la vista no gira mientras está abierta.
##
## La formación no se da al apuntarla: se despliegan sus formaciones en un arco por fuera (y la rueda
## se queda abierta si se suelta o se pulsa sobre ella) y se elige una llevando el cursor hasta allí.
## Trabajad, igual: se despliegan los oficios (set_jobs) y el elegido va a los elegidos (work_chosen).
##
## Abajo, sobre la hotbar (que se tapa mientras tanto), va el grupo en tarjetas (CompanionCards, las
## mismas que en el trono): el número, el retrato, el nombre, qué hace y su vida, su comida y su agua. Las
## teclas 1-9 eligen o quitan a cada uno y 0 (o º) a todos; las órdenes van solo a los elegidos. Se
## abre con todos elegidos menos los ocupados (trabajando en campo o de camino a un sitio) o, si el
## jugador mira a uno, solo con ese (como en Ghost Recon).

signal order_chosen(order: Order, selected: Array[int])
signal formation_chosen(index: int)
signal work_chosen(index: int, selected: Array[int])
signal selection_changed(selected: Array[bool])
signal closed

enum Order { FOLLOW, WAIT, ATTACK, RETREAT, HOME, FORMATION, BOARD, GOTO, WORK }

## En el sentido de las agujas del reloj, empezando arriba: moverse a la derecha (seguid, esperad,
## id allí, trabajad, a los bancos, a casa) y pelear a la izquierda (retirada, atacad), con la formación
## entre medias.
const ORDERS: Array[Order] = [Order.FOLLOW, Order.WAIT, Order.GOTO, Order.WORK, Order.BOARD, Order.HOME,
	Order.FORMATION, Order.RETREAT, Order.ATTACK]
## Las que despliegan un arco por fuera en vez de darse al apuntarlas.
const UNFOLDS: Array[Order] = [Order.FORMATION, Order.WORK]
const LABELS := {
	Order.FOLLOW: "GROUP_ORDER_FOLLOW",
	Order.WAIT: "GROUP_ORDER_WAIT",
	Order.ATTACK: "GROUP_ORDER_ATTACK",
	Order.RETREAT: "GROUP_ORDER_RETREAT",
	Order.HOME: "GROUP_ORDER_HOME",
	Order.FORMATION: "GROUP_ORDER_FORMATION",
	Order.BOARD: "GROUP_ORDER_BOARD",
	Order.GOTO: "GROUP_ORDER_GOTO",
	Order.WORK: "GROUP_ORDER_WORK",
}
const GLYPHS := {Order.FOLLOW: &"follow", Order.WAIT: &"wait", Order.ATTACK: &"attack", Order.RETREAT: &"retreat",
	Order.HOME: &"home", Order.FORMATION: &"formation", Order.BOARD: &"board", Order.GOTO: &"goto",
	Order.WORK: &"work"}
const HINTS := {
	Order.FOLLOW: "GROUP_HINT_FOLLOW",
	Order.WAIT: "GROUP_HINT_WAIT",
	Order.RETREAT: "GROUP_HINT_RETREAT",
	Order.HOME: "GROUP_HINT_HOME",
	Order.BOARD: "GROUP_HINT_BOARD",
	Order.GOTO: "GROUP_HINT_GOTO",
	Order.WORK: "GROUP_HINT_WORK",
}
const ACTION := &"group_orders"
## Medidas en la escala base de 1440 px de alto (las de la rueda del martillo).
const OUTER_RADIUS := 220.0
const INNER_RADIUS := 92.0
const ICON_SIZE := 64.0
const GAP_DEG := 2.5
const FONT_SIZE := 22
const DEAD_ZONE := 36.0
## Los arcos desplegados, por fuera de la rueda: de SUB_INNER a SUB_OUTER; el de las formaciones, de
## SUB_SPAN grados, y los demás, SUB_EACH grados por cosa.
const SUB_INNER := 228.0
const SUB_OUTER := 340.0
const SUB_SPAN := 150.0
const SUB_EACH := 32.0
const SUB_ICON := 52.0
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
## Las formaciones (sus nombres ya traducidos y sus dibujos) y la de ahora.
var _formations: Array[String] = []
var _formation_glyphs: Array[StringName] = []
var _formation_index := 0
## Los oficios de Trabajad (sus nombres ya traducidos y sus dibujos).
var _jobs: Array[String] = []
var _job_glyphs: Array[StringName] = []
## Hay un arco desplegado, de cuál (_unfolded) y lo que se apunta en él (o -1).
var _expanded := false
var _unfolded := Order.FORMATION
var _sub := -1
## El grupo: cada uno como una tarjeta de CompanionCards, y si está elegido.
var _roster: Array[Dictionary] = []
var _selected: Array[bool] = []
## Las tarjetas, sobre la hotbar.
var _cards: CompanionCards


func _ready() -> void:
	layer = 11
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_wheel)
	add_child(_canvas)
	_cards = CompanionCards.new()
	_canvas.add_child(_cards)
	visible = false


## Abre la rueda centrada, sin nada apuntado. [summary]: lo que dice el centro; [formations]: los
## nombres de las formaciones, con sus dibujos ([glyphs]) y la de ahora ([current]); [prey]: el de la
## fiera a la que apunta el jugador, o ""; [roster]: el grupo (como _roster); [only]: el único que se
## elige al abrir, o -1 para todos los que no estén ocupados ([busy], uno por puesto: trabajando o de
## camino); [strip]: dónde va la barra del grupo (la hotbar), o vacío.
func open(summary: String, formations: Array[String], glyphs: Array[StringName], current: int, prey: String,
		roster: Array[Dictionary], only := -1, strip := Rect2(), busy: Array[bool] = []) -> void:
	_cards.strip = strip
	_cards.first = 0
	_summary = summary
	_formations = formations
	_formation_glyphs = glyphs
	_formation_index = current
	_formation = formations[current] if current >= 0 and current < formations.size() else ""
	_prey = prey
	_roster = roster
	_selected.clear()
	for k in roster.size():
		_selected.append(only == k if only >= 0 else not (k < busy.size() and busy[k]))
	_expanded = false
	_sub = -1
	_ui_scale = GameTheme.scale_for(get_viewport())
	_cursor = Vector2.ZERO
	_hovered = -1
	_sticky = false
	_opened_at = Time.get_ticks_msec()
	visible = true
	_update_cards()
	_canvas.queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	_sticky = false
	_expanded = false
	_sub = -1
	closed.emit()


## Con la rueda abierta: lo que se ve de cada uno (vida, comida, qué hace...), en el mismo orden.
func set_roster(roster: Array[Dictionary]) -> void:
	if roster.size() != _roster.size():
		return
	_roster = roster
	if visible:
		_update_cards()


## Con la rueda abierta: el retrato del puesto [k], que acaba de llegar.
func set_portrait(k: int, texture: Texture2D) -> void:
	if k < 0 or k >= _roster.size():
		return
	_roster[k].portrait = texture
	_cards.set_portrait(k, texture)


## Quiénes están elegidos (uno por puesto de la lista).
func selection() -> Array[bool]:
	return _selected.duplicate()


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


## Lo que abre (radianes) el arco de [order] con [count] cosas.
static func sub_span(order: Order, count: int) -> float:
	return deg_to_rad(SUB_SPAN if order == Order.FORMATION else SUB_EACH * count)


## Los oficios que despliega Trabajad: sus nombres (ya traducidos) y sus dibujos (OrderGlyphs).
func set_jobs(names: Array[String], glyphs: Array[StringName]) -> void:
	_jobs = names
	_job_glyphs = glyphs


## Lo que hay en el arco de [order]: nombres y dibujos.
func _sub_names(order: Order) -> Array[String]:
	return _formations if order == Order.FORMATION else _jobs


func _sub_glyphs(order: Order) -> Array[StringName]:
	return _formation_glyphs if order == Order.FORMATION else _job_glyphs


## Formación (u oficio) del arco desplegado hacia la que apunta [cursor] (como en sector_at), de [count], o -1 si
## no cae en el arco (más cerca que [inner] o fuera de sus ángulos).
static func sub_at(cursor: Vector2, inner: float, count: int, order := Order.FORMATION) -> int:
	if count <= 0 or cursor.length() < inner:
		return -1
	var center := ORDERS.find(order) * TAU / ORDERS.size()
	var span := sub_span(order, count)
	var offset := angle_difference(center, atan2(cursor.x, -cursor.y)) + span * 0.5
	if offset < 0.0 or offset >= span:
		return -1
	# Abajo del todo, el ángulo crece hacia la izquierda: se cuenta al revés para leerlas de izquierda a derecha.
	return count - 1 - int(offset / span * count)


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
		_point(look * _reach())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_point((_cursor + event.relative).limit_length(_reach()))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and _roster_key(event.physical_keycode):
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


## Hasta dónde llega el cursor: la rueda o, desplegadas las formaciones, su arco.
func _reach() -> float:
	return (SUB_OUTER if _expanded else OUTER_RADIUS) * _ui_scale


## 1-9 elige o quita a ese del grupo; 0 (o º) elige a todos o, si ya lo estaban, a ninguno. true si
## era una de esas teclas.
func _roster_key(key: Key) -> bool:
	if key == KEY_0 or key == KEY_QUOTELEFT:
		var all := not _selected.has(false)
		for k in _selected.size():
			_selected[k] = not all
	elif key >= KEY_1 and key <= KEY_9:
		var k := int(key - KEY_1)
		if k >= _selected.size():
			return true
		_selected[k] = not _selected[k]
	else:
		return false
	selection_changed.emit(selection())
	_update_cards()
	_canvas.queue_redraw()
	return true


func _point(cursor: Vector2) -> void:
	_cursor = cursor
	var s := _ui_scale
	var hovered := _hovered
	var sub := -1
	if _expanded and _cursor.length() >= OUTER_RADIUS * s:
		sub = sub_at(_cursor, OUTER_RADIUS * s, _sub_names(_unfolded).size(), _unfolded)
		if sub < 0:
			hovered = sector_at(_cursor, DEAD_ZONE * s)
	else:
		hovered = sector_at(_cursor, DEAD_ZONE * s)
	if sub >= 0:
		hovered = ORDERS.find(_unfolded)
	var expanded := hovered >= 0 and UNFOLDS.has(ORDERS[hovered]) and not _sub_names(ORDERS[hovered]).is_empty()
	var unfolded := ORDERS[hovered] if expanded else _unfolded
	if hovered != _hovered or sub != _sub or expanded != _expanded or unfolded != _unfolded:
		_hovered = hovered
		_sub = sub
		_expanded = expanded
		_unfolded = unfolded
		_canvas.queue_redraw()


## Cierra y da lo apuntado, si hay algo (atacar, solo con una fiera a la vista; las demás órdenes,
## solo con alguien elegido). Sobre la formación sin elegir una del arco, la rueda se queda abierta
## con el arco desplegado.
func _finish() -> void:
	if _sub >= 0:
		var index := _sub
		var picked := _picked()
		var order := _unfolded
		if order == Order.WORK and picked.is_empty():
			return
		close()
		if order == Order.FORMATION:
			formation_chosen.emit(index)
		else:
			work_chosen.emit(index, picked)
		return
	if _hovered >= 0 and UNFOLDS.has(ORDERS[_hovered]):
		_sticky = true
		return
	var chosen := _hovered
	var picked := _picked()
	close()
	if chosen >= 0 and _enabled(ORDERS[chosen]):
		order_chosen.emit(ORDERS[chosen], picked)


## Los puestos de la lista que están elegidos.
func _picked() -> Array[int]:
	var out: Array[int] = []
	for k in _selected.size():
		if _selected[k]:
			out.append(k)
	return out


func _enabled(order: Order) -> bool:
	if order == Order.FORMATION:
		return true
	if not _selected.has(true):
		return false
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
	var nobody := not _selected.has(true)
	if _sub >= 0 and _unfolded == Order.WORK:
		lines.append(_jobs[_sub])
		lines.append(tr("GROUP_HINT_NOBODY") if nobody else tr("GROUP_HINT_WORK_PICK"))
	elif _sub >= 0:
		lines.append(_formations[_sub])
		lines.append(tr("GROUP_HINT_FORMATION_NOW") if _sub == _formation_index else tr("GROUP_HINT_FORMATION_PICK"))
	elif _hovered >= 0:
		var order := ORDERS[_hovered]
		lines.append(tr(LABELS[order]))
		if order == Order.FORMATION:
			lines.append(_formation)
		elif nobody:
			lines.append(tr("GROUP_HINT_NOBODY"))
		elif order == Order.ATTACK:
			lines.append(_prey if _prey != "" else tr("GROUP_HINT_NO_PREY"))
		else:
			lines.append(tr(HINTS[order]))
	else:
		lines.append(tr("GROUP_WHEEL_TITLE"))
		lines.append(_who_summary())
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

	if _expanded:
		_draw_sub(center, font, font_size)

	if _cursor.length() >= DEAD_ZONE * s:
		var tip := center + _cursor.normalized() * (inner - 8.0 * s)
		var d := 7.0 * s
		_canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -d), tip + Vector2(d, 0),
			tip + Vector2(0, d), tip + Vector2(-d, 0)]), GameTheme.BRONZE)


## Lo que dice el centro sin nada apuntado: cuántos van o, si no están todos elegidos, a quiénes.
func _who_summary() -> String:
	var picked := _picked()
	if picked.size() == _selected.size():
		return _summary
	if picked.is_empty():
		return tr("GROUP_HINT_NOBODY")
	if picked.size() == 1:
		return String(_roster[picked[0]].get("name", ""))
	return tr("GROUP_SOME") % [picked.size(), _selected.size()]


## El arco desplegado (formaciones u oficios), por fuera de su hueco; la formación de ahora, marcada.
func _draw_sub(center: Vector2, font: Font, font_size: int) -> void:
	var s := _ui_scale
	var names := _sub_names(_unfolded)
	var glyphs := _sub_glyphs(_unfolded)
	var count := names.size()
	if count == 0:
		return
	var inner := SUB_INNER * s
	var outer := SUB_OUTER * s
	var span := sub_span(_unfolded, count)
	var start := ORDERS.find(_unfolded) * TAU / ORDERS.size() - span * 0.5
	var each := span / count
	var gap := deg_to_rad(GAP_DEG)
	var small := roundi(font_size * 0.86)
	for k in count:
		var a0 := start + (count - 1 - k) * each + gap
		var a1 := start + (count - k) * each - gap
		var hovered := k == _sub
		var current := _unfolded == Order.FORMATION and k == _formation_index
		var ring := _sector(center, inner, outer, a0, a1)
		_canvas.draw_colored_polygon(ring, GameTheme.LEATHER_LIGHT if hovered else GameTheme.IRON)
		var outline := ring.duplicate()
		outline.append(ring[0])
		_canvas.draw_polyline(outline, GameTheme.BRONZE if hovered or current else GameTheme.BRONZE_LINE,
			maxf(1.0, (2.0 if hovered or current else 1.0) * s), true)
		var mid := center + _dir((a0 + a1) * 0.5) * (inner + outer) * 0.5
		var tint := GameTheme.BONE if hovered or current else GameTheme.MUTED
		var glyph: StringName = glyphs[k] if k < glyphs.size() else GLYPHS[_unfolded]
		OrderGlyphs.draw(_canvas.get_canvas_item(), glyph, mid - Vector2(0.0, 12.0 * s), SUB_ICON * s, tint)
		var label := names[k]
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, small).x
		_canvas.draw_string(font, mid + Vector2(-width * 0.5, SUB_ICON * 0.5 * s + 12.0 * s), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, small, tint)
		if current:
			_canvas.draw_circle(center + _dir((a0 + a1) * 0.5) * (outer - 10.0 * s), 4.0 * s, GameTheme.BRONZE)


## Las tarjetas del grupo, con quiénes están elegidos.
func _update_cards() -> void:
	_cards.ui_scale = _ui_scale
	_cards.help = tr("GROUP_ROSTER_KEYS") % _roster.size()
	_cards.show_roster(_roster, _selected.duplicate())


## Dibujo de cada orden, en un cuadrado de [size] centrado en [at] (OrderGlyphs).
## La formación lleva el de la de ahora.
func _draw_glyph(order: Order, at: Vector2, size: float, color: Color) -> void:
	var key: StringName = GLYPHS[order]
	if order == Order.FORMATION and _formation_index >= 0 and _formation_index < _formation_glyphs.size():
		key = _formation_glyphs[_formation_index]
	OrderGlyphs.draw(_canvas.get_canvas_item(), key, at, size, color)


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
