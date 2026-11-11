@tool
extends MeshInstance3D

## Trono de troncos: asiento de rollizos sobre cuatro patas, brazos, respaldo alto de travesaños entre
## dos postes rematados con astas, y pieles en el asiento y el respaldo. El frente mira a +Z (hacia
## donde mira quien se sienta). La misma malla se usa en el mundo, en la vista previa y en el icono.
static var _mesh: ArrayMesh

## Alto del asiento (m, sobre el suelo), y dónde se sienta (las caderas: Throne.SEAT).
const SEAT_HEIGHT := 0.5
const HALF_WIDTH := 0.36
const FRONT := 0.24
const BACK := -0.3
const ARM_HEIGHT := 0.76
const POST_HEIGHT := 1.7


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	var wood := builder.st(WeaponMeshes.WOOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	# Las patas de delante suben hasta los brazos; los postes de atrás, hasta arriba del respaldo.
	for side in [-1.0, 1.0]:
		var x: float = side * HALF_WIDTH
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, 0.0, FRONT), Vector3(x, ARM_HEIGHT + 0.03, FRONT)]),
			PackedVector2Array([Vector2.ONE * 0.06, Vector2.ONE * 0.05]), 8)
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, 0.0, BACK), Vector3(x * 1.02, POST_HEIGHT * 0.5, BACK - 0.02),
			Vector3(x * 1.04, POST_HEIGHT, BACK - 0.05)]),
			PackedVector2Array([Vector2.ONE * 0.08, Vector2.ONE * 0.07, Vector2.ONE * 0.055]), 8)
		# El brazo, de poste a pata.
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, ARM_HEIGHT, BACK - 0.04), Vector3(x, ARM_HEIGHT + 0.02, FRONT + 0.08)]),
			PackedVector2Array([Vector2.ONE * 0.05, Vector2.ONE * 0.045]), 8)
		# Travesaño bajo entre las patas de cada lado.
		ProcMesh.tube(wood, PackedVector3Array([Vector3(x, 0.18, BACK), Vector3(x, 0.18, FRONT)]),
			PackedVector2Array([Vector2.ONE * 0.035, Vector2.ONE * 0.035]), 6)
	# El asiento: rollizos de lado a lado.
	for i in 6:
		var z := lerpf(BACK + 0.04, FRONT - 0.02, i / 5.0)
		ProcMesh.tube(wood, PackedVector3Array([Vector3(-HALF_WIDTH - 0.04, SEAT_HEIGHT - 0.04, z),
			Vector3(0.0, SEAT_HEIGHT - 0.035 + rng.randf_range(-0.005, 0.005), z), Vector3(HALF_WIDTH + 0.04, SEAT_HEIGHT - 0.04, z)]),
			PackedVector2Array([Vector2.ONE * 0.045, Vector2.ONE * 0.048, Vector2.ONE * 0.045]), 7)
	# El respaldo: travesaños entre los postes y uno más grueso arriba.
	for y in [0.62, 0.86, 1.1, 1.34]:
		ProcMesh.tube(wood, PackedVector3Array([Vector3(-HALF_WIDTH, y, BACK - 0.01), Vector3(HALF_WIDTH, y, BACK - 0.01)]),
			PackedVector2Array([Vector2.ONE * 0.04, Vector2.ONE * 0.04]), 6)
	ProcMesh.tube(wood, PackedVector3Array([Vector3(-HALF_WIDTH - 0.12, 1.55, BACK - 0.04),
		Vector3(0.0, 1.6, BACK - 0.04), Vector3(HALF_WIDTH + 0.12, 1.55, BACK - 0.04)]),
		PackedVector2Array([Vector2.ONE * 0.06, Vector2.ONE * 0.065, Vector2.ONE * 0.06]), 8)

	var hide := builder.st(SurvivalMeshes.HIDE)
	# La piel del asiento, que cuelga un poco por delante.
	var rings: Array = []
	for y in [SEAT_HEIGHT, SEAT_HEIGHT + 0.03]:
		var ring := PackedVector3Array()
		for i in 32:
			var a := TAU * i / 32.0
			var wave := 1.0 + 0.05 * sin(a * 5.0 + 0.4)
			ring.append(Vector3(cos(a) * (HALF_WIDTH + 0.02) * wave, y, -0.03 + sin(a) * 0.29 * wave))
		rings.append(ring)
	ProcMesh.loft(hide, rings)
	ProcMesh.tube(hide, PackedVector3Array([Vector3(0.0, SEAT_HEIGHT + 0.01, FRONT + 0.03),
		Vector3(0.0, SEAT_HEIGHT - 0.12, FRONT + 0.07)]),
		PackedVector2Array([Vector2(0.3, 0.015), Vector2(0.27, 0.012)]), 8, Vector3.RIGHT)
	# La del respaldo, por delante de los travesaños.
	ProcMesh.tube(hide, PackedVector3Array([Vector3(0.0, 1.5, BACK + 0.05), Vector3(0.0, 1.05, BACK + 0.06),
		Vector3(0.0, 0.58, BACK + 0.08)]),
		PackedVector2Array([Vector2(0.27, 0.02), Vector2(0.3, 0.022), Vector2(0.28, 0.02)]), 8, Vector3.RIGHT)

	# Astas en lo alto de los postes, abiertas hacia fuera, con dos puntas.
	var antler := builder.st(SurvivalMeshes.ANTLER)
	for side in [-1.0, 1.0]:
		var root := Vector3(side * HALF_WIDTH * 1.04, POST_HEIGHT - 0.02, BACK - 0.05)
		var beam := PackedVector3Array([root, root + Vector3(side * 0.12, 0.16, 0.02),
			root + Vector3(side * 0.3, 0.26, 0.05), root + Vector3(side * 0.42, 0.42, 0.02)])
		ProcMesh.tube(antler, beam, PackedVector2Array([Vector2.ONE * 0.035, Vector2.ONE * 0.03,
			Vector2.ONE * 0.024, Vector2.ONE * 0.012]), 6)
		for t in [1, 2]:
			var from: Vector3 = beam[t]
			ProcMesh.tube(antler, PackedVector3Array([from, from + Vector3(side * 0.02, 0.17, 0.06)]),
				PackedVector2Array([Vector2.ONE * 0.02, Vector2.ONE * 0.008]), 5)

	# Ataduras de tendón en las esquinas del asiento.
	var ties := builder.st(SurvivalMeshes.SINEW)
	for side in [-1.0, 1.0]:
		for z in [FRONT, BACK]:
			var points := PackedVector3Array()
			var radii := PackedVector2Array()
			for i in 13:
				var a := TAU * i / 12.0
				points.append(Vector3(side * HALF_WIDTH + cos(a) * 0.075, SEAT_HEIGHT - 0.05, z + sin(a) * 0.075))
				radii.append(Vector2.ONE * 0.008)
			ProcMesh.tube(ties, points, radii, 4)
	_mesh = builder.commit(SurvivalMeshes.make_material)
	return _mesh
