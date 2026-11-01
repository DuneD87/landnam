class_name FurnaceInventoryRules
extends InventoryRules

## El combustible ocupa un montón de lo que calienta para fundir; el crisol, lo que pide alguna receta
## del horno; la salida no admite nada de fuera (la llena el horno: Furnace._finish).
func accepts(slot: int, data: ItemData) -> bool:
	if data == null:
		return false
	if slot == Furnace.FUEL_SLOT:
		var fuel := data.get_trait(FuelTrait) as FuelTrait
		return fuel != null and fuel.smelt_heat > 0.0
	if slot < Furnace.FIRST_OUT:
		return Furnace.smelts(data.id)
	return false
