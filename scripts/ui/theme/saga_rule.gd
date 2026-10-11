@tool
class_name SagaRule
extends StyleBox

## Separador de Saga: un filete que se desvanece hacia los extremos, con un rombo en el centro.
## Es el estilo de HSeparator; se dibuja centrado en el alto que le da el contenedor.

@export var color := Color(0.79, 0.64, 0.42, 0.45)
@export var thickness := 1.0
## Medio lado del rombo central (0 = filete solo).
@export var diamond := 4.0
## Hueco entre el filete y el rombo.
@export var gap := 8.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var y := rect.position.y + rect.size.y * 0.5
	var left := rect.position.x
	var right := rect.end.x
	var centre := (left + right) * 0.5
	var clear := Color(color, 0.0)
	if diamond <= 0.0:
		RenderingServer.canvas_item_add_polyline(to_canvas_item,
			PackedVector2Array([Vector2(left, y), Vector2(centre, y), Vector2(right, y)]),
			PackedColorArray([clear, color, clear]), thickness, true)
		return
	var reach := diamond + gap
	RenderingServer.canvas_item_add_polyline(to_canvas_item,
		PackedVector2Array([Vector2(left, y), Vector2(centre - reach, y)]),
		PackedColorArray([clear, color]), thickness, true)
	RenderingServer.canvas_item_add_polyline(to_canvas_item,
		PackedVector2Array([Vector2(centre + reach, y), Vector2(right, y)]),
		PackedColorArray([color, clear]), thickness, true)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, SagaFrame.diamond(Vector2(centre, y), diamond),
		PackedColorArray([Color(color, minf(color.a * 1.8, 1.0))]))
