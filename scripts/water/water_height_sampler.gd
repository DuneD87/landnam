class_name WaterHeightSampler extends Node
const Spectrum = preload("res://scripts/water/ocean_spectrum.gd")
var _wind := Vector3(0,0,-1)
var spectrum_spread: float = 0.8

## Réplica en CPU de las olas Gerstner de water_shader.gdshader para física/flotabilidad.
## Devuelve el radio de superficie (desplazamiento radial) en una posición, invirtiendo el
## arrastre horizontal de Gerstner para coincidir con la superficie visual del shader. Debe
## mantenerse en sincronía con gerstner_surface().

var wave_speed: float
var wave_amplitude: float
var wave_steepness: float
var wave_base_length: float
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
var shore_chop: float

## Mapa del planeta, opcional. Con él, el oleaje de tormenta se queda donde el shader lo dibuja
## (mar abierto) en vez de zarandear a los barcos dentro de un lago o pegados a la orilla. Sin él
## la exposición es 1 en todas partes, o sea el comportamiento de siempre.
var world_map: PlanetWorldMap

## Multiplicador global de la corriente, compartido por toda la flota. Lo mueve el comando 'drift'.
static var drift_scale: float = 5.0
## Profundidad (m) del punto al que se pide la corriente: la atenúa con e^-kz. Los cuerpos flotantes
## la dejan en 0 y se ahorran las exponenciales.
var flow_depth: float = 0.0
## Velocidad del agua (vaivén orbital + corriente) de la última evaluación, en world-space. Sale casi
## gratis del bucle de _gerstner_disp: quien ya haya llamado a get_height_at la tiene aquí sin
## volver a muestrear. Ver get_flow_at.
var last_flow: Vector3 = Vector3.ZERO
## Puertas que apagan el oleaje de mar abierto en la última evaluación. Solo diagnóstico ('drift').
var last_exposure: float = 1.0
var last_ocean_weight: float = 1.0
var last_shore_presence: float = 0.0
var last_amp_effective: float = 0.0
## Hielo marino (0..1) de la última evaluación: 1 = banquisa, sin oleaje. Lo lee el jugador para
## caminar sobre el hielo en vez de nadar.
var last_ice: float = 0.0

## Hielo marino del material (sea_ice_enabled / sea_ice_params de gerstner_waves.gdshaderinc).
var sea_ice_enabled: bool = false
var sea_ice_params := Vector4(57.0, 63.0, 10.0, 300.0)

var _material: ShaderMaterial
var _water_radius: float = 0.0
## Normal analítica de la última evaluación de _gerstner_disp. Se acumula siempre porque sale casi
## gratis del mismo bucle; la lee get_surface_at.
var _last_normal: Vector3 = Vector3.UP
var _last_du := Vector3.ZERO
var _last_dv := Vector3.ZERO

## Parámetros y marco de viento actualizados una vez por frame de física.
## OceanSpectrum comparte los modos constantes entre todas las sondas.
var _frame_stamp: int = -1

static var _frame_cache: Dictionary = {}
## Defaults declarados por el shader, por RID de shader y nombre. Ver _param.
static var _default_cache: Dictionary = {}

const _TAU := 6.28318530718

## Corriente superficial en m/s con mar tendida y con temporal pleno. Su magnitud sale de los
## uniforms globales del oleaje y NO de la geometría local de la ola: donde flota un barco (poco
## fondo, cerca de la costa) el oleaje de mar abierto está apagado por la máscara de temporal y por
## el relevo con la rompiente, así que de ahí salía la misma corriente con temporal que sin él.
const CURRENT_CALM := 0.6
const CURRENT_STORM := 3.0
## Cuánto ha de crecer la ola sobre la calma para dar el estado de mar por temporal pleno.
const CURRENT_SEA_STATE_SPAN := 6.0
## Corriente que conserva el agua abrigada. No es cero a propósito: la máscara de temporal se apaga
## bajo 30 m de fondo, justo donde navegan los barcos, y como factor dejaría la costa sin arrastre.
const CURRENT_SHELTERED_FRAC := 0.4
## La rompiente empuja hacia tierra pero la resaca devuelve parte: el empujón neto es una fracción.
const CURRENT_SHORE_FRAC := 0.7


## Réplica CPU de shore_breakup() en shore_breakup.gdshaderinc: rotura de la ola de orilla.
## x = desplazamiento de fase en radianes; y = factor de amplitud en [0,1].
static func _shore_breakup(local: Vector3, time: float, wavelength: float) -> Vector2:
	var wl := maxf(wavelength, 1.0)

	var p := local / 55.0
	var a := sin(p.dot(Vector3(0.73, 0.21, 0.65)) + time * 0.037)
	var b := sin(p.dot(Vector3(-0.31, 0.88, 0.36)) * 1.37 + 1.7 - time * 0.026)
	var env := clampf(0.5 + a * 0.325 + b * 0.175, 0.0, 1.0)

	var m1 := local * (_TAU / (wl * 3.0))
	var m2 := local * (_TAU / (wl * 1.5))
	var w1 := sin(m1.dot(Vector3(0.83, -0.28, 0.48)) + time * 0.19)
	var w2 := sin(m2.dot(Vector3(-0.37, 0.62, 0.69)) + 1.3 - time * 0.31)

	var c1 := local * (_TAU / (wl * 4.0))
	var e1 := sin(c1.dot(Vector3(0.29, 0.75, -0.60)) + time * 0.13)
	var e2 := sin(c1.dot(Vector3(-0.71, 0.41, 0.57)) * 1.63 - time * 0.11)
	var cells := clampf(0.5 + e1 * 0.34 + e2 * 0.22, 0.0, 1.0)

	var packet := env * 0.5 + cells * 0.5
	return Vector2((env - 0.5) * 0.9 + w1 * 0.85 + w2 * 0.25,
		lerpf(0.25, 1.0, smoothstep(0.2, 0.8, packet)))


## Lee del material los parámetros que intervienen en la altura de ola. 'planet_map' es opcional;
## ver el comentario de 'world_map'. 'surface_radius' solo lo necesita get_surface_at (la línea de
## flotación): pásalo cuando lo conozcas, porque el uniform water_radius del material lo pone el
## mesh manager cada frame y el .tres lo trae a 0.0, así que leerlo aquí cachearía un radio falso.
func setup(water_material: ShaderMaterial, planet_map: PlanetWorldMap = null,
		surface_radius: float = -1.0) -> void:
	_material = water_material
	world_map = planet_map
	# Cambiar de material o de planeta invalida los parámetros aunque no haya cambiado el frame.
	_frame_stamp = -1
	var direction: Variant = _param(water_material,"wave_direction")
	wave_direction = direction if direction != null else Vector2(2,0)
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
			"speed": _param(mat,"wave_speed"),
			"amplitude": _param(mat,"wave_amplitude"),
			"steepness": _param(mat,"wave_steepness"),
			"base_length": _param(mat,"wave_base_length"),
			"spectrum_spread": _param(mat,"spectrum_spread"),
			"direction": _param(mat,"wave_direction"),
			"pole": _param(mat,"wave_pole"),
			"radius": _param(mat,"water_radius"),

			# Si el material no los expone (planeta sin clima), la calma es el estado actual y la
			# mezcla de más abajo se vuelve una identidad.
			"calm_amplitude": _param(mat,"wave_calm_amplitude"),
			"calm_steepness": _param(mat,"wave_calm_steepness"),
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
			"shore_chop": _param(mat, "shore_chop"),
			"sea_ice_enabled": _param(mat, "sea_ice_enabled"),
			"sea_ice_params": _param(mat, "sea_ice_params"),
		}
		_frame_cache[key] = cached
	return cached

## Tiempo de agua del material, con la misma caché por frame.
static func get_water_time(mat: ShaderMaterial) -> float:
	return _get_frame_params(mat)["time"]

## Relee los parámetros que el weather muta en caliente sobre el material.
## Relee del material lo que weather muta en caliente, una vez por frame de física: la flotación
## entra aquí una vez por caja y no puede pagar el refresco en cada una.
func _ensure_frame_params() -> void:
	if _material == null:
		return
	var frame := Engine.get_physics_frames()
	if _frame_stamp == frame:
		return
	_frame_stamp = frame
	_refresh_dynamic_params()
	_rebuild_wave_frame()


## Estado de mar en [0,1]: 0 = mar tendida, 1 = temporal pleno. Es la MISMA medida con la que
## se resuelve la corriente; está expuesta para que nadie (el audio del océano, por ejemplo)
## invente otra escala y acabe discrepando de la física sobre cuánto sopla.
func get_sea_state() -> float:
	_ensure_frame_params()
	return _sea_state()


func _sea_state() -> float:
	return clampf(
		(wave_amplitude / maxf(wave_calm_amplitude, 0.01) - 1.0) / CURRENT_SEA_STATE_SPAN, 0.0, 1.0)


func _refresh_dynamic_params() -> void:
	var params := _get_frame_params(_material)
	var spread_value: Variant = params["spectrum_spread"]
	spectrum_spread = float(spread_value) if spread_value != null else 0.8
	if params.direction != null:
		wave_direction = params.direction
	if params.pole != null:
		wave_pole = params.pole
	if _water_radius<=0.0 and params.radius != null:
		_water_radius = params.radius
	wave_speed = params["speed"]
	wave_amplitude = params["amplitude"]
	wave_steepness = params["steepness"]
	wave_base_length = params["base_length"]
	var calm_amp: Variant = params["calm_amplitude"]
	var calm_steep: Variant = params["calm_steepness"]
	wave_calm_amplitude = calm_amp if calm_amp != null else wave_amplitude
	wave_calm_steepness = calm_steep if calm_steep != null else wave_steepness
	var ice_on: Variant = params["sea_ice_enabled"]
	sea_ice_enabled = ice_on != null and bool(ice_on)
	var ice_params: Variant = params["sea_ice_params"]
	if ice_params is Vector4:
		sea_ice_params = ice_params

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
	# Mismo relevo que con la calma: un material con un shader anterior al chop se queda sin él en vez
	# de reventar al asignar nulo.
	var chop: Variant = params["shore_chop"]
	shore_chop = chop if chop != null else 0.0


## Marco de viento compartido por los grupos locales.
func _rebuild_wave_frame() -> void:
	var pole := wave_pole.normalized() if wave_pole.length_squared()>0.0001 else Vector3.UP
	var gx := pole.cross(Vector3.RIGHT if absf(pole.x)<0.9 else Vector3(0,0,1)).normalized()
	var gy := pole.cross(gx)
	var d := wave_direction.normalized() if wave_direction.length_squared()>0.0001 else Vector2.RIGHT
	_wind = gx*d.x+gy*d.y


## Altura en world_pos. Invierte con Newton el arrastre
## horizontal de Gerstner: sin esto, con oleaje marcado la física y el visual se separan varios metros.
func get_height_at(world_pos: Vector3, time: float, planet_center: Vector3) -> float:
	if _material == null:
		return 0.0
	_ensure_frame_params()

	var input_local := world_pos - planet_center
	if input_local.length_squared()<0.0001:
		last_flow = Vector3.ZERO
		_last_normal = Vector3.UP
		return 0.0
	var radius := _water_radius if _water_radius>0.0 else input_local.length()
	var local_q := input_local.normalized()*radius
	var ctx := _context(local_q)
	var exposure: float = ctx[0]
	var shore_dir: Vector3 = ctx[1]
	var shore_signed_dist: float = ctx[2]
	var shore_quality: float = ctx[3]
	var shore_depth: float = ctx[4]
	var ice: float = ctx[5]
	last_ice = ice

	# Busca la posición "en reposo" cuya ola desplazada horizontalmente cae bajo world_pos.
	var guess := local_q
	var target_up := local_q.normalized()
	var target_u := target_up.cross(Vector3.RIGHT if absf(target_up.x)<0.9 else Vector3.UP).normalized()
	var target_v := target_up.cross(target_u)
	for _i in 4:
		var radial := guess.normalized()
		var disp := _gerstner_disp(
			guess, radial, time, exposure,
			shore_dir, shore_signed_dist, shore_quality, shore_depth, ice)
		var residual := guess+disp-local_q
		var error := Vector2(residual.dot(target_u),residual.dot(target_v))
		if error.length_squared()<0.000025:
			return (guess+disp).length()-radius
		var a := _last_du.dot(target_u)
		var b := _last_dv.dot(target_u)
		var c := _last_du.dot(target_v)
		var d := _last_dv.dot(target_v)
		var det := a*d-b*c
		var u := radial.cross(Vector3.RIGHT if absf(radial.x)<0.9 else Vector3.UP).normalized()
		var v := radial.cross(u)
		if det>0.05:
			var step := (u*(d*error.x-b*error.y)+v*(a*error.y-c*error.x))/det
			guess = (guess-step.limit_length(maxf(wave_base_length*0.4,1.0))).normalized()*radius
		else:
			guess = (local_q-(disp-radial*disp.dot(radial))).normalized()*radius

	var final_radial := guess.normalized()
	var final_disp := _gerstner_disp(
		guess, final_radial, time, exposure,
		shore_dir, shore_signed_dist, shore_quality, shore_depth, ice)
	return (guess+final_disp).length()-radius


## Lo que la superficie necesita del mapa del planeta en un punto (réplica de wave_context):
## [exposición, dirección a tierra, distancia firmada, calidad, profundidad, hielo]. Se resuelve una
## vez por muestra, no dentro de la inversión: el punto fijo mueve la posición unos metros y la
## máscara varía en decenas, así que la diferencia no se aprecia y ahorra 3/4 del coste.
func _context(local_q: Vector3) -> Array:
	var exposure := world_map.storm_exposure_local(local_q) if world_map != null else 1.0
	# El campo de orilla y la profundidad, por lo mismo, una sola vez por muestra.
	var shore_dir := Vector3.ZERO
	var shore_signed_dist := 0.0
	var shore_quality := 0.0
	var shore_depth := 0.0
	# Distancia a la costa para el hielo: igual que ice_shore en wave_context (gerstner_waves).
	var ice_shore := -1.0
	if shore_enabled:
		ice_shore = 0.0
	if shore_enabled and world_map.shore_waves_allowed_local(local_q):
		var field := world_map.shore_sample_local(local_q)
		var raw_dir := Vector3(field.x, field.y, field.z)
		shore_quality = clampf(raw_dir.length(), 0.0, 1.0)
		ice_shore = absf(field.w)
		# Fuera del if a propósito: el shader resuelve shore_depth en cuanto la costera está permitida,
		# sin mirar la distancia. Daba igual mientras solo lo usara el shoaling (que vive dentro de la
		# rama de distancia), pero el tope de agua somera del chop lo consulta SIEMPRE, y dejarlo aquí
		# dentro apagaba el chop en CPU y no en GPU justo en la línea de agua.
		shore_depth = world_map.water_depth_local(local_q)
		if absf(field.w) > 1.0:
			shore_dir = raw_dir / shore_quality if shore_quality > 1e-4 else Vector3.ZERO
			shore_signed_dist = field.w
	var ice := ClimateField.sea_ice_with(local_q, ice_shore, sea_ice_params) if sea_ice_enabled else 0.0
	return [exposure, shore_dir, shore_signed_dist, shore_quality, shore_depth, ice]


## Desplazamiento de la partícula de agua que en reposo está en `local_rest` (relativa al centro,
## sobre el radio del mar), sin inversión: es lo que sigue un cuerpo que flota con la ola, como un
## témpano. min_length apaga las octavas más cortas que él, igual que gerstner_surface_ctx en el
## shader. Deja la normal en last_normal y el hielo en last_ice.
func rest_displacement(local_rest: Vector3, time: float, min_length: float) -> Vector3:
	if _material == null:
		return Vector3.ZERO
	_ensure_frame_params()
	var ctx := _context(local_rest)
	last_ice = ctx[5]
	return _gerstner_disp(local_rest, local_rest.normalized(), time, ctx[0],
		ctx[1], ctx[2], ctx[3], ctx[4], ctx[5], min_length)


## Normal analítica de la última evaluación.
func last_normal() -> Vector3:
	return _last_normal


## Velocidad del agua en world_pos: vaivén orbital de la ola más la corriente superficial, que es la
## que transporta de verdad. Ajusta flow_depth antes de llamar si el punto va sumergido. Cuesta lo
## mismo que get_height_at: quien ya la haya llamado aquí debe leer last_flow en vez de remuestrear.
func get_flow_at(world_pos: Vector3, time: float, planet_center: Vector3) -> Vector3:
	if _material == null:
		return Vector3.ZERO
	get_height_at(world_pos, time, planet_center)
	return last_flow


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
## Réplica de gerstner_surface() del shader: posición, normal y tangentes para la inversión.
func _gerstner_disp(local: Vector3, radial: Vector3, time: float, exposure: float,
		shore_dir: Vector3, shore_signed_dist: float,
		shore_quality: float, shore_depth: float, ice: float = 0.0,
		min_length: float = 0.0) -> Vector3:
	var shore_dist := absf(shore_signed_dist)
	# Relevo entre familias: donde manda la orilla, el oleaje de mar abierto se apaga. Suma de las
	# dos a la vez y en una costa a sotavento el swell global viaja mar adentro sobre la rompiente.
	var shore_gate := 0.0
	if shore_dist > 1.0:
		var reach := shore_reach if shore_reach > 0.0 else shore_range
		shore_gate = 1.0 - smoothstep(
			reach * (1.0 - shore_fade), reach, shore_dist)
	# La profundidad del mapa es demasiado gruesa para decidir si existe la costera: puede decir
	# "tierra" donde la superficie visible aún es agua. La distancia al litoral apaga en su lugar el
	# desplazamiento durante los primeros metros de la línea de contacto.
	var shoreline_fade := smoothstep(
		1.0, maxf(shore_length * 0.25, shore_depth_fade), shore_dist)
	var shore_presence := shore_gate * shoreline_fade
	if min_length > 0.0:
		shore_presence *= smoothstep(min_length * 0.5, min_length * 1.5, shore_length)
	# Asimétrico a propósito: ver shore_handover en gerstner_waves.gdshaderinc.
	var ocean_weight := 1.0 - smoothstep(0.0, shore_handover, shore_presence)

	# Misma mezcla que gerstner_surface_lod; la exposición viene resuelta de get_height_at.
	var amp := maxf(lerpf(wave_calm_amplitude, wave_amplitude, exposure),0.0) * (1.0 - ice)
	var steepness := lerpf(wave_calm_steepness, wave_steepness, exposure)
	var horiz := Vector3.ZERO
	var vert := 0.0
	var swell_dir := Vector3.ZERO
	# Términos de la normal analítica, réplica de out_normal en gerstner_surface_ctx.
	var grad := Vector3.ZERO
	var n_up_sub := 0.0
	# Velocidad del agua: derivada temporal del propio desplazamiento (órbita) más la corriente.
	var flow := Vector3.ZERO
	var depth_fade := flow_depth > 0.01

	# Suelo del relevo para las octavas mucho más cortas que la rompiente; ver shore_chop en
	# gerstner_waves.gdshaderinc. Sin familia costera el relevo no existe y esto queda en 0.
	var chop_floor := shore_chop if shore_enabled else 0.0
	var wind := _wind
	swell_dir = -(wind-radial*wind.dot(radial)).normalized()
	var surface_field := Spectrum.evaluate(local,wind,time,amp,steepness,wave_base_length,wave_speed,
		spectrum_spread,ocean_weight,shore_depth,maxf(shore_length,1.0),chop_floor,flow_depth,min_length)
	flow = surface_field.velocity
	last_amp_effective = amp*ocean_weight
	var shore_axis := Vector3.ZERO

	# Corriente de mar abierto, en el sentido de avance del swell principal. La exposición entra como
	# atenuador con suelo, no mezclada en la amplitud: distingue una rada sin dejar la costa a cero.
	var storm_state := _sea_state()
	var current_mag := lerpf(CURRENT_CALM, CURRENT_STORM, storm_state) * drift_scale \
		* lerpf(CURRENT_SHELTERED_FRAC, 1.0, exposure)
	if current_mag > 0.0:
		# El reparto con la costera va por shore_presence y no por ocean_weight: ese relevo es
		# asimétrico a propósito y copiarlo deja una franja sin corriente al acercarse a tierra.
		var ocean_current := swell_dir * (current_mag * (1.0 - shore_presence))
		if depth_fade:
			ocean_current *= exp(-(_TAU / maxf(wave_base_length, 0.1)) * flow_depth)
		flow += ocean_current

	last_exposure = exposure
	last_ocean_weight = ocean_weight
	last_shore_presence = shore_presence

	if shore_presence > 0.001:
		var seaward := -shore_dir
		seaward = (seaward - radial * seaward.dot(radial)).normalized()
		var shoal_raw := clampf(
			pow(maxf(shore_depth, 0.5) / maxf(shore_length * 0.5, 1.0), -0.25),
			1.0, shore_shoal_max)
		var shoal := lerpf(1.0, shoal_raw, shore_quality)
		var lee_target := lerpf(
			0.35, 1.0, smoothstep(-0.9, 0.6, swell_dir.dot(-seaward)))
		var lee := lerpf(1.0, lee_target, shore_incidence * shore_quality)
		var w := shore_presence * lee * (1.0 - ice)

		var k := _TAU / maxf(shore_length, 0.1)
		var amp_ref := minf(shore_amplitude * shoal, shore_length * 0.08)
		var q := shore_steepness / maxf(k * amp_ref, 1e-4)
		var breakup := _shore_breakup(local, time, shore_length)
		var omega := shore_speed * sqrt(k)
		var phase := k * shore_signed_dist + time * omega + breakup.x
		w *= breakup.y
		# Solo el arrastre horizontal se reduce cuando dos riberas dan direcciones opuestas. La
		# amplitud vertical y la cresta permanecen continuas, evitando tanto picos como cortes.
		shore_axis = seaward
		horiz += seaward * (q * amp_ref * cos(phase) * w * shore_quality)
		vert += amp_ref * sin(phase) * w
		grad += seaward * (k * amp_ref * cos(phase) * w * shore_quality)
		n_up_sub += q * k * amp_ref * sin(phase) * w
		# La rompiente avanza hacia tierra (-seaward) y ahí va su corriente: el empujón que vara los
		# botes en la playa. La órbita sale de la misma derivada que en mar abierto.
		var shore_orbital := seaward * (-q * amp_ref * omega * sin(phase) * shore_quality) \
			+ radial * (amp_ref * omega * cos(phase))
		var shore_current := -seaward * (current_mag * CURRENT_SHORE_FRAC * shore_quality)
		if depth_fade:
			var att := exp(-k * flow_depth)
			shore_orbital *= att
			shore_current *= att
		flow += (shore_orbital + shore_current) * w

	last_flow = flow
	surface_field.lateral += horiz
	surface_field.height += vert
	surface_field.slope += grad
	var jacobian: Basis = surface_field.jacobian
	surface_field.jacobian = Basis(jacobian.x-shore_axis*(shore_axis.x*n_up_sub),
		jacobian.y-shore_axis*(shore_axis.y*n_up_sub),jacobian.z-shore_axis*(shore_axis.z*n_up_sub))
	var u := radial.cross(Vector3.RIGHT if absf(radial.x)<0.9 else Vector3.UP).normalized()
	var v := radial.cross(u)
	var du := Spectrum.tangent(u,radial,maxf(local.length(),1.0),surface_field)
	var dv := Spectrum.tangent(v,radial,maxf(local.length(),1.0),surface_field)
	_last_normal = du.cross(dv).normalized()
	_last_du = du
	_last_dv = dv
	return surface_field.lateral-radial*radial.dot(surface_field.lateral)+radial*surface_field.height
