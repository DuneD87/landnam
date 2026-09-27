class_name Ragdoll
extends SkeletonModifier3D

## Muñeco de trapo para caer muerto: un cuerpo rígido por segmento (pelvis, vientre, pecho,
## cabeza, brazos, antebrazos, muslos y piernas) unidos por articulaciones con los límites del
## cuerpo (codos y rodillas solo doblan hacia su lado, hombros y caderas en cono, la columna y
## el cuello poco). Mientras está activo, este modificador copia a los huesos el giro de cada
## cuerpo; las manos, los pies y los dedos siguen a su segmento con la pose que tenían.
##
## Los cuerpos van sueltos en el mundo (sin la escala del esqueleto, que va en centímetros) y la
## gravedad la pone quien lo activa (la del planeta). Arranca desde la pose que haya en ese
## instante, así que no hay salto.

## Signo del ángulo de flexión de Generic6DOFJoint3D (giro del segundo cuerpo sobre +X del joint).
const FLEX_SIGN := -1.0

## Capa de física propia (las partes chocan entre sí y con el suelo, no con el jugador).
const LAYER := 1 << 11

## [hueso, hueso hasta donde llega, radio (m), masa (kg), segmento padre, articulación]
## Articulación (grados): [&"cone", giro lateral máximo, torsión máxima], [&"hinge", dobla hasta]
## o [&"flex", hacia atrás, hacia delante, a los lados, torsión] (se dobla hacia delante mucho
## más que hacia atrás, como la cadera, la columna y el cuello).
const PARTS := [
	["mixamorig_Hips", "mixamorig_Spine1", 0.13, 12.0, "", []],
	["mixamorig_Spine1", "mixamorig_Spine2", 0.12, 9.0, "mixamorig_Hips", [&"flex", 10.0, 30.0, 14.0, 14.0]],
	["mixamorig_Spine2", "mixamorig_Neck", 0.14, 13.0, "mixamorig_Spine1", [&"flex", 6.0, 22.0, 10.0, 14.0]],
	["mixamorig_Head", "mixamorig_HeadTop_End", 0.095, 5.0, "mixamorig_Spine2", [&"flex", 25.0, 40.0, 30.0, 45.0]],
	["mixamorig_LeftArm", "mixamorig_LeftForeArm", 0.05, 2.5, "mixamorig_Spine2", [&"cone", 75.0, 40.0]],
	["mixamorig_LeftForeArm", "mixamorig_LeftHand", 0.042, 2.0, "mixamorig_LeftArm", [&"hinge", 140.0]],
	["mixamorig_RightArm", "mixamorig_RightForeArm", 0.05, 2.5, "mixamorig_Spine2", [&"cone", 75.0, 40.0]],
	["mixamorig_RightForeArm", "mixamorig_RightHand", 0.042, 2.0, "mixamorig_RightArm", [&"hinge", 140.0]],
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.075, 8.0, "mixamorig_Hips", [&"flex", 15.0, 105.0, 35.0, 25.0]],
	["mixamorig_LeftLeg", "mixamorig_LeftFoot", 0.055, 4.5, "mixamorig_LeftUpLeg", [&"hinge", 145.0]],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.075, 8.0, "mixamorig_Hips", [&"flex", 15.0, 105.0, 35.0, 25.0]],
	["mixamorig_RightLeg", "mixamorig_RightFoot", 0.055, 4.5, "mixamorig_RightUpLeg", [&"hinge", 145.0]],
]
## Piezas que van pegadas a un segmento sin articulación propia: [segmento, desde, hasta, radio].
const EXTRA_SHAPES := [
	["mixamorig_LeftForeArm", "mixamorig_LeftHand", "mixamorig_LeftHandMiddle2", 0.035],
	["mixamorig_RightForeArm", "mixamorig_RightHand", "mixamorig_RightHandMiddle2", 0.035],
	["mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase", 0.045],
	["mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase", 0.045],
]

## Nodo cuyo marco manda (+Z adelante, +Y arriba), para saber hacia dónde doblan codos y rodillas.
var frame_node: Node3D
## Gravedad en mundo (m/s²). La cambia quien lo lleva si cambia (planeta).
var gravity: Vector3 = Vector3(0, -9.8, 0)
## Máscara del suelo con el que choca.
var world_mask: int = 1
## Cuerpo que no debe tocar (el del jugador).
var exclude_body: PhysicsBody3D

var _skel: Skeleton3D
var _root: Node3D
var _bodies: Dictionary = {}
var _offsets: Dictionary = {}
var _order: Array[int] = []
var _bone_of: Dictionary = {}
var _running: bool = false
var _blend: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_skel = get_skeleton()
	active = false


func is_running() -> bool:
	return _running


## Arranca desde la pose actual. [velocity] la que llevaba el cuerpo; [push] un empujón (mundo,
## N·s) al pecho, p. ej. el del golpe que lo mata.
func start(velocity: Vector3 = Vector3.ZERO, push: Vector3 = Vector3.ZERO) -> void:
	if _running or _skel == null:
		return
	stop()
	_root = Node3D.new()
	_root.name = "RagdollBodies"
	_root.top_level = true
	add_child(_root)
	_root.global_transform = Transform3D.IDENTITY
	var skel_xf := _skel.global_transform
	var m := 1.0 / skel_xf.basis.get_scale().x
	for part in PARTS:
		var bone := _skel.find_bone(part[0])
		var tip := _skel.find_bone(part[1])
		if bone < 0 or tip < 0:
			continue
		var p0 := skel_xf * _skel.get_bone_global_pose(bone).origin
		var p1 := skel_xf * _skel.get_bone_global_pose(tip).origin
		var body := RigidBody3D.new()
		body.name = String(part[0]).trim_prefix("mixamorig_")
		body.mass = part[3]
		body.gravity_scale = 0.0
		body.linear_damp = 0.15
		body.angular_damp = 2.5
		body.collision_layer = LAYER
		body.collision_mask = world_mask | LAYER
		body.continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.friction = 1.0
		pm.rough = true
		pm.bounce = 0.05
		body.physics_material_override = pm
		body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		_root.add_child(body)
		body.global_transform = _segment_xform(p0, p1)
		_add_capsule(body, p0, p1, part[2])
		for extra in EXTRA_SHAPES:
			if extra[0] == part[0]:
				var a := _skel.find_bone(extra[1])
				var b := _skel.find_bone(extra[2])
				if a >= 0 and b >= 0:
					_add_capsule(body, skel_xf * _skel.get_bone_global_pose(a).origin,
						skel_xf * _skel.get_bone_global_pose(b).origin, extra[3])
		if exclude_body != null:
			body.add_collision_exception_with(exclude_body)
		_bodies[bone] = body
		_bone_of[body] = bone
		_offsets[bone] = body.global_transform.affine_inverse() * (skel_xf * _skel.get_bone_global_pose(bone))
		_order.append(bone)
		body.linear_velocity = velocity
	for part in PARTS:
		if part[4] == "":
			continue
		var bone := _skel.find_bone(part[0])
		var parent := _skel.find_bone(part[4])
		if _bodies.has(bone) and _bodies.has(parent):
			_join(_bodies[parent], _bodies[bone], bone, part[5], skel_xf)
	var chest := _skel.find_bone("mixamorig_Spine2")
	if push != Vector3.ZERO and _bodies.has(chest):
		(_bodies[chest] as RigidBody3D).apply_central_impulse(push)
	_running = true
	_blend = 0.0
	_time = 0.0
	active = true


## Dónde está el muñeco (la pelvis), en mundo.
func center() -> Vector3:
	for body in _bone_of:
		if _bone_of[body] == _skel.find_bone("mixamorig_Hips") and is_instance_valid(body):
			return (body as Node3D).global_position
	return _skel.global_position


func stop() -> void:
	_running = false
	active = false
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_bodies.clear()
	_offsets.clear()
	_order.clear()
	_bone_of.clear()


## Cuerpo con +Y a lo largo del segmento y el origen en su centro.
static func _segment_xform(p0: Vector3, p1: Vector3) -> Transform3D:
	var y := (p1 - p0).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), (p0 + p1) * 0.5)


func _add_capsule(body: RigidBody3D, p0: Vector3, p1: Vector3, radius: float) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(p0.distance_to(p1) + radius * 2.0 * 0.6, radius * 2.0 + 0.01)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	col.global_transform = _segment_xform(p0, p1)


## Articulación entre [parent] y [child] en el origen del hueso [bone].
func _join(parent: RigidBody3D, child: RigidBody3D, bone: int, spec: Array, skel_xf: Transform3D) -> void:
	var pivot := skel_xf * _skel.get_bone_global_pose(bone).origin
	var dir := (child.global_transform.basis.y).normalized()
	var joint: Joint3D
	if spec[0] == &"hinge":
		# Eje de la bisagra: el del reposo (el segmento dobla hacia delante el codo y hacia
		# atrás la rodilla), girado como está ahora el segmento de arriba.
		var parent_bone := _skel.get_bone_parent(bone)
		var rest_dir := (_skel.get_bone_global_rest(_skel.find_bone(_tip_of(bone))).origin - _skel.get_bone_global_rest(bone).origin).normalized()
		var bend := _model_dir(Vector3.BACK if "Arm" in _skel.get_bone_name(bone) else Vector3.FORWARD)
		var axis_rest := rest_dir.cross(bend).normalized()
		var delta := (_skel.get_bone_global_pose(parent_bone).basis.orthonormalized()
			* _skel.get_bone_global_rest(parent_bone).basis.orthonormalized().inverse())
		var axis := (skel_xf.basis.orthonormalized() * (delta * axis_rest)).normalized()
		var parent_dir := parent.global_transform.basis.y.normalized()
		var flexed := rad_to_deg(parent_dir.angle_to(dir))
		var hinge := HingeJoint3D.new()
		var z := axis
		var x := (dir - z * dir.dot(z)).normalized()
		hinge.global_transform = Transform3D(Basis(x, z.cross(x), z), pivot)
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-flexed - 2.0))
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(spec[1] - flexed))
		joint = hinge
	elif spec[0] == &"flex":
		# X: eje de flexión (girar el hijo sobre +X lo lleva hacia delante), Y: a lo largo del
		# hijo (torsión), Z: doblarse de lado.
		var fwd := (skel_xf.basis.orthonormalized() * _model_dir(Vector3.BACK)).normalized()
		var y := dir
		var x := y.cross(fwd)
		if x.length_squared() < 1e-6:
			x = (skel_xf.basis.orthonormalized() * _model_dir(Vector3.RIGHT)).normalized()
		x = x.normalized()
		var six := Generic6DOFJoint3D.new()
		six.global_transform = Transform3D(Basis(x, y, x.cross(y)), pivot)
		six.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		six.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		six.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		six.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-spec[1] * FLEX_SIGN))
		six.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(spec[2] * FLEX_SIGN))
		if FLEX_SIGN < 0.0:
			six.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-spec[2]))
			six.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(spec[1]))
		six.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-spec[4]))
		six.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(spec[4]))
		six.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-spec[3]))
		six.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(spec[3]))
		joint = six
	else:
		var cone := ConeTwistJoint3D.new()
		# El eje de torsión (X del joint) a lo largo del segmento hijo.
		var x := dir
		var y := x.cross(Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT).normalized()
		cone.global_transform = Transform3D(Basis(x, y, x.cross(y)), pivot)
		cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(spec[1]))
		cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(spec[2]))
		joint = cone
	_root.add_child(joint)
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(child)


func _tip_of(bone: int) -> String:
	for part in PARTS:
		if _skel.find_bone(part[0]) == bone:
			return part[1]
	return _skel.get_bone_name(bone)


func _model_dir(model_axis: Vector3) -> Vector3:
	var basis := frame_node.global_basis if frame_node != null else _skel.global_basis
	return (_skel.global_basis.inverse() * (basis * model_axis)).normalized()


## Tras la caída el cuerpo se asienta: la carne roza y no rueda como un saco de canicas (en
## una ladera, sin esto, resbala metros).
const SETTLE := Vector2(0.9, 2.2)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_time += delta
	var settle := smoothstep(SETTLE.x, SETTLE.y, _time)
	for body in _bone_of:
		var rb := body as RigidBody3D
		if rb.freeze:
			continue
		rb.apply_central_force(gravity * rb.mass)
		rb.linear_damp = lerpf(0.15, 4.0, settle)
		rb.angular_damp = lerpf(2.5, 9.0, settle)
		# Ya en el suelo y casi quieto: se queda donde está.
		if settle >= 1.0 and rb.linear_velocity.length() < 0.6:
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = true


func _process_modification_with_delta(delta: float) -> void:
	if not _running:
		return
	_blend = minf(1.0, _blend + delta / 0.08)
	var inv := _skel.global_transform.affine_inverse()
	for bone in _order:
		var body: RigidBody3D = _bodies[bone]
		if not is_instance_valid(body):
			continue
		var offset: Transform3D = _offsets[bone]
		var want: Transform3D = inv * (body.get_global_transform_interpolated() * offset)
		var parent := _skel.get_bone_parent(bone)
		var local: Transform3D = want
		if parent >= 0:
			local = _skel.get_bone_global_pose(parent).affine_inverse() * want
		else:
			_skel.set_bone_pose_position(bone, _skel.get_bone_pose_position(bone).lerp(local.origin, _blend))
		var q: Quaternion = local.basis.orthonormalized().get_rotation_quaternion()
		_skel.set_bone_pose_rotation(bone, _skel.get_bone_pose_rotation(bone).slerp(q, _blend))
