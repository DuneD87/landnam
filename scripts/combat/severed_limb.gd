class_name SeveredLimb
extends Node3D

## Un miembro cercenado: lo que LimbCutter ha separado del cuerpo (piel, armadura y la tapa del
## corte), con piel sobre una copia del esqueleto en la pose del instante del corte. Lo mueve un
## muñeco de trapo (Ragdoll) solo de sus segmentos, que empieza en el corte: un brazo entero dobla
## el codo al caer y una pierna, la rodilla. Gotea por el corte unos segundos y, cuando se queda
## quieto, deja debajo un charco que se va extendiendo. Se va pasado un rato, como los cadáveres.

const LIFETIME := 120.0
## Los que caben a la vez en el mundo: al pasar, se va el más viejo.
const MAX_ALIVE := 10
## Goteo por el corte: cuánto dura (s) y cada cuánto sale una gota (s).
const DRIP_TIME := 5.0
const DRIP_EVERY := 0.22
## El charco: tras cuánto quieto sale (s), su tamaño (m) y lo que tarda en extenderse (s).
const POOL_AFTER := 0.8
const POOL_SIZE := Vector2(0.8, 1.3)
const POOL_GROW := 10.0

static var _alive: Array[SeveredLimb] = []

## La copia del esqueleto que mueve sus mallas, y el muñeco que la mueve.
var skeleton: Skeleton3D
var ragdoll: Ragdoll
var _gravity := Vector3.ZERO
var _world_mask := 1
var _time := 0.0
var _drip := 0.0
var _still := 0.0
var _pool: BloodPool
## El segmento del corte y, en su marco, el centro del corte y hacia dónde mira (fuera del miembro).
var _cut_body: RigidBody3D
var _cut_point := Vector3.ZERO
var _cut_dir := Vector3.ZERO


## Suelta en [host] las mallas [parts] ({mesh, skin, transform (respecto al esqueleto),
## material_override}) cortadas de [source] por el hueso [cut_bone]. [chain]: los segmentos del
## Ragdoll que se llevan; [cut_point] y [cut_dir] (mundo): el centro del corte y hacia dónde mira,
## fuera del miembro. [frame_node] es el marco del cuerpo de donde sale (hacia dónde doblan codos
## y rodillas). Sale con [velocity].
static func spawn(host: Node, source: Skeleton3D, frame_node: Node3D, parts: Array,
		cut_bone: StringName, chain: PackedStringArray, cut_point: Vector3, cut_dir: Vector3,
		velocity: Vector3, gravity: Vector3, world_mask: int, exclude: PhysicsBody3D) -> SeveredLimb:
	var limb := SeveredLimb.new()
	limb.name = "SeveredLimb"
	limb._gravity = gravity
	limb._world_mask = world_mask
	host.add_child(limb, true)
	limb.add_to_group(&"floating_origin")

	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for b in source.get_bone_count():
		skel.add_bone(source.get_bone_name(b))
	for b in source.get_bone_count():
		skel.set_bone_parent(b, source.get_bone_parent(b))
		skel.set_bone_rest(b, source.get_bone_rest(b))
	limb.add_child(skel)
	skel.global_transform = source.global_transform
	for b in source.get_bone_count():
		var pose := source.get_bone_global_pose(b)
		var parent := source.get_bone_parent(b)
		if parent >= 0:
			pose = source.get_bone_global_pose(parent).affine_inverse() * pose
		skel.set_bone_pose_position(b, pose.origin)
		skel.set_bone_pose_rotation(b, pose.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(b, pose.basis.get_scale())
	for part: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		mi.skin = part.skin
		mi.material_override = part.material_override
		skel.add_child(mi)
		mi.transform = part.transform
	limb.skeleton = skel

	var rd := Ragdoll.new()
	rd.name = "Ragdoll"
	rd.frame_node = frame_node
	rd.gravity = gravity
	rd.world_mask = world_mask
	rd.exclude_body = exclude
	rd.only_parts = chain
	rd.root_bones = PackedStringArray([cut_bone])
	rd.segment_start = {String(cut_bone): cut_point}
	skel.add_child(rd)
	rd.start(velocity)
	limb.ragdoll = rd
	for body: RigidBody3D in rd.bodies():
		body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 5.0
	limb._cut_body = rd.body_for(cut_bone)
	if limb._cut_body != null:
		limb._cut_point = limb._cut_body.global_transform.affine_inverse() * cut_point
		limb._cut_dir = limb._cut_body.global_basis.inverse() * cut_dir

	# Fuera los que ya se han ido. Sin filter: un liberado no entra en un parámetro tipado.
	for i in range(_alive.size() - 1, -1, -1):
		if not is_instance_valid(_alive[i]):
			_alive.remove_at(i)
	_alive.append(limb)
	while _alive.size() > MAX_ALIVE:
		_alive.pop_front().queue_free()
	return limb


func _process(delta: float) -> void:
	_time += delta
	if _time >= LIFETIME:
		queue_free()
		return
	if _cut_body == null or not is_instance_valid(_cut_body):
		return
	var point := _cut_body.global_transform * _cut_point
	if _time < DRIP_TIME:
		_drip -= delta
		if _drip <= 0.0:
			_drip = DRIP_EVERY * randf_range(0.7, 1.3)
			CombatFx.spurt(self, point, (_cut_body.global_basis * _cut_dir).normalized(),
					(1.0 - _time / DRIP_TIME) * 0.6)
	if _pool != null:
		return
	if _cut_body.freeze or _cut_body.linear_velocity.length() < 0.2:
		_still += delta
	else:
		_still = 0.0
	if _still >= POOL_AFTER:
		_pool = BloodPool.spawn(self, point, _gravity, randf_range(POOL_SIZE.x, POOL_SIZE.y),
				POOL_GROW, _world_mask)
		# Sin suelo debajo (se ha caído al agua, a un hueco) no lo vuelve a intentar.
		_still = -INF
