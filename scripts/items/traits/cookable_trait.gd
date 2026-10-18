class_name CookableTrait
extends ItemTrait

## Se asa en una hoguera (Campfire): en qué se convierte y cuántos segundos de fuego tarda.

@export var result: StringName = &""
@export var cook_time := 40.0


func describe() -> Array:
	return [["TRAIT_ROASTS_IN", number(cook_time) + " s"]]
