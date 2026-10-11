class_name InventorySlot
extends ItemSlotView

## Hueco del inventario (o del botín): enseña un InventoryItem.

@export var slot_index: int = 0

var item: InventoryItem = null


func set_item(inventory_item: InventoryItem) -> void:
	item = inventory_item
	if item and item.data:
		show_item(item.data.icon, item.quantity)
	else:
		clear()


func clear() -> void:
	item = null
	show_empty()
