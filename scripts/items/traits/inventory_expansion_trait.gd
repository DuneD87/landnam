class_name InventoryExpansionTrait
extends ItemTrait

## Huecos que aporta mientras está equipado. La capacidad se deriva del equipo completo.
@export_range(1, 200, 1, "or_greater") var extra_slots := 8


func describe() -> Array:
	return [["TRAIT_INVENTORY", tr("TRAIT_EXTRA_SLOTS") % extra_slots]]
