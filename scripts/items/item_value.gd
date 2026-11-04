class_name ItemValue
extends RefCounted

## Lo que vale un objeto para la gente de los poblados (al regalar y, más adelante, al comerciar), en
## piezas de leña: lo que no se fabrica tiene su valor en BASE (o el de su categoría) y lo fabricado vale
## lo que sus ingredientes por la mano de obra, repartido entre lo que sale. Ver docs/villagers.md.

## Lo que no sale de ninguna receta (o vale más de lo que cuesta hacerlo).
const BASE := {
	&"wood_01": 1.0, &"branch_01": 0.5, &"stone_01": 0.5, &"plant_fiber": 0.3, &"flint": 1.0,
	&"obsidian": 3.0, &"coal": 1.0, &"sulfur": 2.0, &"yarrow": 2.0, &"feather": 0.5,
	&"bone": 1.0, &"sinew": 2.0, &"antler": 4.0, &"horn": 4.0, &"boar_tusk": 5.0, &"ivory": 12.0,
	&"raw_hide": 4.0, &"raw_meat": 3.0, &"raw_fish": 2.5, &"cooked_meat": 5.0, &"cooked_fish": 4.0,
	&"copper_ore": 3.0, &"tin_ore": 4.0, &"bog_iron": 4.0, &"silver_ore": 8.0, &"iron_01": 10.0,
	&"gold_01": 25.0, &"glass_01": 2.0,
}
## Sin valor propio ni receta, por categoría.
const BY_CATEGORY := {
	ItemData.Category.MATERIAL: 1.0, ItemData.Category.TOOL: 8.0, ItemData.Category.WEAPON: 12.0,
	ItemData.Category.CONSUMABLE: 2.0, ItemData.Category.ARMOR: 10.0, ItemData.Category.BLOCK: 0.5,
}
## Lo que se paga el trabajo de hacerlo, sobre los ingredientes.
const LABOUR := 1.25

static var _cache := {}


## El valor de una unidad de [data].
static func of(data: ItemData) -> float:
	if data == null:
		return 0.0
	if not _cache.has(data.id):
		_cache[data.id] = INF
		_cache[data.id] = _compute(data)
	var value: float = _cache[data.id]
	# Una receta que se cierra sobre sí misma: vale lo de su categoría.
	return value if is_finite(value) else float(BY_CATEGORY.get(data.category, 1.0))


static func _compute(data: ItemData) -> float:
	if BASE.has(data.id):
		return BASE[data.id]
	var best := INF
	for recipe in Recipes.all():
		if recipe.result != data.id:
			continue
		var cost := 0.0
		for id: StringName in recipe.inputs:
			cost += of(ItemCatalog.get_item(id)) * recipe.inputs[id]
		best = minf(best, cost * LABOUR / maxi(recipe.amount, 1))
	return best if is_finite(best) else float(BY_CATEGORY.get(data.category, 1.0))
