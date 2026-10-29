class_name BoatAnchor
extends Node3D

## Ancla y cabo que bajan por la proa al fondear. Solo decoran: la sujeción la da
## DynamicGridBody._apply_anchor. La proa sale de las cajas de colisión del casco (espacio local del
## body, proa +Z), así que vale para cualquier barco construido.
## Segundos en echar el ancla y en levarla (se iza a mano, más despacio).
const DROP_TIME := 1.8
const WEIGH_TIME := 3.0
## Lo que el ancla baja por debajo de la quilla (queda bajo el agua) y lo que se adelanta a la proa.
const BELOW_KEEL := 2.5
const AHEAD := 0.8
## Ancla colgada del escobén antes de soltarla.
const HANG := 0.9
const ROPE_RADIUS := 0.03

var anchored := false
var _progress := 0.0
var _hull_version := -1
var _hawse := Vector3.ZERO
var _seabed := Vector3.ZERO
var _anchor: MeshInstance3D
var _rope: MeshInstance3D
static var _anchor_mesh: ArrayMesh
static var _rope_mesh: ArrayMesh


func _ready() -> void:
	name = "Anchor"
	visible = false
	set_process(false)
	_anchor = MeshInstance3D.new()
	_anchor.mesh = anchor_mesh()
	add_child(_anchor)
	_rope = MeshInstance3D.new()
	_rope.mesh = rope_mesh()
	add_child(_rope)


func update(value: bool, box_pos: PackedVector3Array, box_half: PackedVector3Array, hull_version: int) -> void:
	if hull_version != _hull_version:
		_hull_version = hull_version
		var points := hawse_points(box_pos, box_half)
		_hawse = points[0]
		_seabed = points[1]
		_pose()
	if value == anchored:
		return
	anchored = value
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	var target := 1.0 if anchored else 0.0
	_progress = move_toward(_progress, target, delta / (DROP_TIME if anchored else WEIGH_TIME))
	_pose()
	if _progress == target:
		set_process(false)
		visible = anchored


func _pose() -> void:
	var hanging := _hawse + Vector3.DOWN * HANG
	# Cae acelerando y sube a ritmo constante de quien tira del cabo.
	var t := _progress * _progress if anchored else _progress
	var ring := hanging.lerp(_seabed, t)
	_anchor.position = ring
	var span := ring - _hawse
	var side := span.cross(Vector3.BACK)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	_rope.transform = Transform3D(Basis(side, span, side.cross(span).normalized()), _hawse)


## [escobén, ancla en el fondo]: el escobén en lo alto de la proa, centrado en las cajas que la forman.
static func hawse_points(box_pos: PackedVector3Array, box_half: PackedVector3Array) -> Array[Vector3]:
	if box_pos.is_empty():
		return [Vector3.ZERO, Vector3.DOWN * BELOW_KEEL]
	var bow := -INF
	var keel := INF
	for k in box_pos.size():
		bow = maxf(bow, box_pos[k].z + box_half[k].z)
		keel = minf(keel, box_pos[k].y - box_half[k].y)
	var top := -INF
	var x_sum := 0.0
	var count := 0
	for k in box_pos.size():
		if box_pos[k].z + box_half[k].z < bow - 0.5:
			continue
		top = maxf(top, box_pos[k].y + box_half[k].y)
		x_sum += box_pos[k].x
		count += 1
	var hawse := Vector3(x_sum / count, top + 0.05, bow + 0.1)
	return [hawse, Vector3(hawse.x, keel - BELOW_KEEL, bow + AHEAD)]


## Ancla de hierro con cepo de madera, colgada de la argolla (origen) hacia -Y.
static func anchor_mesh() -> ArrayMesh:
	if _anchor_mesh:
		return _anchor_mesh
	var b := ProcMesh.Builder.new()
	var iron := b.st(WeaponMeshes.IRON)
	ProcMesh.tube(iron, PackedVector3Array([Vector3(0, -0.08, 0), Vector3(0, -1.3, 0)]),
		PackedVector2Array([Vector2(0.045, 0.045), Vector2(0.055, 0.055)]), 8)
	var ring := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in 13:
		var a := TAU * i / 12.0
		ring.append(Vector3(0, 0.03 + cos(a) * 0.11, sin(a) * 0.11))
		radii.append(Vector2(0.022, 0.022))
	ProcMesh.tube(iron, ring, radii, 6, Vector3.RIGHT, false)
	for side: float in [-1.0, 1.0]:
		var arm := PackedVector3Array()
		var arm_radii := PackedVector2Array()
		for i in 7:
			var a := PI * 0.5 * i / 6.0
			arm.append(Vector3(side * sin(a) * 0.55, -1.3 + (1.0 - cos(a)) * 0.45, 0))
			arm_radii.append(Vector2(0.045, 0.045).lerp(Vector2(0.03, 0.03), i / 6.0))
		ProcMesh.tube(iron, arm, arm_radii, 8)
		# Uña: pala triangular en la punta del brazo, abierta hacia fuera.
		var tip := Vector3(side * 0.55, -0.85, 0)
		ProcMesh.box(iron, tip + Vector3(side * -0.05, -0.08, 0), Vector3(0.05, 0.26, 0.24),
			Basis(Vector3.BACK, side * 0.35))
	var wood := b.st(WeaponMeshes.DARK_WOOD)
	ProcMesh.box(wood, Vector3(0, -0.22, 0), Vector3(0.09, 0.09, 1.1))
	ProcMesh.set_flat(wood, true)
	_anchor_mesh = b.commit(WeaponMeshes.make_material)
	return _anchor_mesh


## Cabo de 1 m a lo largo de +Y: se escala en Y hasta el ancla.
static func rope_mesh() -> ArrayMesh:
	if _rope_mesh:
		return _rope_mesh
	var b := ProcMesh.Builder.new()
	ProcMesh.lathe(b.st(WeaponMeshes.CORD), [Vector2(ROPE_RADIUS, 0.0), Vector2(ROPE_RADIUS, 1.0)], 6,
		Vector3.ZERO, 1.0, 12.0)
	_rope_mesh = b.commit(WeaponMeshes.make_material)
	return _rope_mesh
