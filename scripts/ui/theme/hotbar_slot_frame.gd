@tool
class_name HotbarSlotFrame
extends StyleBox

## Cartucho de hierro con bisel ancho, cámara oscura para el icono y una tecla grabada en la base.
## El color por vértice da el volumen; la selección añade bronce y la otra mano, acero azulado.

var ui_scale := 1.0
var fill := Color("171714")
var accent := Color("6e5a38")
var emphasis := 0.0
var empty := false


func _draw(item: RID, rect: Rect2) -> void:
	if rect.size.x <= 12.0 * ui_scale or rect.size.y <= 12.0 * ui_scale:
		return
	var s := ui_scale
	var cut := 10.0 * s
	SagaFrame._fill(item, rect.grow(1.5 * s), cut, Color(0, 0, 0, 0.65))
	var shoulder := Color("282c31") if empty else Color("4c5156")
	_gradient(item, rect, cut, shoulder.lerp(accent.darkened(0.35), emphasis * 0.65), Color("171a1e"))
	SagaFrame._stroke(item, rect.grow(-0.5 * s), cut, Color("07090b"), s)
	var well := rect.grow(-5.0 * s)
	_gradient(item, well, 6.0 * s, fill.darkened(0.5), fill)
	SagaFrame._stroke(item, well, 6.0 * s, Color(0, 0, 0, 0.85), 1.5 * s)
	# Las abrazaderas de bronce en las esquinas hacen legible el relieve a 1080p.
	var points := SagaFrame.chamfered(rect.grow(-1.5 * s), cut)
	var metal := accent.lerp(GameTheme.BONE, 0.12)
	for corner in [[7, 0, 1], [2, 1, 0]]:
		var a: Vector2 = points[corner[0]]
		var b: Vector2 = points[corner[1]]
		var tip: Vector2 = b.move_toward(points[corner[2]], 12.0 * s)
		RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([a, b, tip]),
			PackedColorArray([Color(metal, (0.15 if empty else 0.3) + emphasis * 0.5)]), 1.5 * s, true)
	# La base separa la tecla del objeto. El filete se ilumina al sacar el objeto o el escudo.
	var base := Rect2(Vector2(well.position.x, rect.end.y - 29.0 * s),
		Vector2(well.size.x, 24.0 * s))
	_gradient(item, base, 4.0 * s, Color("16191c"), Color("0b0d10"))
	RenderingServer.canvas_item_add_line(item,
		Vector2(base.position.x + 5.0 * s, base.position.y),
		Vector2(base.end.x - 5.0 * s, base.position.y),
		Color(accent, 0.2 + emphasis * 0.35), s, true)
	RenderingServer.canvas_item_add_line(item,
		Vector2(rect.position.x + cut, rect.end.y - 1.5 * s),
		Vector2(rect.end.x - cut, rect.end.y - 1.5 * s),
		Color(accent, 0.18 + emphasis * 0.45), s, true)


static func _gradient(item: RID, rect: Rect2, cut: float, top: Color, bottom: Color) -> void:
	var points := SagaFrame.chamfered(rect, cut)
	var colors := PackedColorArray()
	for point in points:
		colors.append(top.lerp(bottom, (point.y - rect.position.y) / rect.size.y))
	RenderingServer.canvas_item_add_polygon(item, points, colors)
