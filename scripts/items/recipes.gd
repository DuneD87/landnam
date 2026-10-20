class_name Recipes
extends RefCounted

## El recetario: todas las recetas (RecipeData) de data/recipes/, en orden de era, dónde se hacen
## (a mano y luego cada estación) y tipo de objeto. Dice lo que falta para hacer una receta las
## veces que se pida y la hace. Lo usa la ventana de fabricar (CraftingPanel). Ver docs/items.md.

const DIR := "res://data/recipes/"
## Estación de las que se hacen a mano.
const HAND := &""
## Lo que falta de agua de los odres, en missing(): tragos.
const WATER := &"water"

static var _all: Array[RecipeData] = []


static func all() -> Array[RecipeData]:
	if _all.is_empty():
		_load(DIR)
		_all.sort_custom(func(a: RecipeData, b: RecipeData) -> bool: return _less(sort_key(a), sort_key(b)))
	return _all


## Dónde se hace, ya traducido: «A mano» o el nombre de la estación.
static func station_name(station: StringName) -> String:
	if station == HAND:
		return TranslationServer.translate(&"RECIPE_BY_HAND")
	var data: ItemData = ItemCatalog.get_item(station)
	return data.get_display_name() if data != null else String(station)


## Era, a mano antes que en una estación, la estación y el objeto que sale (ItemTaxonomy).
static func sort_key(recipe: RecipeData) -> Array:
	var result: ItemData = ItemCatalog.get_item(recipe.result)
	var item_key: Array = ItemTaxonomy.sort_key(result) if result != null else [99, 99, String(recipe.result)]
	return [int(recipe.era), 0 if recipe.station == HAND else 1, station_name(recipe.station).to_lower()] + item_key


## Lo que falta de cada cosa para hacer [recipe] [times] veces con [inventory] y el agua de los
## odres de [needs] (vacío = se puede). El agua que falta va en WATER, en tragos.
static func missing(recipe: RecipeData, inventory: Inventory, times: int = 1,
		needs: SurvivalNeeds = null) -> Dictionary:
	var out := {}
	for id: StringName in recipe.inputs:
		var need := recipe.inputs[id] * times
		var have := inventory.get_item_count(ItemCatalog.get_item(id))
		if have < need:
			out[id] = need - have
	var water := _water(needs)
	if recipe.water > 0 and water < recipe.water * times:
		out[WATER] = recipe.water * times - water
	return out


static func can_craft(recipe: RecipeData, inventory: Inventory, times: int = 1,
		needs: SurvivalNeeds = null) -> bool:
	return times > 0 and missing(recipe, inventory, times, needs).is_empty()


## Cuántas veces se puede hacer con lo que hay.
static func max_times(recipe: RecipeData, inventory: Inventory, needs: SurvivalNeeds = null) -> int:
	var best := -1
	for id: StringName in recipe.inputs:
		var need := recipe.inputs[id]
		if need <= 0:
			continue
		var times := inventory.get_item_count(ItemCatalog.get_item(id)) / need
		best = times if best < 0 else mini(best, times)
	if recipe.water > 0:
		var times := _water(needs) / recipe.water
		best = times if best < 0 else mini(best, times)
	return maxi(best, 0)


## Gasta lo que pide [times] veces (y el agua, de los odres de [needs]) y añade lo que sale.
## Devuelve lo que no cupo (para tirarlo al suelo), o -1 si no se podía.
static func craft(recipe: RecipeData, inventory: Inventory, times: int = 1,
		needs: SurvivalNeeds = null) -> int:
	var result: ItemData = ItemCatalog.get_item(recipe.result)
	if result == null or not can_craft(recipe, inventory, times, needs):
		return -1
	for id: StringName in recipe.inputs:
		inventory.remove_item(ItemCatalog.get_item(id), recipe.inputs[id] * times)
	if recipe.water > 0:
		needs.water -= recipe.water * times
	return inventory.add_item(result, recipe.amount * times)


static func _water(needs: SurvivalNeeds) -> int:
	return needs.water if needs != null else 0


static func _load(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Recipes: no está %s" % path)
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_load(path.path_join(sub))
	for file in dir.get_files():
		# Exportado, el .tres llega como .tres.remap.
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var recipe := load(path.path_join(file)) as RecipeData
		if recipe != null and recipe.result != &"":
			_all.append(recipe)
		else:
			push_warning("Recipes: no es una receta: %s" % path.path_join(file))


static func _less(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()
