@tool
class_name SagaFrame
extends StyleBox

## Marco de Saga para ventanas y fichas: una placa con las esquinas biseladas, un filete de bronce
## por fuera, otro más tenue hacia dentro y un remache (un rombo) en cada bisel. Las medidas van
## en píxeles de pantalla: GameTheme ya las escala.

@export var fill := Color(0.043, 0.047, 0.054, 0.93)
@export var border := Color(0.79, 0.64, 0.42, 0.34)
@export var border_width := 1.0
## Corte de cada esquina.
@export var chamfer := 14.0
## Distancia del filete interior al borde (0 = sin filete).
@export var inset := 0.0
@export var inset_color := Color(0.79, 0.64, 0.42, 0.12)
## Medio lado del rombo de cada esquina (0 = sin remaches).
@export var rivet := 0.0
@export var rivet_color := Color("c9a46a")


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	_fill(to_canvas_item, rect, chamfer, fill)
	if border_width > 0.0 and border.a > 0.0:
		_stroke(to_canvas_item, rect.grow(-border_width * 0.5), chamfer, border, border_width)
	if inset > 0.0 and inset_color.a > 0.0:
		_stroke(to_canvas_item, rect.grow(-inset), maxf(chamfer - inset * 0.6, 1.0), inset_color,
			maxf(border_width, 1.0))
	if rivet > 0.0:
		var cut := _cut(rect, chamfer)
		var half := Vector2(cut, cut) * 0.5
		for centre in [rect.position + half, Vector2(rect.end.x - half.x, rect.position.y + half.y),
				rect.end - half, Vector2(rect.position.x + half.x, rect.end.y - half.y)]:
			RenderingServer.canvas_item_add_polygon(to_canvas_item, diamond(centre, rivet),
				PackedColorArray([rivet_color]))


## Contorno de [rect] con las cuatro esquinas cortadas [cut] píxeles.
static func chamfered(rect: Rect2, cut: float) -> PackedVector2Array:
	cut = _cut(rect, cut)
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut),
	])


static func diamond(centre: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([centre + Vector2(0, -half), centre + Vector2(half, 0),
		centre + Vector2(0, half), centre + Vector2(-half, 0)])


static func _cut(rect: Rect2, cut: float) -> float:
	return clampf(cut, 0.0, minf(rect.size.x, rect.size.y) * 0.5)


static func _fill(item: RID, rect: Rect2, cut: float, color: Color) -> void:
	if color.a <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	# Sin corte el contorno repetiría puntos y no se triangula.
	if _cut(rect, cut) < 0.5:
		RenderingServer.canvas_item_add_rect(item, rect, color)
	else:
		RenderingServer.canvas_item_add_polygon(item, chamfered(rect, cut), PackedColorArray([color]))


static func _stroke(item: RID, rect: Rect2, cut: float, color: Color, width: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var points := chamfered(rect, cut)
	points.append(points[0])
	RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([color]), width, true)
