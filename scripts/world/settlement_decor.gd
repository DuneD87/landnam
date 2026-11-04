class_name SettlementDecor extends RefCounted

## Lo que se ve de los sitios de trabajo de los poblados (SettlementWorkplace), que SettlementManager
## pone con su casa: decorado, ni se guarda ni se recoge. La leñera (troncos apilados y el tajo), el
## huerto (montones de tierra con sus matas, cada una a su altura) y el banco de trabajo.

const BENCH_VISUAL := "res://scenes/world/stone_workbench_visual.tscn"
## El banco (StoneWorkbenchVisual): 1,22 m de largo, 0,76 de alto y 0,47 de fondo.
const BENCH_SIZE := Vector3(1.22, 0.76, 0.47)
## La leñera, en su pose: la pila a lo largo de X detrás (-Z) y el tajo delante.
const PILE_CENTER := Vector3(0.0, 0.0, -0.95)
const PILE_SIZE := Vector3(2.2, 0.9, 0.9)
const STUMP_AT := Vector3(0.0, 0.0, 0.45)
const STUMP_RADIUS := 0.24
const STUMP_HEIGHT := 0.45
const LOG_RADIUS := 0.085
const SOIL_COLOR := Color(0.2, 0.14, 0.09)

static var _woodpile: ArrayMesh
static var _plant: ArrayMesh
static var _mound: Mesh


## El nodo de [work] (SettlementLayout._workplace) en [frame] (de su marco, el del terreno, al del
## padre que lo vaya a llevar).
static func make(work: Dictionary, frame: Transform3D) -> Node3D:
	var pose: Transform3D = work.pose
	var node := Node3D.new()
	node.transform = frame * pose
	match StringName(work.kind):
		&"woodpile":
			var mesh := MeshInstance3D.new()
			mesh.mesh = woodpile_mesh()
			node.add_child(mesh)
			node.add_child(_body([[Vector3(PILE_SIZE.x, PILE_SIZE.y, PILE_SIZE.z), PILE_CENTER + Vector3.UP * PILE_SIZE.y * 0.5],
				[Vector3(STUMP_RADIUS * 2.0, STUMP_HEIGHT, STUMP_RADIUS * 2.0), STUMP_AT + Vector3.UP * STUMP_HEIGHT * 0.5]]))
		&"garden":
			_garden(node, pose, work.plants)
		&"bench":
			node.add_child((load(BENCH_VISUAL) as PackedScene).instantiate())
			node.add_child(_body([[BENCH_SIZE, Vector3.UP * BENCH_SIZE.y * 0.5]]))
	return node


## Un cuerpo estático con una caja por [size, centro].
static func _body(boxes: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	for box: Array in boxes:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box[0]
		shape.shape = b
		shape.position = box[1]
		body.add_child(shape)
	return body


## Las matas del huerto en [plants] (marco del terreno), cada una sobre su montón de tierra, giradas al
## azar (con la semilla de su sitio: siempre igual).
static func _garden(node: Node3D, pose: Transform3D, plants: PackedVector3Array) -> void:
	var to_local := pose.affine_inverse()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pose.origin)
	var mounds := MultiMesh.new()
	mounds.transform_format = MultiMesh.TRANSFORM_3D
	mounds.mesh = mound_mesh()
	mounds.instance_count = plants.size()
	var tufts := MultiMesh.new()
	tufts.transform_format = MultiMesh.TRANSFORM_3D
	tufts.mesh = plant_mesh()
	tufts.instance_count = plants.size()
	for i in plants.size():
		var at := to_local * plants[i]
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		mounds.set_instance_transform(i, Transform3D(yaw, at))
		tufts.set_instance_transform(i, Transform3D(yaw.scaled(Vector3.ONE * rng.randf_range(0.75, 1.2)), at + Vector3.UP * 0.05))
	for multimesh in [mounds, tufts]:
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		node.add_child(instance)


## Troncos apilados en capas que se estrechan hacia arriba, cada uno algo movido, y el tajo: un tocón
## con un leño de pie encima.
static func woodpile_mesh() -> ArrayMesh:
	if _woodpile != null:
		return _woodpile
	var builder := ProcMesh.Builder.new()
	var bark := builder.st(WeaponMeshes.BARK)
	var wood := builder.st(WeaponMeshes.WOOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var layers := 4
	for layer in layers:
		var count := 11 - layer * 2
		var y := LOG_RADIUS + layer * LOG_RADIUS * 1.75
		for k in count:
			var x := (k - (count - 1) * 0.5) * LOG_RADIUS * 2.05
			var r := LOG_RADIUS * rng.randf_range(0.85, 1.1)
			var depth := PILE_SIZE.z * 0.5 * rng.randf_range(0.9, 1.05)
			var shift := rng.randf_range(-0.04, 0.04)
			ProcMesh.tube(bark, PackedVector3Array([PILE_CENTER + Vector3(x, y, -depth + shift),
				PILE_CENTER + Vector3(x, y, depth + shift)]), PackedVector2Array([Vector2.ONE * r, Vector2.ONE * r]), 7)
	ProcMesh.tube(bark, PackedVector3Array([STUMP_AT, STUMP_AT + Vector3.UP * STUMP_HEIGHT]),
		PackedVector2Array([Vector2.ONE * STUMP_RADIUS * 1.08, Vector2.ONE * STUMP_RADIUS]), 10, Vector3.RIGHT)
	ProcMesh.tube(wood, PackedVector3Array([STUMP_AT + Vector3(0.03, STUMP_HEIGHT, 0.0),
		STUMP_AT + Vector3(0.03, STUMP_HEIGHT + 0.3, 0.0)]),
		PackedVector2Array([Vector2.ONE * 0.08, Vector2.ONE * 0.075]), 7)
	# Los tubos de ProcMesh van en el orden contrario al frontal de Godot: se dan la vuelta.
	_woodpile = builder.commit(SurvivalMeshes.make_material, true)
	return _woodpile


## Una mata de hojas: unas cuantas que salen del centro y se abren al subir.
static func plant_mesh() -> ArrayMesh:
	if _plant != null:
		return _plant
	var builder := ProcMesh.Builder.new()
	var leaf := builder.st(SurvivalMeshes.HERB)
	for i in 7:
		var a := TAU * i / 7.0
		var out := Vector3(cos(a), 0.0, sin(a))
		var tall := 0.28 + 0.06 * (i % 3)
		ProcMesh.tube(leaf, PackedVector3Array([Vector3.ZERO, out * 0.06 + Vector3.UP * tall * 0.6,
			out * 0.16 + Vector3.UP * tall]),
			PackedVector2Array([Vector2(0.03, 0.006), Vector2(0.035, 0.006), Vector2(0.005, 0.003)]), 4, out.cross(Vector3.UP))
	_plant = builder.commit(SurvivalMeshes.make_material, true)
	return _plant


## Un montón de tierra removida, achatado.
static func mound_mesh() -> Mesh:
	if _mound != null:
		return _mound
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.16
	sphere.radial_segments = 10
	sphere.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = SOIL_COLOR
	material.roughness = 1.0
	sphere.material = material
	_mound = sphere
	return _mound
