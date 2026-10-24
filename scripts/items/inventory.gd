class_name Inventory
extends Node

## Contenido común del jugador, botín y almacenamientos. take_at, put_at e insert no emiten
## señales: quien lleva el cursor notifica al terminar de colocar todos los restos.
## transfer_to completa la operación y notifica una vez a cada inventario afectado.
signal item_added(item_data: ItemData, quantity: int)
signal item_removed(item_data: ItemData, quantity: int)
signal inventory_changed()

var items: Array[InventoryItem] = []
var _max_slots := 20

@export_range(1, 200, 1, "or_greater") var max_slots: int = 20:
	get:
		return _max_slots
	set(value):
		resize_slots(value)
@export var rules: InventoryRules


func _init(slot_count: int = 20) -> void:
	_max_slots = maxi(1, slot_count)
	items.resize(_max_slots)


## Nunca recorta huecos ocupados. Sirve para configurar escenas y desde código.
func resize_slots(count: int) -> bool:
	if count < 1:
		return false
	for i in range(count, items.size()):
		if items[i] != null:
			return false
	var changed := items.size() != count
	_max_slots = count
	items.resize(count)
	if changed:
		inventory_changed.emit()
	return true


## Comprueba la capacidad compactando montones en una copia del plan, sin modificar nada.
## Los objetos adicionales solo reservan espacio (p. ej. la mochila que se va a quitar).
func can_repack(count: int, additional: Array[InventoryItem] = []) -> bool:
	return not _packing_plan(count, additional).is_empty()


func repack_slots(count: int) -> bool:
	var plan := _packing_plan(count)
	if plan.is_empty():
		return false
	for item: InventoryItem in plan.quantities:
		item.quantity = plan.quantities[item]
	items = plan.items
	_max_slots = count
	inventory_changed.emit()
	return true


func _packing_plan(count: int, additional: Array[InventoryItem] = []) -> Dictionary:
	if count < 1:
		return {}
	var packed: Array[InventoryItem] = []
	packed.resize(count)
	var quantities := {}
	for item: InventoryItem in items + additional:
		if item == null:
			continue
		var left := item.quantity
		for i in count:
			var target := packed[i]
			if target != null and target.can_stack_with(item):
				var moved := mini(left, maxi(0, _packing_capacity(i, target.data) - int(quantities[target])))
				quantities[target] += moved
				left -= moved
				if left == 0:
					break
		for i in count:
			if left == 0:
				break
			if packed[i] != null:
				continue
			var amount := mini(left, _packing_capacity(i, item.data))
			if amount <= 0:
				continue
			var stack := item if amount == left else InventoryItem.new(item.data, amount)
			packed[i] = stack
			quantities[stack] = amount
			left -= amount
		if left > 0:
			return {}
		if not packed.has(item):
			quantities[item] = 0
	return {"items": packed, "quantities": quantities}


func _packing_capacity(slot: int, data: ItemData) -> int:
	var limit := maxi(1, data.max_stack) if data.stackable else 1
	if rules == null:
		return limit
	return mini(limit, maxi(0, rules.capacity(slot, data))) if rules.accepts(slot, data) else 0


func accepts(slot: int, data: ItemData) -> bool:
	return slot >= 0 and slot < items.size() and data != null \
		and (rules == null or rules.accepts(slot, data))


func capacity(slot: int, data: ItemData) -> int:
	if not accepts(slot, data):
		return 0
	var limit := maxi(1, data.max_stack) if data.stackable else 1
	return mini(limit, maxi(0, rules.capacity(slot, data))) if rules != null else limit


func take_at(slot: int, quantity: int = -1) -> InventoryItem:
	var item := get_item_at_slot(slot)
	if item == null or quantity == 0:
		return null
	if quantity < 0 or quantity >= item.quantity:
		items[slot] = null
		return item
	return InventoryItem.new(item.data, item.remove(quantity))


## Devuelve lo que queda en la mano, o el objeto desplazado al intercambiar montones enteros.
func put_at(slot: int, item: InventoryItem, quantity: int = -1,
		allow_swap: bool = true) -> InventoryItem:
	if item == null or item.is_empty() or not accepts(slot, item.data) or items.has(item):
		return item
	var amount := item.quantity if quantity < 0 else mini(quantity, item.quantity)
	var target := items[slot]
	if amount <= 0:
		return item
	var limit := capacity(slot, item.data)
	if target != null and target.can_stack_with(item):
		var added := mini(amount, maxi(0, limit - target.quantity))
		item.remove(added - target.add(added))
		return null if item.is_empty() else item
	if target != null:
		if allow_swap and amount == item.quantity and amount <= limit:
			items[slot] = item
			return target
		return item
	amount = mini(amount, limit)
	if amount <= 0:
		return item
	if amount == item.quantity:
		items[slot] = item
		return null
	items[slot] = InventoryItem.new(item.data, item.remove(amount))
	return item


## Apila y usa huecos libres, conservando en el resultado lo que no cabe. No intercambia objetos.
func insert(item: InventoryItem) -> InventoryItem:
	if item == null:
		return null
	for i in items.size():
		if items[i] != null and items[i].can_stack_with(item):
			item = put_at(i, item, -1, false)
			if item == null:
				return null
	for i in items.size():
		if items[i] == null:
			item = put_at(i, item, -1, false)
			if item == null:
				return null
	return item


## Devuelve cuántas unidades se han movido. -1 como destino busca sitio automáticamente.
func transfer_to(target: Inventory, from_slot: int, quantity: int = -1,
		to_slot: int = -1) -> int:
	if target == null or target == self or quantity == 0:
		return 0
	var held := take_at(from_slot, quantity)
	if held == null:
		return 0
	var data := held.data
	var amount := held.quantity
	var left := target.insert(held) if to_slot == -1 else target.put_at(to_slot, held, -1, false)
	var moved := amount - (left.quantity if left != null else 0)
	if left != null:
		# Sin notificaciones intermedias, el hueco de origen sigue admitiendo exactamente su resto.
		put_at(from_slot, left, -1, false)
	if moved > 0:
		item_removed.emit(data, moved)
		target.item_added.emit(data, moved)
		inventory_changed.emit()
		target.inventory_changed.emit()
	return moved


func move_item(from_slot: int, to_slot: int, quantity: int = -1) -> bool:
	var source := get_item_at_slot(from_slot)
	if source == null or from_slot == to_slot or quantity == 0 or not accepts(to_slot, source.data):
		return false
	var target := items[to_slot]
	var amount := mini(quantity, source.quantity) if quantity > 0 else source.quantity
	var swap := target != null and not target.can_stack_with(source)
	if swap and (amount < source.quantity or capacity(to_slot, source.data) < amount \
			or capacity(from_slot, target.data) < target.quantity):
		return false
	var left := put_at(to_slot, take_at(from_slot, amount))
	var moved := swap or left == null or left.quantity < amount
	if left != null:
		put_at(from_slot, left, -1, false)
	if moved:
		inventory_changed.emit()
	return moved


func split_item(from_slot: int, to_slot: int) -> bool:
	var item := get_item_at_slot(from_slot)
	return move_item(from_slot, to_slot, ceili(item.quantity / 2.0)) if item != null else false


func get_item_at_slot(slot: int) -> InventoryItem:
	return items[slot] if slot >= 0 and slot < items.size() else null


func find_empty_slot() -> int:
	return items.find(null)


func add_item(data: ItemData, quantity: int = 1) -> int:
	if data == null or quantity <= 0:
		return maxi(0, quantity)
	var remaining := quantity
	while remaining > 0:
		var item := InventoryItem.new(data, mini(remaining, maxi(1, data.max_stack) if data.stackable else 1))
		var amount := item.quantity
		var left := insert(item)
		var added := amount - (left.quantity if left != null else 0)
		remaining -= added
		if added < amount:
			break
	if remaining < quantity:
		item_added.emit(data, quantity - remaining)
		inventory_changed.emit()
	return remaining


func remove_item(data: ItemData, quantity: int = 1) -> int:
	if data == null or quantity <= 0:
		return 0
	var removed := 0
	for i in range(items.size() - 1, -1, -1):
		if items[i] != null and items[i].data.id == data.id:
			var taken := take_at(i, quantity - removed)
			removed += taken.quantity
			if removed == quantity:
				break
	if removed > 0:
		item_removed.emit(data, removed)
		inventory_changed.emit()
	return removed


func has_item(data: ItemData, quantity: int = 1) -> bool:
	return get_item_count(data) >= quantity


func get_item_count(data: ItemData) -> int:
	if data == null:
		return 0
	var total := 0
	for item in items:
		if item != null and item.data != null and item.data.id == data.id:
			total += item.quantity
	return total


func get_all_items() -> Array[InventoryItem]:
	return items.duplicate()


func is_full() -> bool:
	return not items.has(null)


func clear() -> void:
	items.fill(null)
	inventory_changed.emit()


func add_item_at(data: ItemData, amount: int, slot: int) -> bool:
	if amount <= 0 or amount > capacity(slot, data) or items[slot] != null:
		return false
	items[slot] = InventoryItem.new(data, amount)
	inventory_changed.emit()
	return true


func get_free_slots() -> int:
	return items.count(null)


func get_save_data() -> Dictionary:
	var entries: Array[Dictionary] = []
	for i in items.size():
		if items[i] != null:
			entries.append({"item_id": str(items[i].data.id), "quantity": items[i].quantity,
				"slot_index": i})
	return {"max_slots": max_slots, "items": entries}


## También lee la lista de huecos de las partidas anteriores. Valida antes de sustituir nada.
func restore_save_data(saved: Variant) -> bool:
	if not saved is Array and not saved is Dictionary:
		return false
	var entries: Array = saved if saved is Array else saved.get("items", [])
	var count := maxi(1, int(saved.get("max_slots", max_slots))) if saved is Dictionary else max_slots
	for entry in entries:
		count = maxi(count, int(entry.get("slot_index", -1)) + 1)
	var restored: Array[InventoryItem] = []
	restored.resize(count)
	for entry in entries:
		var slot := int(entry.get("slot_index", -1))
		var data := ItemCatalog.get_item(StringName(entry.get("item_id", "")))
		if data == null:
			push_warning("Inventory: item desconocido '%s'" % entry.get("item_id", ""))
			continue
		var amount := int(entry.get("quantity", 0))
		if slot < 0 or restored[slot] != null or amount < 1 \
				or amount > (maxi(1, data.max_stack) if data.stackable else 1):
			return false
		if rules != null and (not rules.accepts(slot, data) or amount > rules.capacity(slot, data)):
			return false
		restored[slot] = InventoryItem.new(data, amount)
	_max_slots = count
	items = restored
	inventory_changed.emit()
	return true
