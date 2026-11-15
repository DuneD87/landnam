class_name StorageTrait
extends ItemTrait

## Lo que cabe en cada instancia. Los objetos viven en su propio Inventory.
@export_range(1, 200, 1, "or_greater") var slots := 24
@export var rules: InventoryRules
## Comedero: de él comen los colonos (SettlerMeals) y en él deja el cocinero lo asado; los demás
## oficios no dejan aquí lo que sacan.
@export var feeder := false


func describe() -> Array:
	return [["TRAIT_HOLDS", tr("TRAIT_SLOTS") % slots]]
