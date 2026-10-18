class_name FuelTrait
extends ItemTrait

## Arde en una hoguera (Campfire): segundos de fuego que da cada unidad.

@export var burn_time := 60.0


func describe() -> Array:
	return [["TRAIT_BURNS", number(burn_time) + " s"]]
