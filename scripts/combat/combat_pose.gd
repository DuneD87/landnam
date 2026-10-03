class_name CombatPose
extends SkeletonModifier3D

## Poses de combate que el esqueleto Mixamo no trae animadas, montadas por código sobre la
## animación que esté sonando:
##   - ovillo al rodar (pose absoluta, no sumada a la animación; el giro y el apoyo en el suelo
##     los pone RollMotion sobre PlayerModel),
##   - apuntar con arco, tirachinas o lanza (torso de perfil y brazos por IK de dos huesos hacia
##     el blanco y la mejilla),
##   - caída al morir (brazos abiertos y cabeza ladeada; el vuelco lo pone PlayerCombat).
##
## Todos los giros se expresan en el marco del modelo (adelante +Z, arriba +Y, +X a la izquierda
## del personaje) y se convierten al del esqueleto, así que no dependen de los ejes de cada hueso.
## Después de posar llama a [after_pose], donde el dueño coloca el arco, la flecha o la lanza
## sobre las manos ya resueltas.

## Marco de agarre en la mano derecha (hueso RightHandMiddle2, que va en centímetros): el +Y
## del arma (hacia la punta) sale por el lado del pulgar, el +Z (filo) hacia el dorso de la
## mano. Medido sobre cómo sujeta el rig el hacha y el pico de piedra que ya existían.
const RIGHT_GRIP := Transform3D(Basis(Vector3(0, 0, 100), Vector3(100, 0, 0), Vector3(0, 100, 0)), Vector3(-1.5, -2.0, 1.0))
## Lo mismo en la izquierda: el rig refleja el eje X de los huesos del lado izquierdo.
const LEFT_GRIP := Transform3D(Basis(Vector3(0, 0, -100), Vector3(-100, 0, 0), Vector3(0, 100, 0)), Vector3(1.5, -2.0, 1.0))

const B_HIPS := "mixamorig_Hips"
const SPINE := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
const NECK := ["mixamorig_Neck", "mixamorig_Head"]
const L_ARM := ["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"]
const R_ARM := ["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"]
const L_LEG := ["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot"]
const R_LEG := ["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"]

## Nodo cuyo marco manda (PlayerModel): +Z adelante, +Y arriba.
var frame_node: Node3D

## 0..1 cuánto ovillo (agachada del paso atrás).
var tuck: float = 0.0
## Fase de la voltereta (0..1), o negativo si no está rodando. Ver RollMotion.
var roll_x: float = -1.0
## Rueda sobre el hombro izquierdo en vez del derecho.
var roll_mirror: bool = false
## 0..1 cuánto manda la pose de apuntar.
var aim_weight: float = 0.0
## Dirección de tiro en mundo (normalizada).
var aim_dir: Vector3 = Vector3.FORWARD
## 0..1 tensión (arco/tirachinas) o carga del lanzamiento.
var draw: float = 0.0
## &"bow", &"sling" o &"throw".
var aim_style: StringName = &"bow"
## 0..1 avance del brazo al soltar la lanza.
var release: float = 0.0
## Brazos por IK al apuntar. Con una animación de apuntar (arco, lanza) va apagado y solo se
## inclina el tronco hacia el blanco, sobre la pose de la animación.
var aim_arms_ik: bool = true
## Giro (grados, marco del modelo) de la cadera en la animación de tronco que suena, o NAN si
## no hay. Ese canal no mueve la cadera (las piernas siguen andando), así que el tronco se
## lleva a donde lo tendría sobre la cadera de la animación: el arquero y el lanzador se ponen
## de perfil como en el original.
var upper_hips_yaw: float = NAN
## 0..1 pose de muerto.
var death: float = 0.0
## Movimiento de cuerpo entero en curso (BodyMotion.STAGGER o BACKSTEP), su fase 0..1 (o
## negativa si no hay), hacia dónde se mueve el cuerpo (marco del modelo, horizontal), cuántos
## metros recorre, cuánta fuerza (escala los gestos) y qué pie da el primer paso.
var motion: Dictionary = {}
var motion_x: float = -1.0
var motion_push: Vector3 = Vector3.FORWARD
var motion_distance: float = 0.0
var motion_power: float = 1.0
var motion_left_first: bool = true
var motion_travel: Callable = BodyMotion.stagger_travel

## Ciclo del arquero (arco con los brazos por IK).
var archery := ArcheryPose.new()
## Lanzamiento de lanza por IK.
var throw := ThrowPose.new()
## Arco con las animaciones de Mixamo (con aim_arms_ik apagado): coloca arco, cuerda y flecha.
var bow_rig := BowAnimRig.new()

## Arma de combate en la mano derecha: los dedos cierran el puño alrededor del mango y
## right_grip_xform (mundo) dice dónde va el marco de agarre del arma (+Y hacia la punta, +Z
## hacia donde mira el filo), respecto a la palma y no a un dedo.
var grip_right: bool = false
var right_grip_xform: Transform3D
## 0..1 cuánto manda la pose de llevar el arma al correr (ver _apply_carry), y si el arma va
## perpendicular al antebrazo (hojas) o con la inclinación de la lanza.
var carry: float = 0.0
var carry_perpendicular: bool = true

## Muleta (Cripple): 0..1 cuánto manda, en qué mano va ("Left"/"Right": la del lado de la
## pierna que falta, o la contraria a la pierna rota) y dónde se clava la punta (mundo; los pone
## Cripple). El puño lo pone _apply_crutch respecto al hombro. Tras posar, crutch_hand (mundo) es
## dónde querría ir la mano (Cripple clava la punta debajo), crutch_xform dónde va la rama (su +Y
## de la punta al puño) y crutch_grip dónde ha quedado el puño.
var crutch: float = 0.0
var crutch_side: String = "Left"
var crutch_tip: Vector3
var crutch_hand: Vector3
var crutch_xform: Transform3D
var crutch_grip: Vector3

## Llamado tras posar, con este modificador (para colocar visuales sobre las manos).
var after_pose: Callable
## Si está activo, tras posar mide los huesos de contacto de la voltereta (RollMotion.sample) y
## los deja en contact_sample. Tiene que ser aquí: fuera del modificador el esqueleto devuelve la
## pose animada, sin el ovillo.
var sample_contacts: bool = false
var contact_sample: Dictionary = {}
var _contact_cache: Dictionary = {}

var _skel: Skeleton3D
var _idx: Dictionary = {}
var _delta: float = 1.0 / 60.0


func _ready() -> void:
	_skel = get_skeleton()
	if _skel == null:
		active = false
		return
	for group in [[B_HIPS], SPINE, NECK, L_ARM, R_ARM, L_LEG, R_LEG,
			["mixamorig_LeftShoulder", "mixamorig_RightShoulder"]]:
		for bone_name in group:
			_idx[bone_name] = _skel.find_bone(bone_name)


func _process_modification_with_delta(delta: float) -> void:
	_delta = delta
	_apply()


func _process_modification() -> void:
	_apply()


func is_idle() -> bool:
	return tuck <= 0.001 and aim_weight <= 0.001 and death <= 0.001 and roll_x < 0.0 and motion_x < 0.0


func _apply() -> void:
	if _skel == null or frame_node == null:
		return
	if not is_idle():
		if roll_x >= 0.0:
			_apply_roll(roll_x)
		elif tuck > 0.001:
			_apply_tuck(tuck)
		if motion_x >= 0.0 and not motion.is_empty():
			_apply_motion(motion_x)
		if death > 0.001:
			_apply_death(death)
		if aim_weight > 0.001:
			_apply_aim(aim_weight)
	if grip_right:
		if carry > 0.001:
			_apply_carry(carry)
		_apply_grip()
	if crutch > 0.001:
		_apply_crutch(crutch)
	if sample_contacts:
		contact_sample = RollMotion.sample(_skel, frame_node, _contact_cache)
	if after_pose.is_valid():
		after_pose.call(self)


# ---------------------------------------------------------------------------------------------
# Utilidades


## Eje del marco del modelo expresado en el espacio del esqueleto.
func model_dir(model_axis: Vector3) -> Vector3:
	var world := frame_node.global_basis * model_axis
	return (_skel.global_basis.inverse() * world).normalized()


## Dirección de mundo al espacio del esqueleto.
func to_skel_dir(world: Vector3) -> Vector3:
	return (_skel.global_basis.inverse() * world).normalized()


func to_skel_point(world: Vector3) -> Vector3:
	return _skel.global_transform.affine_inverse() * world


func to_world_point(skel_point: Vector3) -> Vector3:
	return _skel.global_transform * skel_point


func bone_idx(bone_name: String) -> int:
	if not _idx.has(bone_name) and _skel != null:
		_idx[bone_name] = _skel.find_bone(bone_name)
	return _idx.get(bone_name, -1)


## Giro de la cadera en el marco del modelo, en grados (mismo criterio que
## PlayerCombat._anim_hips_yaw: el +Z de su base proyectado en el suelo).
func hips_yaw() -> float:
	var hips := bone_idx(B_HIPS)
	if hips < 0:
		return 0.0
	var basis := frame_node.global_basis.inverse() * _skel.global_basis * _skel.get_bone_global_pose(hips).basis
	var z := basis.orthonormalized().z
	return rad_to_deg(atan2(z.x, z.z))


func bone_world(bone_name: String) -> Vector3:
	var i: int = bone_idx(bone_name)
	if i < 0:
		return Vector3.ZERO
	return _skel.global_transform * _skel.get_bone_global_pose(i).origin


## Transform del hueso en mundo, con la escala del esqueleto (para colgar cosas en su marco).
func bone_world_xform(bone_name: String) -> Transform3D:
	var i: int = bone_idx(bone_name)
	if i < 0:
		return _skel.global_transform
	return _skel.global_transform * _skel.get_bone_global_pose(i)


func bone_world_basis(bone_name: String) -> Basis:
	var i: int = bone_idx(bone_name)
	if i < 0:
		return Basis.IDENTITY
	return (_skel.global_transform * _skel.get_bone_global_pose(i)).basis.orthonormalized()


## Gira el hueso [rot] (espacio del esqueleto) sobre su pose actual, conservando su origen.
func rotate_bone(bone_name: String, rot: Quaternion) -> void:
	var bone: int = bone_idx(bone_name)
	if bone < 0:
		return
	var new_basis := Basis(rot) * _skel.get_bone_global_pose(bone).basis
	var parent := _skel.get_bone_parent(bone)
	if parent >= 0:
		new_basis = _skel.get_bone_global_pose(parent).basis.inverse() * new_basis
	_skel.set_bone_pose_rotation(bone, new_basis.get_rotation_quaternion())


func rotate_about(bone_name: String, model_axis: Vector3, degrees: float) -> void:
	if absf(degrees) < 0.01:
		return
	rotate_bone(bone_name, Quaternion(model_dir(model_axis), deg_to_rad(degrees)))


## Rotación mínima que lleva [from] a [to].
static func arc(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var axis := a.cross(b)
	var s := axis.length()
	if s < 1e-6:
		return Quaternion.IDENTITY
	return Quaternion(axis / s, atan2(s, a.dot(b)))


## IK analítico de dos huesos. [target] y [pole] en espacio del esqueleto. [weight] mezcla con la
## pose animada.
func two_bone(chain: Array, target: Vector3, pole: Vector3, weight: float) -> void:
	var i0: int = bone_idx(chain[0])
	var i1: int = bone_idx(chain[1])
	var i2: int = bone_idx(chain[2])
	if i0 < 0 or i1 < 0 or i2 < 0 or weight <= 0.0:
		return
	var p0 := _skel.get_bone_global_pose(i0).origin
	var p1 := _skel.get_bone_global_pose(i1).origin
	var p2 := _skel.get_bone_global_pose(i2).origin
	var l1 := p0.distance_to(p1)
	var l2 := p1.distance_to(p2)
	var to_target := target - p0
	var d := clampf(to_target.length(), 0.001, (l1 + l2) * 0.999)
	var dir := to_target.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 1e-8:
		bend = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP)
	bend = bend.normalized()
	var elbow := p0 + dir * a + bend * h
	var q1 := arc(p1 - p0, elbow - p0)
	q1 = Quaternion.IDENTITY.slerp(q1, weight)
	rotate_bone(chain[0], q1)
	# Tras girar el brazo, el antebrazo arranca en el codo nuevo.
	var p1n := _skel.get_bone_global_pose(i1).origin
	var p2n := _skel.get_bone_global_pose(i2).origin
	var q2 := arc(p2n - p1n, target - p1n)
	q2 = Quaternion.IDENTITY.slerp(q2, weight)
	rotate_bone(chain[1], q2)


## Eje de la bisagra del codo en el marco de reposo del antebrazo: doblar el codo es girar en
## positivo sobre él (medido en las animaciones de correr y nadar; la X pequeña es el ángulo de
## carga del brazo).
const ELBOW_HINGE := {"Left": Vector3(0.11, 0.0, 0.99), "Right": Vector3(0.17, 0.0, -0.98)}


## IK de brazo como two_bone, pero anatómico: el brazo rota sobre su eje hasta que la bisagra del
## codo queda perpendicular al plano hombro-codo-muñeca, y el antebrazo solo dobla sobre esa
## bisagra. Con two_bone el codo dobla sobre cualquier eje y la torsión que sobra acaba en el
## antebrazo (o salta de un lado a otro al tensar), y la piel sin huesos de torsión se estruja.
## [side] "Left"/"Right"; [target] y [pole] como en two_bone.
func arm_ik(side: String, target: Vector3, pole: Vector3, weight: float) -> void:
	var chain: Array = L_ARM if side == "Left" else R_ARM
	var i0: int = bone_idx(chain[0])
	var i1: int = bone_idx(chain[1])
	var i2: int = bone_idx(chain[2])
	if i0 < 0 or i1 < 0 or i2 < 0 or weight <= 0.0:
		return
	var anim0 := _skel.get_bone_pose_rotation(i0)
	var anim1 := _skel.get_bone_pose_rotation(i1)
	var p0 := _skel.get_bone_global_pose(i0).origin
	var l1 := p0.distance_to(_skel.get_bone_global_pose(i1).origin)
	var l2 := _skel.get_bone_global_pose(i1).origin.distance_to(_skel.get_bone_global_pose(i2).origin)
	var to_target := target - p0
	var d := clampf(to_target.length(), 0.001, (l1 + l2) * 0.999)
	var dir := to_target.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 1e-8:
		bend = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP)
	bend = bend.normalized()
	var elbow := p0 + dir * a + bend * h
	# Normal del plano del brazo (definida aunque el brazo vaya recto): la bisagra va por ella.
	var normal := bend.cross(dir).normalized()
	# Antebrazo en reposo respecto al brazo: su torsión la pone luego orient_hand.
	_skel.set_bone_pose_rotation(i1, _skel.get_bone_rest(i1).basis.get_rotation_quaternion())
	rotate_bone(chain[0], arc(_skel.get_bone_global_pose(i1).origin - p0, elbow - p0))
	var hinge_local: Vector3 = ELBOW_HINGE[side].normalized()
	var upper := (elbow - p0).normalized()
	var hinge := _skel.get_bone_global_pose(i1).basis.orthonormalized() * hinge_local
	rotate_bone(chain[0], Quaternion(upper, _signed_angle(hinge, normal, upper)))
	# El codo dobla sobre la bisagra, y un retoque mínimo por el ángulo de carga.
	hinge = _skel.get_bone_global_pose(i1).basis.orthonormalized() * hinge_local
	var p1 := _skel.get_bone_global_pose(i1).origin
	var fore := _skel.get_bone_global_pose(i2).origin - p1
	rotate_bone(chain[1], Quaternion(hinge.normalized(), _signed_angle(fore, target - p1, hinge.normalized())))
	p1 = _skel.get_bone_global_pose(i1).origin
	rotate_bone(chain[1], arc(_skel.get_bone_global_pose(i2).origin - p1, target - p1))
	if weight < 1.0:
		_skel.set_bone_pose_rotation(i0, anim0.slerp(_skel.get_bone_pose_rotation(i0), weight))
		_skel.set_bone_pose_rotation(i1, anim1.slerp(_skel.get_bone_pose_rotation(i1), weight))


## Eje para girar [from] hacia [to] (uno cualquiera perpendicular si son opuestos).
static func _perp_axis(from: Vector3, to: Vector3) -> Vector3:
	var axis := from.cross(to)
	if axis.length_squared() < 1e-8:
		axis = from.cross(Vector3.RIGHT if absf(from.x) < 0.9 else Vector3.UP)
	return axis.normalized()


## Ángulo con signo que lleva [from] a [to] girando sobre [axis] (proyectados en su plano).
static func _signed_angle(from: Vector3, to: Vector3, axis: Vector3) -> float:
	var n := axis.normalized()
	var u := from - n * from.dot(n)
	var v := to - n * to.dot(n)
	if u.length_squared() < 1e-10 or v.length_squared() < 1e-10:
		return 0.0
	return atan2(n.dot(u.cross(v)), u.dot(v))


## Unidades del esqueleto por metro (este rig va en centímetros).
func unit() -> float:
	return frame_node.global_basis.get_scale().x / _skel.global_basis.get_scale().x


func skeleton() -> Skeleton3D:
	return _skel


## Posición del hueso en el espacio del esqueleto (pose ya modificada hasta aquí).
func bone_pos(bone_name: String) -> Vector3:
	var i := bone_idx(bone_name)
	return _skel.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


## Cuánto ha girado el hueso respecto a su reposo, en el espacio del esqueleto: lleva una
## dirección del cuerpo en reposo a donde apunta ahora.
func rest_delta(bone_name: String) -> Basis:
	var i := bone_idx(bone_name)
	if i < 0:
		return Basis.IDENTITY
	var now := _skel.get_bone_global_pose(i).basis.orthonormalized()
	var rest := _skel.get_bone_global_rest(i).basis.orthonormalized()
	return now * rest.inverse()


## Marco de la cara en el espacio del esqueleto: x a su derecha, y arriba, z hacia donde mira.
func face_frame() -> Basis:
	var d := rest_delta(NECK[1])
	var fwd := (d * model_dir(Vector3.BACK)).normalized()
	var up := (d * model_dir(Vector3.UP)).normalized()
	return Basis(fwd.cross(up), up, fwd)


## Rota el hueso para que su segmento (hasta [child]) se incline [degrees] hacia [toward].
func swing_bone(bone_name: String, child: String, toward: Vector3, degrees: float) -> void:
	if absf(degrees) < 0.01:
		return
	var seg := bone_pos(child) - bone_pos(bone_name)
	var axis := seg.cross(toward)
	if axis.length_squared() < 1e-10:
		return
	rotate_bone(bone_name, Quaternion(axis.normalized(), deg_to_rad(degrees)))


# ---------------------------------------------------------------------------------------------
# Manos


const FINGERS := ["Index", "Middle", "Ring", "Pinky"]


## Marco de la mano [side] ("Left"/"Right") en el espacio del esqueleto: x de la muñeca al
## nudillo del corazón, y la normal de la palma (hacia donde se cierran los dedos) y z el eje
## sobre el que se doblan (x × y). Con [rest], el de la pose de reposo.
func hand_frame(side: String, rest: bool = false) -> Basis:
	var pos := func(bone_name: String) -> Vector3:
		var i := bone_idx(bone_name)
		if i < 0:
			return Vector3.ZERO
		return (_skel.get_bone_global_rest(i) if rest else _skel.get_bone_global_pose(i)).origin
	var hand: Vector3 = pos.call("mixamorig_%sHand" % side)
	var d: Vector3 = (pos.call("mixamorig_%sHandMiddle1" % side) - hand).normalized()
	var lat: Vector3 = pos.call("mixamorig_%sHandPinky1" % side) - pos.call("mixamorig_%sHandIndex1" % side)
	var n := d.cross(lat) if side == "Right" else lat.cross(d)
	n = (n - d * n.dot(d)).normalized()
	return Basis(d, n, d.cross(n))


## Gira la mano para que sus nudillos apunten a [dir] y la palma mire a [palm] (espacio del
## esqueleto). La parte del giro que es torcer la muñeca sobre el antebrazo la hace sobre todo
## el antebrazo (pronación), como el cuerpo: si la hiciera solo la mano, la piel de la muñeca se
## retorcería. [max_bend] (grados) limita cuánto se dobla la muñeca respecto al antebrazo: si
## la dirección pedida se pasa, la mano se queda en el límite, apuntando lo más cerca posible.
func orient_hand(side: String, dir: Vector3, palm: Vector3, weight: float, forearm_share: float = 0.7,
		max_bend: float = 180.0) -> void:
	if weight <= 0.001:
		return
	var forearm := "mixamorig_%sForeArm" % side
	var hand := "mixamorig_%sHand" % side
	var axis := (bone_pos(hand) - bone_pos(forearm)).normalized()
	var d := dir.normalized()
	var p := palm
	if max_bend < 180.0 and axis.angle_to(d) > deg_to_rad(max_bend):
		var limited := axis.rotated(_perp_axis(axis, d), deg_to_rad(max_bend))
		p = arc(d, limited) * p
		d = limited
	var n := (p - d * p.dot(d)).normalized()
	var want := Basis(d, n, d.cross(n))
	var q := (want * hand_frame(side).inverse()).get_rotation_quaternion()
	# Giro alrededor del eje del antebrazo (descomposición swing-twist).
	var proj := axis * Vector3(q.x, q.y, q.z).dot(axis)
	var twist := Quaternion(proj.x, proj.y, proj.z, q.w)
	if twist.length_squared() > 1e-8:
		twist = twist.normalized()
		rotate_bone(forearm, Quaternion.IDENTITY.slerp(twist, forearm_share * weight))
	q = (want * hand_frame(side).inverse()).get_rotation_quaternion()
	rotate_bone(hand, Quaternion.IDENTITY.slerp(q, weight))


## Dedos de la mano [side] en una pose absoluta, sea cual sea la animación: [curls] da por dedo
## ("Index", "Middle", "Ring", "Pinky") los grados que se dobla cada falange (Vector3, de la base
## a la punta) y para "Thumb" (oposición hacia la palma, flexión de la segunda y la tercera). Se
## conserva la separación de los dedos del reposo.
func pose_fingers(side: String, curls: Dictionary, weight: float) -> void:
	if weight <= 0.001:
		return
	var rest_hand := hand_frame(side, true)
	var hand := hand_frame(side)
	var s := 1.0 if side == "Right" else -1.0
	for finger in FINGERS + ["Thumb"]:
		var angles: Vector3 = curls.get(finger, Vector3.ZERO)
		var total := 0.0
		for k in 3:
			var bone := "mixamorig_%sHand%s%d" % [side, finger, k + 1]
			var child := "mixamorig_%sHand%s%d" % [side, finger, k + 2]
			var bi := bone_idx(bone)
			var ci := bone_idx(child)
			if bi < 0 or ci < 0:
				break
			var rest_dir := rest_hand.inverse() * (_skel.get_bone_global_rest(ci).origin - _skel.get_bone_global_rest(bi).origin).normalized()
			var want: Vector3
			if finger == "Thumb":
				# Oposición: el pulgar gira sobre el eje de la mano hacia la palma; luego se dobla.
				var opp := Basis(Vector3.RIGHT, deg_to_rad(-s * angles.x))
				var dir := opp * rest_dir
				if k > 0:
					total += angles[k]
					var flex_axis := dir.cross(Vector3.UP).normalized()
					dir = Basis(flex_axis, deg_to_rad(total)) * dir
				want = hand * dir
			else:
				total += angles[k]
				want = hand * (Basis(Vector3.BACK, deg_to_rad(total)) * rest_dir)
			var cur := _skel.get_bone_global_pose(ci).origin - _skel.get_bone_global_pose(bi).origin
			rotate_bone(bone, Quaternion.IDENTITY.slerp(arc(cur, want), weight))


## Mezcla dos poses de dedos (ver pose_fingers).
static func blend_fingers(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a:
		out[key] = (a[key] as Vector3).lerp(b.get(key, a[key]), t)
	return out


# ---------------------------------------------------------------------------------------------
# Poses


## Ovillo de voltereta como pose ABSOLUTA, en cuclillas y con la espalda redonda (sin girar es
## como se acaba la voltereta; el tirarse de cabeza lo pone el giro de RollMotion): cada segmento apunta a una dirección fija del marco
## del cuerpo, sea cual sea la animación de debajo (si se sumara a la de correr, las piernas
## seguirían corriendo dentro del ovillo). Espalda redonda, barbilla al pecho, muslos contra el
## pecho, talones a las nalgas y brazos abrazando las espinillas.
## [hueso, hijo, dirección en el marco del modelo (+Z adelante, +Y arriba, +X izquierda)].
static func _tuck_segments() -> Array:
	if not _tuck_cache.is_empty():
		return _tuck_cache
	var arc_dir := func(deg: float) -> Vector3:
		return Vector3(0.0, cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))
	var segs: Array = [
		["mixamorig_Hips", "mixamorig_Spine", arc_dir.call(8.0)],
		["mixamorig_Spine", "mixamorig_Spine1", arc_dir.call(24.0)],
		["mixamorig_Spine1", "mixamorig_Spine2", arc_dir.call(42.0)],
		["mixamorig_Spine2", "mixamorig_Neck", arc_dir.call(62.0)],
		["mixamorig_Neck", "mixamorig_Head", arc_dir.call(88.0)],
		["mixamorig_Head", "mixamorig_HeadTop_End", arc_dir.call(112.0)],
	]
	for side in [["Left", 1.0], ["Right", -1.0]]:
		var n: String = side[0]
		var s: float = side[1]
		segs.append(["mixamorig_%sUpLeg" % n, "mixamorig_%sLeg" % n, Vector3(0.13 * s, 0.62, 0.78).normalized()])
		segs.append(["mixamorig_%sLeg" % n, "mixamorig_%sFoot" % n, Vector3(0.05 * s, -0.22, -0.97).normalized()])
		segs.append(["mixamorig_%sFoot" % n, "mixamorig_%sToeBase" % n, Vector3(0.0, -0.55, -0.83).normalized()])
		segs.append(["mixamorig_%sArm" % n, "mixamorig_%sForeArm" % n, Vector3(0.30 * s, -0.50, 0.81).normalized()])
		segs.append(["mixamorig_%sForeArm" % n, "mixamorig_%sHand" % n, Vector3(-0.60 * s, -0.05, 0.80).normalized()])
	_tuck_cache = segs
	return segs


static var _tuck_cache: Array = []


## Voltereta por posturas clave (RollMotion): cada segmento a su dirección de la fase actual,
## mezclada con la animación según el peso de entrada y salida.
func _apply_roll(x: float) -> void:
	var w := RollMotion.weight(x)
	if w <= 0.001:
		return
	for seg in RollMotion.SEGMENTS:
		var bone := bone_idx(seg[0])
		var child := bone_idx(seg[1])
		if bone < 0 or child < 0:
			continue
		var current := _skel.get_bone_global_pose(child).origin - _skel.get_bone_global_pose(bone).origin
		var q := arc(current, model_dir(RollMotion.direction(seg[2], x, roll_mirror)))
		rotate_bone(seg[0], Quaternion.IDENTITY.slerp(q, w))


func _apply_tuck(w: float) -> void:
	for seg in _tuck_segments():
		var bone := bone_idx(seg[0])
		var child := bone_idx(seg[1])
		if bone < 0 or child < 0:
			continue
		var current := _skel.get_bone_global_pose(child).origin - _skel.get_bone_global_pose(bone).origin
		var q := arc(current, model_dir(seg[2]))
		rotate_bone(seg[0], Quaternion.IDENTITY.slerp(q, w))


## Puño cerrado sobre un mango (dedos casi del todo doblados, el pulgar por encima).
const FIST := {"Index": Vector3(58, 72, 42), "Middle": Vector3(66, 78, 44), "Ring": Vector3(72, 78, 42),
	"Pinky": Vector3(78, 74, 40), "Thumb": Vector3(52, 30, 28)}
## Mango respecto a la muñeca, en el marco de la mano (hacia los nudillos, hacia la palma), m.
const FIST_HANDLE := Vector2(0.078, 0.026)
## El arma sale del puño algo inclinada hacia los nudillos (grados).
const FIST_TILT := 14.0


## Llevar el arma al correr. La animación de correr cruza el puño por delante del pecho y la
## hoja, que sale por el lado del pulgar, atraviesa la cabeza y el torso. Aquí el brazo corre por
## un costado, por fuera de la cadera, casi colgando y al compás del balanceo de la animación, y
## el arma va rígida en el puño, perpendicular al antebrazo, con el filo hacia los nudillos: hacia
## abajo. El péndulo lo hace el propio brazo: delante, la punta sube; atrás, el arma queda casi
## horizontal (no más abajo: la rodilla de ese lado viene subiendo).
## Mano por fuera del hombro (m): lo justo para no rozar el muslo (deja unos 4 cm). Más abre el
## brazo hacia fuera y se nota.
const CARRY_OUT := 0.10
## Brazo (grados desde colgando, + hacia delante) y flexión del codo, con el brazo atrás y
## delante.
const CARRY_UPPER := Vector2(-20.0, 16.0)
const CARRY_ELBOW := Vector2(25.0, 24.0)
## Balanceo de la mano en la animación (m, atrás y adelante del hombro) que va de un extremo al
## otro del péndulo; medido en running (-0.16, 0.34) y sprinting (-0.26, 0.26).
const CARRY_SWING_RANGE := Vector2(-0.2, 0.3)
## Cuánto se abre el arma hacia fuera (grados; con el filo hacia abajo va en el plano de la
## zancada y no hace falta), y el codo (hacia fuera por cada uno hacia atrás).
const CARRY_YAW := 0.0
const CARRY_ELBOW_OUT := 0.2
## La lanza no va perpendicular (quedaría de pie): su inclinación sobre la horizontal (grados)
## con el brazo atrás y delante, y la punta algo hacia dentro para que la cola salga atrás y por
## fuera, lejos de las piernas y del suelo.
const CARRY_PITCH_SPEAR := Vector2(6.0, 28.0)
const CARRY_YAW_SPEAR := -7.0


func _apply_carry(w: float) -> void:
	var m := unit()
	var fwd := model_dir(Vector3.BACK)
	var up := model_dir(Vector3.UP)
	var out := model_dir(Vector3.RIGHT) * -1.0
	var shoulder := bone_pos(R_ARM[0])
	var elbow := bone_pos(R_ARM[1])
	var wrist := bone_pos(R_ARM[2])
	var phase := smoothstep(CARRY_SWING_RANGE.x, CARRY_SWING_RANGE.y, (wrist - shoulder).dot(fwd) / m)
	# Brazo y antebrazo en el plano de la zancada, con sus largos reales.
	var upper := deg_to_rad(lerpf(CARRY_UPPER.x, CARRY_UPPER.y, phase))
	var fore := upper + deg_to_rad(lerpf(CARRY_ELBOW.x, CARRY_ELBOW.y, phase))
	var target := shoulder + out * CARRY_OUT * m \
		+ (fwd * sin(upper) - up * cos(upper)) * shoulder.distance_to(elbow) \
		+ (fwd * sin(fore) - up * cos(fore)) * elbow.distance_to(wrist)
	# Codo atrás y algo hacia fuera, como al correr.
	arm_ik("Right", target, -fwd + out * CARRY_ELBOW_OUT, w)
	var blade: Vector3
	if carry_perpendicular:
		# Perpendicular al antebrazo, hacia delante y arriba, abierta CARRY_YAW hacia fuera.
		var forearm := (bone_pos(R_ARM[2]) - bone_pos(R_ARM[1])).normalized()
		var side := (out - forearm * out.dot(forearm)).normalized()
		blade = side.cross(forearm)
		if blade.dot(fwd + up) < 0.0:
			blade = -blade
		blade = blade * cos(deg_to_rad(CARRY_YAW)) + side * sin(deg_to_rad(CARRY_YAW))
	else:
		var pitch := deg_to_rad(lerpf(CARRY_PITCH_SPEAR.x, CARRY_PITCH_SPEAR.y, phase))
		var yaw := deg_to_rad(CARRY_YAW_SPEAR)
		blade = (fwd * cos(yaw) + out * sin(yaw)) * cos(pitch) + up * sin(pitch)
	blade = blade.normalized()
	# Puño: la palma mira al cuerpo y el pulgar (el arma sale inclinada FIST_TILT hacia los
	# nudillos) hacia donde toca.
	var palm := -out
	palm = (palm - blade * palm.dot(blade)).normalized()
	var thumb := blade.rotated(palm, deg_to_rad(FIST_TILT))
	orient_hand("Right", palm.cross(thumb), palm, w, 0.7, 70.0)


func _apply_grip() -> void:
	# La lanza apuntada la agarra ThrowPose a su manera.
	var w := 1.0
	if aim_style == &"throw":
		w = 1.0 - clampf(aim_weight, 0.0, 1.0)
	# Con la muleta en la izquierda, la derecha se queda sin nada que agarrar.
	if crutch_side == "Left":
		w *= 1.0 - clampf(crutch, 0.0, 1.0)
	pose_fingers("Right", FIST, w)
	var hand := hand_frame("Right")
	var m := unit()
	# El mango cruza la palma: la punta sale por el lado del pulgar (+Z del marco de la mano en
	# la derecha) y el filo mira hacia los nudillos, como un martillo: con el brazo colgando,
	# hacia abajo; al golpear, por delante.
	var y := hand.z.rotated(hand.y, deg_to_rad(-FIST_TILT)).normalized()
	var z := hand.x
	var x := y.cross(z).normalized()
	z = x.cross(y)
	var origin := bone_pos("mixamorig_RightHand") + (hand.x * FIST_HANDLE.x + hand.y * FIST_HANDLE.y) * m
	var to_world := _skel.global_transform
	right_grip_xform = Transform3D((to_world.basis.orthonormalized() * Basis(x, y, z)).orthonormalized(), to_world * origin)


## Hasta dónde baja la rama por debajo de su agarre (la malla empieza 0,18 m por detrás de él).
const CRUTCH_BUTT := 0.18
## Puño de la muleta respecto al hombro (m, marco del modelo): hacia fuera, abajo y adelante. Como
## quien lleva un bastón: el codo doblado a medias y el antebrazo hacia delante, que así la muñeca
## va casi recta (con el brazo colgando habría que doblarla 90° para rodear la rama). Va con el
## hombro, así que acompaña al cuerpo cuando la cojera lo balancea.
const CRUTCH_FIST := Vector3(0.16, 0.36, 0.28)
## Hacia dónde sale el codo de la muleta (marco del modelo: fuera, arriba, adelante): atrás y abajo,
## apenas hacia fuera. Cuanto más hacia fuera, más tiene que girar el antebrazo para que la palma
## mire a la rama con el pulgar arriba (y se ve retorcido).
const CRUTCH_ELBOW := Vector3(0.2, -1.0, -0.6)
## La mano agarra la rama a esta distancia de la punta (m; quedan 33 cm por encima) y no resbala
## por el puño: lo que la cojera sube y baja el hombro lo absorbe el codo. En cuesta (el suelo bajo
## la mano más alto o más bajo que los pies) se recoloca despacio, a CRUTCH_REGRIP m/s, dentro de
## CRUTCH_GRIP_RANGE.
const CRUTCH_GRIP := 0.95
const CRUTCH_GRIP_RANGE := Vector2(0.75, 1.15)
const CRUTCH_REGRIP := 0.1
var _crutch_grip_len := CRUTCH_GRIP


## Muleta: la punta está clavada (crutch_tip, bajo donde va la mano) y la rama pivota en ella hasta
## la mano, que la agarra a CRUTCH_GRIP de la punta, hacia donde querría estar: bajo el hombro y por
## delante (CRUTCH_FIST). El codo va atrás y abajo, y la mano rodea la rama con el pulgar arriba (el
## meñique hacia la punta) y los nudillos siguiendo al antebrazo, así que la muñeca casi no se
## dobla ni se tuerce.
func _apply_crutch(w: float) -> void:
	var m := unit()
	var side := crutch_side
	var chain: Array = L_ARM if side == "Left" else R_ARM
	var fwd := model_dir(Vector3.BACK)
	var up := model_dir(Vector3.UP)
	var out := model_dir(Vector3.RIGHT) * (1.0 if side == "Left" else -1.0)
	var tip := to_skel_point(crutch_tip)
	var shoulder := bone_pos(chain[0])
	var wanted := shoulder + (out * CRUTCH_FIST.x - up * CRUTCH_FIST.y + fwd * CRUTCH_FIST.z) * m
	crutch_hand = to_world_point(wanted)
	var stick := (wanted - tip).normalized()
	var need := clampf(wanted.distance_to(tip) / m, CRUTCH_GRIP_RANGE.x, CRUTCH_GRIP_RANGE.y)
	_crutch_grip_len = move_toward(_crutch_grip_len, need, CRUTCH_REGRIP * _delta)
	var fist := tip + stick * _crutch_grip_len * m
	# Primero los nudillos van hacia donde está el puño; con el brazo ya puesto, siguen al antebrazo.
	var knuckles := _around_stick(fist - shoulder, stick, fwd)
	var palm := _crutch_palm(side, knuckles, stick)
	var elbow := out * CRUTCH_ELBOW.x + up * CRUTCH_ELBOW.y + fwd * CRUTCH_ELBOW.z
	arm_ik(side, fist - (knuckles * FIST_HANDLE.x + palm * FIST_HANDLE.y) * m, elbow, w)
	knuckles = _around_stick(bone_pos(chain[2]) - bone_pos(chain[1]), stick, knuckles)
	orient_hand(side, knuckles, _crutch_palm(side, knuckles, stick), w, 0.7, 70.0)
	pose_fingers(side, FIST, w)
	var hand := hand_frame(side)
	var grip := bone_pos("mixamorig_%sHand" % side) + (hand.x * FIST_HANDLE.x + hand.y * FIST_HANDLE.y) * m
	var top := to_world_point(grip)
	crutch_grip = top
	var axis := (top - crutch_tip).normalized()
	var forward := frame_node.global_basis.z
	var x := axis.cross(forward).normalized()
	if x.length_squared() < 1e-6:
		x = frame_node.global_basis.x
	crutch_xform = Transform3D(Basis(x, axis, x.cross(axis)), crutch_tip + axis * CRUTCH_BUTT)


## [v] sin su parte a lo largo de la rama: hacia dónde apuntan los nudillos que la rodean. Si [v] va
## casi a lo largo de ella, manda [fallback].
static func _around_stick(v: Vector3, stick: Vector3, fallback: Vector3) -> Vector3:
	var a := v.normalized() + fallback.normalized() * 0.2
	a -= stick * a.dot(stick)
	return a.normalized() if a.length_squared() > 1e-6 else fallback


## Palma de la mano que rodea la rama con el pulgar arriba, en el marco de hand_frame: sale de los
## nudillos y del meñique, que mira a la punta.
static func _crutch_palm(side: String, knuckles: Vector3, stick: Vector3) -> Vector3:
	return knuckles.cross(-stick) if side == "Right" else (-stick).cross(knuckles)


## Tambaleo o paso atrás (BodyMotion): cadera, tronco, cabeza y brazos por claves, y las
## piernas por IK hacia donde toca cada pie (apoyado, fijo al suelo, o en el aire dando el paso).
func _apply_motion(x: float) -> void:
	var w := smoothstep(0.0, 0.05, x) * (1.0 - smoothstep(0.85, 1.0, x))
	if w <= 0.001:
		return
	var push := Vector3(motion_push.x, 0.0, motion_push.z)
	push = push.normalized() if push.length_squared() > 1e-6 else Vector3.FORWARD
	var power := clampf(motion_power, 0.4, 1.5)
	var lean_axis := Vector3.UP.cross(push).normalized()
	var get := func(key: String) -> float:
		return float(BodyMotion.sample(motion[key], x))
	# Pies: dónde estaban en la animación (ya apoyados por el IK de pies) antes de mover nada.
	var feet := {}
	for chain in [L_LEG, R_LEG]:
		feet[chain[2]] = bone_pos(chain[2])
	var foot_basis := {}
	for chain in [L_LEG, R_LEG]:
		foot_basis[chain[2]] = _skel.get_bone_global_pose(bone_idx(chain[2])).basis
	# Cadera: empujada y hundida (rodillas que ceden).
	var hips := bone_idx(B_HIPS)
	if hips >= 0:
		var shift: Vector3 = (push * get.call("hips_push") * power + Vector3.DOWN * get.call("hips_down")) * w
		var shift_s: Vector3 = _skel.global_basis.inverse() * (frame_node.global_basis * shift)
		_skel.set_bone_pose_position(hips, _skel.get_bone_pose_position(hips) + shift_s)
	# Tronco y cabeza hacia el empujón.
	var lean: float = get.call("lean") * power * w
	var shares := [0.3, 0.35, 0.35]
	for i in SPINE.size():
		rotate_about(SPINE[i], lean_axis, lean * shares[i])
	rotate_about(NECK[1], lean_axis, get.call("head") * power * w)
	# Brazos: se quedan atrás (contra el empujón) y se abren para equilibrar.
	var fling: float = get.call("arms_fling") * w
	var out: float = get.call("arms_out") * w
	var elbows: float = get.call("elbows") * w
	rotate_about(L_ARM[0], lean_axis, -fling)
	rotate_about(R_ARM[0], lean_axis, -fling)
	rotate_about(L_ARM[0], Vector3.BACK, out)
	rotate_about(R_ARM[0], Vector3.BACK, -out)
	swing_bone(L_ARM[1], L_ARM[2], model_dir(Vector3.BACK) + model_dir(Vector3.UP) * 0.3, elbows)
	swing_bone(R_ARM[1], R_ARM[2], model_dir(Vector3.BACK) + model_dir(Vector3.UP) * 0.3, elbows)
	# Piernas: primero el pie del lado del empujón (o el que toque si va recto).
	var side := push.dot(Vector3.RIGHT)
	var left_first := side > 0.3 or (absf(side) <= 0.3 and motion_left_first)
	var steps: Array = motion["steps"]
	var order := [L_LEG, R_LEG] if left_first else [R_LEG, L_LEG]
	var knee_pole := model_dir(Vector3.BACK)
	for k in 2:
		var chain: Array = order[k]
		var off := BodyMotion.foot_offset(x, steps[k], push, motion_distance, motion_travel)
		# Del marco del modelo (m) al del esqueleto (sus unidades) pasando por el mundo.
		var target: Vector3 = feet[chain[2]] + _skel.global_basis.inverse() * (frame_node.global_basis * off)
		two_bone(chain, target, knee_pole, w)
		# El pie conserva su orientación (plano), no la que le deja el giro de la pierna.
		var foot := bone_idx(chain[2])
		var want: Basis = foot_basis[chain[2]]
		var now := _skel.get_bone_global_pose(foot).basis
		rotate_bone(chain[2], Quaternion.IDENTITY.slerp((want.orthonormalized() * now.orthonormalized().inverse()).get_rotation_quaternion(), w))


## Muerto boca arriba: brazos abiertos, rodillas algo dobladas, cabeza ladeada.
func _apply_death(w: float) -> void:
	rotate_about(L_ARM[0], Vector3.BACK, 45.0 * w)
	rotate_about(R_ARM[0], Vector3.BACK, -40.0 * w)
	rotate_about(L_ARM[1], Vector3.RIGHT, -25.0 * w)
	rotate_about(R_ARM[1], Vector3.RIGHT, -35.0 * w)
	rotate_about(L_LEG[0], Vector3.RIGHT, -18.0 * w)
	rotate_about(L_LEG[1], Vector3.RIGHT, 30.0 * w)
	rotate_about(R_LEG[0], Vector3.BACK, -8.0 * w)
	rotate_about(NECK[1], Vector3.UP, 35.0 * w)


## Torso de perfil hacia el blanco y brazos por IK: la izquierda sostiene (arco/tirachinas) o
## equilibra (lanza), la derecha tensa hasta la mejilla o echa la lanza atrás.
## Con la cuerda tensada, el anclaje de la animación deja la mano derecha bajo la mandíbula, y
## con guante y capucha se mete en el cuello. Las dos manos se apartan de la cara lo mismo, en
## horizontal y de lado a la flecha: la línea de tiro se separa sin cambiar de dirección.
const BOW_FACE_CLEARANCE := 0.04


func _clear_face(w: float) -> void:
	if w <= 0.001:
		return
	var fingers := (bone_pos("mixamorig_RightHandIndex2") + bone_pos("mixamorig_RightHandMiddle2")) * 0.5
	var arrow := (bone_pos(L_ARM[2]) - fingers).normalized()
	var up := model_dir(Vector3.UP)
	var away := fingers - bone_pos(NECK[1])
	away -= arrow * away.dot(arrow)
	away -= up * away.dot(up)
	if away.length_squared() < 1e-8:
		return
	var offset := away.normalized() * BOW_FACE_CLEARANCE * unit() * w
	for chain in [L_ARM, R_ARM]:
		# El codo sigue en el plano que le da la animación.
		var shoulder := bone_pos(chain[0])
		two_bone(chain, bone_pos(chain[2]) + offset, bone_pos(chain[1]) - shoulder, 1.0)


func _apply_aim(w: float) -> void:
	var up_m := Vector3.UP
	# El arquero se pone de perfil: el pecho gira a la derecha y el hombro izquierdo apunta.
	var twist := 0.0
	match aim_style:
		&"bow":
			twist = -42.0
		&"sling":
			twist = -22.0
		&"throw":
			twist = lerpf(-35.0, 10.0, release)
	# Reparto del giro y de la inclinación hacia el blanco entre las vértebras.
	var aim_local := (frame_node.global_basis.inverse() * aim_dir).normalized()
	var pitch := rad_to_deg(asin(clampf(aim_local.y, -1.0, 1.0)))
	if not aim_arms_ik:
		if not is_nan(upper_hips_yaw):
			var delta := wrapf(upper_hips_yaw - hips_yaw(), -180.0, 180.0)
			rotate_about(SPINE[0], up_m, delta * w)
		# La animación ya apunta al frente (la flecha del arquero de Mixamo, ver BowAnimRig):
		# solo falta llevar el tronco a la altura y al lado del blanco.
		var yaw_fix := -BowAnimRig.ANIM_ARROW_YAW if aim_style == &"bow" else 0.0
		var pitch_fix := pitch - (BowAnimRig.ANIM_ARROW_PITCH if aim_style == &"bow" else 0.0)
		for bone_name in SPINE:
			rotate_about(bone_name, up_m, yaw_fix / SPINE.size() * w)
			rotate_about(bone_name, Vector3.RIGHT, -pitch_fix / SPINE.size() * w)
		if aim_style == &"bow":
			_clear_face(w * bow_rig.face_clearance_weight())
			bow_rig.apply(self)
		return
	if aim_style == &"bow":
		archery.apply(self, w, _delta)
		return
	if aim_style == &"throw":
		throw.apply(self, w)
		return
	for bone_name in SPINE:
		rotate_about(bone_name, up_m, twist / SPINE.size() * w)
		rotate_about(bone_name, Vector3.RIGHT, -pitch * 0.18 * w)

	var aim_s := to_skel_dir(aim_dir)
	var up_s := model_dir(Vector3.UP)
	var left_s := model_dir(Vector3.RIGHT)
	var right_s := -left_s
	var l_shoulder := _skel.get_bone_global_pose(_idx[L_ARM[0]]).origin
	var r_shoulder := _skel.get_bone_global_pose(_idx[R_ARM[0]]).origin
	var head := _skel.get_bone_global_pose(_idx[NECK[1]]).origin
	# Las longitudes del esqueleto van en su espacio (centímetros en este rig).
	var arm_len := l_shoulder.distance_to(_skel.get_bone_global_pose(_idx[L_ARM[1]]).origin) \
		+ _skel.get_bone_global_pose(_idx[L_ARM[1]]).origin.distance_to(_skel.get_bone_global_pose(_idx[L_ARM[2]]).origin)
	var unit := arm_len / 0.56 # metros → unidades del esqueleto

	match aim_style:
		&"bow", &"sling":
			var reach := 0.97 if aim_style == &"bow" else 0.93
			var hold := l_shoulder + aim_s * arm_len * reach
			two_bone(L_ARM, hold, -up_s * 0.6 + left_s, w)
			# Mano derecha: de la cuerda en reposo al ancla bajo el pómulo.
			var string_rest := hold - aim_s * 0.16 * unit
			var anchor := head + right_s * 0.06 * unit - up_s * 0.08 * unit + aim_s * 0.03 * unit
			if aim_style == &"sling":
				string_rest = hold - aim_s * 0.10 * unit - up_s * 0.02 * unit
				anchor = head + right_s * 0.09 * unit - up_s * 0.06 * unit - aim_s * 0.02 * unit
			var pull := string_rest.lerp(anchor, clampf(draw, 0.0, 1.0))
			two_bone(R_ARM, pull, right_s * 0.8 + up_s * 0.35 - aim_s * 0.5, w)
		&"throw":
			var back := r_shoulder + up_s * 0.20 * unit + right_s * 0.12 * unit - aim_s * (0.30 + 0.12 * draw) * unit
			var forward := r_shoulder + aim_s * 0.50 * unit + up_s * 0.02 * unit
			var hand := back.lerp(forward, release)
			two_bone(R_ARM, hand, right_s + -up_s * 0.6 - aim_s * 0.4, w)
			var balance := l_shoulder + aim_s * 0.38 * unit - up_s * 0.12 * unit + left_s * 0.10 * unit
			two_bone(L_ARM, balance, -up_s + left_s * 0.5, w * 0.8)
