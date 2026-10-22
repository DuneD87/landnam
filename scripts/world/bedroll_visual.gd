@tool
extends MeshInstance3D

## Colchón de fibras sobre ramas, cubierto por pieles irregulares y con una cabecera enrollada.
## La misma malla se usa en el mundo, en la vista previa y en el icono.
static var _mesh: ArrayMesh


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	var wood := builder.st(WeaponMeshes.WOOD)
	for side in [-1.0, 1.0]:
		ProcMesh.tube(wood, PackedVector3Array([Vector3(side * 0.39, 0.05, -1.02),
			Vector3(side * 0.42, 0.055, 0.0), Vector3(side * 0.38, 0.04, 1.03)]),
			PackedVector2Array([Vector2.ONE * 0.025, Vector2.ONE * 0.032, Vector2.ONE * 0.02]), 7)
	var straw := builder.st(SurvivalMeshes.PLANT_FIBER)
	var rng := RandomNumberGenerator.new()
	rng.seed = 715
	for i in 32:
		var z := lerpf(-1.0, 1.0, i / 31.0)
		var width := rng.randf_range(0.39, 0.47)
		ProcMesh.tube(straw, PackedVector3Array([Vector3(-width, 0.075, z),
			Vector3(0.0, 0.105, z + rng.randf_range(-0.02, 0.02)), Vector3(width, 0.075, z)]),
			PackedVector2Array([Vector2(0.034, 0.022), Vector2(0.04, 0.028), Vector2(0.035, 0.02)]), 6)
	var hide := builder.st(SurvivalMeshes.HIDE)
	var rings: Array = []
	for y in [0.105, 0.14]:
		var ring := PackedVector3Array()
		for i in 40:
			var a := TAU * i / 40.0
			var wave := 1.0 + 0.045 * sin(a * 7.0) + 0.03 * sin(a * 11.0 + 0.7)
			ring.append(Vector3(cos(a) * 0.43 * wave, y, sin(a) * 0.99 * wave))
		rings.append(ring)
	ProcMesh.loft(hide, rings)
	# El rollo en la cabecera hace de almohada.
	ProcMesh.tube(hide, PackedVector3Array([Vector3(-0.37, 0.20, -0.78), Vector3(0.37, 0.20, -0.78)]),
		PackedVector2Array([Vector2(0.12, 0.10), Vector2(0.12, 0.10)]), 12, Vector3.UP)
	var ties := builder.st(SurvivalMeshes.SINEW)
	for x in [-0.27, 0.27]:
		var points := PackedVector3Array()
		var radii := PackedVector2Array()
		for i in 17:
			var a := TAU * i / 16.0
			points.append(Vector3(x, 0.20 + cos(a) * 0.105, -0.78 + sin(a) * 0.125))
			radii.append(Vector2.ONE * 0.007)
		ProcMesh.tube(ties, points, radii, 5)
	_mesh = builder.commit(SurvivalMeshes.make_material)
	return _mesh
