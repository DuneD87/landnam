class_name InsulationTrait
extends ItemTrait

## Abriga: grados (°C) que suma, puesto, a la temperatura que se siente (SurvivalNeeds).

@export var warmth := 2.0


func describe() -> Array:
	return [["TRAIT_WARMTH", "+%s °C" % number(warmth)]]
