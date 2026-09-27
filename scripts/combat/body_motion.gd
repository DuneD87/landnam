class_name BodyMotion
extends RefCounted

## Movimientos de cuerpo entero por claves (tambaleo al encajar un golpe, paso atrás), que
## CombatPose monta sobre la animación de estar quieto. Cada curva es una lista de claves
## [x, valor] en la fase 0..1 del movimiento, interpolada con Catmull-Rom (sin esquinas).
##
## Los pies dan pasos de verdad: mientras un pie está apoyado se queda fijo en el suelo aunque
## el cuerpo retroceda (en el marco del cuerpo se desliza hacia delante exactamente lo que el
## cuerpo avanza hacia atrás), y en el aire describe un arco hasta donde aterriza. Para eso
## cada movimiento conoce su perfil de desplazamiento, el mismo con el que PlayerCombat mueve
## el cuerpo.

## Tambaleo: grados de inclinación del tronco hacia el empujón, latigazo de la cabeza, cadera
## empujada (m) y bajada (m), brazos lanzados contra el empujón y abiertos (grados).
const STAGGER := {
	"lean": [[0.0, 0.0], [0.1, 12.0], [0.22, 16.0], [0.45, 9.0], [0.7, -4.0], [0.88, -1.0], [1.0, 0.0]],
	"head": [[0.0, 0.0], [0.06, -9.0], [0.18, 10.0], [0.4, 4.0], [0.7, -2.0], [1.0, 0.0]],
	"hips_push": [[0.0, 0.0], [0.12, 0.07], [0.35, 0.04], [0.7, 0.0], [1.0, 0.0]],
	"hips_down": [[0.0, 0.0], [0.15, 0.05], [0.35, 0.07], [0.65, 0.03], [1.0, 0.0]],
	"arms_fling": [[0.0, 0.0], [0.12, 30.0], [0.3, 40.0], [0.6, 15.0], [1.0, 0.0]],
	"arms_out": [[0.0, 0.0], [0.15, 25.0], [0.35, 30.0], [0.7, 10.0], [1.0, 0.0]],
	"elbows": [[0.0, 0.0], [0.15, 25.0], [0.4, 35.0], [1.0, 10.0]],
	# Pies: [despega, aterriza, dónde aterriza (m a lo largo del empujón), altura del paso (m)].
	# El primero es el del lado del empujón.
	"steps": [[0.02, 0.2, 0.3, 0.12], [0.18, 0.45, 0.12, 0.09]],
}

## Paso atrás (saltito): lo mismo; el empujón es hacia atrás. Los dos pies despegan casi a la
## vez y aterrizan al final, con las rodillas absorbiendo.
const BACKSTEP := {
	"lean": [[0.0, 0.0], [0.15, -6.0], [0.45, -10.0], [0.75, -3.0], [0.9, 2.0], [1.0, 0.0]],
	"head": [[0.0, 0.0], [0.1, 4.0], [0.5, 3.0], [0.8, -3.0], [1.0, 0.0]],
	"hips_push": [[0.0, 0.0], [1.0, 0.0]],
	"hips_down": [[0.0, 0.0], [0.08, 0.06], [0.2, -0.02], [0.5, -0.05], [0.78, 0.02], [0.88, 0.08], [1.0, 0.0]],
	"arms_fling": [[0.0, 0.0], [0.15, 20.0], [0.5, 28.0], [0.85, 12.0], [1.0, 0.0]],
	"arms_out": [[0.0, 0.0], [0.2, 12.0], [0.6, 15.0], [1.0, 0.0]],
	"elbows": [[0.0, 0.0], [0.2, 30.0], [0.6, 40.0], [1.0, 10.0]],
	"steps": [[0.04, 0.8, 0.12, 0.14], [0.08, 0.85, 0.0, 0.12]],
}


## Valor de la curva [keys] en [x] (float o Vector3).
static func sample(keys: Array, x: float) -> Variant:
	if keys.is_empty():
		return 0.0
	if x <= keys[0][0]:
		return keys[0][1]
	var n := keys.size()
	if x >= keys[n - 1][0]:
		return keys[n - 1][1]
	var k := 0
	while k < n - 2 and x > keys[k + 1][0]:
		k += 1
	var a: Array = keys[k]
	var b: Array = keys[k + 1]
	var t: float = (x - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-5)
	var p0: Variant = keys[maxi(k - 1, 0)][1]
	var p3: Variant = keys[mini(k + 2, n - 1)][1]
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * a[1]) + (-p0 + b[1]) * t + (2.0 * p0 - 5.0 * a[1] + 4.0 * b[1] - p3) * t2
		+ (-p0 + 3.0 * a[1] - 3.0 * b[1] + p3) * t3)


## Fracción (0..1) del desplazamiento total recorrida en la fase [x] del tambaleo: la velocidad
## cae en línea recta hasta pararse a 0,556 (PlayerCombat: 1 - 1,8·x).
static func stagger_travel(x: float) -> float:
	x = clampf(x, 0.0, 1.0 / 1.8)
	return (x - 0.9 * x * x) / (1.0 / 1.8 - 0.9 / (1.8 * 1.8))


## Lo mismo para el paso atrás (velocidad 1 - x³).
static func backstep_travel(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return (x - x * x * x * x * 0.25) / 0.75


## Desplazamiento de un pie (m, marco del cuerpo) respecto a donde lo pone la animación, en la
## fase [x]. [push] dirección del movimiento del cuerpo (marco del cuerpo, horizontal),
## [distance] metros que recorre el cuerpo en total y [travel] su perfil. [step] = [despega,
## aterriza, dónde aterriza a lo largo de push, altura].
static func foot_offset(x: float, step: Array, push: Vector3, distance: float, travel: Callable) -> Vector3:
	var lift: float = step[0]
	var land: float = step[1]
	var d := func(at: float) -> float:
		return float(travel.call(at)) * distance
	if x <= lift:
		return -push * d.call(x)
	var landed: Vector3 = push * float(step[2])
	if x >= land:
		return landed - push * (d.call(x) - d.call(land))
	var u := (x - lift) / (land - lift)
	var from: Vector3 = -push * d.call(lift)
	return from.lerp(landed, smoothstep(0.0, 1.0, u)) + Vector3.UP * float(step[3]) * sin(PI * u)
