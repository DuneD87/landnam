@tool
extends MeshInstance3D

## Bancada: un tablón de lado a lado sobre dos tablas de canto, con un travesaño abajo y las juntas
## atadas con tendón. Quien se sienta mira a -Z. La misma malla en el mundo, la vista previa y el icono.
static var _mesh: ArrayMesh

## Alto del asiento (m, sobre la cubierta), medio ancho y medio fondo del tablón.
const SEAT_HEIGHT := 0.48
const HALF_WIDTH := 0.55
const HALF_DEPTH := 0.17
const PLANK := 0.05
## Las tablas de las patas, a esta distancia del centro.
const LEG_X := 0.4


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	var wood := builder.st(WeaponMeshes.WOOD)
	# El tablón, algo combado y con los cantos rebajados.
	ProcMesh.box(wood, Vector3(0.0, SEAT_HEIGHT - PLANK * 0.5, 0.0), Vector3(HALF_WIDTH * 2.0, PLANK, HALF_DEPTH * 2.0))
	ProcMesh.box(wood, Vector3(0.0, SEAT_HEIGHT - PLANK - 0.015, 0.0),
		Vector3(HALF_WIDTH * 2.0 - 0.06, 0.03, HALF_DEPTH * 2.0 - 0.06))
	for side in [-1.0, 1.0]:
		var x: float = side * LEG_X
		# La pata: una tabla de canto, más ancha abajo.
		ProcMesh.box(wood, Vector3(x, (SEAT_HEIGHT - PLANK) * 0.5, 0.0),
			Vector3(0.045, SEAT_HEIGHT - PLANK, HALF_DEPTH * 2.0 - 0.04))
		ProcMesh.box(wood, Vector3(x, 0.03, 0.0), Vector3(0.09, 0.06, HALF_DEPTH * 2.0 + 0.04))
	# El travesaño entre las patas, para apoyar los pies.
	ProcMesh.tube(wood, PackedVector3Array([Vector3(-LEG_X, 0.14, 0.02), Vector3(LEG_X, 0.14, 0.02)]),
		PackedVector2Array([Vector2.ONE * 0.03, Vector2.ONE * 0.03]), 6)

	# Ataduras de tendón donde el tablón apoya en las patas.
	var ties := builder.st(SurvivalMeshes.SINEW)
	for side in [-1.0, 1.0]:
		for z in [-HALF_DEPTH + 0.05, HALF_DEPTH - 0.05]:
			var points := PackedVector3Array()
			var radii := PackedVector2Array()
			for i in 13:
				var a := TAU * i / 12.0
				points.append(Vector3(side * LEG_X + cos(a) * 0.05, SEAT_HEIGHT - PLANK * 0.5 + sin(a) * 0.045, z))
				radii.append(Vector2.ONE * 0.007)
			ProcMesh.tube(ties, points, radii, 4)
	_mesh = builder.commit(SurvivalMeshes.make_material)
	return _mesh
