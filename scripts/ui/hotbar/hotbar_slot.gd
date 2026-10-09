class_name HotbarSlot
extends PanelContainer

signal slot_clicked(slot: HotbarSlot, button_index: int)

@onready var icon_rect: TextureRect = $MarginContainer/IconRect
@onready var key_label: Label = $KeyLabel

@export var slot_index: int = 0

var assigned_data: ItemData = null
var selected: bool = false
## Lo lleva puesto la otra mano (el escudo): se resalta aparte de la selección.
var equipped: bool = false
var style_empty: StyleBoxFlat
var style_filled: StyleBoxFlat
var style_selected: StyleBoxFlat
var style_equipped: StyleBoxFlat


func _ready() -> void:
	_create_styles()
	custom_minimum_size = Vector2(85, 85)
	mouse_filter = Control.MOUSE_FILTER_PASS
	key_label.text = str((slot_index + 1) % 10)
	clear()

func _create_styles() -> void:
	style_empty = StyleBoxFlat.new()
	style_empty.bg_color = Color(0.08, 0.08, 0.08, 0.75)
	style_empty.set_corner_radius_all(4)
	style_empty.set_border_width_all(1)
	style_empty.border_color = Color(0.3, 0.3, 0.3, 0.8)

	style_filled = StyleBoxFlat.new()
	style_filled.bg_color = Color(0.18, 0.18, 0.18, 0.85)
	style_filled.set_corner_radius_all(4)
	style_filled.set_border_width_all(1)
	style_filled.border_color = Color(0.45, 0.45, 0.45, 0.9)

	style_selected = StyleBoxFlat.new()
	style_selected.bg_color = Color(0.22, 0.22, 0.18, 0.95)
	style_selected.set_corner_radius_all(4)
	style_selected.set_border_width_all(2)
	style_selected.border_color = Color(0.9, 0.75, 0.3, 1.0)

	style_equipped = StyleBoxFlat.new()
	style_equipped.bg_color = Color(0.16, 0.19, 0.22, 0.95)
	style_equipped.set_corner_radius_all(4)
	style_equipped.set_border_width_all(2)
	style_equipped.border_color = Color(0.45, 0.65, 0.85, 1.0)


func assign(item_data: ItemData) -> void:
	assigned_data = item_data
	if assigned_data:
		icon_rect.texture = assigned_data.icon
		icon_rect.visible = true
		tooltip_text = "%s\n%s" % [assigned_data.display_name, assigned_data.description]
	else:
		clear()
	_update_style()


## Vuelve a leer el icono del item. Los de bloque se renderizan en el arranque y pueden llegar
## después de que el hueco se haya rellenado (restaurar una partida), y assign() solo copia.
func refresh_icon() -> void:
	if assigned_data:
		icon_rect.texture = assigned_data.icon


func clear() -> void:
	assigned_data = null
	icon_rect.texture = null
	icon_rect.visible = false
	tooltip_text = ""
	_update_style()


func set_selected(value: bool) -> void:
	selected = value
	_update_style()


func set_equipped(value: bool) -> void:
	equipped = value
	_update_style()


func _update_style() -> void:
	if selected:
		add_theme_stylebox_override("panel", style_selected)
	elif equipped and assigned_data:
		add_theme_stylebox_override("panel", style_equipped)
	elif assigned_data:
		add_theme_stylebox_override("panel", style_filled)
	else:
		add_theme_stylebox_override("panel", style_empty)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		slot_clicked.emit(self, event.button_index)
