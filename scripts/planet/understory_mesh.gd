@tool
extends MeshInstance3D

## Prefabs de sotobosque sin texturas. Se construyen una vez por especie y se
## comparten entre instancias; el planeta duplica solo los materiales por banda.
const Builder = preload("res://scripts/planet/understory_geometry.gd")
@export_enum("wood_fern", "royal_fern", "round_shrub", "willow_shrub", "flowering_shrub", "wild_asparagus", "broadleaf", "wildflowers")
var species: String = "wood_fern":
	set(value):
		species = value
		mesh = Builder.build(species)[0]


func _init() -> void:
	mesh = Builder.build(species)[0]


func bake_lods() -> Array:
	return Builder.build(species)
