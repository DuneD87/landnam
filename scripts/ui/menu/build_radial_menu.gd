class_name BuildRadialMenu
extends CanvasLayer

## Rueda del martillo (clic derecho). Se abre al pulsar; se apunta a una opción moviendo el ratón y
## se elige al soltar, o con el clic izquierdo. Un toque corto sin apuntar a nada la deja abierta
## hasta el siguiente clic. El ratón sigue capturado: su movimiento lleva un cursor virtual desde
## el centro y, como este nodo recibe la entrada antes que la cámara, la vista no gira mientras
## está abierta.

signal option_chosen(option: Option)

enum Option { ADD, REMOVE, SELECT_BLOCK, BLUEPRINTS, SYMMETRY }

## En el sentido de las agujas del reloj, empezando arriba: lo de cada golpe (poner, quitar,
## simetría) a la derecha y los menús a la izquierda.
const OPTIONS: Array[Option] = [Option.ADD, Option.REMOVE, Option.SYMMETRY, Option.BLUEPRINTS,
	Option.SELECT_BLOCK]
const LABELS := {
	Option.ADD: "BUILD_RADIAL_ADD",
	Option.REMOVE: "BUILD_RADIAL_REMOVE",
	Option.SELECT_BLOCK: "BUILD_RADIAL_SELECT_BLOCK",
	Option.BLUEPRINTS: "BUILD_RADIAL_BLUEPRINTS",
	Option.SYMMETRY: "BUILD_RADIAL_SYMMETRY",
}
## Medidas en la escala base de 1440 px de alto.
const OUTER_RADIUS := 220.0
const INNER_RADIUS := 92.0
const ICON_SIZE := 64.0
const GAP_DEG := 2.5
const FONT_SIZE := 22
## Recorrido del cursor virtual por debajo del cual no se apunta a nada.
const DEAD_ZONE := 36.0
## Un clic derecho más corto que esto (s), sin apuntar a nada, deja la rueda abierta.
const TAP_TIME := 0.25

var _canvas: Control
var _cursor := Vector2.ZERO
var _hovered := -1
var _sticky := false
var _opened_at := 0
var _ui_scale := 1.0
## La opción del modo activo (poner o quitar) se marca en bronce.
var _active: Option = Option.ADD
var _block_icon: Texture2D = null
var _block_name := ""
## Eje de la simetría puesta («X», «Y», «Z») o "" sin ella.
var _symmetry := ""


func _ready() -> void:
	layer = 11
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_wheel)
	add_child(_canvas)
	visible = false


## Abre la rueda centrada, sin nada apuntado. [active] es el modo en curso; [block], lo que se
## pone ahora (su icono va en la opción de elegir bloque); [symmetry], el eje de la simetría puesta
## o "" (va en su hueco).
func open(active: Option, block: ItemData, symmetry: String = "") -> void:
	_active = active
	_symmetry = symmetry
	_block_icon = block.icon if block else null
	_block_name = block.get_display_name() if block else ""
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
	var step := TAU / OPTIONS.size()
	# 0 arriba y creciendo en el sentido de las agujas del reloj.
	var angle := atan2(cursor.x, -cursor.y)
	return int(fposmod(angle + step * 0.5, TAU) / step) % OPTIONS.size()


func _process(_delta: float) -> void:
	# Si otra cosa suelta el ratón (inventario, consola), la rueda sobra.
	if visible and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_cursor = (_cursor + event.relative).limit_length(OUTER_RADIUS * _ui_scale)
		var hovered := sector_at(_cursor, DEAD_ZONE * _ui_scale)
		if hovered != _hovered:
			_hovered = hovered
			_canvas.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_finish()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if _sticky:
					_finish()
			elif not _sticky:
				var held := (Time.get_ticks_msec() - _opened_at) / 1000.0
				if _hovered < 0 and held < TAP_TIME:
					_sticky = true
				else:
					_finish()


## Cierra y elige lo apuntado, si hay algo.
func _finish() -> void:
	var chosen := _hovered
	close()
	if chosen >= 0:
		option_chosen.emit(OPTIONS[chosen])


func _draw_wheel() -> void:
	var s := _ui_scale
	var center := _canvas.size * 0.5
	var outer := OUTER_RADIUS * s
	var inner := INNER_RADIUS * s
	var step := TAU / OPTIONS.size()
	var gap := deg_to_rad(GAP_DEG)
	var font := GameTheme.medium_font()
	var font_size := roundi(FONT_SIZE * s)

	for i in OPTIONS.size():
		var option := OPTIONS[i]
		var a0 := i * step - step * 0.5 + gap
		var a1 := i * step + step * 0.5 - gap
		var hovered := i == _hovered
		var ring := _sector(center, inner, outer, a0, a1)
		_canvas.draw_colored_polygon(ring, GameTheme.LEATHER_LIGHT if hovered else GameTheme.IRON)
		var outline := ring.duplicate()
		outline.append(ring[0])
		_canvas.draw_polyline(outline, GameTheme.BRONZE if hovered else GameTheme.BRONZE_LINE,
			maxf(1.0, (2.0 if hovered else 1.0) * s), true)
		if option == _active or (option == Option.SYMMETRY and _symmetry != ""):
			_canvas.draw_arc(center, outer - 5.0 * s, a0 - PI * 0.5 + gap, a1 - PI * 0.5 - gap, 24,
				GameTheme.BRONZE, 3.0 * s, true)

		var mid := center + _dir(i * step) * (inner + outer) * 0.5
		var tint := GameTheme.BONE if hovered else GameTheme.MUTED
		_draw_glyph(option, mid - Vector2(0.0, 12.0 * s), ICON_SIZE * s, tint)
		var label := _label(option)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		_canvas.draw_string(font, mid + Vector2(-width * 0.5, ICON_SIZE * 0.5 * s + 14.0 * s), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, tint)

	# Centro: lo apuntado o, sin nada, lo que se está haciendo ahora.
	_canvas.draw_circle(center, inner - 8.0 * s, GameTheme.IRON_DEEP)
	_canvas.draw_arc(center, inner - 8.0 * s, 0.0, TAU, 48, GameTheme.BRONZE_LINE, maxf(1.0, s), true)
	var lines: Array[String] = []
	if _hovered >= 0:
		lines.append(_label(OPTIONS[_hovered]))
		if OPTIONS[_hovered] == Option.SYMMETRY:
			lines.append(tr(_symmetry_next()))
	else:
		lines.append(_label(_active))
		if _block_name != "":
			lines.append(_block_name)
	# La primera línea en hueso y la segunda, más pequeña, en gris; las dos parten la línea si no
	# caben en el círculo.
	var box := (inner - 22.0 * s) * 2.0
	var sizes := [font_size, roundi(font_size * 0.82)]
	var heights: Array[float] = []
	var total := 0.0
	for k in lines.size():
		var h := font.get_multiline_string_size(lines[k], HORIZONTAL_ALIGNMENT_CENTER, box, sizes[k], 2).y
		heights.append(h)
		total += h
	var y := center.y - total * 0.5
	for k in lines.size():
		_canvas.draw_multiline_string(font, Vector2(center.x - box * 0.5, y + font.get_ascent(sizes[k])),
			lines[k], HORIZONTAL_ALIGNMENT_CENTER, box, sizes[k], 2, GameTheme.BONE if k == 0 else GameTheme.MUTED)
		y += heights[k]

	# Hacia dónde apunta el cursor virtual: un rombo en el borde del centro.
	if _cursor.length() >= DEAD_ZONE * s:
		var tip := center + _cursor.normalized() * (inner - 8.0 * s)
		var d := 7.0 * s
		_canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -d), tip + Vector2(d, 0),
			tip + Vector2(0, d), tip + Vector2(-d, 0)]), GameTheme.BRONZE)


func _label(option: Option) -> String:
	if option == Option.SYMMETRY and _symmetry != "":
		return tr("BUILD_RADIAL_SYMMETRY_AXIS") % _symmetry
	return tr(LABELS[option])


## Lo que hará elegir la simetría: ponerla, pasar al eje siguiente o quitarla.
func _symmetry_next() -> String:
	match _symmetry:
		"":
			return "BUILD_SYMMETRY_NEXT_ON"
		"Z":
			return "BUILD_SYMMETRY_NEXT_OFF"
	return "BUILD_SYMMETRY_NEXT_AXIS"


## Dibujo de cada opción, en un cuadrado de [size] centrado en [at].
func _draw_glyph(option: Option, at: Vector2, size: float, color: Color) -> void:
	var w := maxf(2.0, size * 0.08)
	var h := size * 0.3
	match option:
		Option.ADD:
			_canvas.draw_line(at - Vector2(h, 0), at + Vector2(h, 0), color, w, true)
			_canvas.draw_line(at - Vector2(0, h), at + Vector2(0, h), color, w, true)
		Option.REMOVE:
			_canvas.draw_line(at - Vector2(h, 0), at + Vector2(h, 0), color, w, true)
		Option.SELECT_BLOCK:
			if _block_icon:
				var side := size * 0.95
				_canvas.draw_texture_rect(_block_icon, Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)),
					false)
			else:
				_draw_cube(at, h * 1.2, color, w * 0.6)
		Option.SYMMETRY:
			# Dos medios bloques a los lados de un eje discontinuo.
			var r := h * 1.1
			for side in [-1.0, 1.0]:
				var tri := PackedVector2Array([at + Vector2(side * r * 0.25, -r), at + Vector2(side * r * 1.1, r),
					at + Vector2(side * r * 0.25, r), at + Vector2(side * r * 0.25, -r)])
				_canvas.draw_polyline(tri, color, w * 0.6, true)
			var dash := r * 0.28
			var y := -r * 1.15
			while y < r * 1.15:
				_canvas.draw_line(at + Vector2(0, y), at + Vector2(0, minf(y + dash, r * 1.15)), color, w * 0.45, true)
				y += dash * 1.8
		Option.BLUEPRINTS:
			# Un plano: hoja cuadrada con su cuadrícula.
			var r := h * 1.15
			var rect := PackedVector2Array([at + Vector2(-r, -r), at + Vector2(r, -r), at + Vector2(r, r),
				at + Vector2(-r, r), at + Vector2(-r, -r)])
			_canvas.draw_polyline(rect, color, w * 0.7, true)
			for t in [-1.0 / 3.0, 1.0 / 3.0]:
				_canvas.draw_line(at + Vector2(-r, r * t), at + Vector2(r, r * t), color, w * 0.35, true)
				_canvas.draw_line(at + Vector2(r * t, -r), at + Vector2(r * t, r), color, w * 0.35, true)


## Cubo en isométrica, para cuando aún no hay icono del bloque.
func _draw_cube(at: Vector2, r: float, color: Color, width: float) -> void:
	var top := at + Vector2(0, -r)
	var bottom := at + Vector2(0, r)
	var right := Vector2(r * 0.87, 0.0)
	var up := Vector2(0, -r * 0.5)
	var hexagon := PackedVector2Array([top, at + right + up, at + right - up, bottom, at - right - up,
		at - right + up, top])
	_canvas.draw_polyline(hexagon, color, width, true)
	_canvas.draw_line(at, top, color, width, true)
	_canvas.draw_line(at, at + right - up, color, width, true)
	_canvas.draw_line(at, at - right - up, color, width, true)


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
