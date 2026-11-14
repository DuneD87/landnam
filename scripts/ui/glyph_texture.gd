class_name GlyphTexture
extends Texture2D

## Un dibujo de OrderGlyphs como textura: sirve de icono de un Button o en un TextureRect, que lo
## pintan a su tamaño y con su modulación (el icono apagado de un botón desactivado, por ejemplo).

## El dibujo (OrderGlyphs.draw), su lado en píxeles y su color.
var key: StringName:
	set(value):
		if key != value:
			key = value
			emit_changed()
var side := 32.0:
	set(value):
		if side != value:
			side = value
			emit_changed()
var color := Color.WHITE:
	set(value):
		if color != value:
			color = value
			emit_changed()


func _init(p_key: StringName = &"", p_side := 32.0, p_color := Color.WHITE) -> void:
	key = p_key
	side = p_side
	color = p_color


func _get_width() -> int:
	return maxi(1, roundi(side))


func _get_height() -> int:
	return maxi(1, roundi(side))


func _has_alpha() -> bool:
	return true


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
	_paint(to_canvas_item, Rect2(pos, Vector2(side, side)), modulate)


func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
	_paint(to_canvas_item, rect, modulate)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, modulate: Color, _transpose: bool,
		_clip_uv: bool) -> void:
	_paint(to_canvas_item, rect, modulate)


func _paint(ci: RID, rect: Rect2, modulate: Color) -> void:
	if key != &"":
		OrderGlyphs.draw(ci, key, rect.get_center(), minf(rect.size.x, rect.size.y), color * modulate)
