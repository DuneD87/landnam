class_name InventoryRules
extends Resource

## Configuración compartida, sin contenido mutable. Una especialización puede decidir por hueco.
func accepts(_slot: int, data: ItemData) -> bool:
	return data != null


func capacity(_slot: int, data: ItemData) -> int:
	return maxi(1, data.max_stack) if data.stackable else 1
