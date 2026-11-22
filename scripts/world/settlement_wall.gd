class_name SettlementWall extends RefCounted

## La cerca de un poblado (SettlementLayout._wall), que SettlementManager pone mientras el poblado está
## cerca: decorado con colisión, ni se guarda ni se toca con el martillo. Dos clases:
##
## - &"palisade", la empalizada: troncos de pie con la punta afilada, uno junto a otro y enterrados un
##   palmo, con un larguero por dentro. Las puertas, entre dos postes altos con un dintel, con las dos
##   hojas abiertas hacia fuera.
## - &"fence", la cerca de varas de las granjas: postes y tres varas. Las puertas, dos postes.
##
## Los troncos siguen el suelo entre los vértices del plano (interpolado, no leído) y van enterrados
## lo bastante para que no floten en un suelo algo abombado.

const LOG_STEP := 0.3
const LOG_RADIUS := Vector2(0.12, 0.16)
## Alto de la empalizada sobre el suelo (m) y lo que va enterrado.
const PALISADE_HEIGHT := Vector2(2.7, 3.1)
const BURY := 0.5
const FENCE_POST_STEP := 2.2
const FENCE_HEIGHT := 1.25
const FENCE_RAILS: Array[float] = [0.35, 0.75, 1.1]
const GATE_POST_RADIUS := 0.22
const GATE_HEIGHT := 4.0
const THICKNESS := 0.4

static var _log: ArrayMesh
static var _post: ArrayMesh
static var _rail: ArrayMesh
static var _leaf: ArrayMesh


## El nodo de la cerca [wall] en [frame] (del marco del terreno al del padre que la lleve).
static func build(wall: Dictionary, frame: Transform3D, seed: int) -> Node3D:
	var node := Node3D.new()
	node.transform = frame
	var points: PackedVector3Array = wall.points
	var open: PackedByteArray = wall.open
	var n := points.size()
	if n < 3:
		return node
	var palisade := StringName(wall.kind) == &"palisade"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var logs: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	var gate_posts: Array[Transform3D] = []
	var leaves: Array[Transform3D] = []
	var boxes: Array = []
	var center := Vector3.ZERO
	for p in points:
		center += p
	center /= n
	for j in n:
		var a := points[j]
		var b := points[(j + 1) % n]
		var up := (a + b).normalized()
		var run := (b - a).slide(up)
		var length := run.length()
		if length < 0.01:
			continue
		var along := run / length
		var out := along.cross(up)
		if out.dot(a - center) < 0.0:
			out = -out
		if open[j] == 2:
			continue
		if open[j] == 1:
			# Postes de la puerta a los dos lados de la abertura, si el tramo de al lado tiene cerca.
			for side: int in [0, 1]:
				var k := posmod(j - 1, n) if side == 0 else (j + 1) % n
				if open[k] != 0:
					continue
				var at := a if side == 0 else b
				var post := _upright(at, up, GATE_POST_RADIUS, GATE_HEIGHT if palisade else FENCE_HEIGHT + 0.4)
				posts.append(post)
				gate_posts.append(post)
				if palisade:
					# La hoja abierta hacia fuera desde la bisagra, a lo largo de [out].
					var hinge := at + along * (GATE_POST_RADIUS if side == 0 else -GATE_POST_RADIUS)
					var basis := Basis(up.cross(out), up, out).orthonormalized()
					leaves.append(Transform3D(basis, hinge + out * 0.8))
					boxes.append([Vector3(0.12, 2.4, 1.6), basis, hinge + out * 0.8 + up * 1.2])
			continue
		var height := 0.0
		if palisade:
			var count := maxi(1, roundi(length / LOG_STEP))
			for i in count:
				var t := (i + 0.5) / count
				var at := _ground(a, b, t)
				height = rng.randf_range(PALISADE_HEIGHT.x, PALISADE_HEIGHT.y)
				var r := rng.randf_range(LOG_RADIUS.x, LOG_RADIUS.y)
				var tilt := Basis(along, rng.randf_range(-0.03, 0.03)) * Basis(out, rng.randf_range(-0.03, 0.03))
				var basis := tilt * Basis(along, up, along.cross(up)).orthonormalized()
				logs.append(Transform3D(basis.scaled_local(Vector3(r, height + BURY, r)), at - up * BURY))
			# El larguero, por dentro a media altura.
			var inner := -out * (LOG_RADIUS.y + 0.06)
			rails.append(_beam(a + inner + up * 1.9, b + inner + up * 1.9, up, 0.08))
			rails.append(_beam(a + inner + up * 0.6, b + inner + up * 0.6, up, 0.08))
			boxes.append([Vector3(length, PALISADE_HEIGHT.x, THICKNESS), Basis(along, up, along.cross(up)).orthonormalized(),
				(a + b) * 0.5 + up * PALISADE_HEIGHT.x * 0.5])
		else:
			var count := maxi(1, roundi(length / FENCE_POST_STEP))
			for i in count:
				posts.append(_upright(_ground(a, b, float(i) / count), up, 0.07, FENCE_HEIGHT))
			for h in FENCE_RAILS:
				rails.append(_beam(a + up * h, b + up * h, up, 0.035))
			boxes.append([Vector3(length, FENCE_HEIGHT, 0.2), Basis(along, up, along.cross(up)).orthonormalized(),
				(a + b) * 0.5 + up * FENCE_HEIGHT * 0.5])
	# Los dinteles de las puertas de la empalizada: de poste a poste de cada abertura corta.
	if palisade:
		var j := 0
		while j < n:
			if open[j] == 1 and open[posmod(j - 1, n)] == 0:
				var k := j
				while open[k % n] == 1 and k - j < n:
					k += 1
				if open[k % n] == 0 and points[j].distance_to(points[k % n]) < 9.0:
					var a := points[j]
					var b := points[k % n]
					var up := (a + b).normalized()
					rails.append(_beam(a + up * (GATE_HEIGHT - 0.35), b + up * (GATE_HEIGHT - 0.35), up, 0.16))
				j = k
			else:
				j += 1
	_instances(node, log_mesh(), logs)
	_instances(node, post_mesh(), posts)
	_instances(node, rail_mesh(), rails)
	_instances(node, leaf_mesh(), leaves)
	var body := StaticBody3D.new()
	for box: Array in boxes:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box[0]
		shape.shape = box_shape
		shape.transform = Transform3D(box[1], box[2])
		body.add_child(shape)
	for post in gate_posts:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(0.3, 2.0, 0.3)
		shape.shape = box_shape
		shape.transform = Transform3D(post.basis.orthonormalized(), post.origin + post.basis.y.normalized() * 1.5)
		body.add_child(shape)
	node.add_child(body)
	return node


## El suelo entre los vértices [a] y [b] en [t]: la recta, con el radio también interpolado.
static func _ground(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).normalized() * lerpf(a.length(), b.length(), t)


## Un poste (la malla de radio y alto 1) de radio [r] y alto [h] sobre el suelo en [at], enterrado.
static func _upright(at: Vector3, up: Vector3, r: float, h: float) -> Transform3D:
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized()
	return Transform3D(basis.scaled_local(Vector3(r, h + BURY, r)), at - up * BURY)


## Una vara (la malla de radio 1 a lo largo de Y, de 0 a 1) de [a] a [b], de radio [r].
static func _beam(a: Vector3, b: Vector3, up: Vector3, r: float) -> Transform3D:
	var axis := b - a
	var side := axis.cross(up).normalized()
	var normal := side.cross(axis).normalized()
	return Transform3D(Basis(side * r, axis, normal * r), a)


static func _instances(node: Node3D, mesh: Mesh, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = xforms.size()
	for i in xforms.size():
		multimesh.set_instance_transform(i, xforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	node.add_child(instance)


## Tronco de la empalizada: radio 1 y alto 1 (lo escala cada instancia), con la punta afilada.
static func log_mesh() -> ArrayMesh:
	if _log == null:
		var b := ProcMesh.Builder.new()
		_turned(b.st(WeaponMeshes.BARK), [Vector2(1.0, 0.0), Vector2(0.97, 0.9), Vector2(0.75, 0.93)], 8)
		_turned(b.st(WeaponMeshes.WOOD), [Vector2(0.75, 0.93), Vector2(0.0, 1.0)], 8)
		_log = b.commit(SurvivalMeshes.make_material)
	return _log


## Poste: radio 1 y alto 1, romo.
static func post_mesh() -> ArrayMesh:
	if _post == null:
		var b := ProcMesh.Builder.new()
		_turned(b.st(WeaponMeshes.BARK), [Vector2(1.0, 0.0), Vector2(0.95, 1.0)], 8)
		_post = b.commit(SurvivalMeshes.make_material)
	return _post


## Vara: radio 1 a lo largo de Y, de 0 a 1.
static func rail_mesh() -> ArrayMesh:
	if _rail == null:
		var b := ProcMesh.Builder.new()
		_turned(b.st(WeaponMeshes.BARK), [Vector2(1.0, 0.0), Vector2(1.0, 1.0)], 6)
		_rail = b.commit(SurvivalMeshes.make_material)
	return _rail


## Hoja de la puerta de la empalizada: tablones de 1,6 × 2,4 m con dos travesaños, con la bisagra en
## el origen y abierta hacia +Z (la hoja va a lo largo de Z, de -0,8 a 0,8 del centro que pone el poste).
static func leaf_mesh() -> ArrayMesh:
	if _leaf == null:
		var b := ProcMesh.Builder.new()
		var wood := b.st(WeaponMeshes.WOOD)
		for k in 7:
			ProcMesh.box(wood, Vector3(0.0, 1.2, -0.8 + 0.115 + k * 0.228), Vector3(0.08, 2.4 - (k % 2) * 0.08, 0.215))
		var dark := b.st(WeaponMeshes.DARK_WOOD)
		for y: float in [0.5, 1.9]:
			ProcMesh.box(dark, Vector3(0.07, y, 0.0), Vector3(0.06, 0.16, 1.6))
		_leaf = b.commit(SurvivalMeshes.make_material)
	return _leaf


## Superficie de revolución alrededor de +Y por el [profile] [(radio, y)], con las caras hacia fuera:
## un tubo vertical. ProcMesh.lathe las da al revés (sus mallas se cierran con commit(..., true)), y en
## estos builders van junto a cajas y tubos, que van del derecho.
static func _turned(st: SurfaceTool, profile: Array, segments: int) -> void:
	var points := PackedVector3Array()
	var radii := PackedVector2Array()
	for q: Vector2 in profile:
		points.append(Vector3(0.0, q.y, 0.0))
		radii.append(Vector2(q.x, q.x))
	ProcMesh.tube(st, points, radii, segments)
