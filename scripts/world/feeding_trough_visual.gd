@tool
extends MeshInstance3D

## Comedero: un pesebre de dos tablas en V sobre cuatro patas, con los cabeceros cerrados y las juntas
## atadas con tendón. A lo largo va X; de frente, Z. La misma malla en el mundo y en la vista previa.
static var _mesh: ArrayMesh

## Largo (m), y alto y medio ancho del fondo y de la boca de la V.
const LENGTH := 1.2
const BOTTOM := 0.42
const TOP := 0.78
const HALF_BOTTOM := 0.06
const HALF_TOP := 0.3
const PLANK := 0.04
## Las patas, a esta distancia del centro a lo largo.
const LEG_X := 0.5


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	var wood := builder.st(WeaponMeshes.WOOD)
	var half := LENGTH * 0.5
	# Las dos tablas de la V, de punta a punta.
	for side in [-1.0, 1.0]:
		var a := Vector3(0.0, BOTTOM, side * HALF_BOTTOM)
		var b := Vector3(0.0, TOP, side * HALF_TOP)
		var run := b - a
		var tilt := Basis(Vector3.RIGHT, atan2(run.z, run.y))
		ProcMesh.box(wood, (a + b) * 0.5, Vector3(LENGTH, run.length(), PLANK), tilt)
	# El fondo, y los cabeceros: un trapecio de tablas en cada punta.
	ProcMesh.box(wood, Vector3(0.0, BOTTOM - PLANK * 0.5, 0.0), Vector3(LENGTH, PLANK, HALF_BOTTOM * 2.0 + PLANK))
	for end in [-1.0, 1.0]:
		var x: float = end * (half - PLANK * 0.5)
		var steps := 4
		for k in steps:
			var y0 := lerpf(BOTTOM, TOP, float(k) / steps)
			var y1 := lerpf(BOTTOM, TOP, float(k + 1) / steps)
			var width := lerpf(HALF_BOTTOM, HALF_TOP, (k + 0.5) / steps) * 2.0
			ProcMesh.box(wood, Vector3(x, (y0 + y1) * 0.5, 0.0), Vector3(PLANK, y1 - y0 - 0.004, width))
	# Las patas, en aspa bajo cada cabecero, y un travesaño entre ellas.
	for end in [-1.0, 1.0]:
		var x: float = end * LEG_X
		for side in [-1.0, 1.0]:
			ProcMesh.tube(wood, PackedVector3Array([Vector3(x, 0.0, side * 0.26), Vector3(x, BOTTOM + 0.1, -side * 0.08)]),
				PackedVector2Array([Vector2.ONE * 0.035, Vector2.ONE * 0.03]), 6)
	ProcMesh.tube(wood, PackedVector3Array([Vector3(-LEG_X, 0.2, 0.0), Vector3(LEG_X, 0.2, 0.0)]),
		PackedVector2Array([Vector2.ONE * 0.028, Vector2.ONE * 0.028]), 6)
	# Las ataduras donde se cruzan las patas.
	var ties := builder.st(SurvivalMeshes.SINEW)
	for end in [-1.0, 1.0]:
		var at := Vector3(end * LEG_X, BOTTOM * 0.62, 0.0)
		var points := PackedVector3Array()
		var radii := PackedVector2Array()
		for i in 13:
			var a := TAU * i / 12.0
			points.append(at + Vector3(0.0, sin(a) * 0.05, cos(a) * 0.05))
			radii.append(Vector2.ONE * 0.008)
		ProcMesh.tube(ties, points, radii, 4)
	_mesh = builder.commit(SurvivalMeshes.make_material)
	return _mesh
