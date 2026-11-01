extends Node

## El horno de fundición (Furnace): lo que admite cada hueco, que funda con el calor de lo que arde
## (mucha madera o poco carbón), varias tandas seguidas, que espere con la salida llena y empiece de
## cero si cambia el crisol, guardar y cargar, y su panel en el inventario.
##   godot --headless --path . res://tests/items/test_furnace.tscn

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_check_rules()
	_check_coal()
	_check_wood()
	_check_batches()
	_check_waits()
	_check_save()
	await _check_panel()
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _item(id: StringName) -> ItemData:
	return ItemCatalog.get_item(id)


func _furnace(copper: int, tin: int, fuel: StringName = &"", fuel_count := 0) -> Furnace:
	var furnace: Furnace = load("res://scenes/world/smelting_furnace.tscn").instantiate()
	add_child(furnace)
	if copper > 0:
		furnace.inventory.items[1] = InventoryItem.new(_item(&"copper_ore"), copper)
	if tin > 0:
		furnace.inventory.items[2] = InventoryItem.new(_item(&"tin_ore"), tin)
	if fuel_count > 0:
		furnace.inventory.items[Furnace.FUEL_SLOT] = InventoryItem.new(_item(fuel), fuel_count)
	return furnace


func _ingots(furnace: Furnace) -> int:
	var count := 0
	for slot in range(Furnace.FIRST_OUT, Furnace.FIRST_OUT + Furnace.OUT_SLOTS):
		var item := furnace.inventory.items[slot]
		if item != null and item.data.id == &"bronze_ingot":
			count += item.quantity
	return count


func _recipe() -> RecipeData:
	return Recipes.of_station(Furnace.ITEM_ID)[0]


## Combustible: lo que calienta para fundir (no la rama); crisol: lo que pide una receta del horno;
## salida: nada de fuera.
func _check_rules() -> void:
	var furnace := _furnace(0, 0)
	check(furnace.accepts(Furnace.FUEL_SLOT, _item(&"coal")) and furnace.accepts(Furnace.FUEL_SLOT, _item(&"wood_01")),
		"el carbón y la madera van al combustible")
	check(not furnace.accepts(Furnace.FUEL_SLOT, _item(&"branch_01")), "las ramas no calientan para fundir")
	check(furnace.accepts(1, _item(&"copper_ore")) and furnace.accepts(4, _item(&"tin_ore")), "la mena va al crisol")
	check(not furnace.accepts(1, _item(&"stone_01")) and not furnace.accepts(1, _item(&"coal")), "la piedra y el carbón, no")
	check(not furnace.accepts(Furnace.FIRST_OUT, _item(&"bronze_ingot")), "en la salida no se pone nada")
	check(not furnace.ignite(), "sin combustible no enciende")
	furnace.free()


## Con carbón: una tanda en RecipeData.time segundos, y sobra carbón para la siguiente.
func _check_coal() -> void:
	var recipe := _recipe()
	var furnace := _furnace(3, 1, &"coal", 1)
	check(furnace.current_recipe() == recipe, "con 3 de malaquita y 1 de casiterita, funde bronce")
	check(furnace.ignite() and furnace.lit, "con carbón enciende")
	furnace.advance(recipe.time * 0.5)
	check(is_equal_approx(furnace.smelt_ratio(), 0.5) and _ingots(furnace) == 0, "a medio tiempo, la mitad (%.2f)" % furnace.smelt_ratio())
	furnace.advance(recipe.time * 0.5 + 0.01)
	check(_ingots(furnace) == recipe.amount, "al acabar, %d lingotes" % _ingots(furnace))
	check(furnace.inventory.items[1] == null and furnace.inventory.items[2] == null, "y el crisol queda vacío")
	check(furnace.lit and furnace.fuel_left > 0.0, "el carbón sigue ardiendo (quedan %d s)" % furnace.fuel_left)
	furnace.free()


## Con madera funde a su calor (smelt_heat): tarda más y gasta mucha más.
func _check_wood() -> void:
	var recipe := _recipe()
	var wood := _item(&"wood_01").get_trait(FuelTrait) as FuelTrait
	var needed := recipe.time / wood.smelt_heat
	var furnace := _furnace(3, 1, &"wood_01", 10)
	furnace.ignite()
	furnace.advance(needed - 5.0)
	check(_ingots(furnace) == 0, "con madera, a %d s todavía no" % roundi(needed - 5.0))
	furnace.advance(10.0)
	check(_ingots(furnace) == recipe.amount, "a %d s, sí" % roundi(needed + 5.0))
	var left := furnace.inventory.items[Furnace.FUEL_SLOT].quantity
	check(10 - left >= 3, "ha gastado %d de madera" % (10 - left))
	furnace.free()


## Varias tandas en un solo avance (dormir acelera el mundo) y sin combustible se apaga.
func _check_batches() -> void:
	var recipe := _recipe()
	var furnace := _furnace(9, 3, &"coal", 2)
	furnace.ignite()
	furnace.advance(recipe.time * 3.0 + 1.0)
	check(_ingots(furnace) == recipe.amount * 3, "tres tandas seguidas: %d lingotes" % _ingots(furnace))
	furnace.advance(10000.0)
	check(not furnace.lit and not furnace.has_fuel(), "sin carbón se apaga")
	furnace.free()


## Con la salida llena espera; si cambia el crisol, la receta empieza de cero; sin lo que pide, nada.
func _check_waits() -> void:
	var recipe := _recipe()
	var furnace := _furnace(2, 1, &"coal", 5)
	check(furnace.current_recipe() == null, "con 2 de malaquita no llega")
	furnace.ignite()
	furnace.advance(recipe.time)
	check(_ingots(furnace) == 0 and furnace.lit, "no funde nada, pero arde")
	furnace.inventory.items[3] = InventoryItem.new(_item(&"copper_ore"), 1)
	furnace.advance(recipe.time * 0.5)
	check(furnace.smelt_ratio() > 0.4, "con la que faltaba, empieza")
	furnace.inventory.items[2] = null
	furnace.advance(1.0)
	check(furnace.smelt_ratio() == 0.0 and furnace.progress == 0.0, "sin la casiterita, vuelve a cero")
	furnace.inventory.items[2] = InventoryItem.new(_item(&"tin_ore"), 1)
	var ingot := _item(&"bronze_ingot")
	for slot in range(Furnace.FIRST_OUT, Furnace.FIRST_OUT + Furnace.OUT_SLOTS):
		furnace.inventory.items[slot] = InventoryItem.new(ingot, ingot.max_stack)
	check(furnace.current_recipe() == null, "con la salida llena no hay receta")
	furnace.advance(recipe.time * 2.0)
	check(furnace.inventory.items[1] != null and furnace.inventory.items[1].quantity + furnace.inventory.items[3].quantity == 3,
		"y la mena espera en el crisol")
	furnace.free()


func _check_save() -> void:
	var recipe := _recipe()
	var furnace := _furnace(3, 1, &"coal", 2)
	furnace.ignite()
	furnace.advance(recipe.time * 0.25)
	var data := furnace.get_save_data()
	var copy: Furnace = load("res://scenes/world/smelting_furnace.tscn").instantiate()
	add_child(copy)
	copy.restore_save_data(JSON.parse_string(JSON.stringify(data)))
	check(copy.lit and is_equal_approx(copy.fuel_left, furnace.fuel_left) and is_equal_approx(copy.fuel_heat, furnace.fuel_heat),
		"guardado: encendido y con lo que le quedaba al carbón")
	check(is_equal_approx(copy.smelt_ratio(), 0.25), "y la cuarta parte de la tanda (%.2f)" % copy.smelt_ratio())
	check(copy.inventory.items[1].quantity == 3 and copy.inventory.items[Furnace.FUEL_SLOT].quantity == 1,
		"y lo que había en cada hueco")
	copy.advance(recipe.time * 0.75 + 0.01)
	check(_ingots(copy) == recipe.amount, "al cargar sigue donde iba")
	furnace.free()
	copy.free()


## El panel: se abre en la columna de la derecha, recoge lo fundido y solo se desmonta apagado y vacío.
func _check_panel() -> void:
	var ui: InventoryUI = load("res://scenes/ui/inventory_ui.tscn").instantiate()
	add_child(ui)
	var inventory := Inventory.new()
	add_child(inventory)
	ui.inventory = inventory
	var furnace := _furnace(3, 1, &"coal", 1)
	furnace.ignite()
	furnace.advance(_recipe().time + 1.0)
	ui.open_furnace(furnace)
	check(ui.visible and ui._furnace_box.visible and ui._side_column.visible, "E en el horno: su panel a la derecha")
	check(ui._furnace_slots.size() == 1 + Furnace.ORE_SLOTS + Furnace.OUT_SLOTS, "con sus %d huecos" % ui._furnace_slots.size())
	ui._dismantle_furnace()
	check(is_instance_valid(furnace) and not furnace.is_queued_for_deletion(), "encendido no se desmonta")
	ui._take_smelted()
	check(inventory.get_item_count(_item(&"bronze_ingot")) == _recipe().amount and _ingots(furnace) == 0,
		"«Recoger lo fundido» pasa los lingotes al inventario")
	furnace.extinguish()
	furnace.inventory.transfer_to(inventory, Furnace.FUEL_SLOT)
	ui._dismantle_furnace()
	check(furnace.is_queued_for_deletion() and inventory.get_item_count(_item(Furnace.ITEM_ID)) == 1,
		"apagado y vacío, vuelve al inventario")
	check(not ui._furnace_box.visible and ui.open_furnace_node() == null, "y el panel se cierra")
	await get_tree().process_frame
