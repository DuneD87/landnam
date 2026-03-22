class_name Inventory
extends Node

signal item_added(item_data: ItemData, quantity: int)
signal item_removed(item_data: ItemData, quantity: int)
signal inventory_changed()

@export var max_slots: int = 20

var items: Array[InventoryItem] = []

func _init():
	items.resize(max_slots)
	for i in range(max_slots):
		items[i] = null

# Mueve un item de un slot a otro
func move_item(from_slot: int, to_slot: int, quantity: int = -1) -> bool:
	if from_slot < 0 or from_slot >= max_slots:
		return false
	if to_slot < 0 or to_slot >= max_slots:
		return false
	if from_slot == to_slot:
		return false
	
	var from_item = items[from_slot]
	if from_item == null:
		return false
	
	var qty_to_move = quantity if quantity > 0 else from_item.quantity
	qty_to_move = min(qty_to_move, from_item.quantity)
	
	var to_item = items[to_slot]
	
	# Si el destino es null (vacío)
	if to_item == null:
		if qty_to_move == from_item.quantity:
			# Mover todo
			items[to_slot] = from_item
			items[from_slot] = null
		else:
			# Mover parcialmente
			items[to_slot] = InventoryItem.new(from_item.data, qty_to_move)
			from_item.remove(qty_to_move)
		
		inventory_changed.emit()
		return true
	
	# Si son del mismo tipo y stackeable, intenta apilar
	if from_item.data.object_type == to_item.data.object_type and from_item.data.stackable:
		var space_available = to_item.data.max_stack - to_item.quantity
		var actually_moved = min(qty_to_move, space_available)
		
		to_item.add(actually_moved)
		from_item.remove(actually_moved)
		
		if from_item.is_empty():
			items[from_slot] = null
		
		inventory_changed.emit()
		return true
	
	# Si son diferentes, intercambiar
	if quantity == -1 or quantity == from_item.quantity:
		var temp = items[from_slot]
		items[from_slot] = items[to_slot]
		items[to_slot] = temp
		
		inventory_changed.emit()
		return true
	
	return false

# Divide un stack entre dos slots
func split_item(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= max_slots:
		return false
	if to_slot < 0 or to_slot >= max_slots:
		return false
	if from_slot == to_slot:
		return false
	
	var from_item = items[from_slot]
	if from_item == null:
		return false
	
	# Solo se puede dividir si tiene más de 1 unidad
	if from_item.quantity <= 1:
		return move_item(from_slot, to_slot)
	
	# Dividir a la mitad (redondeando hacia arriba)
	var half = int(ceil(from_item.quantity / 2.0))
	return move_item(from_slot, to_slot, half)

# Obtiene el item en un slot específico
func get_item_at_slot(slot: int) -> InventoryItem:
	if slot >= 0 and slot < max_slots:
		return items[slot]
	return null

# Encuentra el primer slot vacío
func find_empty_slot() -> int:
	for i in range(max_slots):
		if items[i] == null:
			return i
	return -1

func add_item(item_data: ItemData, quantity: int = 1) -> int:
	var remaining = quantity
	
	# Intentar apilar en items existentes
	if item_data.stackable:
		for i in range(max_slots):
			if items[i] != null and items[i].data.id == item_data.id and not items[i].is_full():
				remaining = items[i].add(remaining)
				if remaining == 0:
					break
	
	# Crear nuevos stacks en slots vacíos
	while remaining > 0:
		var empty_slot = find_empty_slot()
		if empty_slot == -1:
			break  # No hay más espacio
		
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
		if items[i] != null and items[i].data.object_type == item_data.object_type:
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
			print("  [%d] %s x%d" % [i, items[i].data.object_name, items[i].quantity])
	print("===========================")

func get_item_count(item_data: ItemData) -> int:
	var total = 0
	for item in items:
		if item != null and item.data == item_data:
			total += item.quantity
	return total

func get_all_items() -> Array[InventoryItem]:
	return items.duplicate()

func is_full() -> bool:
	for item in items:
		if item == null:
			return false
	return true

## Vacía todos los slots
func clear() -> void:
	for i in items.size():
		items[i] = null


func add_item_at(item_data: ItemData, amount: int, slot_index: int) -> void:
	if slot_index >= 0 and slot_index < items.size():
		var item := InventoryItem.new(item_data, amount)
		items[slot_index] = item
		
func get_free_slots() -> int:
	var free = 0
	for item in items:
		if item == null:
			free += 1
	return free
