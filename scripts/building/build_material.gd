## Defines a construction material: visual appearance, inventory item, and cost.
class_name BuildMaterial
extends Resource

const DEFAULT_DENSITY := 500.0

@export var material_id: String = ""
## Clave de localization/translations.csv (BUILD_MAT_<ID>).
@export var display_name: String = ""
@export var surface_material: Material = null
@export var item: ItemData = null
@export var base_cost: int = 1
## Masa del material macizo por m³. La masa de construcción se calcula aparte del volumen
## estanco que excluye agua: una pieza de entramado no es un metro cúbico de madera maciza.
@export_range(0.1, 10000.0, 1.0, "or_greater") var density_kg_m3 := DEFAULT_DENSITY
@export_range(0.01, 1.0, 0.01) var solid_fraction := 1.0
## Solo los materiales habilitados aportan empuje. Los demás siguen pesando y rozando el agua.
@export var buoyant := false
## Vacío permite todas las formas. Un material especializado puede ofrecer solo sus piezas.
@export var allowed_block_ids: Array[int] = []
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


func get_mass_for_volume(volume: float) -> float:
	return maxf(volume, 0.0) * maxf(density_kg_m3, 0.0) * clampf(solid_fraction, 0.0, 1.0)
