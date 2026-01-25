class_name Inventory
extends Node

signal item_added(item_data: ItemData, quantity: int)
signal item_removed(item_data: ItemData, quantity: int)
signal inventory_changed()

@export var max_slots: int = 20

var items: Array[InventoryItem] = []

func add_item(item_data: ItemData, quantity: int = 1) -> int:
	var remaining = quantity
	
	if item_data.stackable:
		for item in items:
			if item.data.object_type == item_data.object_type and not item.is_full():
				remaining = item.add(remaining)
				if remaining == 0:
					break
	
	while remaining > 0 and items.size() < max_slots:
		var new_item = InventoryItem.new(item_data, remaining)
		remaining -= new_item.quantity
		items.append(new_item)
	
	var added = quantity - remaining
	if added > 0:
		item_added.emit(item_data, added)
		inventory_changed.emit()
	
	return remaining

func remove_item(item_data: ItemData, quantity: int = 1) -> int:
	var to_remove = quantity
	var removed_total = 0
	
	for i in range(items.size() - 1, -1, -1):
		if items[i].data.object_type == item_data.object_type:
			var removed = items[i].remove(to_remove)
			removed_total += removed
			to_remove -= removed
			
			if items[i].is_empty():
				items.remove_at(i)
			
			if to_remove <= 0:
				break
	
	if removed_total > 0:
		item_removed.emit(item_data, removed_total)
		inventory_changed.emit()
	
	return removed_total

func has_item(item_data: ItemData, quantity: int = 1) -> bool:
	return get_item_count(item_data) >= quantity
	
# En inventory.gd

func print_contents() -> void:
	if items.is_empty():
		print("=== Inventario vacío ===")
		return
	print("=== Inventario (%d/%d slots) ===" % [items.size(), max_slots])
	for i in range(items.size()):
		var item = items[i]
		print("  [%d] %s x%d" % [i, item.data.object_name, item.quantity])
	print("===========================")
	
func get_item_count(item_data: ItemData) -> int:
	var total = 0
	for item in items:
		if item.data == item_data:
			total += item.quantity
	return total

func get_all_items() -> Array[InventoryItem]:
	return items.duplicate()

func is_full() -> bool:
	return items.size() >= max_slots

func get_free_slots() -> int:
	return max_slots - items.size()
