## Defines a construction material: visual appearance, inventory item, and cost.
class_name BuildMaterial
extends Resource

@export var material_id: String = ""
@export var display_name: String = ""
@export var surface_material: Material = null
@export var item: ItemData = null
@export var base_cost: int = 1
@export var preview_color: Color = Color.WHITE

## Returns the actual cost for a given cell size (minimum 1).
func get_cost_for_size(cell_size: float) -> int:
	return maxi(1, ceili(base_cost * cell_size))
