class_name ThrowPose
extends RefCounted

## Lanzamiento de lanza (jabalina) montado por código sobre el cuerpo, como ArcheryPose:
##
##   - listo: medio de perfil, la lanza sobre el hombro apuntando al blanco, la mano junto a la
##     oreja con la palma arriba y el brazo libre señalando el blanco,
##   - cargar: el tronco gira más, el peso va atrás y el brazo se estira hacia atrás,
##   - lanzar: cadena de látigo; primero la cadera adelante, luego el giro del tronco, el
##     hombro, el codo y por último la mano, que suelta por delante y por encima del hombro; el
##     brazo libre tira hacia la cadera y el cuerpo sigue hacia delante tras soltar.
##
## Las posiciones de las manos se dan respecto a su hombro (que ya se ha movido con el tronco),
## en el marco de tiro (derecha, arriba, adelante) y en metros, así que el giro del tronco
## arrastra al brazo y el látigo sale solo.

const SPINE := CombatPose.SPINE
const L_ARM := CombatPose.L_ARM
const R_ARM := CombatPose.R_ARM
const SPINE_SHARE := [0.25, 0.35, 0.40]

## Instante (s desde que empieza a lanzar) en que la mano suelta la lanza.
const RELEASE_AT := 0.13
## Duración del gesto completo tras empezar a lanzar.
const THROW_TIME := 0.55

## Posturas clave. yaw: hacia dónde mira el pecho respecto al blanco (grados; negativo, el
## hombro derecho atrás); lean: tronco adelante (grados); hips: cadera (adelante, abajo) en m;
## r_hand / l_hand: mano respecto a su hombro (derecha, arriba, adelante) en m; r_pole / l_pole:
## hacia dónde sale el codo (derecha, arriba, adelante); palm: palma de la derecha (derecha,
## arriba, adelante); step: pie izquierdo adelantado (m).
const READY := {"yaw": -35.0, "lean": 2.0, "hips": Vector2(0.0, 0.01),
	"r_hand": Vector3(0.15, 0.17, -0.12), "r_pole": Vector3(0.8, -0.6, -0.1), "palm": Vector3(0.0, 1.0, 0.0),
	"l_hand": Vector3(0.05, 0.02, 0.5), "l_pole": Vector3(-0.3, -1.0, 0.0), "step": 0.0}
const COCKED := {"yaw": -68.0, "lean": -9.0, "hips": Vector2(-0.07, 0.035),
	"r_hand": Vector3(0.2, 0.12, -0.5), "r_pole": Vector3(0.5, -0.8, 0.0), "palm": Vector3(0.0, 1.0, 0.0),
	"l_hand": Vector3(0.0, 0.08, 0.52), "l_pole": Vector3(-0.3, -1.0, 0.0), "step": 0.12}
const RELEASE := {"yaw": 12.0, "lean": 10.0, "hips": Vector2(0.07, 0.03),
	"r_hand": Vector3(-0.02, 0.22, 0.28), "r_pole": Vector3(0.6, 0.2, 0.6), "palm": Vector3(0.0, 0.2, 1.0),
	"l_hand": Vector3(-0.05, -0.30, 0.10), "l_pole": Vector3(-0.6, 0.0, -0.8), "step": 0.24}
const FOLLOW := {"yaw": 32.0, "lean": 24.0, "hips": Vector2(0.12, 0.07),
	"r_hand": Vector3(-0.35, -0.32, 0.32), "r_pole": Vector3(0.7, 0.3, -0.2), "palm": Vector3(-0.6, -0.4, 0.3),
	"l_hand": Vector3(-0.05, -0.42, -0.05), "l_pole": Vector3(-0.6, 0.0, -0.8), "step": 0.24}
const SETTLE := {"yaw": 5.0, "lean": 8.0, "hips": Vector2(0.04, 0.03),
	"r_hand": Vector3(0.0, -0.45, 0.12), "r_pole": Vector3(0.6, 0.0, -0.8), "palm": Vector3(-1.0, 0.0, 0.0),
	"l_hand": Vector3(0.05, -0.5, 0.05), "l_pole": Vector3(-0.6, 0.0, -0.8), "step": 0.1}

const SPEAR_FINGERS := {"Index": Vector3(55, 65, 35), "Middle": Vector3(62, 72, 40), "Ring": Vector3(66, 72, 40),
	"Pinky": Vector3(70, 70, 35), "Thumb": Vector3(40, 20, 20)}
const POINT_FINGERS := {"Index": Vector3(3, 5, 3), "Middle": Vector3(10, 18, 10), "Ring": Vector3(18, 25, 14),
	"Pinky": Vector3(24, 30, 16), "Thumb": Vector3(20, 10, 8)}

# --- Entradas ---

## 0..1 carga (brazo atrás).
var draw: float = 0.0
## Segundos desde que empezó a lanzar, o negativo.
var throw_t: float = -1.0

# --- Resultados ---

## Marco de la mano derecha en mundo: origen en el agarre, -Z hacia donde apunta la lanza.
var grip_xform: Transform3D

var _last_draw: float = 0.0
var _from: Dictionary = {}


func apply(p: CombatPose, w: float) -> void:
	var up := p.model_dir(Vector3.UP)
	var f := p.to_skel_dir(p.aim_dir)
	var f_h := f - up * f.dot(up)
	if f_h.length_squared() < 1e-6:
		f_h = p.model_dir(Vector3.BACK)
	f_h = f_h.normalized()
	var right := f_h.cross(up).normalized()
	var m := p.unit()
	var key := _current()

	# 1. Tronco: el pecho hacia donde toca respecto al blanco, e inclinado adelante o atrás.
	var shoulders := p.bone_pos(L_ARM[0]) - p.bone_pos(R_ARM[0])
	shoulders = (shoulders - up * shoulders.dot(up)).normalized()
	var chest := shoulders.cross(up)
	var facing := rad_to_deg(atan2(up.dot(f_h.cross(chest)), f_h.dot(chest)))
	var yaw := clampf(float(key.yaw) - facing, -85.0, 85.0)
	for i in SPINE.size():
		p.rotate_bone(SPINE[i], Quaternion(up, deg_to_rad(yaw * SPINE_SHARE[i] * w)))
	var lean_axis := up.cross(f_h).normalized()
	for i in SPINE.size():
		p.rotate_bone(SPINE[i], Quaternion(lean_axis, deg_to_rad(float(key.lean) * SPINE_SHARE[i] * w)))
	# 2. Cadera: el peso atrás al cargar y adelante al lanzar.
	var hips := p.bone_idx(CombatPose.B_HIPS)
	var skel := p.skeleton()
	if hips >= 0:
		var hv: Vector2 = key.hips
		var shift := (f_h * hv.x - up * hv.y) * m * w
		skel.set_bone_pose_position(hips, skel.get_bone_pose_position(hips) + shift)
	# 3. Cabeza al blanco.
	var face := p.face_frame()
	p.rotate_bone(CombatPose.NECK[0], Quaternion.IDENTITY.slerp(p.arc(face.z, f), 0.4 * w))
	face = p.face_frame()
	p.rotate_bone(CombatPose.NECK[1], Quaternion.IDENTITY.slerp(p.arc(face.z, f), 0.85 * w))
	# 4. Brazos.
	var frame := func(v: Vector3) -> Vector3:
		return right * v.x + up * v.y + f * v.z
	var rs := p.bone_pos(R_ARM[0])
	var ls := p.bone_pos(L_ARM[0])
	var r_target: Vector3 = rs + frame.call(key.r_hand) * m
	var l_target: Vector3 = ls + frame.call(key.l_hand) * m
	p.two_bone(R_ARM, r_target, frame.call(key.r_pole), w)
	p.two_bone(L_ARM, l_target, frame.call(key.l_pole), w)
	# Mano de la lanza: palma arriba con la lanza cruzando la palma hacia el blanco; al soltar
	# la muñeca rompe hacia delante.
	var palm: Vector3 = (frame.call(key.palm) as Vector3).normalized()
	var r_dir := right.lerp(f, clampf(palm.dot(f), 0.0, 1.0) * 0.6).normalized()
	if absf(r_dir.dot(palm)) > 0.95:
		r_dir = right
	p.orient_hand("Right", r_dir, palm, w)
	p.orient_hand("Left", (l_target - p.bone_pos(L_ARM[1])).normalized(), -right * 0.3 - up, w * 0.7)
	var released := throw_t >= RELEASE_AT
	var open := smoothstep(RELEASE_AT, RELEASE_AT + 0.05, throw_t) if throw_t >= 0.0 else 0.0
	p.pose_fingers("Right", CombatPose.blend_fingers(SPEAR_FINGERS, ArcheryPose.OPEN, open), w)
	var point := 1.0 - smoothstep(0.0, 0.12, throw_t) if throw_t >= 0.0 else 1.0
	p.pose_fingers("Left", CombatPose.blend_fingers(ArcheryPose.RELAXED, POINT_FINGERS, point), w * 0.8)
	# 5. Pie izquierdo adelante al cargar y lanzar.
	var step := float(key.step) * w
	if step > 0.001:
		var foot := p.bone_pos(CombatPose.L_LEG[2])
		var knee := p.model_dir(Vector3.BACK)
		var lift := sin(clampf(step / 0.24, 0.0, 1.0) * PI) * 0.03 if throw_t >= 0.0 and throw_t < 0.2 else 0.0
		p.two_bone(CombatPose.L_LEG, foot + (f_h * step + up * lift) * m, knee, 1.0)
	# Resultado: dónde va la lanza (la mano real tras posar). -Z = hacia donde apunta.
	var hand := p.hand_frame("Right")
	var grip := p.bone_pos(R_ARM[2]) + (hand.x * 0.055 + hand.y * 0.03) * m
	var spear_dir := -hand.z
	if not released:
		# Mientras la sostiene, que apunte al blanco aunque la mano no llegue del todo.
		spear_dir = spear_dir.slerp(f, 0.6).normalized()
	var to_world := skel.global_transform
	var z := -(to_world.basis * spear_dir).normalized()
	var y := (to_world.basis * up).normalized()
	var x := y.cross(z).normalized()
	grip_xform = Transform3D(Basis(x, z.cross(x), z), to_world * grip)


## Postura clave del momento: entre lista y cargada según la carga; lanzando, por el tiempo.
func _current() -> Dictionary:
	if throw_t < 0.0:
		_last_draw = draw
		_from = _mix(READY, COCKED, smoothstep(0.0, 1.0, draw))
		return _from
	if _from.is_empty():
		_from = _mix(READY, COCKED, smoothstep(0.0, 1.0, _last_draw))
	var keys := [[0.0, _from], [RELEASE_AT, RELEASE], [0.3, FOLLOW], [THROW_TIME, SETTLE]]
	var k := 0
	while k < keys.size() - 2 and throw_t > keys[k + 1][0]:
		k += 1
	var a: Array = keys[k]
	var b: Array = keys[k + 1]
	var t := clampf((throw_t - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	# El brazo acelera (látigo): tarda en arrancar y llega de golpe.
	if k == 0:
		t = t * t * (3.0 - 2.0 * t) * 0.35 + t * t * 0.65
	else:
		t = smoothstep(0.0, 1.0, t)
	return _mix(a[1], b[1], t)


static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a:
		var va: Variant = a[key]
		var vb: Variant = b[key]
		if va is float:
			out[key] = lerpf(va, vb, t)
		elif va is Vector2:
			out[key] = (va as Vector2).lerp(vb, t)
		else:
			out[key] = (va as Vector3).lerp(vb, t)
	return out
