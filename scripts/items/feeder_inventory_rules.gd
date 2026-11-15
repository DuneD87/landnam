class_name FeederInventoryRules
extends InventoryRules

## El comedero (Storage con StorageTrait.feeder): solo lo que se come y llena (EdibleTrait.hunger).
func accepts(_slot: int, data: ItemData) -> bool:
	if data == null:
		return false
	var edible := data.get_trait(EdibleTrait) as EdibleTrait
	return edible != null and edible.hunger > 0.0
