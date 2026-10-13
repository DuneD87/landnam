class_name HotbarSlot
extends ItemSlotView

## Hueco de la barra rápida: lo que se saca con su tecla (en el pie del hueco). No guarda
## cantidad: apunta a un ItemData del inventario. Elegido (lo que va en la mano) se ilumina en
## bronce; lo que lleva la otra mano (el escudo), en escarcha.

@export var slot_index: int = 0

var assigned_data: ItemData = null
var _content: Control
## El recorte se comparte entre huecos y solo se calcula cuando aparece una textura nueva.
static var _framed_icons: Dictionary[Texture2D, Texture2D] = {}


func _init() -> void:
	super()
	size_kind = &"hotbar"
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	for child in [_icon, _mark, _count, _ghost]:
		child.reparent(_content)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mark.add_theme_font_override("font", GameTheme.bold_font())
	_mark.add_theme_constant_override("outline_size", 0)
	_content.resized.connect(_layout_content)


func _ready() -> void:
	set_mark(str((slot_index + 1) % 10))
	_layout_content()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_instance_valid(_content):
		_layout_content.call_deferred()


func _layout_content() -> void:
	var s := float(get_theme_constant(&"hotbar", &"ItemSlot")) / 92.0
	var area := _content.size
	if area.x <= 0.0:
		return
	var key_size := HotbarSlotFrame.key_size(s)
	var key_top := area.y - 3.0 * s - key_size.y
	_icon.position = Vector2(8.0, 6.0) * s
	_icon.size = Vector2(area.x - 16.0 * s, key_top - 10.0 * s)
	_mark.add_theme_font_size_override("font_size", maxi(12, roundi(19.0 * s)))
	_mark.position = Vector2(area.x * 0.5 - key_size.x * 0.5, key_top)
	_mark.size = key_size


func _refresh_style() -> void:
	super()
	theme_type_variation = StringName("Hotbar" + str(theme_type_variation))
	var lit := selected or (equipped and _filled) or held
	_mark.add_theme_color_override("font_color", GameTheme.INK if lit else
		(GameTheme.BONE if _filled or hovered else GameTheme.MUTED))


## Normalizar el margen transparente hace que una espada fina se lea tan bien como un hacha.
## AtlasTexture conserva el dibujo original y evita recrear imágenes en cada asignación.
static func _frame_icon(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	if _framed_icons.has(source):
		return _framed_icons[source]
	var image := source.get_image()
	if image == null or image.is_empty():
		return source
	if image.is_compressed():
		image.decompress()
	var used := image.get_used_rect()
	if not used.has_area():
		return source
	var framed := AtlasTexture.new()
	framed.atlas = source
	framed.region = Rect2(used)
	framed.filter_clip = true
	_framed_icons[source] = framed
	return framed


func assign(item_data: ItemData) -> void:
	assigned_data = item_data
	if assigned_data:
		show_item(_frame_icon(assigned_data.icon))
	else:
		clear()


## Vuelve a leer el icono del item. Los de bloque se renderizan en el arranque y pueden llegar
## después de que el hueco se haya rellenado (restaurar una partida), y assign() solo copia.
func refresh_icon() -> void:
	if assigned_data:
		show_item(_frame_icon(assigned_data.icon))


func clear() -> void:
	assigned_data = null
	show_empty()
