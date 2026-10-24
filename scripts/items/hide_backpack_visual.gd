@tool
extends MeshInstance3D

## Mochila de piel con solapa, costuras, correas y un rollo de piel en la parte de arriba.
## Metros; Y arriba, +Z hacia la espalda de quien la lleva. Mundo, equipo e icono comparten malla.
static var _mesh: ArrayMesh


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	var hide := builder.st(SurvivalMeshes.HIDE)
	var rings: Array = []
	for shape in [Vector3(-0.25, 0.13, 0.065), Vector3(-0.20, 0.18, 0.10),
			Vector3(0.08, 0.18, 0.11), Vector3(0.20, 0.15, 0.09), Vector3(0.22, 0.12, 0.07)]:
		var ring := PackedVector3Array()
		for i in 16:
			var angle := TAU * i / 16.0
			ring.append(Vector3(cos(angle) * shape.y, shape.x, sin(angle) * shape.z))
		rings.append(ring)
	ProcMesh.loft(hide, rings)
	# Rollo superior; la solapa cae por la cara exterior (-Z).
	ProcMesh.tube(hide, PackedVector3Array([Vector3(-0.18, 0.23, 0), Vector3(0.18, 0.23, 0)]),
		PackedVector2Array([Vector2(0.07, 0.065), Vector2(0.07, 0.065)]), 12)
	var leather := builder.st(WeaponMeshes.LEATHER)
	ProcMesh.box(leather, Vector3(0, 0.09, -0.112), Vector3(0.27, 0.17, 0.014))
	for side in [-1.0, 1.0]:
		# Las asas rodean los hombros; la parte delantera queda por delante del saco.
		ProcMesh.tube(leather, PackedVector3Array([Vector3(side * 0.12, -0.17, 0.08),
			Vector3(side * 0.19, -0.10, 0.32), Vector3(side * 0.18, 0.20, 0.34),
			Vector3(side * 0.12, 0.23, 0.06)]),
			PackedVector2Array([Vector2(0.024, 0.008), Vector2(0.025, 0.008),
				Vector2(0.025, 0.008), Vector2(0.024, 0.008)]), 6)
		ProcMesh.box(leather, Vector3(side * 0.105, 0.02, -0.13), Vector3(0.025, 0.25, 0.012))
		for y in [-0.16, -0.10, -0.04, 0.02, 0.08]:
			ProcMesh.box(builder.st(SurvivalMeshes.SINEW), Vector3(side * 0.164, y, -0.062),
				Vector3(0.018, 0.006, 0.012))
		ProcMesh.box(builder.st(SurvivalMeshes.BONE), Vector3(side * 0.105, -0.025, -0.143),
			Vector3(0.048, 0.012, 0.012))
	_mesh = builder.commit(SurvivalMeshes.make_material)
	return _mesh
