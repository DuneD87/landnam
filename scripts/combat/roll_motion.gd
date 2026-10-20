class_name RollMotion
extends RefCounted

## Voltereta de esquiva: curvas de tiempo, giro del cuerpo y apoyo en el suelo. La usan
## PlayerCombat (en el juego) y tests/combat/roll_preview.gd (banco de pruebas), así que lo que
## se ve en uno es lo que se ve en el otro.
##
## x va de 0 a 1 a lo largo de la esquiva. El cuerpo pasa por ocho posturas clave, asimétricas
## e interpoladas con curvas (sin detenerse en ninguna), mientras da la vuelta entera en diagonal
## sobre un hombro:
##   0,02 preparación: un paso con los brazos atrás, cogiendo impulso,
##   0,12 impulso: se lanza con una pierna atrás y los brazos buscando el suelo,
##   0,24 apoyo: manos al suelo, barbilla al pecho, las piernas llegan,
##   0,42 de espaldas: ovillo cerrado,
##   0,58 se incorpora: piernas abriéndose hacia el suelo, brazos adelante para tirar del peso,
##   0,74 aterriza en cuclillas con un pie plantado y la otra rodilla baja,
##   0,88 arranca a correr y 1,0 la siguiente zancada, mientras se funde con la carrera.
## Nada se queda quieto: cada tramo tiene su propio recorrido de brazos y piernas.
## Manos, antebrazos, pies y cabeza van un poco por detrás del tronco (inercia).
## El cuerpo gira alrededor del centro del ovillo y, en cada fotograma, se sube o se baja lo justo
## para que su punto más bajo quede en el suelo: rueda apoyado, ni se hunde ni flota.

## Huesos que pueden tocar el suelo y cuánto sobresale la carne de cada uno (m).
const CONTACT_BONES := {
	HumanRig.HIPS: 0.12, HumanRig.SPINE: 0.12, HumanRig.SPINE1: 0.13,
	HumanRig.SPINE2: 0.13, HumanRig.NECK: 0.06, HumanRig.HEAD: 0.10,
	HumanRig.HEAD_TOP_END: 0.03,
	HumanRig.LEFT_ARM: 0.06, HumanRig.RIGHT_ARM: 0.06,
	HumanRig.LEFT_FORE_ARM: 0.05, HumanRig.RIGHT_FORE_ARM: 0.05,
	HumanRig.LEFT_HAND: 0.04, HumanRig.RIGHT_HAND: 0.04,
	HumanRig.LEFT_UP_LEG: 0.09, HumanRig.RIGHT_UP_LEG: 0.09,
	HumanRig.LEFT_LEG: 0.06, HumanRig.RIGHT_LEG: 0.06,
	HumanRig.LEFT_FOOT: 0.06, HumanRig.RIGHT_FOOT: 0.06,
	HumanRig.LEFT_TOE_BASE: 0.03, HumanRig.RIGHT_TOE_BASE: 0.03,
	HumanRig.LEFT_TOE_END: 0.02, HumanRig.RIGHT_TOE_END: 0.02,
}
## Huesos cuyo centro marca el eje del ovillo.
const PIVOT_BONES := [HumanRig.HIPS, HumanRig.SPINE1, HumanRig.LEFT_LEG,
	HumanRig.RIGHT_LEG, HumanRig.SPINE2]
## Cuánto se desvía el eje de la vuelta respecto al lateral: rueda en diagonal sobre el hombro
## derecho, no de cabeza.
const SHOULDER_TILT_DEG := 22.0


## Ovillo simple (lo usa el paso atrás como agachada).
static func tuck(x: float) -> float:
	return smoothstep(0.0, 0.18, x) * (1.0 - smoothstep(0.70, 0.97, x))


static func angle(x: float) -> float:
	var t := clampf((x - 0.06) / 0.72, 0.0, 1.0)
	# smootherstep: arranca y termina sin tirón.
	return TAU * t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## Eje de giro en el marco del modelo (+X es la izquierda del personaje: girar en positivo sobre
## +X lleva la cabeza hacia delante). [mirror] rueda sobre el hombro izquierdo.
static func axis(mirror: bool = false) -> Vector3:
	var tilt := SHOULDER_TILT_DEG if mirror else -SHOULDER_TILT_DEG
	return Basis(Vector3.UP, deg_to_rad(tilt)) * Vector3.RIGHT


# ---------------------------------------------------------------------------------------------
# Posturas clave


## Segmentos que anima la voltereta: [hueso, hijo, clave]. Cada clave es la dirección del
## segmento en el marco del modelo sin girar (+Z adelante, +Y arriba, +X izquierda).
const SEGMENTS := [
	[HumanRig.HIPS, HumanRig.SPINE, "s0"],
	[HumanRig.SPINE, HumanRig.SPINE1, "s1"],
	[HumanRig.SPINE1, HumanRig.SPINE2, "s2"],
	[HumanRig.SPINE2, HumanRig.NECK, "s3"],
	[HumanRig.NECK, HumanRig.HEAD, "s4"],
	[HumanRig.HEAD, HumanRig.HEAD_TOP_END, "s5"],
	[HumanRig.LEFT_UP_LEG, HumanRig.LEFT_LEG, "lthigh"],
	[HumanRig.LEFT_LEG, HumanRig.LEFT_FOOT, "lshin"],
	[HumanRig.LEFT_FOOT, HumanRig.LEFT_TOE_BASE, "lfoot"],
	[HumanRig.RIGHT_UP_LEG, HumanRig.RIGHT_LEG, "rthigh"],
	[HumanRig.RIGHT_LEG, HumanRig.RIGHT_FOOT, "rshin"],
	[HumanRig.RIGHT_FOOT, HumanRig.RIGHT_TOE_BASE, "rfoot"],
	[HumanRig.LEFT_ARM, HumanRig.LEFT_FORE_ARM, "larm"],
	[HumanRig.LEFT_FORE_ARM, HumanRig.LEFT_HAND, "lfore"],
	[HumanRig.RIGHT_ARM, HumanRig.RIGHT_FORE_ARM, "rarm"],
	[HumanRig.RIGHT_FORE_ARM, HumanRig.RIGHT_HAND, "rfore"],
]

## Retraso (en x) de cada segmento respecto al tronco: lo que cuelga más lejos llega después.
const LAG := {"s4": 0.012, "s5": 0.02, "lshin": 0.02, "rshin": 0.02, "lfoot": 0.035, "rfoot": 0.035,
	"lfore": 0.025, "rfore": 0.025}

## Postura clave: x y, por clave, dirección. Las del tronco (s0..s5) se dan como ángulo desde
## +Y hacia +Z (0 = erguido, 90 = horizontal hacia delante); el resto, como vector.
const KEYS := [
	# Preparación: un paso con el peso adelante y los brazos atrás, cogiendo impulso.
	{"x": 0.02, "spine": [10.0, 16.0, 22.0, 28.0, 32.0, 36.0],
		"lthigh": Vector3(0.08, -0.95, 0.30), "lshin": Vector3(0.05, -0.90, -0.43), "lfoot": Vector3(0.0, -0.40, 0.90),
		"rthigh": Vector3(-0.08, -0.90, -0.40), "rshin": Vector3(-0.03, -0.60, -0.80), "rfoot": Vector3(0.0, -0.70, -0.70),
		"larm": Vector3(0.25, -0.85, -0.45), "lfore": Vector3(0.10, -0.80, 0.30),
		"rarm": Vector3(-0.25, -0.85, -0.40), "rfore": Vector3(-0.10, -0.80, 0.35)},
	# Impulso: se lanza con una pierna atrás y los brazos por delante, buscando el suelo.
	{"x": 0.12, "spine": [20.0, 38.0, 55.0, 72.0, 95.0, 115.0],
		"lthigh": Vector3(0.08, -0.80, -0.40), "lshin": Vector3(0.05, -0.35, -0.94), "lfoot": Vector3(0.0, -0.20, -0.98),
		"rthigh": Vector3(-0.10, -0.55, 0.83), "rshin": Vector3(-0.05, -0.98, -0.20), "rfoot": Vector3(0.0, -0.35, 0.94),
		"larm": Vector3(0.22, -0.35, 0.91), "lfore": Vector3(0.08, -0.55, 0.83),
		"rarm": Vector3(-0.28, -0.30, 0.91), "rfore": Vector3(-0.10, -0.50, 0.86)},
	# Apoyo: manos al suelo bajo los hombros; el brazo del hombro que rueda se recoge.
	{"x": 0.24, "spine": [30.0, 55.0, 78.0, 100.0, 128.0, 150.0],
		"lthigh": Vector3(0.12, 0.10, 0.99), "lshin": Vector3(0.05, -0.60, -0.80), "lfoot": Vector3(0.0, -0.60, -0.80),
		"rthigh": Vector3(-0.12, 0.35, 0.93), "rshin": Vector3(-0.05, -0.40, -0.92), "rfoot": Vector3(0.0, -0.60, -0.80),
		"larm": Vector3(0.25, -0.85, 0.45), "lfore": Vector3(0.05, -0.90, 0.40),
		"rarm": Vector3(-0.15, -0.60, 0.78), "rfore": Vector3(0.20, -0.70, 0.68)},
	# De espaldas: ovillo, abrazando las rodillas.
	{"x": 0.42, "spine": [8.0, 24.0, 42.0, 62.0, 88.0, 112.0],
		"lthigh": Vector3(0.13, 0.62, 0.78), "lshin": Vector3(0.05, -0.22, -0.97), "lfoot": Vector3(0.0, -0.55, -0.83),
		"rthigh": Vector3(-0.13, 0.58, 0.80), "rshin": Vector3(-0.05, -0.28, -0.96), "rfoot": Vector3(0.0, -0.55, -0.83),
		"larm": Vector3(0.30, 0.15, 0.94), "lfore": Vector3(-0.60, -0.20, 0.77),
		"rarm": Vector3(-0.30, 0.10, 0.95), "rfore": Vector3(0.60, -0.20, 0.77)},
	# Se incorpora: brazos adelante y arriba para tirar del peso, piernas buscando el suelo.
	{"x": 0.58, "spine": [5.0, 18.0, 32.0, 48.0, 70.0, 92.0],
		"lthigh": Vector3(0.12, 0.40, 0.91), "lshin": Vector3(0.05, -0.55, -0.83), "lfoot": Vector3(0.0, -0.95, 0.30),
		"rthigh": Vector3(-0.12, 0.25, 0.97), "rshin": Vector3(-0.05, -0.70, -0.71), "rfoot": Vector3(0.0, -0.95, 0.30),
		"larm": Vector3(0.25, 0.35, 0.90), "lfore": Vector3(0.05, 0.30, 0.95),
		"rarm": Vector3(-0.20, 0.25, 0.95), "rfore": Vector3(-0.05, 0.35, 0.94)},
	# Aterriza en cuclillas: un pie plantado, la otra rodilla baja, brazos equilibrando.
	{"x": 0.74, "spine": [15.0, 28.0, 38.0, 45.0, 55.0, 70.0],
		"lthigh": Vector3(0.10, -0.55, 0.83), "lshin": Vector3(0.05, -0.25, -0.97), "lfoot": Vector3(0.0, -0.10, -0.99),
		"rthigh": Vector3(-0.12, 0.15, 0.99), "rshin": Vector3(-0.03, -0.99, -0.10), "rfoot": Vector3(0.0, -0.30, 0.95),
		"larm": Vector3(0.35, -0.75, 0.55), "lfore": Vector3(0.10, -0.50, 0.86),
		"rarm": Vector3(-0.25, -0.88, 0.10), "rfore": Vector3(-0.10, -0.60, 0.80)},
	# Arranca a correr.
	{"x": 0.88, "spine": [10.0, 14.0, 18.0, 20.0, 15.0, 10.0],
		"lthigh": Vector3(0.08, -0.85, 0.52), "lshin": Vector3(0.05, -0.95, -0.30), "lfoot": Vector3(0.0, -0.30, 0.95),
		"rthigh": Vector3(-0.08, -0.95, -0.30), "rshin": Vector3(-0.03, -0.70, -0.71), "rfoot": Vector3(0.0, -0.60, -0.80),
		"larm": Vector3(0.20, -0.90, -0.40), "lfore": Vector3(0.10, -0.40, 0.90),
		"rarm": Vector3(-0.20, -0.80, 0.55), "rfore": Vector3(-0.10, -0.10, 0.99)},
	# Siguiente zancada, mientras se funde con la animación de correr.
	{"x": 1.0, "spine": [8.0, 10.0, 12.0, 14.0, 10.0, 6.0],
		"lthigh": Vector3(0.08, -0.95, -0.30), "lshin": Vector3(0.03, -0.70, -0.71), "lfoot": Vector3(0.0, -0.60, -0.80),
		"rthigh": Vector3(-0.08, -0.85, 0.52), "rshin": Vector3(-0.05, -0.95, -0.30), "rfoot": Vector3(0.0, -0.30, 0.95),
		"larm": Vector3(0.20, -0.85, 0.50), "lfore": Vector3(0.10, -0.15, 0.98),
		"rarm": Vector3(-0.20, -0.90, -0.40), "rfore": Vector3(-0.10, -0.50, 0.85)},
]


## Cuánto manda la voltereta sobre la animación: entra en el impulso y se funde con la carrera.
static func weight(x: float) -> float:
	return smoothstep(0.0, 0.10, x) * (1.0 - smoothstep(0.84, 1.0, x))


static func _key_dir(key: Dictionary, name: String) -> Vector3:
	if name.begins_with("s"):
		var deg: float = key.spine[int(name.substr(1))]
		return Vector3(0.0, cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))
	return (key[name] as Vector3).normalized()


## Dirección de la clave [name] en la fase [x]: spline de Hermite entre posturas, con tangentes
## de Catmull-Rom, así el cuerpo fluye por las posturas sin frenar en cada una. [mirror] rueda
## sobre el otro hombro: izquierda y derecha se intercambian y el eje X cambia de signo.
static func direction(name: String, x: float, mirror: bool = false) -> Vector3:
	var source := name
	if mirror and (name.begins_with("l") or name.begins_with("r")):
		source = ("r" if name.begins_with("l") else "l") + name.substr(1)
	var t := x - float(LAG.get(source, 0.0))
	var n := KEYS.size()
	var dir: Vector3
	if t <= KEYS[0].x:
		dir = _key_dir(KEYS[0], source)
	elif t >= KEYS[n - 1].x:
		dir = _key_dir(KEYS[n - 1], source)
	else:
		var i := 0
		while i < n - 2 and t > KEYS[i + 1].x:
			i += 1
		var x0: float = KEYS[i].x
		var x1: float = KEYS[i + 1].x
		var p0 := _key_dir(KEYS[i], source)
		var p1 := _key_dir(KEYS[i + 1], source)
		var prev := _key_dir(KEYS[maxi(i - 1, 0)], source)
		var next := _key_dir(KEYS[mini(i + 2, n - 1)], source)
		var xp: float = KEYS[maxi(i - 1, 0)].x
		var xn: float = KEYS[mini(i + 2, n - 1)].x
		var h := x1 - x0
		var m0 := (p1 - prev) / maxf(x1 - xp, 1e-4) * h
		var m1 := (next - p0) / maxf(xn - x0, 1e-4) * h
		var u := (t - x0) / h
		var u2 := u * u
		var u3 := u2 * u
		dir = p0 * (2.0 * u3 - 3.0 * u2 + 1.0) + m0 * (u3 - 2.0 * u2 + u) \
			+ p1 * (-2.0 * u3 + 3.0 * u2) + m1 * (u3 - u2)
	if mirror:
		dir.x = -dir.x
	return dir.normalized() if dir.length_squared() > 1e-8 else Vector3.UP


## Transform de PlayerModel respecto al cuerpo para la fase [x]. [points] y [radii] son los
## huesos de contacto en el espacio del modelo sin girar (pose actual, ya encogida).
## [ground_normal] y [ground_offset] describen el suelo en el espacio del cuerpo (normal·p =
## offset); por defecto, el plano de los pies. En una ladera el apoyo se mide contra ella, y el
## ajuste se hace en vertical para no desplazar la voltereta de su sitio.
static func model_transform(x: float, points: PackedVector3Array, radii: PackedFloat32Array,
		pivot: Vector3, ground_normal: Vector3 = Vector3.UP, ground_offset: float = 0.0,
		mirror: bool = false) -> Transform3D:
	var basis := Basis(axis(mirror), angle(x))
	var xform := Transform3D(basis, pivot - basis * pivot)
	if points.is_empty():
		return xform
	var n := ground_normal.normalized()
	var lowest := INF
	for i in points.size():
		lowest = minf(lowest, n.dot(xform * points[i]) - ground_offset - radii[i])
	xform.origin.y -= lowest / maxf(n.y, 0.4)
	return xform


## Cuánto hay que subir el cuerpo (en su vertical) para que ningún hueso de contacto quede
## bajo el suelo. Nunca baja: una animación que se despega del suelo (un salto) se respeta.
static func ground_lift(points: PackedVector3Array, radii: PackedFloat32Array,
		ground_normal: Vector3 = Vector3.UP, ground_offset: float = 0.0) -> float:
	var n := ground_normal.normalized()
	var lowest := INF
	for i in points.size():
		lowest = minf(lowest, n.dot(points[i]) - ground_offset - radii[i])
	if lowest == INF or lowest >= 0.0:
		return 0.0
	return -lowest / maxf(n.y, 0.4)


## Recoge los huesos de contacto de [skeleton] en el espacio de [model] (sin su giro actual).
## Devuelve {points, radii, pivot}.
static func sample(skeleton: Skeleton3D, model: Node3D, cache: Dictionary) -> Dictionary:
	if cache.is_empty():
		for bone_name in CONTACT_BONES:
			cache[bone_name] = skeleton.find_bone(bone_name)
	var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var pivot := Vector3.ZERO
	var pivot_count := 0
	for bone_name in CONTACT_BONES:
		var idx: int = cache[bone_name]
		if idx < 0:
			continue
		var p := to_model * skeleton.get_bone_global_pose(idx).origin
		points.append(p)
		radii.append(CONTACT_BONES[bone_name])
		if bone_name in PIVOT_BONES:
			pivot += p
			pivot_count += 1
	if pivot_count > 0:
		pivot /= pivot_count
	return {"points": points, "radii": radii, "pivot": pivot}
