class_name SeveredLimb
extends Node3D

## Un miembro cercenado: lo que LimbCutter ha separado del cuerpo (piel, armadura y la tapa del
## corte), con piel sobre una copia del esqueleto en la pose del instante del corte. Lo mueve un
## muñeco de trapo (Ragdoll) solo de sus segmentos, que empieza en el corte: un brazo entero dobla
## el codo al caer y una pierna, la rodilla. Gotea por el corte unos segundos y, cuando se queda
## quieto, deja debajo un charco que se va extendiendo. Se va pasado un rato, como los cadáveres.
## Uno que se queda (keep(): lo que una fiera arranca a los restos del jugador, PlayerRemains) no se
## va, y al asentarse deja de moverlo el muñeco (settle()).

const LIFETIME := 120.0
## Uno que se queda: a los cuántos segundos se deja quieto del todo.
const KEPT_SETTLE := 8.0
## Al agarrarlo con la boca (grab), lo que tarda el corte en llegar a ella (s).
const HOLD_SNAP := 0.15
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
## El hueso por el que se cortó.
var cut_bone := &""
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
var _kept := false
var _settled := false
## Quien lo lleva en la boca (grab): da cada fotograma dónde está la boca (mundo).
var _holder := Callable()
var _holding := false
var _hold_blend := 0.0
var _hold_from := Transform3D()
## El giro del segmento del corte respecto a la boca, al agarrarlo.
var _hold_turn := Basis()


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
	limb.cut_bone = cut_bone
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


## Lo lleva una fiera en la boca por el corte: [holder] da cada fotograma dónde está la boca
## (mundo). El segmento del corte va con ella (cinemático: llega en HOLD_SNAP) y lo demás cuelga
## del muñeco. release() lo suelta.
func grab(holder: Callable) -> void:
	if _cut_body == null or not is_instance_valid(_cut_body) or ragdoll == null:
		return
	var mouth: Transform3D = holder.call()
	_holder = holder
	_holding = true
	_hold_blend = 0.0
	_hold_from = _cut_body.global_transform
	_hold_turn = mouth.basis.orthonormalized().inverse() * _cut_body.global_basis.orthonormalized()
	_cut_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_cut_body.freeze = true
	ragdoll.wake()


## Lo suelta con [velocity] (m/s).
func release(velocity := Vector3.ZERO) -> void:
	if not _holding:
		return
	_holding = false
	_holder = Callable()
	if _cut_body != null and is_instance_valid(_cut_body):
		_cut_body.freeze = false
		_cut_body.linear_velocity = velocity
	_still = 0.0
	if ragdoll != null:
		ragdoll.wake()


func _physics_process(delta: float) -> void:
	if not _holding:
		return
	# Quien lo llevaba ya no está: se cae.
	if not _holder.is_valid() or _cut_body == null or not is_instance_valid(_cut_body):
		release()
		return
	var mouth: Transform3D = _holder.call()
	_hold_blend = minf(_hold_blend + delta / HOLD_SNAP, 1.0)
	# El corte, en la boca.
	var basis := mouth.basis.orthonormalized() * _hold_turn
	var want := Transform3D(basis, mouth.origin - basis * _cut_point)
	_cut_body.global_transform = _hold_from.interpolate_with(want, smoothstep(0.0, 1.0, _hold_blend))


## Cómo ha quedado, para guardarlo (PlayerRemains): el sitio de su esqueleto respecto a [frame] y
## el giro de cada hueso de lo cortado. Lo que da es lo que sale de la animación: vale una vez quieto
## (settle()).
func saved_pose(frame: Transform3D) -> Dictionary:
	var poses := {}
	var root := skeleton.find_bone(cut_bone)
	for b in skeleton.get_bone_count():
		if b == root or _below(b, root):
			var origin := skeleton.get_bone_pose_position(b)
			var rotation := skeleton.get_bone_pose_rotation(b)
			poses[String(skeleton.get_bone_name(b))] = [origin.x, origin.y, origin.z,
				rotation.x, rotation.y, rotation.z, rotation.w]
	var xf := frame.affine_inverse() * skeleton.global_transform
	return {xform = [xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z,
		xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z], poses = poses}


## Lo deja como estaba guardado ([data], de saved_pose(), respecto a [frame]): quieto, sin muñeco,
## y se queda.
func place(frame: Transform3D, data: Dictionary) -> void:
	keep()
	_settled = true
	if ragdoll != null:
		ragdoll.stop()
	_cut_body = null
	var x: Array = data.get("xform", [])
	if x.size() == 12:
		skeleton.global_transform = frame * Transform3D(Basis(Vector3(x[0], x[1], x[2]), Vector3(x[3], x[4], x[5]),
			Vector3(x[6], x[7], x[8])), Vector3(x[9], x[10], x[11]))
	var poses: Dictionary = data.get("poses", {})
	for bone_name in poses:
		var b := skeleton.find_bone(bone_name)
		var p: Array = poses[bone_name]
		if b >= 0 and p.size() == 7:
			skeleton.set_bone_pose_position(b, Vector3(p[0], p[1], p[2]))
			skeleton.set_bone_pose_rotation(b, Quaternion(p[3], p[4], p[5], p[6]).normalized())
	set_process(false)


func _below(bone: int, ancestor: int) -> bool:
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		if parent == ancestor:
			return true
		parent = skeleton.get_bone_parent(parent)
	return false


## Se queda en el mundo: ni caduca ni cuenta para MAX_ALIVE.
func keep() -> void:
	_kept = true
	_alive.erase(self)


## Lo deja quieto donde está: la pose que le ha dado el muñeco pasa al esqueleto y el muñeco se va
## (sin cuerpos que simular ni huesos que mover cada fotograma, ni nada que se caiga si el suelo
## deja de tener colisión al irse el jugador). Fuera del modificador el esqueleto da la pose sin él:
## se lee al actualizarse (skeleton_updated).
func settle() -> void:
	# En la boca de una fiera no: se asienta solo (KEPT_SETTLE) cuando la suelte.
	if _settled or ragdoll == null or not ragdoll.is_running() or _holding:
		return
	_settled = true
	skeleton.skeleton_updated.connect(_on_settle_pose, CONNECT_ONE_SHOT)


func _on_settle_pose() -> void:
	var poses: Array[Transform3D] = []
	for b in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(b))
	_keep_pose.call_deferred(poses)


func _keep_pose(poses: Array[Transform3D]) -> void:
	ragdoll.stop()
	_cut_body = null
	for b in poses.size():
		skeleton.set_bone_pose_position(b, poses[b].origin)
		skeleton.set_bone_pose_rotation(b, poses[b].basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(b, poses[b].basis.get_scale())
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	if _kept:
		if _time >= KEPT_SETTLE:
			settle()
	elif _time >= LIFETIME:
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
