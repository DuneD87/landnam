class_name WeatherState
extends RefCounted

## Estado meteorológico resuelto: el conjunto de valores que el WeatherController empuja
## cada frame a los subsistemas (atmósfera, sol, agua, vegetación, terreno). Cada preset de
## clima es un WeatherState y una transición es un lerp entre el estado de salida y el de destino.

var cloud_coverage: float = 0.4
var cloud_density: float = 0.5
var cloud_absorption: float = 0.15
var cloud_shadow: float = 0.7
var cloud_albedo: float = 1.0
var cloud_min_height: float = 400.0
var cloud_max_height: float = 700.0
var cloud_wind_speed: float = 0.05

var fog_density: float = 0.0
var fog_coverage: float = 0.6
# 0 = manto global; 1 = la niebla solo cuaja bajo la celda de nubes del evento.
var fog_group: float = 0.0
var fog_wind_speed: float = 0.04
var fog_floor_height: float = 0.0
var fog_top_height: float = 130.0

var sun_energy: float = 1.0
var ambient_energy: float = 1.0

var atmosphere_scatter: float = 1.0

var wind_multiplier: float = 1.0

var water_wave_multiplier: float = 1.0
var water_speed_multiplier: float = 1.0
var water_foam_multiplier: float = 1.0
var water_steepness: float = 0.5
var water_wave_length_mult: float = 1.0

# Olas de orilla. Van por libre y no por los multiplicadores de mar abierto de arriba porque la
# máscara de temporal las excluye por construcción: solo expone lo que está a más de storm_depth_start
# metros de profundidad, y la rompiente vive justo donde no llega. Son multiplicadores sobre lo
# autorado en el material (1.0 = el mar de siempre), no valores absolutos, para que el .tres siga
# siendo el único sitio donde se decide cómo rompe este planeta.
var water_shore_multiplier: float = 1.0
var water_shore_steepness_mult: float = 1.0
var water_shore_speed_mult: float = 1.0
var water_shore_length_mult: float = 1.0

var wetness: float = 0.0
var snow_coverage: float = 0.0

var rain_rate: float = 0.0
var snow_rate: float = 0.0
var lightning_frequency: float = 0.0


# Campos numéricos recorridos por blend() y apply_overrides().
const FIELDS: Array[StringName] = [
	&"cloud_coverage", &"cloud_density", &"cloud_absorption", &"cloud_shadow", &"cloud_albedo",
	&"cloud_min_height", &"cloud_max_height", &"cloud_wind_speed",
	&"fog_density", &"fog_coverage", &"fog_group", &"fog_wind_speed",
	&"fog_floor_height", &"fog_top_height",
	&"sun_energy", &"ambient_energy", &"atmosphere_scatter", &"wind_multiplier",
	&"water_wave_multiplier", &"water_speed_multiplier", &"water_foam_multiplier", &"water_steepness",
	&"water_wave_length_mult",
	&"water_shore_multiplier", &"water_shore_steepness_mult", &"water_shore_speed_mult",
	&"water_shore_length_mult",
	&"wetness", &"snow_coverage",
	&"rain_rate", &"snow_rate", &"lightning_frequency",
]


## Interpola dos estados (t en [0,1]) y devuelve uno nuevo.
static func blend(a: WeatherState, b: WeatherState, t: float) -> WeatherState:
	var s := WeatherState.new()
	for field in FIELDS:
		s.set(field, lerp(float(a.get(field)), float(b.get(field)), t))
	return s


## Sobrescribe solo los campos presentes en el diccionario de overrides del JSON.
func apply_overrides(d: Dictionary) -> void:
	for field in FIELDS:
		var key := String(field)
		if d.has(key):
			set(field, float(d[key]))
