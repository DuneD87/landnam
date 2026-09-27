class_name ArcheryPose
extends RefCounted

## Ciclo del arquero montado por código sobre el cuerpo (lo llama CombatPose con el peso de
## apuntar, dentro del modificador del esqueleto):
##
##   - de perfil al blanco: el tronco gira hasta poner la línea de hombros en la de tiro y se
##     inclina entero (en T) para tiros altos o bajos; la cabeza mira al blanco algo ladeada,
##   - brazo del arco casi recto con el codo girado fuera de la cuerda y el hombro bajo; la mano
##     cierra el puño alrededor de la empuñadura, que queda en diagonal por la palma,
##   - la mano de la cuerda engancha con tres dedos y tira por la línea de la flecha hasta el
##     anclaje bajo el pómulo; el codo sube detrás, en línea con la flecha, y la escápula se
##     cierra,
##   - sostener mucho rato o sin aguante hace temblar el pulso,
##   - al soltar, los dedos se abren, la mano sigue hacia atrás rozando la mandíbula, la cuerda
##     vibra y el arco cabecea hacia delante,
##   - recarga: la mano va por encima del hombro a la aljaba de la espalda, saca una flecha, la
##     trae por fuera de la cabeza y la encaja en la cuerda mientras el brazo del arco baja un
##     poco y vuelve a subir.
##
## Todo se calcula en el espacio del esqueleto a partir de la dirección de tiro, así que vale
## con cualquier animación debajo (quieto, andando) y con el cuerpo girado. Deja en sus
## resultados dónde van el arco, la cuerda y la flecha, para que quien los lleva los coloque en
## el mismo fotograma.

const SPINE := CombatPose.SPINE
const L_ARM := CombatPose.L_ARM
const R_ARM := CombatPose.R_ARM

## Reparto del giro y la inclinación del tronco entre las vértebras (de abajo arriba).
const SPINE_SHARE := [0.25, 0.35, 0.40]
## Cuánto del giro hasta ponerse de perfil hace el tronco, y el máximo (grados).
const TORSO_SIDE := 0.92
const TORSO_MAX := 70.0
## Inclinación máxima del tronco hacia tiros altos o bajos; el resto lo ponen brazos y cabeza.
const TORSO_PITCH_MAX := 32.0
## Cabeza ladeada hacia la cuerda (grados).
const HEAD_TILT := 7.0

## Anclaje a tope bajo el pómulo derecho, respecto al hueso de la cabeza y en el marco de la
## cara (x a su derecha, y arriba, z adelante), en metros.
const ANCHOR := Vector3(0.05, 0.0, 0.07)
## La flecha va apoyada sobre el nudillo del índice, por encima del centro del puño.
const ARROW_REST := 0.035
## Inclinación del arco (grados): la pala de arriba hacia fuera de la cara.
const CANT := 10.0
## Brazo del arco casi recto (fracción del largo del brazo).
const BOW_REACH := 0.975
## Centro de la empuñadura respecto a la muñeca, en el marco de la mano (adelante, palma).
const GRIP_OFFSET := Vector2(0.075, 0.03)
## Cuerda en el pliegue de la primera falange, respecto a la muñeca (adelante, palma).
const NOCK_OFFSET := Vector2(0.105, 0.03)

## Duración de la recarga completa, en segundos (la cuenta PlayerCombat).
const RELOAD_TIME := 0.72

## Dedos (ver CombatPose.pose_fingers).
const GRIP := {"Index": Vector3(60, 70, 40), "Middle": Vector3(68, 78, 42), "Ring": Vector3(72, 78, 40),
	"Pinky": Vector3(76, 72, 38), "Thumb": Vector3(45, 25, 25)}
const HOOK := {"Index": Vector3(10, 72, 55), "Middle": Vector3(10, 75, 55), "Ring": Vector3(16, 72, 50),
	"Pinky": Vector3(55, 85, 60), "Thumb": Vector3(55, 35, 30)}
const OPEN := {"Index": Vector3(4, 10, 6), "Middle": Vector3(4, 10, 6), "Ring": Vector3(8, 12, 8),
	"Pinky": Vector3(14, 16, 10), "Thumb": Vector3(15, 5, 5)}
const RELAXED := {"Index": Vector3(18, 30, 18), "Middle": Vector3(22, 35, 20), "Ring": Vector3(28, 38, 22),
	"Pinky": Vector3(34, 40, 22), "Thumb": Vector3(25, 15, 10)}
const PINCH := {"Index": Vector3(35, 45, 25), "Middle": Vector3(50, 65, 40), "Ring": Vector3(60, 72, 45),
	"Pinky": Vector3(66, 72, 45), "Thumb": Vector3(55, 20, 20)}

# --- Entradas (las pone PlayerCombat o el escenario de pruebas) ---

## 0..1 tensión de la cuerda.
var draw: float = 0.0
## Segundos desde que soltó la flecha, o negativo.
var release_t: float = -1.0
## 0..1 avance de la recarga, o negativo si no está recargando.
var reload: float = -1.0
## Segundos sosteniendo la cuerda a tope.
var hold_t: float = 0.0
## 0..1 cansancio (aguante bajo): el pulso tiembla más.
var fatigue: float = 0.0
## Hay flecha encajada (sin munición, el arco va vacío).
var nocked: bool = true

# --- Resultados, en mundo ---

var bow_xform: Transform3D
## 0..1 cuánto se doblan las palas.
var bow_flex: float = 0.0
## Punto de la cuerda donde tira (o vibra) y si la cuerda va a ese punto o está en reposo.
var string_point: Vector3
var string_pulled: bool = false
## "" sin flecha a la vista, &"nocked" en la cuerda, &"hand" en la mano (recarga).
var arrow_mode: StringName = &""
var arrow_xform: Transform3D

var _time: float = 0.0
var _last_draw: float = 0.0
var _release_draw: float = 0.0
var _last_release_t: float = -1.0


## Aljaba a la espalda: boca por encima del hombro derecho. Respecto al hueso Spine2 y en el
## marco del cuerpo (x a la izquierda, y arriba, z adelante), en metros; +Y del transform es la
## salida de las flechas. La usan la pose (a dónde va la mano) y quien la dibuja.
const QUIVER_MOUTH := Vector3(-0.12, 0.25, -0.17)
const QUIVER_AXIS := Vector3(-0.42, 1.0, -0.2)
const QUIVER_LENGTH := 0.56


## Transform de la aljaba en el espacio del esqueleto (origen en la boca, +Y hacia fuera).
static func quiver_skel(p: CombatPose) -> Transform3D:
	var m := p.unit()
	var torso := p.rest_delta(SPINE[2])
	var to_skel := func(v: Vector3) -> Vector3:
		return torso * (p.model_dir(Vector3.RIGHT) * v.x + p.model_dir(Vector3.UP) * v.y + p.model_dir(Vector3.BACK) * v.z)
	var mouth: Vector3 = p.bone_pos(SPINE[2]) + to_skel.call(QUIVER_MOUTH) * m
	var y: Vector3 = (to_skel.call(QUIVER_AXIS) as Vector3).normalized()
	var back: Vector3 = to_skel.call(Vector3(0, 0, -1))
	var x := y.cross(back).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), mouth)


func apply(p: CombatPose, w: float, delta: float) -> void:
	_time += delta
	var skel := p.skeleton()
	var m := p.unit()
	var up := p.model_dir(Vector3.UP)
	var f := p.to_skel_dir(p.aim_dir)
	var f_h := f - up * f.dot(up)
	if f_h.length_squared() < 1e-6:
		f_h = p.model_dir(Vector3.BACK)
	f_h = f_h.normalized()
	var l := up.cross(f_h).normalized()
	var pitch := rad_to_deg(asin(clampf(f.dot(up), -1.0, 1.0)))

	# Fases.
	if release_t >= 0.0 and (_last_release_t < 0.0 or release_t < _last_release_t):
		_release_draw = _last_draw
	_last_release_t = release_t
	if release_t < 0.0:
		_last_draw = draw
	var releasing := release_t >= 0.0 and reload < 0.0
	var rl := clampf(reload, 0.0, 1.0) if reload >= 0.0 else -1.0
	# El brazo del arco baja un poco mientras la otra mano va a la aljaba.
	var lower := sin(PI * rl) if rl >= 0.0 else 0.0
	var dd := draw if not releasing else 0.0

	# 1. Tronco de perfil: la línea de hombros a la de tiro.
	var shoulders := p.bone_pos(L_ARM[0]) - p.bone_pos(R_ARM[0])
	shoulders = (shoulders - up * shoulders.dot(up)).normalized()
	var yaw := rad_to_deg(atan2(up.dot(shoulders.cross(f_h)), shoulders.dot(f_h)))
	yaw = clampf(yaw * TORSO_SIDE, -TORSO_MAX, TORSO_MAX) * (1.0 - 0.15 * lower)
	for i in SPINE.size():
		p.rotate_bone(SPINE[i], Quaternion(up, deg_to_rad(yaw * SPINE_SHARE[i] * w)))
	# 2. Tiros altos o bajos: la T entera se inclina por la cintura.
	var lean := clampf(pitch, -TORSO_PITCH_MAX, TORSO_PITCH_MAX) * (1.0 - 0.6 * lower)
	for i in SPINE.size():
		p.rotate_bone(SPINE[i], Quaternion(l, deg_to_rad(-lean * SPINE_SHARE[i] * w)))
	# 3. Escápulas: el hombro del arco abajo y asentado; el de la cuerda se cierra al tensar.
	var back := l
	p.swing_bone("mixamorig_LeftShoulder", L_ARM[0], -up, 7.0 * w)
	p.swing_bone("mixamorig_RightShoulder", R_ARM[0], back, 12.0 * dd * w)
	p.swing_bone("mixamorig_RightShoulder", R_ARM[0], up, (4.0 * dd + 10.0 * lower) * w)

	# 4. Cabeza al blanco, algo ladeada hacia la cuerda.
	var face := p.face_frame()
	var look := p.arc(face.z, f)
	p.rotate_bone(CombatPose.NECK[0], Quaternion.IDENTITY.slerp(look, 0.4 * w))
	face = p.face_frame()
	look = p.arc(face.z, f)
	p.rotate_bone(CombatPose.NECK[1], Quaternion.IDENTITY.slerp(look, w))
	p.rotate_bone(CombatPose.NECK[1], Quaternion(f, deg_to_rad(-HEAD_TILT * w * (1.0 - lower))))
	face = p.face_frame()
	var head := p.bone_pos(CombatPose.NECK[1])
	var anchor := head + (face.x * ANCHOR.x + face.y * ANCHOR.y + face.z * ANCHOR.z) * m

	# 5. Arco: la flecha pasa por el anclaje en la dirección de tiro; el puño va donde el brazo
	# queda casi recto.
	var y_b := (up - f * up.dot(f)).normalized().rotated(f, deg_to_rad(-CANT))
	var x_b := y_b.cross(f)
	var l_palm := (-x_b * 0.9 - y_b * 0.35).normalized()
	var l_dir := (f - x_b * 0.18).normalized()
	l_palm = (l_palm - l_dir * l_palm.dot(l_dir)).normalized()
	var grip_off := (l_dir * GRIP_OFFSET.x + l_palm * GRIP_OFFSET.y) * m
	var ls := p.bone_pos(L_ARM[0])
	var reach := (ls.distance_to(p.bone_pos(L_ARM[1])) + p.bone_pos(L_ARM[1]).distance_to(p.bone_pos(L_ARM[2]))) * BOW_REACH
	var c0 := anchor - y_b * ARROW_REST * m - grip_off - ls
	var b := f.dot(c0)
	var disc := b * b - c0.length_squared() + reach * reach
	var draw_len := -b + sqrt(maxf(disc, 0.0))
	var grip := anchor + f * draw_len - y_b * ARROW_REST * m
	# Pulso: temblor al sostener mucho o sin aguante, y la respiración.
	var shake := clampf((hold_t - 1.0) / 2.5, 0.0, 1.0) * 0.003 + fatigue * 0.004
	var tremble := (up * (sin(_time * 41.0) + 0.5 * sin(_time * 67.0 + 1.3))
		+ l * (sin(_time * 37.0 + 2.1) + 0.5 * sin(_time * 59.0))) * shake * m
	tremble += up * sin(_time * 1.9) * 0.002 * m * w
	grip += tremble
	# Al soltar, el arco empuja hacia el blanco y cae un poco.
	var bow_nod := 0.0
	if release_t >= 0.0:
		var k := _kick(release_t)
		grip += (f * 0.012 - up * 0.02) * m * k
		bow_nod = 11.0 * k
	# Recarga: el brazo baja y se recoge un poco.
	if lower > 0.0:
		grip = ls + (grip - ls).rotated(l, deg_to_rad(16.0 * lower)) * (1.0 - 0.06 * lower)
	var bow_basis := Basis(x_b, y_b, f).rotated(x_b, deg_to_rad(bow_nod)).orthonormalized()
	l_dir = Basis(x_b, deg_to_rad(bow_nod)) * l_dir
	l_palm = Basis(x_b, deg_to_rad(bow_nod)) * l_palm
	if lower > 0.0:
		bow_basis = bow_basis.rotated(l, deg_to_rad(16.0 * lower)).orthonormalized()
		l_dir = l_dir.rotated(l, deg_to_rad(16.0 * lower))
		l_palm = l_palm.rotated(l, deg_to_rad(16.0 * lower))
	var l_wrist := grip - (l_dir * GRIP_OFFSET.x + l_palm * GRIP_OFFSET.y) * m
	var bow_want := Transform3D(bow_basis, grip)
	var l_want := Transform3D(Basis(l_dir, l_palm, l_dir.cross(l_palm)), l_wrist)

	# 6. Mano de la cuerda.
	var string_rest := bow_want * (Vector3(0, ARROW_REST, WeaponMeshes.bow_tip(true).z) * m)
	var r_dir := (f - y_b * 0.12).normalized()
	var r_palm := x_b
	var nock := string_rest.lerp(anchor, _ease_draw(dd)) + tremble
	var r_fingers: Dictionary = HOOK
	var r_pole := -f * 0.9 + up * 0.08 + l * 0.25
	if releasing:
		# Suelta: los dedos se abren al instante y la mano sigue hacia atrás por la mandíbula.
		var from := string_rest.lerp(anchor, _ease_draw(_release_draw))
		var follow := 1.0 - exp(-release_t / 0.04)
		var settle := smoothstep(0.35, 0.8, release_t)
		nock = from + ((-f * 0.10 - face.x * 0.02 - up * 0.01) * follow * _release_draw * (1.0 - 0.3 * settle)) * m
		r_fingers = CombatPose.blend_fingers(OPEN, RELAXED, settle)
	if rl >= 0.0:
		var path := _reload_path(p, anchor, string_rest, face, f, up, rl)
		nock = path.point
		r_dir = path.dir
		r_palm = path.palm
		r_fingers = path.fingers
		r_pole = r_pole.lerp(up * 0.9 + f * 0.3 - l * 0.2, lower)
	var r_off := (r_dir * NOCK_OFFSET.x + (r_palm - r_dir * r_palm.dot(r_dir)).normalized() * NOCK_OFFSET.y) * m
	var r_wrist := nock - r_off
	var rn := (r_palm - r_dir * r_palm.dot(r_dir)).normalized()
	var r_want := Transform3D(Basis(r_dir, rn, r_dir.cross(rn)), r_wrist)

	# 7. Brazos, manos y dedos.
	p.two_bone(L_ARM, l_wrist, l * 0.7 - up * 0.7, w)
	p.two_bone(R_ARM, r_wrist, r_pole, w)
	p.orient_hand("Left", l_dir, l_palm, w)
	p.orient_hand("Right", r_dir, rn, w)
	p.pose_fingers("Left", GRIP, w)
	p.pose_fingers("Right", r_fingers, w)

	# 8. Resultados: el arco va con la mano real (con peso < 1 aún no ha llegado).
	var l_now := _hand_xform(p, "Left")
	var r_now := _hand_xform(p, "Right")
	var bow_skel := l_now * (l_want.affine_inverse() * bow_want)
	var nock_skel := r_now * (r_want.affine_inverse() * nock)
	var to_world := skel.global_transform
	bow_xform = Transform3D((to_world.basis * bow_skel.basis).orthonormalized(), to_world * bow_skel.origin)
	string_pulled = not releasing and rl < 0.0 and nocked
	var rest_world := to_world * (bow_skel * (Vector3(0, ARROW_REST, WeaponMeshes.bow_tip(true).z) * m))
	string_point = to_world * nock_skel if string_pulled else rest_world
	bow_flex = _ease_draw(dd) if string_pulled else 0.0
	if release_t >= 0.0 and release_t < 0.6:
		# La cuerda vuelve de golpe y vibra; las palas rebotan.
		var vib := exp(-release_t * 11.0)
		string_point = rest_world + (to_world.basis * x_b).normalized() * 0.006 * sin(release_t * TAU * 22.0) * vib
		bow_flex = _release_draw * exp(-release_t * 28.0) * cos(release_t * 50.0)
	arrow_mode = &""
	var arrow_rest_world := to_world * (bow_skel * (Vector3(0, ARROW_REST, 0) * m))
	if rl >= 0.0 and rl >= 0.38:
		var path := _reload_path(p, anchor, string_rest, face, f, up, rl)
		arrow_mode = &"hand" if rl < 0.97 else &"nocked"
		var pinch := to_world * (r_now * (r_want.affine_inverse() * nock))
		var dir: Vector3 = (to_world.basis * (path.arrow as Vector3)).normalized()
		if rl >= 0.82:
			# Ya sobre el arco: la flecha va de los dedos al apoyo de la flecha.
			dir = dir.slerp((arrow_rest_world - pinch).normalized(), smoothstep(0.82, 0.95, rl))
		arrow_xform = _arrow_at(pinch - dir * 0.02, dir, to_world.basis * up)
	elif string_pulled:
		arrow_mode = &"nocked"
		var tail := string_point
		arrow_xform = _arrow_at(tail, (arrow_rest_world - tail).normalized(), to_world.basis * up)


## Flecha con el culatín en [nock] apuntando a [dir] (mundo). La malla va centrada, punta en +Y.
static func _arrow_at(nock: Vector3, dir: Vector3, up: Vector3) -> Transform3D:
	var y := dir.normalized()
	var x := y.cross(up)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), nock + y * (WeaponMeshes.ARROW_LENGTH * 0.5 - 0.012))


## Marco real de la mano tras posar (mismo criterio que hand_frame), con origen en la muñeca.
static func _hand_xform(p: CombatPose, side: String) -> Transform3D:
	return Transform3D(p.hand_frame(side), p.bone_pos("mixamorig_%sHand" % side))


## Recorrido de la mano al tensar: arranca rápido y frena al llegar al anclaje.
static func _ease_draw(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 1.6)


## Golpe del arco al soltar: sube en 50 ms y se apaga.
static func _kick(t: float) -> float:
	if t < 0.05:
		return t / 0.05
	return exp(-(t - 0.05) * 7.0)


## Recarga: la mano sube junto a la oreja, entra en la aljaba, saca la flecha, la trae por
## fuera de la cabeza y la encaja. Devuelve punto de la cuerda (donde van los dedos), orientación
## de la mano, dedos y dirección de la flecha que sostiene.
func _reload_path(p: CombatPose, anchor: Vector3, string_rest: Vector3, face: Basis, f: Vector3,
		up: Vector3, x: float) -> Dictionary:
	var m := p.unit()
	var quiver := quiver_skel(p)
	var q_axis := quiver.basis.y
	var mouth := quiver.origin
	var right := face.x
	# [instante, punto, dirección de los nudillos, palma, dedos]
	var keys := [
		[0.0, anchor - f * 0.08 * m - right * 0.02 * m, f, -right, RELAXED],
		[0.2, p.bone_pos(CombatPose.NECK[1]) + (up * 0.16 + right * 0.14 - f * 0.02) * m, up * 0.6 - f * 0.4, -right, OPEN],
		[0.36, mouth + q_axis * 0.03 * m, -q_axis, f, OPEN],
		[0.44, mouth + q_axis * 0.05 * m, -q_axis, f, PINCH],
		[0.62, mouth + (q_axis * 0.42 + right * 0.08) * m, -q_axis * 0.5 + right * 0.5, f, PINCH],
		[0.84, string_rest + (-f * 0.10 + up * 0.10 + right * 0.06) * m, f + up * 0.2, -right, PINCH],
		[1.0, string_rest, f, -right, HOOK],
	]
	var k := 0
	while k < keys.size() - 2 and x > keys[k + 1][0]:
		k += 1
	var a: Array = keys[k]
	var b: Array = keys[k + 1]
	var t := smoothstep(0.0, 1.0, clampf((x - a[0]) / maxf(b[0] - a[0], 1e-4), 0.0, 1.0))
	# Catmull-Rom entre claves, para que la mano describa curvas y no esquinas.
	var p0: Vector3 = keys[maxi(k - 1, 0)][1]
	var p3: Vector3 = keys[mini(k + 2, keys.size() - 1)][1]
	var point := _catmull(p0, a[1], b[1], p3, t)
	var dir := (a[2] as Vector3).normalized().slerp((b[2] as Vector3).normalized(), t)
	var palm := (a[3] as Vector3).normalized().slerp((b[3] as Vector3).normalized(), t)
	var fingers := CombatPose.blend_fingers(a[4], b[4], t)
	# La flecha (del culatín a la punta): hacia dentro de la aljaba, luego por fuera, luego al blanco.
	var arrow := -q_axis
	if x > 0.5:
		arrow = (-q_axis).slerp((right * 0.8 - up * 0.2 + f * 0.3).normalized(), smoothstep(0.5, 0.66, x))
	if x > 0.66:
		arrow = arrow.slerp(f, smoothstep(0.66, 0.86, x))
	return {"point": point, "dir": dir, "palm": palm, "fingers": fingers, "arrow": arrow}


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
