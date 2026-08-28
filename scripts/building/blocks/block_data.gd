class_name BlockData
extends Resource

## Recurso que define un tipo de bloque de construcción.

@export var block_id: int = -1
@export var block_name: String = ""
@export var block_description: String = ""

## Geometría y colisión
@export var mesh: ArrayMesh = null
@export var collision_shape: Shape3D = null

## UI / Inventario
@export var preview_icon: Texture2D = null

## Rotación
@export var can_rotate: bool = false
@export var rotation_steps: int = 1

## Material
@export var material_override: Material = null
## Familia de sonido de respaldo, para bloques que no pasan por un BuildMaterial.
## Vacía = manda la del BuildMaterial con el que se coloque.
@export var sound_material: StringName = &""

## Tamaño de celda en la grid (por defecto 1m³)
@export var cell_size: float = 1.0

## Coste de construcción — lista de materiales necesarios
@export var build_cost: Array[BlockCost] = []

## Destrucción — energía (J) que absorbe un metro cúbico de este bloque antes de romperse por
## impacto. 0 = usa GridBase.DEFAULT_IMPACT_TOUGHNESS.
@export var impact_toughness: float = 0.0


func get_rotation_angle_deg() -> float:
	if rotation_steps <= 1:
		return 0.0
	return 360.0 / rotation_steps

func get_rotation_angle_rad() -> float:
	return deg_to_rad(get_rotation_angle_deg())

## Devuelve true si build_cost está vacío (bloque gratuito / creative)
func is_free() -> bool:
	return build_cost.is_empty()
