class_name OceanSpray
extends Node3D

## Rociones y salpicaduras del agua, alrededor de la cámara. Cuatro fuentes y dos emisores:
##   - crestas que rompen (mar abierto y rompiente de orilla): se sondea la superficie de CPU en unos
##     pocos puntos al azar por frame y, donde la ola se pincha y corre, salta una ráfaga;
##   - la proa de los barcos que abren estela, y su golpe cuando cae o se mete en una ola;
##   - quien cruza la superficie (splash) y el jugador nadando.
## Los emisores no emiten solos: todo entra por emit_particle. Uno dibuja bruma (nubes que el viento
## se lleva) y el otro gotas (balísticas, estiradas por su velocidad).

const PROCESS_SHADER := preload("res://shaders/liquid/water_spray_process.gdshader")
const DRAW_SHADER := preload("res://shaders/liquid/water_spray.gdshader")
const EMIT_FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE \
	| GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM

const MIST_AMOUNT := 700
const DROP_AMOUNT := 3000
## Vida máxima de una partícula (s). El servidor deja de procesar el emisor pasado este tiempo (más
## un 20 %) desde la última emisión, así que ninguna puede pedir más.
const MAX_LIFETIME := 3.0
## Radio de la caja de visibilidad de los emisores, que siguen a la cámara.
const REACH := 140.0
const GRAVITY := 9.8

## Interruptor general (comando de consola 'spray').
static var enabled: bool = true
## Ráfagas de cresta y partículas emitidas en el último segundo; las lee el comando 'spray'.
static var stat_bursts: int = 0
static var stat_particles: int = 0
static var _active: OceanSpray

@export_group("Crestas")
## Puntos de la superficie que se sondean por frame buscando una cresta que rompa.
@export_range(0, 16) var crest_samples: int = 5
## Hasta dónde se buscan (m) y por encima de qué altura de cámara se deja de buscar.
@export var crest_range: float = 75.0
@export var max_altitude: float = 120.0
## Contracción de la cresta (WaterHeightSampler.last_crest) a partir de la que salta rocío.
@export_range(0.0, 1.0, 0.01) var crest_threshold: float = 0.26
## Velocidad del agua en la cresta (m/s) a partir de la que salta: en mar abierto y en la orilla.
@export var crest_min_speed: float = 2.4
@export var shore_min_speed: float = 0.45
## Cantidad general de rocío de cresta.
@export_range(0.0, 3.0, 0.05) var crest_amount: float = 1.0

@export_group("Barcos")
## Velocidad respecto al agua (m/s) a partir de la que la proa levanta rocío.
@export var bow_min_speed: float = 1.5
@export_range(0.0, 3.0, 0.05) var bow_amount: float = 1.0
## Golpe de proa: ritmo (m/s) al que el agua tiene que subir por la roda para que salte, segundos
## mínimos entre dos golpes del mismo barco, y cantidad de agua que levanta.
@export var slam_min_rate: float = 1.8
@export var slam_cooldown: float = 0.6
@export_range(0.0, 3.0, 0.05) var slam_amount: float = 1.0

@export_group("Viento")
## Viento que se lleva la bruma (m/s), con el mar en calma y con temporal pleno.
@export var wind_calm: float = 3.0
@export var wind_storm: float = 18.0

var ocean: OceanSystem
var _sampler: WaterHeightSampler
var _mist: GPUParticles3D
var _drops: GPUParticles3D
var _mist_process: ShaderMaterial
var _drop_process: ShaderMaterial
var _center := Vector3.ZERO
var _wind := Vector3.ZERO
var _pushed_gravity := Vector3.INF
var _pushed_wind := Vector3.INF
var _swim_clock := 0.0
var _bow_debt := {}
var _slam_state := {}
var _arm_debt := {}
## Coronas de los golpes de proa: la cresta del anillo de HullWaves rompiendo mientras se abre.
var _crowns: Array[Dictionary] = []
var _stat_clock := 0.0
var _count_bursts := 0
var _count_particles := 0


func setup(ocean_system: OceanSystem) -> void:
	ocean = ocean_system
	_active = self
	# Los emisores se recolocan en _process sobre la cámara: sin esto la interpolación de física los
	# deja un paso atrás.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mist_process = _process_material(0.12, 1.6)
	_drop_process = _process_material(1.0, 0.25)
	_mist = _emitter("Mist", MIST_AMOUNT, _mist_process,
		_draw_material({"opacity": 0.16, "grow": 2.4, "streak": 0.0, "soft_distance": 0.9, "brightness": 1.0}))
	_mist.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_drops = _emitter("Drops", DROP_AMOUNT, _drop_process,
		_draw_material({"opacity": 0.55, "grow": 0.7, "streak": 0.02, "soft_distance": 0.15,
			"brightness": 1.0}))


func _exit_tree() -> void:
	if _active == self:
		_active = null


## Salpicadura de algo que cruza la superficie en [world_pos]. [strength] 0..1: de meter el pie a
## tirarse desde un acantilado.
static func splash(world_pos: Vector3, strength: float) -> void:
	if _active == null or not is_instance_valid(_active) or not enabled:
		return
	_active._splash(world_pos, clampf(strength, 0.0, 1.0))


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_step(delta)
	DebugStats.report_cost(&"agua:rociones", Time.get_ticks_usec() - start)


func _step(delta: float) -> void:
	_stat_clock += delta
	if _stat_clock >= 1.0:
		_stat_clock = 0.0
		stat_bursts = _count_bursts
		stat_particles = _count_particles
		_count_bursts = 0
		_count_particles = 0
	if ocean == null or _mist == null or ocean.mesh_manager == null:
		return
	var material := ocean.mesh_manager.default_material as ShaderMaterial
	var camera := ocean.camera if ocean.camera != null else get_viewport().get_camera_3d()
	if material == null or camera == null:
		return
	if _sampler == null:
		_sampler = WaterHeightSampler.new()
		add_child(_sampler)
		_sampler.setup(material, ocean.world_map, ocean.radius)
	_sampler.world_map = ocean.world_map
	_sampler.flow_depth = 0.0

	_center = material.get_shader_parameter(&"planet_center")
	var eye := camera.global_position
	var to_eye := eye - _center
	var up := to_eye.normalized()
	# Con la cámara sumergida no se ve nada de lo que pasa encima, y de lejos tampoco.
	var waterline: Vector3 = material.get_shader_parameter(&"waterline_point")
	var waterline_normal: Vector3 = material.get_shader_parameter(&"waterline_normal")
	var submerged := (eye - waterline).dot(waterline_normal) < 0.0
	var altitude := to_eye.length() - ocean.radius
	var in_reach := enabled and not submerged and altitude < max_altitude
	_mist.visible = enabled and not submerged
	_drops.visible = _mist.visible
	_mist.global_position = eye
	_drops.global_position = eye
	if not in_reach:
		return

	var axis := _sampler.wind_axis()
	var downwind := -(axis - up * axis.dot(up))
	downwind = downwind.normalized() if downwind.length_squared() > 0.0001 else Vector3.ZERO
	_wind = downwind * lerpf(wind_calm, wind_storm, _sampler.get_sea_state())
	_push_forces(-up * GRAVITY)

	var time := WaterHeightSampler.get_water_time(material)
	_sample_crests(camera, to_eye, up, time)
	_bow_spray(delta, eye, time)
	_crown_spray(delta)
	_swim_spray(delta)


## Gravedad y viento a los dos materiales de proceso, solo cuando cambian de verdad.
func _push_forces(gravity: Vector3) -> void:
	if gravity.distance_squared_to(_pushed_gravity) > 0.0004:
		_pushed_gravity = gravity
		_mist_process.set_shader_parameter(&"gravity", gravity)
		_drop_process.set_shader_parameter(&"gravity", gravity)
	if _wind.distance_squared_to(_pushed_wind) > 0.01:
		_pushed_wind = _wind
		_mist_process.set_shader_parameter(&"wind", _wind)
		_drop_process.set_shader_parameter(&"wind", _wind)


## Sondea la superficie en unos puntos al azar, casi todos delante de la cámara y más densos cerca,
## y suelta una ráfaga donde encuentra una cresta rompiendo.
func _sample_crests(camera: Camera3D, to_eye: Vector3, up: Vector3, time: float) -> void:
	if crest_samples <= 0 or crest_amount <= 0.0:
		return
	var forward := -camera.global_transform.basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP)
	forward = forward.normalized()
	for _i in crest_samples:
		var angle := randf_range(-1.25, 1.25) if randf() < 0.8 else randf() * TAU
		var reach := lerpf(3.0, crest_range, pow(randf(), 1.4))
		var rest := (to_eye + forward.rotated(up, angle) * reach).normalized() * ocean.radius
		var displacement := _sampler.rest_displacement(rest, time, 0.0)
		if _sampler.last_ice > 0.3:
			continue
		# Bajo tierra clara según el mapa. Junto a la costa el mapa grueso no sabe: decide el rayo.
		if _sampler.shore_enabled and _sampler.last_depth < -4.0:
			continue
		var crest := _sampler.last_crest()
		if crest < crest_threshold:
			continue
		var flow := _sampler.last_flow
		var speed := flow.length()
		var shore := _sampler.last_shore_presence
		if speed < lerpf(crest_min_speed, shore_min_speed, shore):
			continue
		var point := _center + rest + displacement
		if _covered(point, up):
			continue
		var power := clampf((crest - crest_threshold) / 0.2, 0.15, 1.0) \
			* clampf(speed / lerpf(4.0, 1.6, shore), 0.25, 1.6)
		_burst(point, up, flow, power * crest_amount)


## true si sobre ese punto de agua hay terreno o un casco: el agua sigue por debajo de la playa.
func _covered(point: Vector3, up: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(point + up * 40.0, point - up * 0.2,
		PhysicsLayers.WORLD | PhysicsLayers.BODIES)
	return not space.intersect_ray(query).is_empty()


## Ráfaga de una cresta: un velo de gotas finas a lo largo de la cresta. Unas saltan y caen; la
## mayoría flota y se la lleva el viento. Sin nubes: un sprite de bruma suelto se lee como humo.
func _burst(point: Vector3, up: Vector3, flow: Vector3, power: float) -> void:
	_count_bursts += 1
	var along := up.cross(flow)
	along = along.normalized() if along.length_squared() > 0.0001 else _tangent(up)
	var lift := sqrt(minf(power, 1.5))
	for _i in int(round(lerpf(10.0, 34.0, minf(power, 1.0)))):
		var origin := point + along * randf_range(-2.2, 2.2) + up * randf_range(0.0, 0.25)
		var floaty := randf_range(0.25, 1.0)
		var velocity := flow * 0.85 + up * randf_range(0.8, 4.2) * lift + along * randf_range(-1.0, 1.0) \
			+ _wind * 0.15 * floaty
		_emit(_drops, origin, velocity, randf_range(0.012, 0.03), randf_range(0.6, 1.7), 1.0, floaty)


func _splash(world_pos: Vector3, strength: float) -> void:
	var up := (world_pos - _center).normalized()
	for _i in int(round(lerpf(6.0, 30.0, strength))):
		var out := _tangent(up) * randf_range(0.3, 2.2) * lerpf(0.6, 1.4, strength)
		var velocity := out + up * randf_range(1.5, 6.5) * lerpf(0.5, 1.0, strength)
		_emit(_drops, world_pos + out * 0.12, velocity, randf_range(0.03, 0.07), randf_range(0.5, 1.2), 1.0)
	for _i in int(round(lerpf(2.0, 7.0, strength))):
		var out := _tangent(up) * randf_range(0.2, 1.2)
		var velocity := out + up * randf_range(0.6, 2.4) * lerpf(0.6, 1.2, strength)
		_emit(_mist, world_pos + out * 0.3 + up * 0.15, velocity,
			randf_range(0.35, 0.8) * lerpf(0.7, 1.6, strength), randf_range(0.9, 1.8), 0.9)


## El jugador nadando deja caer algo de rocío con cada brazada.
func _swim_spray(delta: float) -> void:
	var player := ocean.player
	if player == null or not is_instance_valid(player):
		return
	var movement := player.get(&"movement") as Movement
	var surface: Variant = player.get(&"_water_surface_radius")
	if movement == null or surface == null or not movement.is_swimming:
		return
	var up := (player.global_position - _center).normalized()
	var velocity := player.velocity
	var horizontal := velocity - up * velocity.dot(up)
	var speed := horizontal.length()
	# Buceando no rompe la superficie.
	var depth := float(surface) - (player.global_position - _center).length()
	if speed < 1.0 or depth > 1.6:
		return
	_swim_clock += delta * clampf(speed / 2.5, 0.5, 2.0)
	if _swim_clock < 0.22:
		return
	_swim_clock = 0.0
	var point := _center + up * float(surface) + _tangent(up) * randf_range(0.0, 0.45)
	for _i in 4:
		_emit(_drops, point, horizontal * 0.6 + up * randf_range(1.0, 2.6) + _tangent(up) * randf_range(0.0, 1.0),
			randf_range(0.025, 0.05), randf_range(0.4, 0.8), 1.0)
	_emit(_mist, point + up * 0.1, horizontal * 0.4 + up * randf_range(0.3, 0.9),
		randf_range(0.3, 0.5), randf_range(0.7, 1.2), 0.7)


## Rocío de proa: de los barcos que abren estela, a los dos lados de la roda y más cuanto más corren.
## Además, el golpe de proa: cuando el agua sube contra la roda de golpe —la proa cae tras pasar una
## cresta o se mete de lleno en la cara de la siguiente— salta una sábana de agua con su chasquido.
func _bow_spray(delta: float, eye: Vector3, time: float) -> void:
	if bow_amount <= 0.0 and slam_amount <= 0.0:
		return
	var seen := {}
	for node in get_tree().get_nodes_in_group(DynamicGridBody.GROUP):
		var body := node as DynamicGridBody
		if body == null or body.get_wake_head_offset() == Vector3.ZERO:
			continue
		var xform := body.get_global_transform_interpolated()
		if xform.origin.distance_squared_to(eye) > REACH * REACH:
			continue
		var bounds := body.get_hull_bounds()
		if not bounds.has("half"):
			continue
		var id := body.get_instance_id()
		seen[id] = true
		var up := (xform.origin - _center).normalized()
		var relative := body.linear_velocity - body.last_water_flow
		var heading := relative - up * relative.dot(up)
		var speed := heading.length()
		# Parado o casi, la proa es la del casco y no la de la marcha.
		if speed < 0.5:
			heading = xform.basis.z - up * xform.basis.z.dot(up)
			if heading.length_squared() < 0.0001:
				continue
		heading = heading.normalized()
		var half: Vector3 = bounds["half"]
		var axes := xform.basis
		var bow := xform * (bounds["pos"] as Vector3) + heading * (absf(axes.x.dot(heading)) * half.x
			+ absf(axes.y.dot(heading)) * half.y + absf(axes.z.dot(heading)) * half.z)
		# La proa sobre la superficie de ahora: cuando cae en una cresta levanta más.
		var rest := (bow - _center).normalized() * ocean.radius
		var point := _center + rest + _sampler.rest_displacement(rest, time, 0.0)
		var crest := _sampler.last_crest()
		var side := up.cross(heading)
		var height := absf(axes.x.dot(up)) * half.x + absf(axes.y.dot(up)) * half.y + absf(axes.z.dot(up)) * half.z
		var beam := absf(axes.x.dot(side)) * half.x + absf(axes.y.dot(side)) * half.y + absf(axes.z.dot(side)) * half.z
		_bow_slam(body, id, delta, bow, point, up, heading, side, speed, height, beam, crest)
		_arm_spray(body, id, delta, time)
		if bow_amount <= 0.0 or speed < bow_min_speed:
			continue
		var slam := 1.0 + crest * 3.0
		var debt: float = _bow_debt.get(id, 0.0)
		debt += clampf((speed - bow_min_speed) * 7.0, 0.0, 45.0) * slam * bow_amount * delta
		var throw := clampf(speed / 6.0, 0.4, 1.5)
		while debt >= 1.0:
			debt -= 1.0
			var outward := side * (1.0 if randf() < 0.5 else -1.0)
			var origin := point + outward * randf_range(0.1, 0.6) - heading * randf_range(0.0, 1.2)
			var velocity := body.linear_velocity * 0.2 + outward * randf_range(0.8, 2.6) * throw \
				+ up * randf_range(1.2, 3.8) * throw
			_emit(_drops, origin, velocity, randf_range(0.03, 0.065), randf_range(0.5, 1.1), 1.0)
			if randf() < 0.3:
				_emit(_mist, origin + up * 0.15, velocity * 0.45,
					randf_range(0.4, 0.9) * throw, randf_range(1.0, 2.0), 0.8)
		_bow_debt[id] = debt
	# Barcos que ya no se ven (hundidos, lejos, fuera del agua): fuera su estado.
	for key: int in _bow_debt.keys():
		if not seen.has(key):
			_bow_debt.erase(key)
	for key: int in _slam_state.keys():
		if not seen.has(key):
			_slam_state.erase(key)
	for key: int in _arm_debt.keys():
		if not seen.has(key):
			_arm_debt.erase(key)


## Golpe de proa. Se sigue cuánto moja el agua la roda (altura del agua sobre el punto de proa) y a qué
## ritmo cambia: cuando sube deprisa con el casco tocando agua, es un pantocazo. Va por frame y con el
## transform interpolado, que es lo que se ve; el ritmo se suaviza un poco para no disparar por ruido.
func _bow_slam(body: DynamicGridBody, id: int, delta: float, bow: Vector3, water: Vector3, up: Vector3,
		heading: Vector3, side: Vector3, speed: float, height: float, beam: float, crest: float) -> void:
	if slam_amount <= 0.0 or delta <= 0.0:
		return
	var wet := (water - _center).length() - (bow - _center).length()
	var state: Dictionary = _slam_state.get(id, {})
	_slam_state[id] = state
	if not state.has("wet"):
		state["wet"] = wet
		state["rate"] = 0.0
		state["cool"] = 0.0
		return
	var raw := (wet - float(state["wet"])) / delta
	state["wet"] = wet
	var rate := lerpf(float(state["rate"]), raw, clampf(delta * 25.0, 0.0, 1.0))
	state["rate"] = rate
	state["cool"] = maxf(float(state["cool"]) - delta, 0.0)
	# El agua tiene que estar en la roda: ni por debajo de la quilla ni ya por encima de la borda.
	if wet < -height - 0.15 or wet > height + 0.6:
		return
	# De lado o a la deriva el agua también sube por la proa con cada ola, y eso no es un golpe.
	var threshold := slam_min_rate * (1.0 if speed >= 1.0 else 1.6) * (1.0 - crest * 0.3)
	if rate < threshold or float(state["cool"]) > 0.0:
		return
	state["cool"] = slam_cooldown
	var power := clampf((rate - threshold) / 3.0 + 0.2, 0.2, 1.0) * (1.0 + crest * 0.5)
	_slam_burst(body, water, up, heading, side, speed, beam, power)


## La sábana del golpe: el agua que la roda aparta sale por los dos costados de la proa, hacia fuera y
## hacia arriba, y se queda atrás (el barco sigue y ella no: apenas hereda su velocidad). Una nube baja
## y el chasquido, y en la malla un anillo que se abre desde la roda. El tamaño crece con la manga.
func _slam_burst(body: DynamicGridBody, point: Vector3, up: Vector3, heading: Vector3, side: Vector3,
		_speed: float, beam: float, power: float) -> void:
	_count_bursts += 1
	var size := clampf(sqrt(maxf(beam, 0.3) / 1.2), 0.6, 2.0)
	var amount := power * slam_amount
	var lift := sqrt(minf(power, 1.5)) * sqrt(size)
	var carry := body.linear_velocity * 0.15
	var bow_length := minf(beam * 1.5, 2.5)
	for _i in int(round(lerpf(18.0, 80.0, minf(power, 1.0)) * size * slam_amount)):
		var wing := 1.0 if randf() < 0.5 else -1.0
		var back := randf()
		# Más adelante la roda es más estrecha: el agua sale pegada a ella.
		var origin := point - heading * back * bow_length + side * wing * beam * lerpf(0.25, 0.9, back) \
			+ up * randf_range(0.0, 0.25)
		var velocity := carry + side * wing * randf_range(1.1, 3.0) * lift + up * randf_range(1.5, 4.0) * lift \
			- heading * randf_range(0.0, 0.8)
		_emit(_drops, origin, velocity, randf_range(0.03, 0.075) * sqrt(size), randf_range(0.8, 1.8), 1.0)
	for _i in int(round(lerpf(2.0, 5.0, minf(power, 1.0)) * size * slam_amount)):
		var wing := 1.0 if randf() < 0.5 else -1.0
		var origin := point - heading * randf() * bow_length + side * wing * beam * randf_range(0.6, 1.1) \
			+ up * randf_range(0.2, 0.6) * lift
		var velocity := carry + side * wing * randf_range(0.6, 1.6) + up * randf_range(0.4, 1.4) * lift
		_emit(_mist, origin, velocity, randf_range(0.5, 1.0) * size, randf_range(0.8, 1.6), 0.6)
	var ring_center := point - heading * bow_length * 0.4
	HullWaves.ring(ring_center, amount, beam)
	var crown := HullWaves.ring_shape(clampf(amount, 0.0, 1.5), beam)
	crown["center"] = ring_center
	crown["up"] = up
	crown["age"] = 0.0
	crown["power"] = amount
	crown["debt"] = 0.0
	if _crowns.size() >= 16:
		_crowns.pop_front()
	_crowns.append(crown)
	AudioManager.play_3d(&"hull_slam", point, {
		"volume_offset_db": lerpf(-12.0, 0.0, clampf(amount, 0.0, 1.0)) + 4.0 * log(size) / log(2.0),
		"pitch": 0.8 * randf_range(0.92, 1.08) / sqrt(size)})


## La cresta del anillo de un golpe rompe mientras se abre: gotas que saltan de su frente, cada vez
## menos, hacia fuera y despacio, como la onda. Va encima de la cresta de la malla porque comparten forma
## (HullWaves.ring_shape).
func _crown_spray(delta: float) -> void:
	const WINDOW := 1.6
	for c in range(_crowns.size() - 1, -1, -1):
		var crown := _crowns[c]
		var age := float(crown["age"]) + delta
		crown["age"] = age
		if age >= WINDOW:
			_crowns.remove_at(c)
			continue
		var fade := 1.0 - age / WINDOW
		var front := float(crown["r0"]) + float(crown["speed"]) * age
		var center: Vector3 = crown["center"]
		var up: Vector3 = crown["up"]
		var debt := float(crown["debt"]) + front * TAU * 5.5 * float(crown["power"]) * fade * fade * delta
		var lift := float(crown["amp"]) * 4.0
		while debt >= 1.0:
			debt -= 1.0
			var out := _tangent(up)
			var origin := center + out * front + up * float(crown["amp"]) * fade * 0.8
			var velocity := out * float(crown["speed"]) * randf_range(0.5, 1.1) \
				+ up * randf_range(0.6, 1.8) * lift * fade
			_emit(_drops, origin, velocity, randf_range(0.02, 0.05), randf_range(0.5, 1.1), 1.0,
				randf_range(0.0, 0.4))
			if randf() < 0.06:
				_emit(_mist, origin + up * 0.2, velocity * 0.4, randf_range(0.4, 0.8), randf_range(0.9, 1.6), 0.5)
		crown["debt"] = debt


## Rocío de los brazos de la ola de proa: donde la V se levanta junto al casco la cresta se deshace en
## gotas que saltan hacia fuera. Sigue la misma curva que la malla (hull_waves.gdshaderinc), más
## densa cerca de la roda, y solo cuando la ola tiene altura para romper.
func _arm_spray(body: DynamicGridBody, id: int, delta: float, time: float) -> void:
	if bow_amount <= 0.0:
		return
	var info := HullWaves.hull_info(body)
	if info.is_empty():
		return
	var amplitude: float = info["amplitude"]
	if amplitude < 0.06:
		return
	var length: float = info["length"]
	var beam: float = info["beam"]
	var speed: float = info["speed"]
	var heading: Vector3 = info["heading"]
	var side: Vector3 = info["side"]
	var up: Vector3 = info["up"]
	var center: Vector3 = info["center"]
	var debt: float = _arm_debt.get(id, 0.0)
	debt += clampf((amplitude - 0.06) * speed * 11.0, 0.0, 50.0) * bow_amount * delta
	while debt >= 1.0:
		debt -= 1.0
		# x: metros detrás del vértice de la V, como en el shader.
		var x := pow(randf(), 1.8) * length * 1.6
		var yc := beam * (1.0 - exp(-x / (0.8 * beam + 0.5))) + x * 0.42
		var wing := 1.0 if randf() < 0.5 else -1.0
		var along := length + 0.3 * beam - x
		var rest := (center + heading * along + side * wing * yc - _center).normalized() * ocean.radius
		var fade := exp(-x / (1.2 * length + 2.0))
		var origin := _center + rest + _sampler.rest_displacement(rest, time, 0.0) + up * amplitude * fade * 0.8
		var velocity := body.linear_velocity * 0.15 + side * wing * randf_range(0.4, 1.4) * sqrt(speed) * fade \
			+ up * randf_range(0.6, 2.2) * sqrt(amplitude) * 2.0 * fade
		_emit(_drops, origin, velocity, randf_range(0.02, 0.05), randf_range(0.5, 1.1), 1.0, randf_range(0.1, 0.6))
	_arm_debt[id] = debt


## [floaty] 0..1: cuánto flota (ver COLOR.r en water_spray_process.gdshader).
func _emit(emitter: GPUParticles3D, origin: Vector3, velocity: Vector3, size: float, life: float,
		alpha: float, floaty: float = 0.0) -> void:
	_count_particles += 1
	emitter.emit_particle(Transform3D(Basis.IDENTITY, origin), velocity, Color(floaty, 1.0, 1.0, alpha),
		Color(randf(), 0.0, size, minf(life, MAX_LIFETIME)), EMIT_FLAGS)


## Dirección horizontal al azar en el plano tangente de [up].
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
	# Por encima del agua (prioridad 3): los dos son transparentes y el rocío va delante.
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
	emitter.fixed_fps = 0
	emitter.interpolate = false
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
