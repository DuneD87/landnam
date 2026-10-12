class_name HotbarSlot
extends ItemSlotView

## Hueco de la barra rápida: lo que se saca con su tecla (que lleva en la esquina). No guarda
## cantidad: apunta a un ItemData del inventario. Elegido (lo que va en la mano) se ilumina en
## bronce; lo que lleva la otra mano (el escudo), en escarcha.

@export var slot_index: int = 0

var assigned_data: ItemData = null
var _content := Control.new()
var _accent := Control.new()
var _selection_light := 0.0
var _hover_light := 0.0
var _selection_target := -1.0
var _hover_target := -1.0
var _transition: Tween


func _init() -> void:
	super()
	size_kind = &"hotbar"
	# Una zona de icono arriba y la tecla grabada abajo; el Container solo coloca la envoltura.
	remove_child(_icon)
	remove_child(_mark)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_content.add_child(_icon)
	_content.add_child(_mark)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mark.theme_type_variation = &"HotbarKey"
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accent.draw.connect(_draw_accent)
	add_child(_accent)


func _ready() -> void:
	set_mark(str((slot_index + 1) % 10))
	_refresh_style()
	_content.resized.connect(_layout_contents)
	resized.connect(_layout_contents)
	_layout_contents()


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_layout_contents.call_deferred()


func _layout_contents() -> void:
	var s := float(get_theme_constant(&"hotbar", &"ItemSlot")) / 88.0
	custom_minimum_size = Vector2(88.0, 108.0) * s
	_icon.position = Vector2(2.0, 1.0) * s
	_icon.size = Vector2(maxf(_content.size.x - 4.0 * s, 0.0), maxf(_content.size.y - 25.0 * s, 0.0))
	_icon.pivot_offset = _icon.size * 0.5
	_mark.position = Vector2(0, _content.size.y - 23.0 * s)
	_mark.size = Vector2(_content.size.x, 23.0 * s)
	_accent.queue_redraw()


func _refresh_style() -> void:
	if selected:
		theme_type_variation = &"HotbarSelected"
	elif equipped and _filled:
		theme_type_variation = &"HotbarEquipped"
	elif hovered:
		theme_type_variation = &"HotbarHover"
	elif _filled:
		theme_type_variation = &"HotbarSlot"
	else:
		theme_type_variation = &"HotbarEmpty"
	if not is_inside_tree():
		return
	_mark.add_theme_color_override("font_color", GameTheme.BRONZE if selected else
		(GameTheme.FROST if equipped and _filled else GameTheme.BONE.darkened(0.2)))
	_accent.queue_redraw()
	var selection_target := 1.0 if selected else 0.0
	var hover_target := 1.0 if hovered else 0.0
	if selection_target == _selection_target and hover_target == _hover_target:
		return
	_selection_target = selection_target
	_hover_target = hover_target
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = create_tween().set_parallel(true)
	_transition.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_method(_set_selection_light, _selection_light, selection_target, 0.16)
	_transition.tween_method(_set_hover_light, _hover_light, hover_target, 0.12)


func _set_selection_light(value: float) -> void:
	_selection_light = value
	_icon.scale = Vector2.ONE * (1.0 + value * 0.04)
	_accent.queue_redraw()


func _set_hover_light(value: float) -> void:
	_hover_light = value
	_accent.queue_redraw()


func _draw_accent() -> void:
	var s := float(get_theme_constant(&"hotbar", &"ItemSlot")) / 88.0
	if s <= 0.0:
		return
	var rect := Rect2(-_accent.position, size).grow(-2.0 * s)
	var light := maxf(_selection_light, _hover_light * 0.35)
	if light > 0.001:
		# Halo corto dentro del bisel: se apaga al soltar el hueco, sin animaciones permanentes.
		for i in 4:
			SagaFrame._stroke(_accent.get_canvas_item(), rect.grow(-float(i) * s), 10.0 * s,
				Color(GameTheme.BRONZE, light * (0.85 if i == 0 else 0.06)), s)
		_accent.draw_line(Vector2(rect.position.x + 6.0 * s, rect.position.y),
			Vector2(rect.end.x - 6.0 * s, rect.position.y),
			Color(GameTheme.BONE, light * 0.6), s, true)
	var strength := _selection_light if selected or _selection_light > 0.001 else (0.7 if equipped and _filled else 0.0)
	if strength > 0.001:
		var tint := GameTheme.FROST if equipped and not selected else GameTheme.BRONZE
		var at := Vector2(size.x * 0.5, size.y - 30.0 * s) - _accent.position
		_accent.draw_line(at - Vector2(18.0 * s, 0), at + Vector2(18.0 * s, 0),
			Color(tint, strength * 0.85), 1.5 * s, true)
		# Dos cuñas marcan el elegido junto a la tecla; el azul identifica la otra mano.
		for side in [-1.0, 1.0]:
			var centre := at + Vector2(side * 29.0 * s, 15.0 * s)
			_accent.draw_colored_polygon(SagaFrame.diamond(centre, 2.0 * s), Color(tint, strength))


func assign(item_data: ItemData) -> void:
	assigned_data = item_data
	if assigned_data:
		show_item(assigned_data.icon)
	else:
		clear()


## Vuelve a leer el icono del item. Los de bloque se renderizan en el arranque y pueden llegar
## después de que el hueco se haya rellenado (restaurar una partida), y assign() solo copia.
func refresh_icon() -> void:
	if assigned_data:
		show_item(assigned_data.icon)


func clear() -> void:
	assigned_data = null
	show_empty()
