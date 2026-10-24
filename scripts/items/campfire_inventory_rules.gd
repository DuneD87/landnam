class_name CampfireInventoryRules
extends InventoryRules

## El combustible ocupa un montón; cada hueco del asador admite una pieza de comida.
func accepts(slot: int, data: ItemData) -> bool:
	if data == null:
		return false
	if slot == 0:
		return data.get_trait(FuelTrait) != null
	return data.get_trait(CookableTrait) != null or data.category == ItemData.Category.CONSUMABLE \
		and data.get_trait(EdibleTrait) != null


func capacity(slot: int, data: ItemData) -> int:
	return super.capacity(slot, data) if slot == 0 else 1
