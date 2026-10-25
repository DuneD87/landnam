class_name NavalPiece
extends RefCounted

## Piezas navales huecas de superficies curvas, divididas en celdas editables. Las medidas son exteriores y
## el fondo y los costados tienen una capa de grosor, sea cual sea el tamaño de celda.
## +Z apunta a proa. El tramo abre sus dos extremos; proa y popa abren la unión con él.
enum Kind { BOW, HULL, STERN }
enum Profile { STRAIGHT, ROUND }

const DEFAULT_SIZE := Vector3i(12, 6, 12)
const MIN_SIZE := Vector3i(3, 2, 3)
const MAX_SIZE := Vector3i(64, 32, 64)
const NAME_KEYS := ["NAVAL_BOW", "NAVAL_HULL", "NAVAL_STERN"]
static var _cache := {}


static func clamp_size(size: Vector3i) -> Vector3i:
	return size.clamp(MIN_SIZE, MAX_SIZE)


static func generate(kind: int, size: Vector3i, profile: int = Profile.ROUND) -> Dictionary:
	if kind < Kind.BOW or kind > Kind.STERN:
		return {}
	size = clamp_size(size)
	var key := "%d:%s:%d" % [kind, size, profile]
	if not _cache.has(key):
		if _cache.size() >= 8:
			_cache.erase(_cache.keys()[0])
		_cache[key] = NavalHullMesh.generate(kind, size, profile == Profile.ROUND)
	return _cache[key]


## Gira alrededor de la pieza y normaliza su esquina mínima. El fantasma y la colocación
## usan este mismo diccionario: no hay una escala/rotación distinta para la física.
static func rotated(blocks: Dictionary, size: Vector3i, rotation: Basis) -> Dictionary:
	var minimum := Vector3.ZERO
	for axis in 3:
		minimum += (rotation[axis] * float(size[axis])).min(Vector3.ZERO)
	var out := {}
	for cell: Vector3i in blocks:
		var center := rotation * (Vector3(cell) + Vector3.ONE * 0.5) - minimum
		var info: Dictionary = blocks[cell].duplicate()
		info["rotation_basis"] = rotation * info.get("rotation_basis", Basis.IDENTITY)
		out[Vector3i(center.floor())] = info
	return out


static func rotated_size(size: Vector3i, rotation: Basis) -> Vector3i:
	return Vector3i((rotation.x.abs() * size.x + rotation.y.abs() * size.y + rotation.z.abs() * size.z).round())
