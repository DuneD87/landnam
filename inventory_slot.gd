# inventory_slot.gd
extends PanelContainer
class_name InventorySlot

@onready var icon_rect: TextureRect = $MarginContainer/VBoxContainer/IconRect
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/QuantityLabel

var item: InventoryItem = null

var style_empty: StyleBoxFlat
var style_filled: StyleBoxFlat

func _ready() -> void:
	_create_styles()
	clear()

func _create_styles() -> void:
	style_empty = StyleBoxFlat.new()
	style_empty.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style_empty.set_corner_radius_all(4)
	style_empty.set_border_width_all(1)
	style_empty.border_color = Color(0.3, 0.3, 0.3, 0.8)
	
	style_filled = StyleBoxFlat.new()
	style_filled.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	style_filled.set_corner_radius_all(4)
	style_filled.set_border_width_all(1)
	style_filled.border_color = Color(0.5, 0.5, 0.5, 0.8)

func set_item(inventory_item: InventoryItem) -> void:
	item = inventory_item
	
	if item and item.data:
		icon_rect.texture = item.data.icon
		icon_rect.visible = true
		quantity_label.text = str(item.quantity) if item.quantity > 1 else ""
		tooltip_text = "%s\n%s" % [item.data.object_name, item.data.description]
		add_theme_stylebox_override("panel", style_filled)
	else:
		clear()

func clear() -> void:
	item = null
	icon_rect.texture = null
	icon_rect.visible = false
	quantity_label.text = ""
	tooltip_text = ""
	add_theme_stylebox_override("panel", style_empty)
