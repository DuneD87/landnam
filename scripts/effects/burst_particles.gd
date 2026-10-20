class_name BurstParticles
extends RefCounted

## Emisores de una sola ráfaga (golpes, sangre, polvo, astillas, plumas) y las curvas y rampas de
## sus materiales de proceso.


## Emisor de [amount] partículas que viven [lifetime] s y salen de golpe según [explosiveness], en
## coordenadas de mundo y sin sombra. Sale apagado: quien lo usa lo coloca y pone emitting = true
## (o lo reinicia cada vez, si lo reutiliza).
static func create(amount: int, lifetime: float, explosiveness: float, node_name := "") -> GPUParticles3D:
	var node := GPUParticles3D.new()
	if node_name != "":
		node.name = node_name
	node.amount = amount
	node.lifetime = lifetime
	node.one_shot = true
	node.explosiveness = explosiveness
	node.emitting = false
	node.local_coords = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Curva de escala o de giro por los puntos [points] (Vector2: instante 0–1, valor).
static func curve(points: Array) -> CurveTexture:
	var shape := Curve.new()
	for point in points:
		shape.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = shape
	return texture


## Rampa de color con [colors] en [offsets] (0–1).
static func ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
