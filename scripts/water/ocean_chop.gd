class_name OceanChop
extends RefCounted

## Mar de viento del agua (ocean_chop.gdshaderinc): las ondas cortas que solo dibuja la normal por
## píxel. Aquí se fijan sus direcciones y se resuelve cada frame su fase en el ancla (la cámara) con
## los float de GDScript, que son de doble precisión: en el shader, k·posición con el planeta de
## 30 km y omega·tiempo tras horas de partida no caben en un float de 32 bits.

## Longitudes de onda (m), de la más larga que la malla suele dejar sin dibujar a diez centímetros.
## Las cuatro últimas sustituyen al rizado de textura, que se repetía cada 8 m.
const LENGTHS := [14.0, 10.1, 7.3, 5.2, 3.8, 2.7, 1.95, 1.4, 1.0, 0.72, 0.52, 0.37, 0.27, 0.19, 0.135, 0.1]
## Ángulo de cada onda respecto al viento (rad). Abiertas a los dos lados: un mar de viento es de
## cresta corta, y con todas las ondas casi paralelas el agua se lee como chapa ondulada.
const ANGLES := [0.3, -0.55, 0.12, -0.9, 0.72, -0.28, 1.05, -0.62, 0.45, -1.15, 0.95, -0.38, 0.6, -0.8, 0.2, -1.0]
## Pendiente máxima de cada onda con el mar tendido.
const SLOPES := [0.06, 0.065, 0.07, 0.075, 0.08, 0.085, 0.09, 0.09, 0.09, 0.085, 0.08, 0.075, 0.07, 0.065, 0.06, 0.055]
const GRAVITY := 9.81


## Direcciones (xyz, fijas en el marco del planeta) y número de onda (w) de cada onda, para el eje de
## viento [wind] del espectro. Misma construcción que ocean_mode_direction: las ondas viajan en
## sentido contrario a su dirección, como las del espectro.
static func waves(wind: Vector3) -> PackedVector4Array:
	var out := PackedVector4Array()
	var side := wind.cross(Vector3.UP if absf(wind.y) < 0.9 else Vector3.RIGHT).normalized()
	var vertical := wind.cross(side)
	for i in LENGTHS.size():
		var angle: float = ANGLES[i]
		var dir := (wind * cos(angle) + side * sin(angle) + vertical * (sin(float(i) * 2.399) * 0.28)).normalized()
		out.append(Vector4(dir.x, dir.y, dir.z, TAU / float(LENGTHS[i])))
	return out


## Fase de cada onda en [anchor] (posición relativa al centro del planeta) en el instante [time], y su
## pendiente escalada por [gain]. Lee dirección y número de onda de [modes] tal como los recibe el
## shader (ya redondeados a 32 bits): así la fase del ancla y el tramo que suma el píxel hablan de la
## misma onda, y mover el ancla no mueve el dibujo.
static func state(modes: PackedVector4Array, anchor: Vector3, time: float, gain: float) -> PackedVector4Array:
	var out := PackedVector4Array()
	for i in modes.size():
		var mode := modes[i]
		var k: float = mode.w
		var along: float = mode.x * anchor.x + mode.y * anchor.y + mode.z * anchor.z
		var phase := fposmod(k * along + sqrt(GRAVITY * k) * time, TAU)
		out.append(Vector4(phase, float(SLOPES[i]) * gain, 0.0, 0.0))
	return out
