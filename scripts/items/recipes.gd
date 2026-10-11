class_name Recipes
extends RefCounted

const Config = preload("res://scripts/config.gd")

## Lo que se fabrica a mano con lo que se lleva encima (la pestaña «Fabricar» del inventario): qué
## sale, cuánto y con qué. Ver docs/items.md.

const LIST := [
	{"result": &"campfire", "amount": 1, "inputs": {&"stone_01": 6, &"branch_01": 4}},
	{"result": &"waterskin", "amount": 1, "inputs": {&"raw_hide": 2}},
]


## Lo que falta de cada cosa para [recipe] en [inventory] (vacío = se puede).
static func missing(recipe: Dictionary, inventory: Inventory) -> Dictionary:
	var out := {}
	for id: StringName in recipe.inputs:
		var have := inventory.get_item_count(Config.get_item(id))
		if have < int(recipe.inputs[id]):
			out[id] = int(recipe.inputs[id]) - have
	return out


static func can_craft(recipe: Dictionary, inventory: Inventory) -> bool:
	return missing(recipe, inventory).is_empty()


## Gasta lo que pide y añade lo que sale. Devuelve lo que no cupo (para tirarlo al suelo), o -1 si
## no se podía.
static func craft(recipe: Dictionary, inventory: Inventory) -> int:
	if not can_craft(recipe, inventory):
		return -1
	for id: StringName in recipe.inputs:
		inventory.remove_item(Config.get_item(id), int(recipe.inputs[id]))
	return inventory.add_item(Config.get_item(recipe.result), int(recipe.amount))
