class_name AbyssSpray
extends Node3D

## Agua a escala de un gigante: la espuma que levantan las piernas de Cthulhu al vadear, el
## reventón de cada pisada, la cortina que le chorrea del cuerpo al salir y el mar que hierve antes
## de que aparezca. Los rociones normales (OceanSpray) siguen a la cámara y son de centímetros: esto
## son nubes de metros y gotas de un palmo, visibles a cientos de metros.
##
## Reutiliza los shaders de OceanSpray (proceso y dibujo). Como allí, nada nace solo: todo entra por
## emit_*. Quien lo usa lo recoloca (follow) para que la caja de visibilidad quede encima.

const PROCESS_SHADER := preload("res://shaders/liquid/water_spray_process.gdshader")
const DRAW_SHADER := preload("res://shaders/liquid/water_spray.gdshader")
const EMIT_FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE \
	| GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM

const MIST_AMOUNT := 1600
const DROP_AMOUNT := 6000
## Vida máxima (s): una gota que cae desde los hombros (unos 60 m) tarda unos 4 s.
const MAX_LIFETIME := 6.0
## Medio lado de la caja de visibilidad (m).
const REACH := 450.0
const GRAVITY := 9.8

var _mist: GPUParticles3D
var _drops: GPUParticles3D
var _mist_process: ShaderMaterial
var _drop_process: ShaderMaterial
var _gravity := Vector3.INF


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mist_process = _process_material(0.08, 0.9)
	_drop_process = _process_material(1.0, 0.12)
	_mist = _emitter("Mist", MIST_AMOUNT, _mist_process,
		_draw_material({"opacity": 0.3, "grow": 2.2, "streak": 0.0, "soft_distance": 6.0, "brightness": 1.0,
			"breakup": 0.85}))
	_mist.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_drops = _emitter("Drops", DROP_AMOUNT, _drop_process,
		_draw_material({"opacity": 0.55, "grow": 0.8, "streak": 0.05, "soft_distance": 1.0, "brightness": 1.0}))


## Pone la caja de visibilidad sobre [point] y la gravedad hacia el centro del planeta.
func follow(point: Vector3, planet_center: Vector3) -> void:
	global_position = point
	var gravity := (planet_center - point).normalized() * GRAVITY
	if gravity.distance_squared_to(_gravity) > 0.0004:
		_gravity = gravity
		_mist_process.set_shader_parameter(&"gravity", gravity)
		_drop_process.set_shader_parameter(&"gravity", gravity)


## Reventón donde algo enorme entra o sale del agua (una pisada, la cabeza al asomar). [power] 0..1
## de una pisada a la cabeza entera; [radius] (m) el ancho de lo que golpea.
func burst(point: Vector3, up: Vector3, power: float, radius: float) -> void:
	var lift := lerpf(10.0, 24.0, power)
	for i in int(lerpf(90.0, 260.0, power)):
		var out := _tangent(up)
		var origin := point + out * randf_range(0.2, 1.0) * radius
		var velocity := up * randf_range(0.35, 1.0) * lift + out * randf_range(2.0, 9.0) * lerpf(0.7, 1.3, power)
		_emit(_drops, origin, velocity, randf_range(0.25, 0.8), randf_range(1.6, 3.6), 1.0, randf_range(0.0, 0.3))
	for i in int(lerpf(14.0, 40.0, power)):
		var out := _tangent(up)
		var origin := point + out * randf_range(0.3, 1.1) * radius + up * randf_range(0.0, 4.0)
		var velocity := up * randf_range(2.0, 7.0) * lerpf(0.8, 1.4, power) + out * randf_range(1.0, 5.0)
		_emit(_mist, origin, velocity, randf_range(5.0, 11.0) * lerpf(0.8, 1.5, power), randf_range(3.0, 5.5),
			0.9, 1.0)


## Espuma donde algo corta la superficie andando: nubes bajas y gotas que saltan hacia delante y a los
## lados. [heading] y [speed]: hacia dónde va y a cuánto (m/s). [amount] partículas de este paso.
func churn(point: Vector3, up: Vector3, heading: Vector3, speed: float, radius: float, amount: float) -> void:
	var count := int(amount)
	if randf() < amount - count:
		count += 1
	for i in count:
		var out := _tangent(up)
		var side := heading.cross(up).normalized() * (1.0 if randf() < 0.5 else -1.0)
		var origin := point + out * randf_range(0.5, 1.0) * radius
		if randf() < 0.35:
			var velocity := up * randf_range(1.0, 4.0) + (heading * 0.6 + side * 0.5) * speed * randf_range(0.2, 0.8)
			_emit(_mist, origin + up * randf_range(0.0, 2.0), velocity, randf_range(4.0, 9.0), randf_range(2.5, 4.5),
				0.85, 1.0)
		else:
			var velocity := up * randf_range(3.0, 9.0) + (heading * 0.8 + side * 0.7) * speed * randf_range(0.3, 1.1)
			_emit(_drops, origin, velocity, randf_range(0.2, 0.55), randf_range(1.0, 2.4), 1.0, randf_range(0.0, 0.4))


## Una gota (o un chorro) que cae desde [from] hasta el agua: vive lo que tarda en llegar.
func drip(from: Vector3, up: Vector3, height: float, size: float = 0.45) -> void:
	if height <= 0.5:
		return
	var v0 := randf_range(0.0, 2.0)
	var life := (-v0 + sqrt(v0 * v0 + 2.0 * GRAVITY * height)) / GRAVITY
	var velocity := -up * v0 + _tangent(up) * randf_range(0.0, 1.5)
	_emit(_drops, from, velocity, size * randf_range(0.6, 1.4), minf(life, MAX_LIFETIME), 0.8, 0.0)


## El mar que hierve: borbotones de agua y vaho sobre una mancha de [radius] m.
func boil(point: Vector3, up: Vector3, radius: float, strength: float) -> void:
	for i in int(lerpf(8.0, 26.0, strength)):
		var out := _tangent(up) * sqrt(randf()) * radius
		var velocity := up * randf_range(1.5, 6.0) * lerpf(0.6, 1.2, strength) + _tangent(up) * randf_range(0.0, 1.5)
		_emit(_drops, point + out, velocity, randf_range(0.12, 0.35), randf_range(0.6, 1.4), 1.0, 0.2)
	for i in int(lerpf(2.0, 7.0, strength)):
		var out := _tangent(up) * sqrt(randf()) * radius
		_emit(_mist, point + out + up * 0.5, up * randf_range(0.5, 1.8), randf_range(2.5, 6.0) * lerpf(0.7, 1.2, strength),
			randf_range(2.0, 4.0), 0.55, 1.0)


func _emit(emitter: GPUParticles3D, origin: Vector3, velocity: Vector3, size: float, life: float,
		alpha: float, floaty: float) -> void:
	emitter.emit_particle(Transform3D(Basis.IDENTITY, origin), velocity, Color(floaty, 1.0, 1.0, alpha),
		Color(randf(), 0.0, size, minf(life, MAX_LIFETIME)), EMIT_FLAGS)


func _tangent(up: Vector3) -> Vector3:
	var x := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
	var angle := randf() * TAU
	return x * cos(angle) + up.cross(x) * sin(angle)


func _process_material(gravity_scale: float, drag: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PROCESS_SHADER
	material.set_shader_parameter(&"gravity_scale", gravity_scale)
	material.set_shader_parameter(&"drag", drag)
	return material


func _draw_material(params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DRAW_SHADER
	material.render_priority = 4
	for key: String in params:
		material.set_shader_parameter(key, params[key])
	return material


func _emitter(node_name: String, amount: int, process: ShaderMaterial, draw: ShaderMaterial) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = amount
	emitter.lifetime = MAX_LIFETIME
	emitter.emitting = false
	emitter.local_coords = false
	emitter.interpolate = false
	emitter.fixed_fps = 0
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3.ONE * -REACH, Vector3.ONE * REACH * 2.0)
	emitter.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = draw
	emitter.draw_pass_1 = quad
	emitter.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(emitter)
	return emitter
