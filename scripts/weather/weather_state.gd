class_name WeatherState
extends RefCounted

## Estado meteorológico "resuelto": el conjunto de valores que el WeatherController
## empuja cada frame a los subsistemas (atmósfera, sol, agua, vegetación, terreno).
## Cada preset de clima ES un WeatherState; una transición es simplemente un lerp
## entre el estado de salida y el de destino.

# --- Nubes / atmósfera (se escriben en el recurso PlanetAtmosphere) ---
var cloud_coverage: float = 0.4
var cloud_density: float = 0.5
var cloud_absorption: float = 0.15
var cloud_shadow: float = 0.7
var cloud_min_height: float = 400.0
var cloud_max_height: float = 700.0
var cloud_wind_speed: float = 0.05

# --- Iluminación (multiplicadores sobre los valores BASE de la escena) ---
var sun_energy: float = 1.0      # multiplica DirectionalLight3D.light_energy
var ambient_energy: float = 1.0  # multiplica Environment.ambient_light_energy

# --- Viento de vegetación (multiplicador sobre wind_speed por item) ---
var wind_multiplier: float = 1.0

# --- Agua (multiplicadores sobre los valores base del material water_shader) ---
var water_wave_multiplier: float = 1.0
var water_speed_multiplier: float = 1.0
var water_foam_multiplier: float = 1.0

# --- Terreno (uniforms del shader planet_biomes) ---
## wetness está reservado para más adelante: el efecto de suelo mojado se desactivó
## porque rompía el terreno, así que de momento NO se empuja a ningún shader.
var wetness: float = 0.0
var snow_coverage: float = 0.0

# --- Fase 2 (definidos para partículas/rayos; aún no consumidos) ---
var rain_rate: float = 0.0
var snow_rate: float = 0.0
var lightning_frequency: float = 0.0


## Lista de campos numéricos: usada por blend() y apply_overrides() para no repetir.
const FIELDS: Array[StringName] = [
	&"cloud_coverage", &"cloud_density", &"cloud_absorption", &"cloud_shadow",
	&"cloud_min_height", &"cloud_max_height", &"cloud_wind_speed",
	&"sun_energy", &"ambient_energy", &"wind_multiplier",
	&"water_wave_multiplier", &"water_speed_multiplier", &"water_foam_multiplier",
	&"wetness", &"snow_coverage",
	&"rain_rate", &"snow_rate", &"lightning_frequency",
]


## Interpola dos estados (t en [0,1]) y devuelve uno nuevo. La base de las transiciones.
static func blend(a: WeatherState, b: WeatherState, t: float) -> WeatherState:
	var s := WeatherState.new()
	for field in FIELDS:
		s.set(field, lerp(float(a.get(field)), float(b.get(field)), t))
	return s


## Sobrescribe solo los campos presentes en el diccionario (overrides del JSON).
## Las claves del JSON son String, por eso comparamos con String(field).
func apply_overrides(d: Dictionary) -> void:
	for field in FIELDS:
		var key := String(field)
		if d.has(key):
			set(field, float(d[key]))
