class_name ClimateField extends RefCounted

## Campo de frío del planeta en CPU: réplica de shaders/lib/climate.gdshaderinc con el mismo ruido
## (ZN_FastNoiseLite, que es el de los grafos de vegetación). Lo usan la fauna para elegir hábitat,
## el hielo marino (física y pisadas), las pisadas en nieve y el clima.
##
## frío = |latitud| + lapse · max(altura - lapse_base, 0) + ruido, en grados de latitud equivalente.
## Zonas por frío (ver "climate_settings" en el JSON del planeta):
##   templado < taiga < tundra < casquete.

## Grados que baja la cota de nieve con el temporal de nieve a pleno. Igual que CLIMATE_FRESH_SHIFT.
const FRESH_SHIFT := 9.0
## Igual que CLIMATE_MAX_ALTITUDE: fuera de esa banda la posición no es de este planeta.
const MAX_ALTITUDE := 4000.0

enum Zone { TEMPERATE, TAIGA, TUNDRA, ICE }
const ZONE_NAMES := {Zone.TEMPERATE: "templado", Zone.TAIGA: "taiga", Zone.TUNDRA: "tundra", Zone.ICE: "casquete"}

var enabled: bool = false
var radius: float = 0.0
var lapse: float = 0.09
var lapse_base: float = 0.0
var noise_period: float = 1800.0
var noise_amplitude: float = 5.0
var noise_seed: int = 1301
var detail_period: float = 260.0
var detail_amplitude: float = 1.5
var detail_seed: int = 1307
var snow_start: float = 37.0
var snow_full: float = 49.0
var glacier_start: float = 64.0
var glacier_full: float = 72.0
var taiga_start: float = 40.0
var tundra_start: float = 53.0
var ice_start: float = 67.0
var sea_ice_start: float = 56.0
var sea_ice_full: float = 62.0
var sea_ice_shore_bias: float = 9.0
var sea_ice_shore_range: float = 300.0
## Nieve reciente del temporal (0..1); la escribe el WeatherController.
var fresh_snow: float = 0.0

var _noise: ZN_FastNoiseLite
var _detail: ZN_FastNoiseLite


func _init(config: Dictionary = {}, planet_radius: float = 0.0) -> void:
	radius = planet_radius
	enabled = not config.is_empty() and bool(config.get("enabled", true))
	lapse = float(config.get("lapse_deg_per_m", lapse))
	lapse_base = float(config.get("lapse_base_height", lapse_base))
	noise_period = float(config.get("noise_period", noise_period))
	noise_amplitude = float(config.get("noise_amplitude", noise_amplitude))
	noise_seed = int(config.get("noise_seed", noise_seed))
	detail_period = float(config.get("detail_period", detail_period))
	detail_amplitude = float(config.get("detail_amplitude", detail_amplitude))
	detail_seed = int(config.get("detail_seed", detail_seed))
	var zones: Dictionary = config.get("zones", {})
	taiga_start = float(zones.get("taiga", taiga_start))
	tundra_start = float(zones.get("tundra", tundra_start))
	ice_start = float(zones.get("ice", ice_start))
	var snow: Dictionary = config.get("snow", {})
	snow_start = float(snow.get("start", snow_start))
	snow_full = float(snow.get("full", snow_full))
	glacier_start = float(snow.get("glacier_start", glacier_start))
	glacier_full = float(snow.get("glacier_full", glacier_full))
	var sea_ice: Dictionary = config.get("sea_ice", {})
	sea_ice_start = float(sea_ice.get("start", sea_ice_start))
	sea_ice_full = float(sea_ice.get("full", sea_ice_full))
	sea_ice_shore_bias = float(sea_ice.get("shore_bias", sea_ice_shore_bias))
	sea_ice_shore_range = float(sea_ice.get("shore_range", sea_ice_shore_range))
	_noise = make_noise(noise_period, noise_seed)
	_detail = make_noise(detail_period, detail_seed)


## El ruido de una octava tal como lo evalúan el shader (fast_noise_lite_open_simplex2_3d) y el
## grafo: OpenSimplex2 sin fractal.
static func make_noise(period: float, seed: int) -> ZN_FastNoiseLite:
	var noise := ZN_FastNoiseLite.new()
	noise.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2
	noise.fractal_type = ZN_FastNoiseLite.FRACTAL_NONE
	noise.period = period
	noise.seed = seed
	return noise


## Escribe los uniforms globales de climate.gdshaderinc. Solo lo llama el planeta con clima: la
## luna no los toca y así no apaga los de la Tierra.
func push_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"climate_shape",
		Vector4(radius, lapse, lapse_base, 1.0 if enabled else 0.0))
	RenderingServer.global_shader_parameter_set(&"climate_noise",
		Vector4(1.0 / noise_period, noise_amplitude, 1.0 / detail_period, detail_amplitude))
	RenderingServer.global_shader_parameter_set(&"climate_seeds", Vector2(noise_seed, detail_seed))
	RenderingServer.global_shader_parameter_set(&"climate_snow",
		Vector4(snow_start, snow_full, glacier_start, glacier_full))
	RenderingServer.global_shader_parameter_set(&"climate_sea_ice",
		Vector4(sea_ice_start, sea_ice_full, sea_ice_shore_bias, sea_ice_shore_range))
	set_fresh_snow(fresh_snow)


func set_fresh_snow(amount: float) -> void:
	fresh_snow = clampf(amount, 0.0, 1.0)
	if enabled:
		RenderingServer.global_shader_parameter_set(&"climate_fresh_snow", fresh_snow)


func is_active_at(local: Vector3) -> bool:
	return enabled and absf(local.length() - radius) < MAX_ALTITUDE


static func abs_latitude(local: Vector3) -> float:
	return rad_to_deg(asin(clampf(absf(local.y) / maxf(local.length(), 0.001), 0.0, 1.0)))


## Frío en `local` (posición relativa al centro del planeta). -100 donde no hay clima.
func coldness(local: Vector3) -> float:
	if not is_active_at(local):
		return -100.0
	var height := local.length() - radius
	var cold := abs_latitude(local) + lapse * maxf(height - lapse_base, 0.0)
	cold += _noise.get_noise_3d(local.x, local.y, local.z) * noise_amplitude
	cold += _detail.get_noise_3d(local.x, local.y, local.z) * detail_amplitude
	return cold


func snow_cover(cold: float) -> float:
	var shift := fresh_snow * FRESH_SHIFT
	return smoothstep(snow_start - shift, snow_full - shift, cold)


func zone(cold: float) -> Zone:
	if cold >= ice_start:
		return Zone.ICE
	if cold >= tundra_start:
		return Zone.TUNDRA
	if cold >= taiga_start:
		return Zone.TAIGA
	return Zone.TEMPERATE


## Hielo marino en `local`, réplica de climate_sea_ice_at. shore_dist < 0 = sin dato de costa.
func sea_ice(local: Vector3, shore_dist: float = -1.0) -> float:
	if not enabled:
		return 0.0
	return sea_ice_with(local, shore_dist, sea_ice_params())


## Los parámetros del hielo como los recibe el agua (uniform sea_ice_params de gerstner_waves).
func sea_ice_params() -> Vector4:
	return Vector4(sea_ice_start, sea_ice_full, sea_ice_shore_bias, sea_ice_shore_range)


## Hielo marino con los parámetros del material del agua: réplica de sea_ice_fraction
## (gerstner_waves.gdshaderinc) y de climate_sea_ice_at. La usa WaterHeightSampler.
static func sea_ice_with(local: Vector3, shore_dist: float, params: Vector4) -> float:
	var d := local.normalized()
	var lat := rad_to_deg(asin(clampf(absf(d.y), 0.0, 1.0)))
	var lon := atan2(d.z, d.x)
	lat += sin(lon * 7.0) * 1.6 + sin(lon * 17.0 + 1.3) * 0.7
	var coast := 0.0
	if shore_dist >= 0.0:
		coast = (1.0 - smoothstep(params.w * 0.25, params.w, shore_dist)) * params.z
	return smoothstep(params.x, params.y, lat + coast)
