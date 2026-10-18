class_name Inventory
extends Node

signal item_added(item_data: ItemData, quantity: int)
signal item_removed(item_data: ItemData, quantity: int)
signal inventory_changed()

@export var max_slots: int = 20

var items: Array[InventoryItem] = []

func _init():
	items.resize(max_slots)

## Operaciones de hueco: devuelven lo retirado o lo que queda en la mano. El llamador emite
## inventory_changed al terminar la transacción, cuando ya ha colocado todos los restos.
func take_at(slot: int, quantity: int = -1) -> InventoryItem:
	var item := get_item_at_slot(slot)
	if item == null:
		return null
	if quantity < 0 or quantity >= item.quantity:
		items[slot] = null
		return item
	if quantity == 0:
		return null
	return InventoryItem.new(item.data, item.remove(quantity))


func put_at(slot: int, item: InventoryItem, quantity: int = -1,
		allow_swap: bool = true) -> InventoryItem:
	if item == null or slot < 0 or slot >= items.size():
		return item
	var amount := item.quantity if quantity < 0 else mini(quantity, item.quantity)
	if amount <= 0 or items[slot] == item:
		return item
	var target := items[slot]
	if target != null and target.can_stack_with(item):
		item.remove(amount - target.add(amount))
		return null if item.is_empty() else item
	if target == null and amount < item.quantity:
		items[slot] = InventoryItem.new(item.data, item.remove(amount))
		return item
	if amount == item.quantity and (target == null or allow_swap):
		items[slot] = item
		return target
	return item


func move_item(from_slot: int, to_slot: int, quantity: int = -1) -> bool:
	var source := get_item_at_slot(from_slot)
	if source == null or from_slot == to_slot or to_slot < 0 or to_slot >= items.size():
		return false
	var target := items[to_slot]
	var amount := mini(quantity, source.quantity) if quantity > 0 else source.quantity
	if target != null and not target.can_stack_with(source) and amount < source.quantity:
		return false
	var remaining := put_at(to_slot, take_at(from_slot, amount))
	if remaining != null:
		put_at(from_slot, remaining)
	inventory_changed.emit()
	return true

func split_item(from_slot: int, to_slot: int) -> bool:
	var from_item := get_item_at_slot(from_slot)
	if from_item == null:
		return false
	return move_item(from_slot, to_slot, ceili(from_item.quantity / 2.0))

func get_item_at_slot(slot: int) -> InventoryItem:
	if slot >= 0 and slot < items.size():
		return items[slot]
	return null

func find_empty_slot() -> int:
	return items.find(null)

func add_item(item_data: ItemData, quantity: int = 1) -> int:
	var remaining = quantity
	
	if item_data.stackable:
		for i in range(max_slots):
			if items[i] != null and items[i].data.id == item_data.id and not items[i].is_full():
				remaining = items[i].add(remaining)
				if remaining == 0:
					break
	
	while remaining > 0:
		var empty_slot = find_empty_slot()
		if empty_slot == -1:
			break
		
		var new_item = InventoryItem.new(item_data, remaining)
		remaining -= new_item.quantity
		items[empty_slot] = new_item
	
	var added = quantity - remaining
	if added > 0:
		item_added.emit(item_data, added)
		inventory_changed.emit()
	
	return remaining

func remove_item(item_data: ItemData, quantity: int = 1) -> int:
	var to_remove = quantity
	var removed_total = 0
	
	for i in range(max_slots - 1, -1, -1):
		if items[i] != null and items[i].data.id == item_data.id:
			var removed = items[i].remove(to_remove)
			removed_total += removed
			to_remove -= removed
			
			if items[i].is_empty():
				items[i] = null
			
			if to_remove <= 0:
				break
	
	if removed_total > 0:
		item_removed.emit(item_data, removed_total)
		inventory_changed.emit()
	
	return removed_total

func has_item(item_data: ItemData, quantity: int = 1) -> bool:
	return get_item_count(item_data) >= quantity

func print_contents() -> void:
	var count = 0
	for item in items:
		if item != null:
			count += 1
	
	if count == 0:
		print("=== Inventario vacío ===")
		return
		
	print("=== Inventario (%d/%d slots) ===" % [count, max_slots])
	for i in range(max_slots):
		if items[i] != null:
			print("  [%d] %s x%d" % [i, items[i].data.get_display_name(), items[i].quantity])
	print("===========================")

func get_item_count(item_data: ItemData) -> int:
	if item_data == null:
		return 0
	var total = 0
	for item in items:
		if item != null and item.data != null and item.data.id == item_data.id:
			total += item.quantity
	return total

func get_all_items() -> Array[InventoryItem]:
	return items.duplicate()

func is_full() -> bool:
	return not items.has(null)

func clear() -> void:
	items.fill(null)


func add_item_at(item_data: ItemData, amount: int, slot_index: int) -> void:
	if slot_index >= 0 and slot_index < items.size():
		var item := InventoryItem.new(item_data, amount)
		items[slot_index] = item
		
func get_free_slots() -> int:
	return items.count(null)
