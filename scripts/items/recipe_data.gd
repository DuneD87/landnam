class_name RecipeData
extends Resource

## Una receta: qué sale, cuánto, con qué y dónde se hace (a mano o junto a una estación de
## trabajo). Cada una es un .tres en data/recipes/ y Recipes las carga todas. Ver docs/items.md.

## Id del objeto que sale y cuántos salen cada vez.
@export var result: StringName
@export var amount := 1
## Lo que gasta cada vez: id del objeto → cantidad.
@export var inputs: Dictionary[StringName, int] = {}
## Id del objeto de la estación junto a la que se hace (lleva CraftingStationTrait); vacío, a mano.
@export var station: StringName = &""
@export var era: Eras.Era = Eras.Era.STONE
