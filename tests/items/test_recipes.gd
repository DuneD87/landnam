extends Node

## El recetario y la ventana de fabricar: que las recetas estén bien hechas, las cuentas de
## materiales para varias veces, fabricar ×N y que lo de una estación de trabajo pida tenerla cerca.
##   godot --headless --path . res://tests/items/test_recipes.tscn

const Config = preload("res://scripts/config.gd")

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
	_check_catalog()
	_check_counts()
	await _check_panel()
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Cada receta sale de algo que existe, con cosas que existen y en una estación que lo es.
func _check_catalog() -> void:
	var all := Recipes.all()
	check(all.size() >= 15, "hay recetas (%d)" % all.size())
	var bad: Array[String] = []
	for recipe in all:
		if Config.get_item(recipe.result) == null:
			bad.append("sale %s" % recipe.result)
		for id: StringName in recipe.inputs:
			if Config.get_item(id) == null or recipe.inputs[id] <= 0:
				bad.append("%s pide %s" % [recipe.result, id])
		if recipe.station != Recipes.HAND and recipe.station != Workstation.CAMPFIRE:
			var station: ItemData = Config.get_item(recipe.station)
			if station == null or station.get_trait(CraftingStationTrait) == null:
				bad.append("%s en %s, que no es una estación" % [recipe.result, recipe.station])
	check(bad.is_empty(), "recetas bien hechas %s" % [bad])
	var keys := all.map(func(r: RecipeData) -> Array: return Recipes.sort_key(r))
	var sorted := true
	for i in range(1, keys.size()):
		if Recipes._less(keys[i], keys[i - 1]):
			sorted = false
	check(sorted, "en orden: era, a mano antes que en estaciones, tipo")
	check(all[0].station == Recipes.HAND, "las primeras, a mano")
	var weapons := [&"flint_sword", &"flint_spear", &"wooden_shield"].all(func(id: StringName) -> bool:
		var recipe := _recipe(id)
		return recipe != null and recipe.station == &"stone_workbench")
	check(weapons, "espada y lanza de sílex y escudo de madera, en el banco de trabajo")
	var bench: ItemData = Config.get_item(&"stone_workbench")
	check(bench != null and bench.get_trait(GroundPlaceableTrait) != null, "el banco de trabajo se planta")
	check(ItemTaxonomy.category_of(bench) == ItemData.Category.BLOCK, "y sale en Construcción")


func _recipe(result: StringName) -> RecipeData:
	for recipe in Recipes.all():
		if recipe.result == result:
			return recipe
	return null


func _inventory(contents: Array) -> Inventory:
	var inventory := Inventory.new()
	add_child(inventory)
	for entry in contents:
		inventory.add_item(Config.get_item(entry[0]), entry[1])
	return inventory


func _check_counts() -> void:
	var campfire := _recipe(&"campfire")
	var inventory := _inventory([[&"stone_01", 13], [&"branch_01", 9]])
	check(Recipes.max_times(campfire, inventory) == 2, "13 piedras y 9 ramas: dos hogueras")
	check(Recipes.missing(campfire, inventory, 3) == {&"stone_01": 5, &"branch_01": 3}, "para tres faltan 5 piedras y 3 ramas")
	check(Recipes.craft(campfire, inventory, 3) == -1, "tres no se pueden")
	check(Recipes.craft(campfire, inventory, 2) == 0, "dos sí, y caben")
	check(inventory.get_item_count(Config.get_item(&"campfire")) == 2
		and inventory.get_item_count(Config.get_item(&"stone_01")) == 1
		and inventory.get_item_count(Config.get_item(&"branch_01")) == 1, "quedan 2 hogueras, 1 piedra y 1 rama")
	var arrows := _recipe(&"arrow")
	inventory = _inventory([[&"stone_01", 5], [&"branch_01", 5], [&"feather", 10]])
	check(Recipes.max_times(arrows, _inventory([[&"stone_01", 5], [&"branch_01", 5], [&"feather", 3]])) == 1,
		"sin plumas no hay flechas: con 3, una tirada")
	Recipes.craft(arrows, inventory, 5)
	check(inventory.get_item_count(Config.get_item(&"arrow")) == 5 * arrows.amount, "cinco tiradas de flechas: %d" % (5 * arrows.amount))
	# El bebedizo se cuece con agua de los odres, junto a la hoguera.
	var draught := _recipe(&"yarrow_draught")
	check(draught != null and draught.station == Workstation.CAMPFIRE and draught.water > 0,
		"el bebedizo se hace junto a la hoguera y gasta agua")
	inventory = _inventory([[&"yarrow", 12]])
	var needs := SurvivalNeeds.new()
	needs.water = draught.water * 2
	check(Recipes.missing(draught, inventory).has(Recipes.WATER), "sin odres, falta el agua")
	check(Recipes.max_times(draught, inventory, needs) == 2, "con agua para dos, dos bebedizos aunque haya hierba para tres")
	check(Recipes.craft(draught, inventory, 2, needs) == 0 and needs.water == 0, "al hacerlos se gasta el agua")
	needs.free()


## La ventana: el hacha pide el banco; sin él no se fabrica, con él al lado sí, las veces pedidas.
func _check_panel() -> void:
	var ui: InventoryUI = load("res://scenes/ui/inventory_ui.tscn").instantiate()
	add_child(ui)
	ui.inventory = _inventory([[&"stone_01", 20], [&"branch_01", 20], [&"raw_hide", 4]])
	var crafter := Node3D.new()
	add_child(crafter)
	ui.crafter = crafter
	ui.open(InventoryUI.View.CRAFTING)
	var panel := ui._crafting_panel
	check(panel.visible and not ui._side_column.visible, "la vista de fabricar sustituye a la columna de la derecha")
	check(panel._tiles.size() == Recipes.all().size(), "salen todas las recetas en «Todo» (%d)" % panel._tiles.size())
	var axe := _recipe(&"stone_axe_01")
	panel._select(axe)
	check(panel._make_button.disabled and panel._where_state.text == tr("CRAFT_NOT_NEAR"), "sin banco cerca, el hacha no se fabrica")
	var bench: Workstation = load("res://scenes/world/stone_workbench.tscn").instantiate()
	add_child(bench)
	bench.position = Vector3(1.5, 0, 0)
	await get_tree().process_frame
	check(Workstation.in_reach(get_tree(), crafter.global_position).has(&"stone_workbench"), "el banco a 1,5 m está al alcance")
	panel._poll = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(not panel._make_button.disabled and panel._where_state.text == tr("CRAFT_NEAR"), "con el banco al lado, sí")
	panel._set_max()
	check(int(panel._quantity.value) == 4, "Máx: cuatro hachas (las pieles mandan)")
	panel._quantity.value = 3
	check(panel._make_button.text == tr("CRAFT_MAKE_N") % 3, "el botón dice cuántas")
	panel._craft()
	check(ui.inventory.get_item_count(Config.get_item(&"stone_axe_01")) == 3, "fabrica tres hachas")
	check(ui.inventory.get_item_count(Config.get_item(&"raw_hide")) == 1, "y gasta tres pieles")
	panel._set_tab(int(ItemData.Category.ARMOR))
	var clothing := true
	for recipe: RecipeData in panel._tiles:
		clothing = clothing and ItemTaxonomy.category_of(Config.get_item(recipe.result)) == ItemData.Category.ARMOR
	check(clothing and not panel._tiles.is_empty(), "la pestaña Ropa solo enseña ropa (%d)" % panel._tiles.size())
	bench.position = Vector3(30, 0, 0)
	panel._poll = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	panel._select(axe)
	check(panel._make_button.disabled, "al alejarse del banco se apaga")
	ui.toggle(InventoryUI.View.CRAFTING)
	check(not ui.visible, "Tab otra vez la cierra")
