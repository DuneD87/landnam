class_name InventoryItem
extends RefCounted

var data: ItemData
var quantity: int = 1

func _init(item_data: ItemData, initial_quantity: int = 1) -> void:
	data = item_data
	quantity = clampi(initial_quantity, 1, item_data.max_stack)

func can_add(amount: int) -> bool:
	return data.stackable and (quantity + amount) <= data.max_stack

func add(amount: int) -> int:
	if not data.stackable:
		return amount
	
	var space_available = data.max_stack - quantity
	var to_add = mini(amount, space_available)
	quantity += to_add
	return amount - to_add

func remove(amount: int) -> int:
	var to_remove = mini(amount, quantity)
	quantity -= to_remove
	return to_remove

func is_empty() -> bool:
	return quantity <= 0

func is_full() -> bool:
	return quantity >= data.max_stack
