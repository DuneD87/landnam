class_name ItemSlotView
extends PanelContainer

## Hueco de objeto de Saga, común al inventario, el equipo, la barra rápida y el botín: el icono,
## la cantidad abajo a la derecha, una marca arriba a la izquierda (la tecla en la barra rápida),
## la silueta grabada de lo que va en él mientras está vacío y sus estados (bajo el ratón,
## elegido, en la otra mano, atenuado por un filtro). Cada estado es una variación del tema
## ("SlotEmpty", "Slot", "SlotHover"...) y el lado sale de la constante `size_kind` del tipo
## "ItemSlot", así que todo se ajusta solo al cambiar de tema o de escala.

signal slot_clicked(slot: ItemSlotView, button_index: int)
## Doble clic izquierdo (llega después del slot_clicked del segundo clic).
signal slot_double_clicked(slot: ItemSlotView)
## El ratón entra en el hueco o sale de él (para la ficha del objeto).
signal hover_changed(slot: ItemSlotView, hovered: bool)

## Silueta de un hueco vacío: bronce casi transparente, como grabada en la placa.
const GHOST_SHADER := preload("res://shaders/ui/tint_alpha.gdshader")

static var _ghost_material: ShaderMaterial

## Constante del tipo "ItemSlot" con el lado (ver GameTheme.SLOT_SIDES).
var size_kind := &"inventory"
var selected := false:
	set(value):
		selected = value
		_refresh_style()
var equipped := false:
	set(value):
		equipped = value
		_refresh_style()
## Es el que va pegado al cursor.
var held := false:
	set(value):
		held = value
		_refresh_style()
## Un filtro lo deja en segundo plano.
var dimmed := false:
	set(value):
		dimmed = value
		modulate = Color(1, 1, 1, 0.28) if value else Color.WHITE
var hovered := false

var _icon := TextureRect.new()
var _ghost := TextureRect.new()
var _count := Label.new()
var _mark := Label.new()
var _filled := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for rect in [_ghost, _icon]:
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
	if _ghost_material == null:
		_ghost_material = ShaderMaterial.new()
		_ghost_material.shader = GHOST_SHADER
	_ghost.material = _ghost_material
	_ghost.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ghost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count.theme_type_variation = &"SlotCount"
	_count.size_flags_horizontal = Control.SIZE_SHRINK_END
	_count.size_flags_vertical = Control.SIZE_SHRINK_END
	_mark.theme_type_variation = &"SlotKey"
	_mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for label in [_count, _mark]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	show_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		var side := get_theme_constant(size_kind, &"ItemSlot")
		if side > 0:
			custom_minimum_size = Vector2(side, side)
			_ghost.custom_minimum_size = Vector2(side, side) * 0.5
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and hovered:
		_set_hovered(false)


func show_item(icon: Texture2D, quantity := 1) -> void:
	_filled = true
	_icon.texture = icon
	_icon.visible = true
	_ghost.visible = false
	_count.text = str(quantity) if quantity > 1 else ""
	_refresh_style()


func show_empty() -> void:
	_filled = false
	_icon.texture = null
	_icon.visible = false
	_ghost.visible = _ghost.texture != null
	_count.text = ""
	_refresh_style()


## Silueta de lo que va en el hueco, para cuando está vacío.
func set_ghost(texture: Texture2D) -> void:
	_ghost.texture = texture
	_ghost.visible = texture != null and not _filled


## Texto pequeño de la esquina de arriba (la tecla de la barra rápida).
func set_mark(text: String) -> void:
	_mark.text = text


func set_selected(value: bool) -> void:
	selected = value


func set_equipped(value: bool) -> void:
	equipped = value


func _set_hovered(value: bool) -> void:
	if hovered == value:
		return
	hovered = value
	_refresh_style()
	hover_changed.emit(self, value)


func _refresh_style() -> void:
	if held:
		theme_type_variation = &"SlotHeld"
	elif selected:
		theme_type_variation = &"SlotSelected"
	elif equipped and _filled:
		theme_type_variation = &"SlotEquipped"
	elif hovered:
		theme_type_variation = &"SlotHover"
	elif _filled:
		theme_type_variation = &"Slot"
	else:
		theme_type_variation = &"SlotEmpty"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		slot_clicked.emit(self, event.button_index)
		if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			slot_double_clicked.emit(self)
