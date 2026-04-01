class_name BuildMaterial
extends Resource

## Defines a construction material: visual appearance, inventory item, and cost.

## Unique identifier (e.g. "wood", "stone")
@export var material_id: String = ""

## Display name for UI (e.g. "Wood", "Stone")
@export var display_name: String = ""

## Visual material applied to block meshes
@export var surface_material: Material = null

## The ItemData consumed from inventory when building
@export var item: ItemData = null

## Base cost for a 1.0 cell_size block.
## Scales proportionally: cost = ceil(base_cost * cell_size)
@export var base_cost: int = 1

## Preview color for UI icons / ghost tint (optional)
@export var preview_color: Color = Color.WHITE


## Returns the actual cost for a given cell size (minimum 1).
func get_cost_for_size(cell_size: float) -> int:
	return maxi(1, ceili(base_cost * cell_size))
