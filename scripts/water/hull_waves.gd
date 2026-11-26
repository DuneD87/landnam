class_name HullWaves
extends Node

## Olas de los barcos en la malla del agua (shaders/liquid/hull_waves.gdshaderinc): cada frame sube
## al material del mar los barcos que se mueven cerca de la cámara —centro, sentido de la marcha,
## eslora, manga, velocidad— y los anillos que dejan los golpes de proa (HullWaves.ring, lo llama
## OceanSpray). Es solo dibujo: la flotación de CPU no ve estas olas.

const MAX_HULLS := 8
## Huecos como mucho para los vadeadores (Cthulhu, sus esbirros): los demás quedan para los barcos.
const MAX_WADERS := 5
const MAX_RINGS := 16
## Hasta dónde de la cámara (m) se dibujan las olas de un barco.
const REACH := 260.0
## Y las de un vadeador (Cthulhu), que se ve desde kilómetros.
const WADER_REACH := 2500.0
const GRAVITY := 9.8

## Interruptor general.
static var enabled: bool = true
static var _active: HullWaves
## Lo que levanta olas sin ser barco (Cthulhu, sus esbirros): nodos con wake_source() -> Dictionary con
## center, heading (mundo, tangente), length y beam (semiejes, m), speed y amplitude, y si quiere reach
## (m, hasta dónde se dibuja; WADER_REACH si no); vacío si ahora no levanta nada. Los más cercanos a la
## cámara, MAX_WADERS como mucho, ocupan los primeros huecos, antes que los barcos.
static var _waders: Array[Node] = []

## Altura de la ola de proa respecto a la carga de velocidad U²/2g: 0,5 = la mitad.
@export_range(0.0, 2.0, 0.05) var bow_amount: float = 0.42
## Velocidad (m/s) a partir de la que el barco levanta ola, y a la que ya la levanta entera.
@export var min_speed: float = 0.4
@export var full_speed: float = 1.6
## Segundos que tarda la altura de la ola en seguir a la velocidad, para que no tiemble con cada
## cabeceo. El rumbo no se suaviza: la V va con el eje del casco, y al girar gira con él al momento.
@export var smoothing: float = 0.25

var ocean: OceanSystem
var _frame := PackedVector4Array()
var _axis := PackedVector4Array()
var _params := PackedVector4Array()
var _ring_pos := PackedVector4Array()
var _ring_params := PackedVector4Array()
var _pushed_hulls := -1
var _pushed_rings := -1
## Por barco: velocidad suavizada respecto al agua a lo largo del casco (m/s, con signo).
var _smoothed := {}
## Anillos vivos: offset desde el centro del planeta (sobrevive a un rebase), edad y forma.
var _rings: Array[Dictionary] = []
## Lo último que se subió de cada barco, por instance id: ver hull_info.
var _info := {}


func setup(ocean_system: OceanSystem) -> void:
	ocean = ocean_system
	_active = self
	_frame.resize(MAX_HULLS)
	_axis.resize(MAX_HULLS)
	_params.resize(MAX_HULLS)
	_ring_pos.resize(MAX_RINGS)
	_ring_params.resize(MAX_RINGS)


func _exit_tree() -> void:
	if _active == self:
		_active = null


## Onda que se abre desde [world_pos], de un golpe de fuerza [strength] (0..1) de un casco de
## semimanga [beam] (m).
static func ring(world_pos: Vector3, strength: float, beam: float) -> void:
	if _active == null or not is_instance_valid(_active) or not enabled:
		return
	_active._add_ring(world_pos, ring_shape(clampf(strength, 0.0, 1.5), beam))


## Onda de forma libre, sin los topes de un casco (las pisadas de Cthulhu): altura [amp] (m), radio
## inicial [r0] (m), velocidad del frente [speed] (m/s) y vida [life] (s).
static func wave_ring(world_pos: Vector3, amp: float, r0: float, speed: float, life: float) -> void:
	if _active == null or not is_instance_valid(_active) or not enabled:
		return
	_active._add_ring(world_pos, {"amp": amp, "r0": r0, "speed": speed, "life": life})


static func add_wader(node: Node) -> void:
	if not _waders.has(node):
		_waders.append(node)


static func remove_wader(node: Node) -> void:
	_waders.erase(node)


## Forma del anillo de un golpe: altura, radio inicial, velocidad de la onda y vida. La comparten la
## malla y la corona de partículas de OceanSpray, que tiene que ir encima de la cresta.
static func ring_shape(strength: float, beam: float) -> Dictionary:
	var size := clampf(beam, 0.5, 5.0)
	return {
		"amp": (0.07 + 0.2 * strength) * sqrt(size),
		"r0": 0.4 + size * 0.5,
		"speed": 0.9 + 1.1 * strength,
		"life": 3.5 + 1.5 * strength,
	}


## Olas del casco de [body] tal como se dibujaron el último frame (vacío si no levanta ninguna):
## center, heading, side, up (mundo), length y beam (semiejes, m), speed y amplitude.
static func hull_info(body: Node) -> Dictionary:
	if _active == null or not is_instance_valid(_active) or body == null:
		return {}
	return _active._info.get(body.get_instance_id(), {})


func _add_ring(world_pos: Vector3, ring: Dictionary) -> void:
	var material := _material()
	if material == null:
		return
	var center: Vector3 = material.get_shader_parameter(&"planet_center")
	if _rings.size() >= MAX_RINGS:
		_rings.pop_front()
	ring["offset"] = world_pos - center
	ring["age"] = 0.0
	_rings.append(ring)


func _process(delta: float) -> void:
	var material := _material()
	if material == null:
		return
	var camera := ocean.camera if ocean.camera != null else get_viewport().get_camera_3d()
	var hulls := 0
	_info.clear()
	if enabled and camera != null:
		hulls = _gather_waders(camera.global_position)
		hulls = _gather_hulls(camera.global_position, delta, hulls)
	var center: Vector3 = material.get_shader_parameter(&"planet_center")
	var rings := 0
	for r in range(_rings.size() - 1, -1, -1):
		var item := _rings[r]
		item["age"] = float(item["age"]) + delta
		if float(item["age"]) >= float(item["life"]):
			_rings.remove_at(r)
	if enabled:
		for item in _rings:
			if rings >= MAX_RINGS:
				break
			var p: Vector3 = center + (item["offset"] as Vector3)
			_ring_pos[rings] = Vector4(p.x, p.y, p.z, item["age"])
			_ring_params[rings] = Vector4(item["amp"], item["r0"], item["speed"], item["life"])
			rings += 1
	if hulls != _pushed_hulls:
		material.set_shader_parameter(&"hull_count", hulls)
		_pushed_hulls = hulls
	if hulls > 0:
		material.set_shader_parameter(&"hull_frame", _frame)
		material.set_shader_parameter(&"hull_axis", _axis)
		material.set_shader_parameter(&"hull_params", _params)
	if rings != _pushed_rings:
		material.set_shader_parameter(&"hull_ring_count", rings)
		_pushed_rings = rings
	if rings > 0:
		material.set_shader_parameter(&"hull_rings", _ring_pos)
		material.set_shader_parameter(&"hull_ring_params", _ring_params)


func _material() -> ShaderMaterial:
	if ocean == null or ocean.mesh_manager == null:
		return null
	return ocean.mesh_manager.default_material as ShaderMaterial


## Los vadeadores, en los primeros huecos de los buffers; devuelve cuántos.
func _gather_waders(eye: Vector3) -> int:
	for i in range(_waders.size() - 1, -1, -1):
		if not is_instance_valid(_waders[i]) or not _waders[i].is_inside_tree():
			_waders.remove_at(i)
	var wakes: Array[Dictionary] = []
	for node in _waders:
		var wake: Dictionary = node.wake_source()
		if wake.is_empty():
			continue
		var distance := (wake["center"] as Vector3).distance_to(eye)
		if distance > float(wake.get("reach", WADER_REACH)):
			continue
		wake["distance"] = distance
		wakes.append(wake)
	if wakes.size() > MAX_WADERS:
		wakes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
		wakes.resize(MAX_WADERS)
	var count := 0
	for wake in wakes:
		var center: Vector3 = wake["center"]
		var heading: Vector3 = wake["heading"]
		var length: float = wake["length"]
		var beam: float = wake["beam"]
		_frame[count] = Vector4(center.x, center.y, center.z, length)
		_axis[count] = Vector4(heading.x, heading.y, heading.z, beam)
		_params[count] = Vector4(wake["speed"], wake["amplitude"], length * 10.0 + beam + 25.0, 0.0)
		count += 1
	return count


## Rellena los buffers con los barcos más cercanos que se mueven en el agua, a partir del hueco
## [start]; devuelve cuántos hay ocupados en total.
func _gather_hulls(eye: Vector3, delta: float, start: int = 0) -> int:
	var found: Array = []
	var seen := {}
	for node in get_tree().get_nodes_in_group(DynamicGridBody.GROUP):
		var body := node as DynamicGridBody
		if body == null or not body.is_inside_tree() or body.planet_node == null:
			continue
		var bounds := body.get_hull_bounds()
		if not bounds.has("half"):
			continue
		var xform := body.get_global_transform_interpolated()
		var distance := xform.origin.distance_to(eye)
		if distance > REACH:
			continue
		var id := body.get_instance_id()
		seen[id] = true
		var planet_pos: Vector3 = body.planet_node.global_pos
		var up := (xform.origin - planet_pos).normalized()
		# Fuera del agua o varado no levanta nada; la velocidad se suaviza hacia cero.
		var target := Vector3.ZERO
		if body.last_displaced_mass > 0.0:
			var relative := body.linear_velocity - body.last_water_flow
			target = relative - up * relative.dot(up)
		# La proa es la del casco (+Z, como el timón de DynamicGridBody), hacia donde avance: ciando,
		# la ola sale por la popa.
		var axis := xform.basis.z - up * xform.basis.z.dot(up)
		if axis.length_squared() < 0.0001:
			continue
		axis = axis.normalized()
		var smoothed: float = _smoothed.get(id, target.dot(axis))
		smoothed = lerpf(smoothed, target.dot(axis), clampf(delta / maxf(smoothing, 0.01), 0.0, 1.0))
		_smoothed[id] = smoothed
		var speed := absf(smoothed)
		if speed < min_speed:
			continue
		found.append({"body": body, "xform": xform, "bounds": bounds, "up": up,
			"heading": axis * signf(smoothed), "speed": speed, "distance": distance})
	for key: int in _smoothed.keys():
		if not seen.has(key):
			_smoothed.erase(key)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])

	_info.clear()
	var count := start
	for item: Dictionary in found:
		if count >= MAX_HULLS:
			break
		var xform: Transform3D = item["xform"]
		var bounds: Dictionary = item["bounds"]
		var up: Vector3 = item["up"]
		var speed: float = item["speed"]
		var heading: Vector3 = item["heading"]
		var side := up.cross(heading)
		var half: Vector3 = bounds["half"]
		var axes := xform.basis
		var length := absf(axes.x.dot(heading)) * half.x + absf(axes.y.dot(heading)) * half.y \
			+ absf(axes.z.dot(heading)) * half.z
		var beam := absf(axes.x.dot(side)) * half.x + absf(axes.y.dot(side)) * half.y \
			+ absf(axes.z.dot(side)) * half.z
		length = maxf(length, 0.5)
		beam = maxf(beam, 0.3)
		var center := xform * (bounds["pos"] as Vector3)
		# Carga de velocidad: lo que sube el agua frenada contra la roda. Topada para que un esquife
		# a toda vela no levante una pared.
		var amplitude := bow_amount * speed * speed / (2.0 * GRAVITY)
		amplitude = minf(amplitude, 0.18 + 0.2 * beam) * smoothstep(min_speed, full_speed, speed)
		var reach := length * 10.0 + beam + 25.0
		_frame[count] = Vector4(center.x, center.y, center.z, length)
		_axis[count] = Vector4(heading.x, heading.y, heading.z, beam)
		_params[count] = Vector4(speed, amplitude, reach, 0.0)
		_info[(item["body"] as Node).get_instance_id()] = {"center": center, "heading": heading, "side": side,
			"up": up, "length": length, "beam": beam, "speed": speed, "amplitude": amplitude}
		count += 1
	return count
