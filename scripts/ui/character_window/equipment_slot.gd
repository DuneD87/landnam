class_name EquipmentSlot
extends ItemSlotView

## Hueco del equipo: lo que se lleva puesto en una parte del cuerpo o en una mano. Vacío enseña la
## silueta de lo que va en él.

@export var slot_type: ItemData.ArmorSlot
@export var background_icon: Texture2D = null:
	set(value):
		background_icon = value
		set_ghost(value)

var equipped_item: InventoryItem = null


func _init() -> void:
	super()
	size_kind = &"equipment"


func set_item(item: InventoryItem) -> void:
	equipped_item = item
	if item and item.data:
		show_item(item.data.icon)
	else:
		clear()


func clear() -> void:
	equipped_item = null
	show_empty()


func has_item() -> bool:
	return equipped_item != null
