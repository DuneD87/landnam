extends Node

## El recetario y la ventana de fabricar: que las recetas estén bien hechas, las cuentas de
## materiales para varias veces, fabricar ×N, que cada sitio enseñe solo sus recetas (con el
## Tabulador, las de a mano; E en una estación, las suyas) y que lo de una estación pida tenerla
## cerca. También la Edad del bronce: el horno, la forja, lo que se hace en cada uno y las vetas que
## pide el pico de bronce.
##   godot --headless --path . res://tests/items/test_recipes.tscn

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
	_check_bronze()
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
		if ItemCatalog.get_item(recipe.result) == null:
			bad.append("sale %s" % recipe.result)
		for id: StringName in recipe.inputs:
			if ItemCatalog.get_item(id) == null or recipe.inputs[id] <= 0:
				bad.append("%s pide %s" % [recipe.result, id])
		if recipe.station != Recipes.HAND and recipe.station != Workstation.CAMPFIRE:
			var station: ItemData = ItemCatalog.get_item(recipe.station)
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
	var hoe := _recipe(&"stone_hoe_01")
	check(hoe != null and hoe.station == &"stone_workbench" and TerrainLeveling.levels(ItemCatalog.get_item(&"stone_hoe_01")),
		"la azada, que allana, en el banco de trabajo")
	var bench: ItemData = ItemCatalog.get_item(&"stone_workbench")
	check(bench != null and bench.get_trait(GroundPlaceableTrait) != null, "el banco de trabajo se planta")
	check(ItemTaxonomy.category_of(bench) == ItemData.Category.BLOCK, "y sale en Construcción")
	# Lo primero (cortar, despellejar, alumbrarse) se hace a mano con lo que se coge del suelo o se
	# pica sin pico.
	var first := [&"stone_axe_01", &"stone_hammer_01", &"flint_knife", &"torch_01", &"torch_placeable_01"]
	var ground := [&"branch_01", &"stone_01", &"plant_fiber", &"flint"]
	check(first.all(func(id: StringName) -> bool:
		var recipe := _recipe(id)
		return recipe != null and recipe.station == Recipes.HAND \
			and recipe.inputs.keys().all(func(input: StringName) -> bool: return input in ground)),
		"hacha, martillo, cuchillo y antorchas, a mano con lo del suelo")


## La Edad del bronce: el lingote sale del horno, con su tiempo; las herramientas de bronce, del
## banco de trabajo; la espada, de la forja, que se hace con lingotes. Las vetas que no hacen falta para
## el bronce piden el pico de bronce.
func _check_bronze() -> void:
	var ingot := _recipe(&"bronze_ingot")
	check(ingot != null and ingot.station == Furnace.ITEM_ID and ingot.time > 0.0 and ingot.era == Eras.Era.BRONZE
		and ingot.inputs.has(&"copper_ore") and ingot.inputs.has(&"tin_ore"),
		"el lingote de bronce se funde en el horno con malaquita y casiterita, con su tiempo")
	var timed := Recipes.all().filter(func(r: RecipeData) -> bool: return r.time > 0.0)
	check(timed.all(func(r: RecipeData) -> bool: return r.station == Furnace.ITEM_ID),
		"solo las del horno llevan tiempo (%d)" % timed.size())
	var furnace := _recipe(&"smelting_furnace")
	check(furnace != null and furnace.station == &"stone_workbench" and furnace.era == Eras.Era.BRONZE,
		"el horno, en el banco de trabajo y de la Edad del bronce")
	var forge := _recipe(&"bronze_forge")
	check(forge != null and forge.station == &"stone_workbench" and forge.inputs.get(&"bronze_ingot", 0) >= 4,
		"la forja pide lingotes de bronce y se hace en el banco de trabajo")
	for id in [&"bronze_axe", &"bronze_pickaxe", &"bronze_hoe", &"bronze_sword"]:
		var recipe := _recipe(id)
		check(recipe != null and recipe.station == &"bronze_forge" and recipe.era == Eras.Era.BRONZE,
			"%s, en la forja y de la Edad del bronce" % id)
	check(Recipes.all().all(func(r: RecipeData) -> bool:
		return not r.inputs.has(&"bronze_ingot") or r.station == &"bronze_forge" or r.result == &"bronze_forge"),
		"lo que lleva bronce se hace en la forja (menos la forja)")
	check(not Recipes.of_station(&"bronze_forge").any(func(r: RecipeData) -> bool:
		return r.result in [&"flint_sword", &"wooden_shield", &"hunting_bow"]),
		"lo de la Edad de piedra sigue en el banco de trabajo")
	for id in [&"smelting_furnace", &"bronze_forge"]:
		var data: ItemData = ItemCatalog.get_item(id)
		check(data != null and data.get_trait(GroundPlaceableTrait) != null and data.get_trait(CraftingStationTrait) != null
			and (data.get_trait(CraftingStationTrait) as CraftingStationTrait).era == Eras.Era.BRONZE,
			"%s se planta y es una estación de la Edad del bronce" % id)
	var stone_pick: ItemData = ItemCatalog.get_item(&"stone_pickaxe_01")
	var bronze_pick: ItemData = ItemCatalog.get_item(&"bronze_pickaxe")
	var axe: ItemData = ItemCatalog.get_item(&"bronze_axe")
	check(bronze_pick.mining_power > stone_pick.mining_power and bronze_pick.harvest_multiplier > 1.0
		and RockMining.mine_power(bronze_pick) > RockMining.mine_power(stone_pick)
		and TreeFelling.chop_power(axe) > TreeFelling.chop_power(ItemCatalog.get_item(&"stone_axe_01")),
		"el pico y el hacha de bronce cunden más que los de piedra")
	var ingot_data: ItemData = ItemCatalog.get_item(&"bronze_ingot")
	check(ItemTaxonomy.group_of(ingot_data) == &"metal" and ItemTaxonomy.category_of(ingot_data) == ItemData.Category.MATERIAL,
		"el lingote va en Materiales · Metales")
	var coal := ItemCatalog.get_item(&"coal").get_trait(FuelTrait) as FuelTrait
	var wood := ItemCatalog.get_item(&"wood_01").get_trait(FuelTrait) as FuelTrait
	var branch := ItemCatalog.get_item(&"branch_01").get_trait(FuelTrait) as FuelTrait
	check(coal.smelt_heat > wood.smelt_heat and wood.smelt_heat > 0.0 and branch.smelt_heat == 0.0,
		"el carbón funde más que la madera; la rama, nada")
	var per_ingot_wood := ingot.time / wood.smelt_heat / wood.burn_time / ingot.amount
	var per_ingot_coal := ingot.time / coal.smelt_heat / coal.burn_time / ingot.amount
	check(per_ingot_wood >= 1.5 and per_ingot_coal <= 0.5,
		"por lingote, mucha madera (%.1f) o poco carbón (%.2f)" % [per_ingot_wood, per_ingot_coal])
	# Las vetas (ore_settings): con el pico de piedra, lo que pide el bronce; el resto, con el de bronce.
	var ores := {}
	var json = JSON.parse_string(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	for ore in json.get("ore_settings", []):
		ores[String(ore.get("drop_item", ""))] = int(ore.get("pick_tier", 1))
	check(ores.get("tin_ore", 9) <= stone_pick.mining_power and ores.get("coal", 9) <= stone_pick.mining_power,
		"la casiterita y el carbón, con el pico de piedra")
	check(["iron_01", "bog_iron", "silver_ore", "gold_01", "sulfur"].all(func(id: String) -> bool:
		return ores.get(id, 0) > stone_pick.mining_power and ores.get(id, 9) <= bronze_pick.mining_power),
		"el hierro, la plata, el oro y el azufre, con el de bronce %s" % [ores])


func _recipe(result: StringName) -> RecipeData:
	for recipe in Recipes.all():
		if recipe.result == result:
			return recipe
	return null


func _inventory(contents: Array) -> Inventory:
	var inventory := Inventory.new()
	add_child(inventory)
	for entry in contents:
		inventory.add_item(ItemCatalog.get_item(entry[0]), entry[1])
	return inventory


func _check_counts() -> void:
	var campfire := _recipe(&"campfire")
	var inventory := _inventory([[&"stone_01", 13], [&"branch_01", 9]])
	check(Recipes.max_times(campfire, inventory) == 2, "13 piedras y 9 ramas: dos hogueras")
	check(Recipes.missing(campfire, inventory, 3) == {&"stone_01": 5, &"branch_01": 3}, "para tres faltan 5 piedras y 3 ramas")
	check(Recipes.craft(campfire, inventory, 3) == -1, "tres no se pueden")
	check(Recipes.craft(campfire, inventory, 2) == 0, "dos sí, y caben")
	check(inventory.get_item_count(ItemCatalog.get_item(&"campfire")) == 2
		and inventory.get_item_count(ItemCatalog.get_item(&"stone_01")) == 1
		and inventory.get_item_count(ItemCatalog.get_item(&"branch_01")) == 1, "quedan 2 hogueras, 1 piedra y 1 rama")
	var arrows := _recipe(&"arrow")
	inventory = _inventory([[&"stone_01", 5], [&"branch_01", 5]])
	check(not arrows.inputs.has(&"feather"), "las flechas no piden plumas: sin arco no se caza un ave")
	check(Recipes.max_times(arrows, _inventory([[&"stone_01", 5], [&"branch_01", 3]])) == 3,
		"5 piedras y 3 ramas: tres tiradas")
	Recipes.craft(arrows, inventory, 5)
	check(inventory.get_item_count(ItemCatalog.get_item(&"arrow")) == 5 * arrows.amount, "cinco tiradas de flechas: %d" % (5 * arrows.amount))
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


## La ventana: con el Tabulador, solo lo de a mano, y el hacha se fabrica también ×N; E en el banco
## enseña solo lo suyo, que pide estar cerca; la hoguera y la forja, igual; desmontar vuelve a mano.
func _check_panel() -> void:
	var ui: InventoryUI = load("res://scenes/ui/inventory_ui.tscn").instantiate()
	add_child(ui)
	ui.inventory = _inventory([[&"stone_01", 25], [&"branch_01", 20], [&"plant_fiber", 12], [&"raw_hide", 1]])
	var crafter := Node3D.new()
	add_child(crafter)
	ui.crafter = crafter
	ui.toggle(InventoryUI.View.CRAFTING)
	var panel := ui._crafting_panel
	check(panel.visible and not ui._side_column.visible, "la vista de fabricar sustituye a la columna de la derecha")
	var hand := Recipes.of_station(Recipes.HAND)
	check(panel._tiles.size() == hand.size() and panel._tiles.keys().all(func(r: RecipeData) -> bool:
		return r.station == Recipes.HAND), "con el Tabulador, solo lo de a mano (%d)" % panel._tiles.size())
	check(not panel._station_state.visible and not panel._dismantle_button.visible, "a mano no hay estación que mirar")
	var axe := _recipe(&"stone_axe_01")
	panel._select(axe)
	check(axe.station == Recipes.HAND and not panel._make_button.disabled and not panel._where_state.visible,
		"el hacha se fabrica a mano sin banco de trabajo")
	panel._set_max()
	check(int(panel._quantity.value) == 4, "Máx: cuatro hachas (la fibra manda)")
	panel._quantity.value = 3
	check(panel._make_button.text == tr("CRAFT_MAKE_N") % 3, "el botón dice cuántas")
	panel._craft()
	check(ui.inventory.get_item_count(ItemCatalog.get_item(&"stone_axe_01")) == 3, "fabrica tres hachas sin banco")
	check(ui.inventory.get_item_count(ItemCatalog.get_item(&"plant_fiber")) == 3, "y gasta nueve fibras")

	var bench: Workstation = load("res://scenes/world/stone_workbench.tscn").instantiate()
	add_child(bench)
	bench.position = Vector3(1.5, 0, 0)
	await get_tree().process_frame
	ui.open_station(bench)
	var here := Recipes.of_station(&"stone_workbench")
	check(panel._tiles.size() == here.size() and panel._tiles.keys().all(func(r: RecipeData) -> bool:
		return r.station == &"stone_workbench"), "E en el banco: solo sus recetas (%d)" % panel._tiles.size())
	check(not panel._tiles.has(axe), "lo de a mano no sale en el banco")
	var pickaxe := _recipe(&"stone_pickaxe_01")
	panel._select(pickaxe)
	check(not panel._make_button.disabled and panel._where_state.text == tr("CRAFT_NEAR"), "con el banco al lado, el pico se fabrica")
	check(panel._station_state.text == tr("CRAFT_NEAR") and panel._dismantle_button.visible, "arriba dice que está cerca y deja desmontarlo")
	panel._set_tab(int(ItemData.Category.ARMOR))
	var clothing := true
	for recipe: RecipeData in panel._tiles:
		clothing = clothing and ItemTaxonomy.category_of(ItemCatalog.get_item(recipe.result)) == ItemData.Category.ARMOR
	check(clothing and not panel._tiles.is_empty(), "la pestaña Ropa solo enseña ropa (%d)" % panel._tiles.size())
	bench.position = Vector3(30, 0, 0)
	panel._poll = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	panel._select(pickaxe)
	check(panel._make_button.disabled and panel._station_state.text == tr("CRAFT_NOT_NEAR"), "al alejarse del banco se apaga")

	# La forja: solo lo suyo, y lo de la Edad del bronce.
	var forge: Workstation = load("res://scenes/world/bronze_forge.tscn").instantiate()
	add_child(forge)
	forge.position = Vector3(0, 0, 1.5)
	await get_tree().process_frame
	ui.open_station(forge)
	check(panel._tiles.size() == Recipes.of_station(&"bronze_forge").size() and panel._tiles.has(_recipe(&"bronze_sword")),
		"E en la forja: la espada de bronce y lo demás de la forja")
	check(panel._title.text == Recipes.station_name(&"bronze_forge").to_upper(), "arriba, el nombre de la forja")

	# La hoguera: sus recetas, encendida.
	var fire: Campfire = load("res://scenes/world/campfire.tscn").instantiate()
	add_child(fire)
	fire.position = Vector3(-1.5, 0, 0)
	await get_tree().process_frame
	ui.open_crafting(fire)
	check(panel._tiles.size() == Recipes.of_station(Workstation.CAMPFIRE).size() and panel._tiles.has(_recipe(&"yarrow_draught")),
		"«Recetas» en la hoguera: lo que se cuece")
	check(panel._station_state.text == tr("CRAFT_FIRE_NOT_NEAR"), "apagada no vale")
	fire.inventory.items[Campfire.FUEL_SLOT] = InventoryItem.new(ItemCatalog.get_item(&"wood_01"), 2)
	fire.ignite()
	panel._poll = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(panel._station_state.text == tr("CRAFT_FIRE_NEAR"), "encendida, sí")

	# Desmontar el banco desde su menú lo devuelve y vuelve a lo de a mano.
	bench.position = Vector3(1.5, 0, 0)
	ui.open_station(bench)
	panel._dismantle(bench)
	check(panel._station == Recipes.HAND and ui.inventory.get_item_count(ItemCatalog.get_item(&"stone_workbench")) == 1,
		"desmontado, vuelve al inventario y la ventana, a lo de a mano")
	ui.toggle(InventoryUI.View.CRAFTING)
	check(not ui.visible, "Tab otra vez la cierra")
	ui.open_station(forge)
	ui.close()
	ui.toggle(InventoryUI.View.CRAFTING)
	check(panel._station == Recipes.HAND, "después de una estación, Tab vuelve a lo de a mano")
