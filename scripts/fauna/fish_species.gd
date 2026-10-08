class_name FishSpecies
extends Resource

## Un pez de un pack para AmbientFish: su malla horneada sin esqueleto
## (tools/fauna/bake_static_mesh.gd, la cabeza hacia -Z), los materiales de cada superficie
## (pack_fish.gdshader, que lo hace nadar), sus tamaños, su velocidad y en qué aguas vive.

@export var id: StringName = &""
@export var mesh: ArrayMesh
## Uno por superficie de la malla, en su orden.
@export var materials: Array[Material] = []
## Escala de la malla para un adulto medio.
@export var scale: float = 1.0
## De qué tamaños salen (alevín, adulto, grande…), sobre scale: cada pez sortea una. Ninguna = todos
## a scale. El mayor tiene que caber en AmbientFish.CLEARANCE.
@export var variants: Array[CreatureVariant] = []
## Velocidad de crucero (m/s) de un adulto medio; cada uno varía ±20 % y con su variante.
@export var speed: float = 1.0
## Lo que se aparta la cola al nadar, en fracción del largo.
@export_range(0.0, 0.3) var sway: float = 0.08
## En qué aguas vive (WorldMapData.WaterType: 0 océano, 1 mar, 2 lago, 3 charca). Vacío = en todas.
@export var water_types: Array[int] = []
## Peso al sortearla entre las que viven en esa agua.
@export var weight: float = 1.0


## La caja que choca, a escala 1: la de la malla, más lo que barre la cola de lado.
func collision_bounds() -> AABB:
	var box := mesh.get_aabb()
	var swing := sway * box.size.z * 1.15
	box.position.x -= swing
	box.size.x += swing * 2.0
	return box.grow(0.015)


## El mayor tamaño al que sale (sobre la malla): scale por la mayor de sus variantes.
func largest_scale() -> float:
	var largest := 1.0 if variants.is_empty() else 0.0
	for v in variants:
		if v != null:
			largest = maxf(largest, v.size.y)
	return scale * largest
