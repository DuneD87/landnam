## Defines a construction material: visual appearance, inventory item, and cost.
class_name BuildMaterial
extends Resource

@export var material_id: String = ""
@export var display_name: String = ""
@export var surface_material: Material = null
@export var item: ItemData = null
@export var base_cost: int = 1
@export var preview_color: Color = Color.WHITE
## Si el material deja ver lo que hay detrás. No se puede deducir de surface_material cuando es un
## ShaderMaterial, y de ello depende el culling de caras (ChunkMeshBuilder).
@export var translucent: bool = false
## Material con el que se renderiza el icono, si el de verdad no vale (un traslúcido sobre el fondo
## transparente del generador sale fantasma). Vacío = se usa surface_material.
@export var icon_material: Material = null
## Familia de sonido del material. El AudioManager compone el evento con ella
## ("footstep_" + sound_material, "block_place_" + sound_material...), así que un material
## nuevo suena bien sin tocar ningún script.
@export var sound_material: StringName = &"rock"

## Returns the actual cost for a given cell size (minimum 1).
func get_cost_for_size(cell_size: float) -> int:
	return maxi(1, ceili(base_cost * cell_size))
