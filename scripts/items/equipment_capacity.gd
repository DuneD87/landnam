class_name EquipmentCapacity
extends RefCounted

## Enlaza el equipo con el inventario sin sumar bonificaciones sobre una capacidad ya ampliada.
var inventory: Inventory
var base_slots: int
var configured_base_slots: int
var equipment: Dictionary


func _init(content: Inventory, slots: Dictionary, base: int) -> void:
	inventory = content
	equipment = slots
	base_slots = maxi(1, base)
	configured_base_slots = base_slots


func capacity_after(slot_type: int = -1, replacement: ItemData = null) -> int:
	var count := base_slots
	for key: int in equipment:
		var slot: EquipmentSlot = equipment[key]
		var data := replacement if key == slot_type else slot.equipped_item.data if slot.has_item() else null
		if data != null:
			var expansion := data.get_trait(InventoryExpansionTrait) as InventoryExpansionTrait
			if expansion != null:
				count += maxi(0, expansion.extra_slots)
	return count


func can_change(slot_type: ItemData.ArmorSlot, replacement: ItemData) -> bool:
	var slot: EquipmentSlot = equipment[slot_type]
	var current := slot.equipped_item
	var old_expansion := current.data.get_trait(InventoryExpansionTrait) if current != null else null
	var new_expansion := replacement.get_trait(InventoryExpansionTrait) if replacement != null else null
	if old_expansion == null and new_expansion == null:
		return true
	# La mochila retirada quedará en el cursor. Se reserva sitio para devolverla al cerrar.
	var reserve: Array[InventoryItem] = []
	if current != null:
		reserve.append(current)
	return inventory.can_repack(capacity_after(slot_type, replacement), reserve)


func sync(compact: bool = false) -> bool:
	var count := capacity_after()
	if count == inventory.max_slots and not compact:
		return true
	return inventory.resize_slots(count) if count > inventory.max_slots else inventory.repack_slots(count)
