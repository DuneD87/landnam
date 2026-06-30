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
## Albedo (reflectividad) de la nube: 1 = blanca, valores bajos = gris de tormenta. Es el knob de
## OSCURIDAD de la nube, distinto de cloud_absorption (opacidad) y de cloud_shadow (sombra al suelo).
var cloud_albedo: float = 1.0
var cloud_min_height: float = 400.0
var cloud_max_height: float = 700.0
var cloud_wind_speed: float = 0.05

# --- Niebla a ras de suelo (capa baja dedicada, independiente de las nubes) ---
## Densidad global de la niebla. 0 = sin niebla. La transición la sube/baja, así que
## la niebla se DESVANECE en su sitio (no baja del cielo) mientras los bancos viajan
## con el viento → "llega de lejos".
var fog_density: float = 0.0
## Cobertura del banco: cuánta área cubre el frente de niebla (0 = parches, 1 = denso).
var fog_coverage: float = 0.6
## Velocidad a la que el banco viaja con el viento. Bajo = niebla que se arrastra lenta.
var fog_wind_speed: float = 0.04
## Suelo de la niebla: altura sobre la superficie donde empieza (m). 0 = a ras de suelo.
var fog_floor_height: float = 0.0
## Techo de la niebla: altura sobre la superficie donde se desvanece (m). Espesor = techo - suelo.
var fog_top_height: float = 130.0

# --- Iluminación (multiplicadores sobre los valores BASE de la escena) ---
var sun_energy: float = 1.0      # multiplica DirectionalLight3D.light_energy
var ambient_energy: float = 1.0  # multiplica Environment.ambient_light_energy

# --- Atmósfera ---
## Multiplicador del in-scatter de Rayleigh (el velo azul de perspectiva aérea sobre el terreno
## lejano y el cielo). 1 = dispersión plena (cielo azul normal); valores bajos lo apagan hacia un
## horizonte plomizo, p.ej. en tormenta. Parámetro propio, independiente de cloud_shadow.
var atmosphere_scatter: float = 1.0

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

# --- Precipitación y rayos (Fase 2) ---
## rain_rate/snow_rate alimentan las partículas (WeatherFX); lightning_frequency es la tasa media
## de descargas por segundo que consume WeatherLightning (parpadeo aditivo sobre la iluminación).
var rain_rate: float = 0.0
var snow_rate: float = 0.0
var lightning_frequency: float = 0.0


## Lista de campos numéricos: usada por blend() y apply_overrides() para no repetir.
const FIELDS: Array[StringName] = [
	&"cloud_coverage", &"cloud_density", &"cloud_absorption", &"cloud_shadow", &"cloud_albedo",
	&"cloud_min_height", &"cloud_max_height", &"cloud_wind_speed",
	&"fog_density", &"fog_coverage", &"fog_wind_speed",
	&"fog_floor_height", &"fog_top_height",
	&"sun_energy", &"ambient_energy", &"atmosphere_scatter", &"wind_multiplier",
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
