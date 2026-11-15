class_name CompanionCards
extends Control

## La barra de tarjetas de compañeros o colonos (como en Mount & Blade), la misma en la rueda de órdenes
## del grupo (GroupOrderWheel) y en la vista del trono (ThroneView): en cada una, el retrato
## (CompanionPortraits) con su número y, si lo tiene, el dibujo de su oficio, el nombre, qué hace y sus
## barras (vida, comida, agua...). Elegida, enmarcada en bronce; si no, apagada. Encima va una ayuda
## (las teclas).
##
## Ocupa todo su padre y dibuja las tarjetas apoyadas en el fondo de [strip] (o, sin él, en el sitio de
## la hotbar), centradas. Si no caben a su tamaño, se encogen hasta MIN_W y, de ahí, se pasan de
## página (scroll: la primera que se ve; con flechas a los lados). No coge el ratón: quien la usa
## pregunta card_at() y mueve scroll(); hover marca una y, si su estado no cabía, lo enseña entero
## encima.
##
## Cada tarjeta (roster) es {name, state (ya traducidos), down, portrait (o null), bars: [[0-1, Color]],
## y opcionales glyph y glyph_color (su oficio, OrderGlyphs) y warn (el estado, en naranja)}.

const CARD_W := 164.0
const MIN_W := 132.0
const CARD_H := 204.0
const CARD_GAP := 10.0
const PORTRAIT := 108.0
const BAR_H := 7.0
const BAR_GAP := 4.0
const FONT_SIZE := 22
const GLYPH := 28.0
const ARROW := 26.0
const HEALTH_COLOR := GameTheme.BLOOD
const FOOD_COLOR := Color(0.86, 0.62, 0.27)
const WATER_COLOR := Color(0.42, 0.66, 0.95)
const WARN_COLOR := Color("d98a5b")
## El sitio de la hotbar sin hotbar: el panel de la consola a la escala base.
const STRIP_SIZE := Vector2(1048.0, 112.0)
const STRIP_GAP := 22.0

var roster: Array[Dictionary] = []
var selected: Array[bool] = []
## Dónde se apoyan (en el marco de este control), o vacío para el sitio de la hotbar.
var strip := Rect2()
## La ayuda de encima ("" sin ella) y si se ponen los números de las teclas en los retratos.
var help := ""
var numbers := true
var ui_scale := 1.0
## La tarjeta bajo el ratón (o -1) y la primera que se ve.
var hover := -1:
	set(value):
		if value != hover:
			hover = value
			queue_redraw()
var first := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Pone las tarjetas y quiénes están elegidos (uno por tarjeta).
func show_roster(entries: Array[Dictionary], picked: Array[bool]) -> void:
	roster = entries
	selected = picked
	first = clampi(first, 0, maxi(roster.size() - _fits(), 0))
	queue_redraw()


## El retrato de la tarjeta [k], que acaba de llegar.
func set_portrait(k: int, texture: Texture2D) -> void:
	if k >= 0 and k < roster.size():
		roster[k].portrait = texture
		queue_redraw()


## Pasa [step] tarjetas (con signo). Falso si no había más por ese lado.
func scroll(step: int) -> bool:
	var to := clampi(first + step, 0, maxi(roster.size() - _fits(), 0))
	if to == first:
		return false
	first = to
	queue_redraw()
	return true


## Cuántas se ven a la vez (lo que pasan las flechas).
func page() -> int:
	return maxi(_fits(), 1)


## Hace que se vea la tarjeta [k].
func reveal(k: int) -> void:
	var fits := _fits()
	if k < first:
		scroll(k - first)
	elif k >= first + fits:
		scroll(k - first - fits + 1)


## La tarjeta bajo [point] (en el marco de este control), o -1.
func card_at(point: Vector2) -> int:
	var layout := _layout()
	for k in range(first, mini(first + _fits(), roster.size())):
		if _card_rect(layout, k).has_point(point):
			return k
	return -1


## Si [point] cae en la barra (tarjetas, flechas y ayuda): ahí el ratón no es del mundo.
func covers(point: Vector2) -> bool:
	if roster.is_empty():
		return false
	var layout := _layout()
	var area: Rect2 = layout.area
	return area.grow_individual(0.0, 40.0 * ui_scale, 0.0, 0.0).has_point(point)


## La flecha bajo [point]: -1 la de la izquierda, 1 la de la derecha, 0 ninguna.
func arrow_at(point: Vector2) -> int:
	var layout := _layout()
	if first > 0 and _arrow_rect(layout, -1).has_point(point):
		return -1
	if first + _fits() < roster.size() and _arrow_rect(layout, 1).has_point(point):
		return 1
	return 0


## La barra de vida, la de comida y la de agua de [c] (0-1).
static func bars_of(c: Companion) -> Array:
	var hp := c.health
	var out := [[hp.health / maxf(hp.max_health, 1.0) if hp != null else 1.0, HEALTH_COLOR]]
	if c.meals != null:
		out.append([c.meals.food_ratio(), FOOD_COLOR])
		out.append([c.meals.water_ratio(), WATER_COLOR])
	return out


# --- Medidas --------------------------------------------------------------------------------------

func _strip() -> Rect2:
	if strip.size.x > 0.0:
		return strip
	var s := STRIP_SIZE * ui_scale
	return Rect2(Vector2((size.x - s.x) * 0.5, size.y - STRIP_GAP * ui_scale - s.y), s)


## Cuántas caben a la vez.
func _fits() -> int:
	var s := ui_scale
	var room := _strip().size.x
	var each := (MIN_W + CARD_GAP) * s
	var n := roster.size()
	if n * MIN_W * s + (n - 1) * CARD_GAP * s <= room:
		return n
	# Con flechas a los lados.
	return maxi(int((room - (ARROW + CARD_GAP) * 2.0 * s + CARD_GAP * s) / each), 1)


## Dónde va todo: {w, h, x0, top, area, paged}.
func _layout() -> Dictionary:
	var s := ui_scale
	var bar := _strip()
	var n := mini(_fits(), roster.size())
	var paged := n < roster.size()
	var gap := CARD_GAP * s
	var room := bar.size.x - ((ARROW + CARD_GAP) * 2.0 * s if paged else 0.0)
	var w := clampf((room - gap * (n - 1)) / maxf(n, 1), MIN_W * s, CARD_W * s) if n > 0 else CARD_W * s
	var h := CARD_H * s
	var total := w * n + gap * maxf(n - 1, 0)
	var x0 := bar.get_center().x - total * 0.5
	var top := bar.end.y - h
	var area := Rect2(x0, top, total, h)
	if paged:
		area = area.grow_individual((ARROW + CARD_GAP) * s, 0.0, (ARROW + CARD_GAP) * s, 0.0)
	return {w = w, h = h, x0 = x0, top = top, area = area, paged = paged}


func _card_rect(layout: Dictionary, k: int) -> Rect2:
	var w: float = layout.w
	return Rect2(layout.x0 + (w + CARD_GAP * ui_scale) * (k - first), layout.top, w, layout.h)


func _arrow_rect(layout: Dictionary, side: int) -> Rect2:
	var s := ui_scale
	var area: Rect2 = layout.area
	var x := area.position.x if side < 0 else area.end.x - ARROW * s
	return Rect2(x, area.position.y, ARROW * s, area.size.y)


# --- Dibujo ---------------------------------------------------------------------------------------

func _draw() -> void:
	if roster.is_empty():
		return
	var s := ui_scale
	var font := GameTheme.medium_font()
	var font_size := roundi(FONT_SIZE * s)
	var small := roundi(font_size * 0.78)
	var layout := _layout()
	var last := mini(first + _fits(), roster.size())
	var cut_state := ""
	var cut_card := Rect2()
	for k in range(first, last):
		var card := _card_rect(layout, k)
		var full := _draw_card(k, card, font, font_size, small)
		if k == hover and full != "":
			cut_state = full
			cut_card = card
	if layout.paged:
		for side in [-1, 1]:
			var on: bool = first > 0 if side < 0 else last < roster.size()
			var rect := _arrow_rect(layout, side)
			var c := rect.get_center()
			var d := 8.0 * s
			var tint := GameTheme.BRONZE if on else Color(GameTheme.MUTED, 0.3)
			_draw_triangle(c, d, side, tint)
	var area: Rect2 = layout.area
	var text := help
	if layout.paged:
		var range_text := "%d-%d / %d" % [first + 1, last, roster.size()]
		text = range_text if text == "" else "%s · %s" % [range_text, text]
	if text != "":
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		draw_string(font, Vector2(area.get_center().x - text_w * 0.5, area.position.y - 8.0 * s - font.get_descent(small)),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, small, GameTheme.MUTED)
	if cut_state != "":
		_draw_full_state(cut_state, cut_card, font, small)


## La tarjeta [k] en [card]. Devuelve su estado entero si no cabía (o "").
func _draw_card(k: int, card: Rect2, font: Font, font_size: int, small: int) -> String:
	var s := ui_scale
	var entry := roster[k]
	var on := k < selected.size() and selected[k]
	var lit := on or k == hover
	var down := bool(entry.get("down", false))
	var w := card.size.x
	var pad := 8.0 * s
	draw_rect(card, GameTheme.LEATHER_LIGHT if on else GameTheme.IRON_DEEP)
	draw_rect(card, GameTheme.BRONZE if lit else GameTheme.BRONZE_LINE, false, maxf(1.0, (2.0 if lit else 1.0) * s))
	# El retrato (o, mientras se hace, una silueta).
	var side := minf(PORTRAIT * s, w - pad * 2.0)
	var frame := Rect2(Vector2(card.get_center().x - side * 0.5, card.position.y + pad), Vector2(side, side))
	draw_rect(frame, Color(0.0, 0.0, 0.0, 0.35))
	var alpha := 1.0 if on else (0.7 if k == hover else 0.45)
	var fade := Color(1, 1, 1, alpha)
	var portrait := entry.get("portrait") as Texture2D
	if portrait != null:
		draw_texture_rect(portrait, frame, false, Color(1.0, 0.55, 0.5, alpha) if down else fade)
	else:
		var ghost := Color(GameTheme.MUTED, 0.35 * alpha)
		draw_circle(frame.get_center() - Vector2(0, side * 0.08), side * 0.2, ghost)
		draw_colored_polygon(PackedVector2Array([frame.position + Vector2(side * 0.2, side),
			frame.position + Vector2(side * 0.3, side * 0.72), frame.position + Vector2(side * 0.7, side * 0.72),
			frame.position + Vector2(side * 0.8, side)]), ghost)
	draw_rect(frame, GameTheme.BRONZE_LINE, false, maxf(1.0, s))
	# Su número, en la esquina del retrato.
	if numbers and k < 9:
		var badge := frame.position + Vector2(13.0, 13.0) * s
		draw_circle(badge, 12.0 * s, GameTheme.IRON_DEEP)
		draw_arc(badge, 12.0 * s, 0.0, TAU, 24, GameTheme.BRONZE if on else GameTheme.BRONZE_LINE, maxf(1.0, s), true)
		var key := str(k + 1)
		var key_w := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		draw_string(font, badge + Vector2(-key_w * 0.5, font.get_ascent(small) * 0.5 - 1.0 * s), key,
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, GameTheme.BRONZE if on else GameTheme.MUTED)
	# Su oficio, en la otra esquina.
	if entry.has("glyph"):
		var glyph_side := GLYPH * s
		var at := Vector2(frame.end.x - glyph_side * 0.5 - 2.0 * s, frame.position.y + glyph_side * 0.5 + 2.0 * s)
		draw_circle(at, glyph_side * 0.58, Color(GameTheme.IRON_DEEP, 0.85))
		var tint: Color = entry.get("glyph_color", GameTheme.BONE)
		tint.a *= maxf(alpha, 0.6)
		OrderGlyphs.draw(get_canvas_item(), entry.glyph, at, glyph_side * 0.8, tint)
	# El nombre y qué hace.
	var inner := w - pad * 2.0
	var name_size := roundi(font_size * 0.86)
	var y := frame.end.y + 6.0 * s
	var name_text := fit(font, String(entry.get("name", "")), name_size, inner)
	var name_w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	draw_string(font, Vector2(card.get_center().x - name_w * 0.5, y + font.get_ascent(name_size)), name_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, GameTheme.BONE if lit else GameTheme.MUTED)
	y += font.get_height(name_size)
	var full := String(entry.get("state", ""))
	var state := fit(font, full, small, inner)
	var state_w := font.get_string_size(state, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	var state_color := GameTheme.MUTED
	if down:
		state_color = HEALTH_COLOR
	elif bool(entry.get("warn", false)):
		state_color = WARN_COLOR
	draw_string(font, Vector2(card.get_center().x - state_w * 0.5, y + font.get_ascent(small)), state,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, state_color)
	# Las barras, al pie.
	var bars: Array = entry.get("bars", [])
	var bar_h := maxf(3.0, BAR_H * s)
	var step := bar_h + BAR_GAP * s
	var bar_y := card.end.y - pad - bar_h - step * (bars.size() - 1)
	for bar: Array in bars:
		_bar(Rect2(card.position.x + pad, bar_y, inner, bar_h), float(bar[0]), bar[1], alpha)
		bar_y += step
	return full if state != full else ""


## El estado entero de la tarjeta [card], que no cabía: en un recuadro encima de ella.
func _draw_full_state(text: String, card: Rect2, font: Font, small: int) -> void:
	var s := ui_scale
	var width := maxf(card.size.x * 1.8, 220.0 * s)
	var pad := 8.0 * s
	var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, small, 4).y
	var box := Rect2(card.get_center().x - width * 0.5 - pad, card.position.y - h - pad * 2.0 - 6.0 * s,
		width + pad * 2.0, h + pad * 2.0)
	box.position.x = clampf(box.position.x, 4.0 * s, maxf(size.x - box.size.x - 4.0 * s, 4.0 * s))
	draw_rect(box, Color(GameTheme.IRON_DEEP, 0.95))
	draw_rect(box, GameTheme.BRONZE_LINE, false, maxf(1.0, s))
	draw_multiline_string(font, box.position + Vector2(pad, pad + font.get_ascent(small)), text,
		HORIZONTAL_ALIGNMENT_LEFT, width, small, 4, GameTheme.BONE)


func _draw_triangle(center: Vector2, d: float, side: int, color: Color) -> void:
	var tip := center + Vector2(d * side, 0.0)
	draw_colored_polygon(PackedVector2Array([tip, center + Vector2(-d * side, -d * 1.3),
		center + Vector2(-d * side, d * 1.3)]), color)


## Una barra de [rect] llena hasta [ratio] (0-1) de [color], con [alpha].
func _bar(rect: Rect2, ratio: float, color: Color, alpha: float) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.5 * alpha))
	var fill := rect
	fill.size.x *= clampf(ratio, 0.0, 1.0)
	if fill.size.x > 0.0:
		draw_rect(fill, Color(color, alpha))
	draw_rect(rect, Color(GameTheme.BRONZE_LINE, GameTheme.BRONZE_LINE.a * alpha), false, 1.0)


## [text] recortado con «…» para que quepa en [width] a [font_size].
static func fit(font: Font, text: String, font_size: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		cut = cut.left(-1)
	return cut + "…"
