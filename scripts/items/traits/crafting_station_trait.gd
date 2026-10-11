class_name CraftingStationTrait
extends ItemTrait

## Es una estación de trabajo: plantada en el suelo (Workstation), deja fabricar las recetas que
## la piden (RecipeData.station = el id de este objeto) a quien esté cerca. Ver docs/items.md.

@export var era: Eras.Era = Eras.Era.STONE
## Hasta dónde se puede estar de ella para usar sus recetas (m, desde los pies).
@export var reach := 3.5


func describe() -> Array:
	return [["Estación", Eras.name_of(era)]]
