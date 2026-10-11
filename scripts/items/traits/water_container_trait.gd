class_name WaterContainerTrait
extends ItemTrait

## Lleva agua: los tragos que caben. El agua que se lleva es del jugador (SurvivalNeeds.water),
## repartida entre todos sus odres; se rellenan junto al agua dulce y se beben desde la barra.

@export var capacity := 5


func describe() -> Array:
	return [["Caben", "%d tragos" % capacity]]
