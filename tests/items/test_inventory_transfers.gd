extends Node

## Transferencias del modelo y del cursor: identidad de objeto y conservación de cantidades.
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _item(id: StringName) -> ItemData:
	var data := ItemData.new()
	data.id = id
	data.stackable = true
	data.max_stack = 10
	return data


func _run() -> void:
	var stone := _item(&"stone")
	var wood := _item(&"wood")
	var bag := Inventory.new()
	add_child(bag)
	bag.items[0] = InventoryItem.new(stone, 7)
	bag.items[1] = InventoryItem.new(_item(&"stone"), 8)
	check(bag.move_item(0, 1), "Se apilan recursos distintos con el mismo id")
	check(bag.items[0].quantity == 5 and bag.items[1].quantity == 10,
		"Al llenar un montón, el sobrante vuelve al origen")
	bag.items[2] = InventoryItem.new(wood, 3)
	check(not bag.move_item(0, 2, 2), "Un traslado parcial no intercambia objetos diferentes")
	check(bag.move_item(0, 2) and bag.items[0].data == wood and bag.items[2].data == stone,
		"Un traslado completo intercambia los montones")
	check(bag.split_item(2, 3) and bag.items[2].quantity == 2 and bag.items[3].quantity == 3,
		"La mitad de un montón impar se redondea hacia arriba")
	var held := bag.take_at(3)
	held = bag.put_at(4, held, 1, false)
	check(held.quantity == 2 and bag.items[4].quantity == 1,
		"Depositar una unidad conserva el resto en la mano")
	check(bag.put_at(1, held, 1, false) == held and held.quantity == 2,
		"Depositar en un montón lleno conserva la mano")
	check(bag.put_at(-1, held) == held and bag.take_at(99) == null,
		"Un hueco inválido no pierde objetos")
	bag.put_at(3, held)
	check(bag.get_item_count(stone) == 15 and bag.get_item_count(wood) == 3,
		"Las operaciones del modelo conservan las cantidades totales")

	bag.clear()
	bag.items[0] = InventoryItem.new(stone, 7)
	bag.items[1] = InventoryItem.new(wood, 3)
	var ui := InventoryUI.new()
	add_child(ui)
	ui.inventory = bag
	bag.inventory_changed.connect(ui._refresh)
	ui._create_slots()
	ui._refresh()
	ui._pickup_half_from_inventory(ui.slots[0])
	ui._drop_to_inventory(ui.slots[1])
	check(bag.get_item_count(stone) == 7 and bag.get_item_count(wood) == 3,
		"Intercambiar desde una mitad conserva el resto que había en el origen")
	check(ui.floating_item == null, "El objeto intercambiado vuelve a otro hueco disponible")
	ui._pickup_from_inventory(ui.slots[1])
	ui._drop_single_to_inventory(ui.slots[0])
	check(bag.items[0].quantity == 4 and ui.floating_item.quantity == 3,
		"El clic derecho de la interfaz usa las mismas reglas de apilado")
	ui._return_to_origin()
	check(bag.get_item_count(stone) == 7, "Cancelar el cursor devuelve todo lo que quedaba")
	ui.free()
	bag.free()
	print("INVENTORY TRANSFERS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
