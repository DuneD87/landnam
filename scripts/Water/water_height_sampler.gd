class_name WaterHeightSampler extends Node

## Réplica en CPU de las olas Gerstner de water_shader.gdshader para física/flotabilidad.
## Devuelve el radio de superficie (desplazamiento radial) en una posición, invirtiendo el
## arrastre horizontal de Gerstner para coincidir con la superficie visual del shader. Debe
## mantenerse en sincronía con gerstner_surface().

var wave_speed: float
var wave_amplitude: float
var wave_steepness: float
var wave_base_length: float
var wave_octaves: int
var wave_direction: Vector2
var wave_pole: Vector3
var wave_calm_amplitude: float
var wave_calm_steepness: float

## Olas de orilla. Se releen con los demás params dinámicos y no en setup(): el mapa del planeta
## enciende shore_waves_enabled cuando termina de hornearse, mucho después de montar el sampler.
var shore_enabled: bool = false
var shore_amplitude: float
var shore_length: float
var shore_speed: float
var shore_steepness: float
var shore_depth_fade: float
var shore_shoal_max: float
var shore_incidence: float
var shore_reach: float
var shore_range: float
var shore_fade: float
var shore_handover: float

## Mapa del planeta, opcional. Con él, el oleaje de tormenta se queda donde el shader lo dibuja
## (mar abierto) en vez de zarandear a los barcos dentro de un lago o pegados a la orilla. Sin él
## la exposición es 1 en todas partes, o sea el comportamiento de siempre.
var world_map: PlanetWorldMap

var _material: ShaderMaterial
var _water_radius: float = 0.0
## Normal analítica de la última evaluación de _gerstner_disp. Se acumula siempre porque sale casi
## gratis del mismo bucle; la lee get_surface_at.
var _last_normal: Vector3 = Vector3.UP

static var _frame_cache: Dictionary = {}
## Defaults declarados por el shader, por RID de shader y nombre. Ver _param.
static var _default_cache: Dictionary = {}

const _GOLDEN_ANGLE := 2.399963
const _TAU := 6.28318530718
const _INVERT_ITERATIONS := 3

## Lee del material los parámetros que intervienen en la altura de ola. 'planet_map' es opcional;
## ver el comentario de 'world_map'. 'surface_radius' solo lo necesita get_surface_at (la línea de
## flotación): pásalo cuando lo conozcas, porque el uniform water_radius del material lo pone el
## mesh manager cada frame y el .tres lo trae a 0.0, así que leerlo aquí cachearía un radio falso.
func setup(water_material: ShaderMaterial, planet_map: PlanetWorldMap = null,
		surface_radius: float = -1.0) -> void:
	_material = water_material
	world_map = planet_map
	wave_octaves = int(water_material.get_shader_parameter("wave_octaves"))
	wave_direction = water_material.get_shader_parameter("wave_direction")
	var pole: Variant = water_material.get_shader_parameter("wave_pole")
	wave_pole = pole if pole != null else Vector3(0, 1, 0)
	if surface_radius >= 0.0:
		_water_radius = surface_radius
	else:
		var radius: Variant = _param(water_material, "water_radius")
		_water_radius = radius if radius != null else 0.0
	_refresh_dynamic_params()

## Valor de un uniform, o el que declare el shader si el material no lo sobrescribe.
## get_shader_parameter() devuelve null para TODO lo que no esté puesto explícitamente en el .tres,
## aunque el shader tenga un default; sin este relevo la CPU vería nulos donde la GPU ve valores.
static func _param(mat: ShaderMaterial, name: StringName) -> Variant:
	var v: Variant = mat.get_shader_parameter(name)
	if v != null or mat.shader == null:
		return v
	var shader_rid: RID = mat.shader.get_rid()
	var defaults: Dictionary = _default_cache.get(shader_rid, {})
	if not defaults.has(name):
		defaults[name] = RenderingServer.shader_get_parameter_default(shader_rid, name)
		_default_cache[shader_rid] = defaults
	return defaults[name]

## Params dinámicos del material releídos como mucho una vez por frame de física y compartidos
## entre todos los samplers (el weather los muta en caliente, pero no dentro de un mismo frame).
static func _get_frame_params(mat: ShaderMaterial) -> Dictionary:
	var key: RID = mat.get_rid()
	var frame := Engine.get_physics_frames()
	var cached: Dictionary = _frame_cache.get(key, {})
	if cached.get("frame", -1) != frame:
		var time: Variant = mat.get_shader_parameter("water_time")
		cached = {
			"frame": frame,
			"speed": mat.get_shader_parameter("wave_speed"),
			"amplitude": mat.get_shader_parameter("wave_amplitude"),
			"steepness": mat.get_shader_parameter("wave_steepness"),
			"base_length": mat.get_shader_parameter("wave_base_length"),
			# Si el material no los expone (planeta sin clima), la calma es el estado actual y la
			# mezcla de más abajo se vuelve una identidad.
			"calm_amplitude": mat.get_shader_parameter("wave_calm_amplitude"),
			"calm_steepness": mat.get_shader_parameter("wave_calm_steepness"),
			"time": time if time != null else 0.0,
			# Olas de orilla. shore_on se enciende cuando el mapa del planeta termina de hornearse,
			# así que no se puede resolver una vez en setup().
			"shore_on": _param(mat, "shore_waves_enabled"),
			"shore_amplitude": _param(mat, "shore_amplitude"),
			"shore_length": _param(mat, "shore_length"),
			"shore_speed": _param(mat, "shore_speed"),
			"shore_steepness": _param(mat, "shore_steepness"),
			"shore_depth_fade": _param(mat, "shore_depth_fade"),
			"shore_shoal_max": _param(mat, "shore_shoal_max"),
			"shore_incidence": _param(mat, "shore_incidence"),
			"shore_reach": _param(mat, "shore_reach"),
			"shore_range": _param(mat, "shore_range"),
			"shore_fade": _param(mat, "shore_fade"),
			"shore_handover": _param(mat, "shore_handover"),
		}
		_frame_cache[key] = cached
	return cached

## Tiempo de agua del material, con la misma caché por frame.
static func get_water_time(mat: ShaderMaterial) -> float:
	return _get_frame_params(mat)["time"]

## Relee los parámetros que el weather muta en caliente sobre el material.
func _refresh_dynamic_params() -> void:
	var params := _get_frame_params(_material)
	wave_speed = params["speed"]
	wave_amplitude = params["amplitude"]
	wave_steepness = params["steepness"]
	wave_base_length = params["base_length"]
	var calm_amp: Variant = params["calm_amplitude"]
	var calm_steep: Variant = params["calm_steepness"]
	wave_calm_amplitude = calm_amp if calm_amp != null else wave_amplitude
	wave_calm_steepness = calm_steep if calm_steep != null else wave_steepness

	var shore_on: Variant = params["shore_on"]
	var amp: Variant = params["shore_amplitude"]
	# Sin amplitud es que el material tira de un shader sin los uniforms de orilla: se queda con el
	# oleaje de siempre en vez de reventar.
	shore_enabled = world_map != null and shore_on != null and bool(shore_on) and amp != null
	if not shore_enabled:
		return
	shore_amplitude = amp
	shore_length = params["shore_length"]
	shore_speed = params["shore_speed"]
	shore_steepness = params["shore_steepness"]
	shore_depth_fade = params["shore_depth_fade"]
	shore_shoal_max = params["shore_shoal_max"]
	shore_incidence = params["shore_incidence"]
	shore_reach = params["shore_reach"]
	shore_range = params["shore_range"]
	shore_fade = params["shore_fade"]
	shore_handover = params["shore_handover"]

## Altura de ola (desplazamiento radial) en world_pos. Invierte por punto-fijo el arrastre
## horizontal de Gerstner: sin esto, con oleaje marcado la física y el visual se separan varios metros.
func get_height_at(world_pos: Vector3, time: float, planet_center: Vector3) -> float:
	if _material == null:
		return 0.0
	_refresh_dynamic_params()

	var local_q := world_pos - planet_center
	# Una sola vez por muestra, no dentro de la inversión: el punto fijo mueve la posición unos
	# metros y la máscara varía en decenas, así que la diferencia no se aprecia y ahorra 3/4 del coste.
	var exposure := world_map.storm_exposure_local(local_q) if world_map != null else 1.0
	# El campo de orilla y la profundidad, por lo mismo, una sola vez por muestra.
	var shore_off := Vector3.ZERO
	var shore_weight := 0.0
	var shore_depth := 0.0
	if shore_enabled:
		var field := world_map.shore_sample_local(local_q)
		var off := Vector3(field.x, field.y, field.z)
		if field.w > 0.001 and off.length_squared() > 1.0:
			shore_off = off
			shore_weight = field.w
			shore_depth = world_map.water_depth_local(local_q)

	# Busca la posición "en reposo" cuya ola desplazada horizontalmente cae bajo world_pos.
	var guess := local_q
	for _i in _INVERT_ITERATIONS:
		var radial := guess.normalized()
		var disp := _gerstner_disp(guess, radial, time, exposure, shore_off, shore_weight, shore_depth)
		var horiz := disp - radial * disp.dot(radial)
		guess = local_q - horiz

	var final_radial := guess.normalized()
	return _gerstner_disp(guess, final_radial, time, exposure, shore_off, shore_weight, shore_depth).dot(final_radial)


## Punto de superficie y normal analítica sobre world_pos, en un diccionario {point, normal}. Los
## dos salen del MISMO punto invertido: evaluar la normal en world_pos sin invertir la deja en otra
## fase de la ola y descuadra el corte de la línea de flotación.
##
## Lo consume OceanSystem una vez por frame para el plano de la línea de flotación, que antes
## calculaba el vertex shader del agua con la posición de la CÁMARA: el mismo valor para todos los
## vértices, tres evaluaciones completas de la superficie por cada uno.
func get_surface_at(world_pos: Vector3, time: float, planet_center: Vector3) -> Dictionary:
	var up_dir := (world_pos - planet_center).normalized()
	var height := get_height_at(world_pos, time, planet_center)
	return {
		"point": planet_center + up_dir * (_water_radius + height),
		"normal": _last_normal,
	}

## Desplazamiento world-space (tangencial + radial) de la suma de olas Gerstner en 'local'.
## Réplica de gerstner_surface() del shader (posición; la normal no hace falta en CPU).
func _gerstner_disp(local: Vector3, radial: Vector3, time: float, exposure: float,
		shore_off: Vector3, shore_weight: float, shore_depth: float) -> Vector3:
	var pole := wave_pole.normalized()
	var gx := pole.cross(Vector3(1, 0, 0) if absf(pole.x) < 0.9 else Vector3(0, 0, 1)).normalized()
	var gy := pole.cross(gx)

	var base_dir := wave_direction
	if absf(base_dir.x) + absf(base_dir.y) < 1e-4:
		base_dir = Vector2(1.0, 0.0)
	else:
		base_dir = base_dir.normalized()

	var octaves := clampi(wave_octaves, 1, 6)
	# Relevo entre familias: donde manda la orilla, el oleaje de mar abierto se apaga. Suma de las
	# dos a la vez y en una costa a sotavento el swell global viaja mar adentro sobre la rompiente.
	var shore_gate := 0.0
	if shore_off != Vector3.ZERO:
		var reach := shore_reach if shore_reach > 0.0 else shore_range
		shore_gate = shore_weight * smoothstep(
			reach, reach * (1.0 - shore_fade), shore_off.length())
	# Asimétrico a propósito: ver shore_handover en gerstner_waves.gdshaderinc.
	var ocean_weight := 1.0 - smoothstep(0.0, shore_handover, shore_gate)

	# Misma mezcla que gerstner_surface_lod; la exposición viene resuelta de get_height_at.
	var amp := lerpf(wave_calm_amplitude, wave_amplitude, exposure)
	var steepness := lerpf(wave_calm_steepness, wave_steepness, exposure)
	var length := wave_base_length
	var ang := 0.0
	var horiz := Vector3.ZERO
	var vert := 0.0
	var swell_dir := Vector3.ZERO
	# Términos de la normal analítica, réplica de out_normal en gerstner_surface_ctx.
	var grad := Vector3.ZERO
	var n_up_sub := 0.0

	for i in octaves:
		var k := _TAU / maxf(length, 0.1)
		var ca := cos(ang)
		var sa := sin(ang)
		var dir_fixed := (gx * (base_dir.x * ca - base_dir.y * sa) + gy * (base_dir.x * sa + base_dir.y * ca)).normalized()
		var dir_dot := clampf(dir_fixed.dot(radial), -1.0, 1.0)
		var dir_tan := dir_fixed - radial * dir_dot
		var tan_len := dir_tan.length()
		var dir_unit := (dir_tan / tan_len) if tan_len > 1e-4 else Vector3.ZERO
		if i == 0:
			swell_dir = -dir_unit
		var q := steepness / maxf(k * amp * float(octaves), 1e-4)
		# Distancia geodésica firmada al gran círculo de la ola. Su gradiente tangente
		# tiene módulo 1, así la longitud de onda no cambia con latitud/longitud.
		var signed_arc := local.length() * asin(dir_dot)
		var phase := k * signed_arc + time * wave_speed * sqrt(k)
		horiz += dir_unit * (q * amp * cos(phase) * ocean_weight)
		vert += amp * sin(phase) * ocean_weight
		grad += dir_unit * (k * amp * cos(phase) * ocean_weight)
		n_up_sub += q * k * amp * sin(phase) * ocean_weight
		amp *= 0.5
		length *= 0.5
		ang += _GOLDEN_ANGLE

	if shore_gate > 0.001:
		var dist := shore_off.length()
		var seaward := -shore_off / dist
		seaward = (seaward - radial * seaward.dot(radial)).normalized()
		var shoal := clampf(
			pow(maxf(shore_depth, 0.5) / maxf(shore_length * 0.5, 1.0), -0.25), 1.0, shore_shoal_max)
		var swash := smoothstep(0.0, shore_depth_fade, shore_depth)
		var lee := lerpf(1.0,
			lerpf(0.35, 1.0, smoothstep(-0.9, 0.6, swell_dir.dot(-seaward))), shore_incidence)
		var w := shore_gate * swash * lee

		var k := _TAU / maxf(shore_length, 0.1)
		var amp_ref := shore_amplitude * shoal
		var q := shore_steepness / maxf(k * amp_ref, 1e-4)
		var phase := k * dist + time * shore_speed * sqrt(k)
		horiz += seaward * (q * amp_ref * cos(phase) * w)
		vert += amp_ref * sin(phase) * w
		grad += seaward * (k * amp_ref * cos(phase) * w)
		n_up_sub += q * k * amp_ref * sin(phase) * w

	_last_normal = (radial * (1.0 - n_up_sub) - grad).normalized()
	return horiz + radial * vert
