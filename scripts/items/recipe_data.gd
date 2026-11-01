class_name RecipeData
extends Resource

## Una receta: qué sale, cuánto, con qué y dónde se hace (a mano o junto a una estación de
## trabajo). Cada una es un .tres en data/recipes/ y Recipes las carga todas. Ver docs/items.md.

## Id del objeto que sale y cuántos salen cada vez.
@export var result: StringName
@export var amount := 1
## Lo que gasta cada vez: id del objeto → cantidad.
@export var inputs: Dictionary[StringName, int] = {}
## Tragos de agua de los odres que gasta cada vez (SurvivalNeeds.water): un bebedizo se cuece en
## agua.
@export var water := 0
## Id del objeto de la estación junto a la que se hace (lleva CraftingStationTrait); vacío, a mano.
@export var station: StringName = &""
@export var era: Eras.Era = Eras.Era.STONE
## Las del horno (Furnace) no se hacen en la ventana de fabricar: se funden solas mientras arde, y
## esto es lo que tardan, en segundos de fuego a pleno calor (FuelTrait.smelt_heat = 1). 0 = las
## demás, que salen al momento.
@export var time := 0.0
