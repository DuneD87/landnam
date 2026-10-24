@tool
extends MeshInstance3D

## Cofre de tablas con travesaños y correas de piel. Una sola malla para mundo, previa e icono.
static var _mesh: ArrayMesh


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	var wood := builder.st(WeaponMeshes.WOOD)
	# Tablas de las paredes y del fondo; el frente mira a +Z.
	for y in [0.14, 0.28, 0.42]:
		for z in [-0.28, 0.28]:
			ProcMesh.box(wood, Vector3(0, y, z), Vector3(1.1, 0.135, 0.045))
		for x in [-0.53, 0.53]:
			ProcMesh.box(wood, Vector3(x, y, 0), Vector3(0.045, 0.135, 0.52))
	ProcMesh.box(wood, Vector3(0, 0.075, 0), Vector3(1.06, 0.04, 0.55))
	for i in 4:
		ProcMesh.box(wood, Vector3(0, 0.51, -0.225 + i * 0.15), Vector3(1.13, 0.065, 0.145))
	for x in [-0.39, 0.39]:
		ProcMesh.box(wood, Vector3(x, 0.035, 0), Vector3(0.09, 0.07, 0.66))
		for z in [-0.31, 0.31]:
			ProcMesh.box(wood, Vector3(x, 0.28, z), Vector3(0.065, 0.43, 0.025))
	var hide := builder.st(SurvivalMeshes.HIDE)
	for x in [-0.36, 0.36]:
		ProcMesh.box(hide, Vector3(x, 0.548, 0), Vector3(0.055, 0.012, 0.61))
		ProcMesh.box(hide, Vector3(x, 0.48, 0.308), Vector3(0.055, 0.13, 0.012))
	ProcMesh.box(hide, Vector3(0, 0.42, 0.308), Vector3(0.075, 0.19, 0.015))
	var peg := builder.st(SurvivalMeshes.BONE)
	ProcMesh.box(peg, Vector3(0, 0.36, 0.328), Vector3(0.11, 0.025, 0.03))
	_mesh = builder.commit(SurvivalMeshes.make_material)
	return _mesh
