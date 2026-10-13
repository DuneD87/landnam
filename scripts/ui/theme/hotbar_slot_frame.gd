@tool
class_name HotbarSlotFrame
extends StyleBox

## Cuero hundido en bronce. La tecla tiene su propio pie; el objeto ocupa la cámara superior.
## El arma activa enciende el borde y la tecla. La otra mano usa el mismo lenguaje en escarcha.

var ui_scale := 1.0
var fill := Color("242019")
var accent := Color("c9a46a")
var emphasis := 0.0
var empty := false


func _draw(item: RID, rect: Rect2) -> void:
	if rect.size.x <= 12.0 * ui_scale or rect.size.y <= 12.0 * ui_scale:
		return
	var s := ui_scale
	var cut := 8.0 * s
	SagaFrame._fill(item, rect.grow(s), cut, Color(0, 0, 0, 0.65))
	_gradient(item, rect, cut, fill.lightened(0.025), fill.darkened(0.4))
	SagaFrame._stroke(item, rect.grow(-0.5 * s), cut,
		Color(accent, (0.13 if empty else 0.28) + emphasis * 0.68), maxf(s, 1.0))
	var inset := rect.grow(-3.0 * s)
	SagaFrame._stroke(item, inset, cut - 2.0 * s, Color(accent, 0.05 + emphasis * 0.2), s)
	# Una luz cálida queda dentro del hueco seleccionado, sin invadir los vecinos.
	if emphasis > 0.5:
		for i in range(1, 5):
			SagaFrame._stroke(item, rect.grow(-(3.0 + i) * s), cut,
				Color(accent, emphasis * 0.025), 2.0 * s)
	# Pie de la tecla, separado del objeto y flanqueado por dos filetes.
	var badge_size := key_size(s)
	var badge := Rect2(Vector2(rect.get_center().x - badge_size.x * 0.5, rect.end.y - 3.0 * s - badge_size.y),
		badge_size)
	var lit := emphasis > 0.5
	SagaFrame._fill(item, badge, 3.0 * s, accent if lit else Color("151410"))
	SagaFrame._stroke(item, badge, 3.0 * s, Color(accent, 0.75 if lit else 0.22), s)
	var y := badge.get_center().y
	for segment in [Vector2(rect.position.x + 8.0 * s, badge.position.x - 4.0 * s),
			Vector2(badge.end.x + 4.0 * s, rect.end.x - 8.0 * s)]:
		RenderingServer.canvas_item_add_line(item, Vector2(segment.x, y), Vector2(segment.y, y),
			Color(accent, 0.12 + emphasis * 0.35), s, true)
	if empty:
		var centre := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.39)
		SagaFrame._stroke(item, Rect2(centre - Vector2.ONE * 4.0 * s, Vector2.ONE * 8.0 * s),
			4.0 * s, Color(accent, 0.13), s)


static func _gradient(item: RID, rect: Rect2, cut: float, top: Color, bottom: Color) -> void:
	var points := SagaFrame.chamfered(rect, cut)
	var colors := PackedColorArray()
	for point in points:
		colors.append(top.lerp(bottom, (point.y - rect.position.y) / rect.size.y))
	RenderingServer.canvas_item_add_polygon(item, points, colors)


## A 720p la tecla sigue teniendo altura suficiente para una cifra de 12 px.
static func key_size(s: float) -> Vector2:
	return Vector2(maxf(16.0, 24.0 * s), maxf(16.0, 22.0 * s))
