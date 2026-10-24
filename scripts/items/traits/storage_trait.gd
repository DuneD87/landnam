class_name StorageTrait
extends ItemTrait

## Lo que cabe en cada instancia. Los objetos viven en su propio Inventory.
@export_range(1, 200, 1, "or_greater") var slots := 24
@export var rules: InventoryRules


func describe() -> Array:
	return [["TRAIT_HOLDS", tr("TRAIT_SLOTS") % slots]]
