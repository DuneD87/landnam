class_name BurstParticles
extends RefCounted

## Emisores de una sola ráfaga (golpes, sangre, polvo, astillas, plumas) y las curvas y rampas de
## sus materiales de proceso.

## Un material de cada efecto, vivo hasta el final (ver keep).
static var _kept := {}


## Mantiene vivo el primer [material] de cada efecto [key]. Los ParticleProcessMaterial y los
## StandardMaterial3D comparten el shader de su combinación de opciones, y Godot lo libera con el
## último material que lo usa: el efecto siguiente, segundos después y ya apagados los anteriores,
## lo volvía a generar (unos 5 ms de CPU por golpe y, con render, su compilación en la GPU).
static func keep(key: StringName, material: Material) -> void:
	if not _kept.has(key):
		_kept[key] = material


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
