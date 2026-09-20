class_name SimpleMarineMesh extends RefCounted

const NAMES := ["Tiburón", "Ballena", "Orca", "Tortuga"]
const IDS := ["shark", "whale", "orca", "turtle"]
const SPEEDS := [2.8, 2.0, 3.2, 0.7]
const ANIMATION_MARGIN := 0.25
## Linear scale relative to the original model.
const MODEL_SCALES := [6.0, 6.0, 4.0, 1.0]
const MESHES: Array[ArrayMesh] = [
	preload("res://data/fauna/meshes/marine/shark.res"),
	preload("res://data/fauna/meshes/marine/whale.res"),
	preload("res://data/fauna/meshes/marine/orca.res"),
	preload("res://data/fauna/meshes/marine/turtle.res"),
]
static var _material: ShaderMaterial


static func mesh(kind: int) -> ArrayMesh:
	return MESHES[kind]


static func collision_bounds(kind: int) -> AABB:
	var bounds := mesh(kind).get_aabb().grow(ANIMATION_MARGIN)
	var size: float = MODEL_SCALES[kind]
	return AABB(bounds.position * size, bounds.size * size)


static func clearance(kind: int) -> float:
	var bounds := collision_bounds(kind)
	return (bounds.position.abs().max(bounds.end.abs())).length()


static func swim_frequency(kind: int, speed: float) -> float:
	return speed * 1.5 / sqrt(MODEL_SCALES[kind])


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/fauna/marine_animal.gdshader")
	return _material
