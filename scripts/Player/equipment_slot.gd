# equipment_slot.gd
class_name EquipmentSlot
extends PanelContainer

signal slot_clicked(slot: EquipmentSlot, button_index: int)

@export var slot_type: String = ""
@export var background_icon: Texture2D = null:
	set(value):
		background_icon = value
		if is_node_ready() and background_texture:
			background_texture.texture = value

@onready var background_texture: TextureRect = $BackgroundIcon
@onready var item_icon: TextureRect = $ItemIcon

var equipped_item: InventoryItem = null


func _ready() -> void:
	_apply_style()
	
	if background_texture and background_icon:
		background_texture.texture = background_icon


func _apply_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.35, 0.35, 1)
	add_theme_stylebox_override("panel", style)


func set_item(item: InventoryItem) -> void:
	equipped_item = item
	if item and item.data and item.data.icon:
		item_icon.texture = item.data.icon
		item_icon.visible = true
	else:
		clear()


func clear() -> void:
	equipped_item = null
	item_icon.texture = null
	item_icon.visible = false


func has_item() -> bool:
	return equipped_item != null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		slot_clicked.emit(self, event.button_index)
