class_name SeveredChunk
extends RigidBody3D

## Un trozo cercenado de un animal (pata, cabeza, cola): lo que LimbCutter ha separado, horneado en
## la pose del instante del corte (la piel aplicada aquí, sin esqueleto) y suelto como un cuerpo
## rígido. Los esqueletos de los animales no tienen muñeco de trapo, y un tramo de pata o una cabeza
## caen bien de una pieza. Gotea por el corte, deja charco al pararse y se va como los cadáveres.

const LIFETIME := 120.0
const MAX_ALIVE := 10
const DRIP_TIME := 5.0
const DRIP_EVERY := 0.22
const POOL_AFTER := 0.8
const POOL_GROW := 10.0
## Densidad para la masa (kg/m³ de la caja que lo envuelve, que es más grande que el trozo).
const DENSITY := 500.0

static var _alive: Array[SeveredChunk] = []

var _gravity := Vector3.ZERO
var _world_mask := 1
var _time := 0.0
var _drip := 0.0
var _still := 0.0
var _pool: BloodPool
var _pool_size := 1.0
## Centro del corte y hacia dónde mira (fuera del trozo), en el marco del cuerpo.
var _cut_point := Vector3.ZERO
var _cut_dir := Vector3.ZERO


## Suelta en [host] las mallas [parts] ({mesh, skin, material_override}) del esqueleto [source],
## horneadas en su pose actual, y los nodos [extras] (mallas sueltas que iban pegadas a lo cortado,
## como los cuernos: se duplican). [cut_point]/[cut_dir] (mundo) son el centro del corte y hacia
## dónde mira, fuera del trozo. Sale con [velocity].
static func spawn(host: Node, source: Skeleton3D, parts: Array, extras: Array[Node3D], cut_point: Vector3,
		cut_dir: Vector3, velocity: Vector3, gravity: Vector3, world_mask: int, exclude: PhysicsBody3D) -> SeveredChunk:
	if gravity.length_squared() < 1e-6:
		return null
	var baked: Array = []
	var box := AABB()
	var first := true
	for part: Dictionary in parts:
		var mesh := _bake(part.mesh, part.skin, source)
		if mesh == null:
			continue
		baked.append([mesh, part.material_override])
		box = mesh.get_aabb() if first else box.merge(mesh.get_aabb())
		first = false
	if baked.is_empty():
		return null
	var chunk := SeveredChunk.new()
	chunk.name = "SeveredChunk"
	chunk._gravity = gravity
	chunk._world_mask = world_mask
	chunk.collision_layer = 0
	chunk.collision_mask = world_mask
	chunk.continuous_cd = true
	chunk.gravity_scale = 0.0
	host.add_child(chunk, true)
	chunk.add_to_group(&"floating_origin")
	var center := box.get_center()
	chunk.global_transform = Transform3D(Basis.IDENTITY, center)
	for entry: Array in baked:
		var mi := MeshInstance3D.new()
		mi.mesh = entry[0]
		mi.material_override = entry[1]
		chunk.add_child(mi)
		mi.position = -center
	for node in extras:
		var copy := node.duplicate() as Node3D
		chunk.add_child(copy)
		copy.global_transform = node.global_transform
		copy.visible = true
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = (box.size * 0.8).max(Vector3.ONE * 0.06)
	shape.shape = bshape
	chunk.add_child(shape)
	chunk.mass = clampf(bshape.size.x * bshape.size.y * bshape.size.z * DENSITY, 1.0, 120.0)
	chunk._pool_size = clampf(box.size.length() * 0.9, 0.6, 1.8)
	if exclude != null:
		chunk.add_collision_exception_with(exclude)
	chunk.linear_velocity = velocity
	chunk.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	chunk._cut_point = chunk.global_transform.affine_inverse() * cut_point
	chunk._cut_dir = chunk.global_basis.inverse() * cut_dir
	_alive = _alive.filter(func(other: SeveredChunk) -> bool: return is_instance_valid(other))
	_alive.append(chunk)
	while _alive.size() > MAX_ALIVE:
		_alive.pop_front().queue_free()
	return chunk


## Matrices de piel de [skin] en la pose actual de [skel], en mundo (para bake_surface).
static func pose_matrices(skin: Skin, skel: Skeleton3D) -> Array[Transform3D]:
	var matrices: Array[Transform3D] = []
	if skin == null:
		return matrices
	for b in skin.get_bind_count():
		var bind_name := skin.get_bind_name(b)
		var bone := skel.find_bone(bind_name) if bind_name != &"" else skin.get_bind_bone(b)
		var pose := skel.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
		matrices.append(skel.global_transform * pose * skin.get_bind_pose(b))
	return matrices


## La superficie [surface] (de LimbCutter) con la piel aplicada con [matrices]: posiciones y
## normales en mundo, sin huesos ni blend shapes. No toca nada del árbol: puede ir en un hilo.
static func bake_surface(surface: Dictionary, matrices: Array[Transform3D]) -> Dictionary:
	var arrays: Array = (surface.arrays as Array).duplicate()
	var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var normals: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() \
		if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	if not verts.is_empty() and not bones.is_empty():
		var wc := bones.size() / verts.size()
		for i in verts.size():
			var bx := Vector3.ZERO
			var by := Vector3.ZERO
			var bz := Vector3.ZERO
			var origin := Vector3.ZERO
			var total := 0.0
			for k in wc:
				var w := weights[i * wc + k]
				var bi := bones[i * wc + k]
				if w <= 0.0 or bi < 0 or bi >= matrices.size():
					continue
				var m := matrices[bi]
				bx += m.basis.x * w
				by += m.basis.y * w
				bz += m.basis.z * w
				origin += m.origin * w
				total += w
			if total <= 0.0:
				continue
			var xf := Transform3D(Basis(bx / total, by / total, bz / total), origin / total)
			verts[i] = xf * verts[i]
			if i < normals.size():
				normals[i] = (xf.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not normals.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = null
	arrays[Mesh.ARRAY_WEIGHTS] = null
	var out := surface.duplicate()
	out.arrays = arrays
	out.blend = []
	out.flags = 0
	return out


## [mesh] con piel [skin] puesta en la pose actual de [skel], en mundo; sin piel, tal cual (ya
## horneada en el hilo del corte).
static func _bake(mesh: Mesh, skin: Skin, skel: Skeleton3D) -> ArrayMesh:
	if mesh == null:
		return null
	if skin == null:
		return mesh as ArrayMesh
	var matrices := pose_matrices(skin, skel)
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var surface := {arrays = mesh.surface_get_arrays(s)}
		var baked := bake_surface(surface, matrices)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, baked.arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out if out.get_surface_count() > 0 else null


func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= LIFETIME:
		queue_free()
		return
	var point := global_transform * _cut_point
	if _time < DRIP_TIME:
		_drip -= delta
		if _drip <= 0.0:
			_drip = DRIP_EVERY * randf_range(0.7, 1.3)
			CombatFx.spurt(self, point, (global_basis * _cut_dir).normalized(), (1.0 - _time / DRIP_TIME) * 0.6)
	if _pool != null:
		return
	if linear_velocity.length() < 0.2:
		_still += delta
	else:
		_still = 0.0
	if _still >= POOL_AFTER:
		_pool = BloodPool.spawn(self, point, _gravity, _pool_size, POOL_GROW, _world_mask)
		_still = -INF


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# La gravedad del planeta, no la del proyecto.
	state.linear_velocity += _gravity * state.step
