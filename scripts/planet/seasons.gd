class_name Seasons
extends RefCounted

## Estaciones en CPU: la fecha que leen los shaders (uniform global season_state, ver
## shaders/lib/season_calendar.gdshaderinc) y su réplica para quien necesite la estación, el frío o
## la luz de un sitio: clima (ClimateField.snow_coldness), tiempo atmosférico, fauna y consola.
##
## El reloj es el sol (sun_controller.gd): cada vuelta del sol es un día. La fase del año va de 0 a 1
## desde el equinoccio de primavera del norte (0,25 solsticio de verano del norte, 0,5 equinoccio de
## otoño, 0,75 solsticio de invierno). El sol sube y baja con la declinación, inclinación · sin(2π·fase):
## los días se alargan y acortan solos y, más allá de 90° − inclinación, hay día y noche polares.
## El sur va medio año por detrás y la franja del ecuador no tiene estaciones.

const NAMES := ["primavera", "verano", "otoño", "invierno"]
## Claves de las estaciones en los JSON (pesos del tiempo por estación).
const KEYS := ["spring", "summer", "autumn", "winter"]
## Igual que SEASON_TROPIC_START / SEASON_TROPIC_END, SEASON_WINTER_COLD y SEASON_THERMAL_LAG de
## shaders/lib/season_calendar.gdshaderinc.
const TROPIC_START := 3.0
const TROPIC_END := 12.0
const WINTER_COLD := 14.0
const THERMAL_LAG := 0.05

## La última fecha empujada (push_globals). Sin calendario (herramientas) no hay estaciones.
static var year_phase: float = 0.0
static var enabled: bool = false
## Dirección hacia el sol (mundo), la de sun_controller.gd. Sin sol, siempre es de día.
static var sun_direction: Vector3 = Vector3.UP
static var has_sun: bool = false


## Declinación del sol (grados) en una fase del año.
static func declination_deg(phase: float, tilt_deg: float) -> float:
	return tilt_deg * sin(TAU * phase)


static func push_globals(phase: float, tilt_deg: float) -> void:
	year_phase = phase
	enabled = true
	RenderingServer.global_shader_parameter_set(&"season_state",
		Vector4(phase, declination_deg(phase, tilt_deg), tilt_deg, 1.0))


## Latitud (grados, con signo) de una posición relativa al centro del planeta.
static func latitude_deg(local: Vector3) -> float:
	var length := local.length()
	return 0.0 if length < 0.001 else rad_to_deg(asin(clampf(local.y / length, -1.0, 1.0)))


## Fase del año en ese sitio: el sur va medio año por detrás.
static func local_phase(local: Vector3, phase: float) -> float:
	return phase if local.y >= 0.0 else fposmod(phase + 0.5, 1.0)


## 0 en el ecuador (sin estaciones) .. 1 con el ciclo completo.
static func strength(local: Vector3) -> float:
	return smoothstep(TROPIC_START, TROPIC_END, absf(latitude_deg(local)))


## Frío de la estación en ese sitio con la fecha actual: 0 en lo más cálido del verano .. 1 en lo
## más frío del invierno. Réplica de season_chill.
static func chill(local: Vector3) -> float:
	if not enabled:
		return 0.0
	var p := local_phase(local, year_phase)
	return (1.0 - cos(TAU * (p - 0.25 - THERMAL_LAG))) * 0.5 * strength(local)


## Estación de la fecha actual en ese sitio, repartida entre las dos más cercanas: [índice de la
## primera, índice de la segunda, peso de la segunda]. Los centros de las estaciones están a 1/8,
## 3/8, 5/8 y 7/8 del año local.
static func blend(local: Vector3) -> Array:
	var phase := local_phase(local, year_phase) * 4.0 - 0.5
	var first := int(floor(phase))
	return [posmod(first, 4), posmod(first + 1, 4), phase - first]


## Altura del sol (grados) sobre el horizonte de `local` (relativa al centro del planeta).
static func sun_elevation(local: Vector3) -> float:
	if not has_sun or local.length_squared() < 0.000001:
		return 90.0
	return rad_to_deg(asin(clampf(local.normalized().dot(sun_direction), -1.0, 1.0)))


## Luz en `local` repartida en día, crepúsculo y noche (suman 1): día con el sol por encima de unos
## pocos grados, noche por debajo del crepúsculo náutico, y el crepúsculo entre medias.
static func light_weights(local: Vector3) -> Vector3:
	var elevation := sun_elevation(local)
	var day := smoothstep(-2.0, 6.0, elevation)
	var night := 1.0 - smoothstep(-12.0, -5.0, elevation)
	return Vector3(day, maxf(1.0 - day - night, 0.0), night)


## Valor por estación (`values`: primavera, verano, otoño, invierno) en `local` con la fecha actual,
## entre las dos estaciones más cercanas. Sin estaciones (calendario apagado, ecuador) vale 1.
static func seasonal_value(local: Vector3, values: PackedFloat32Array) -> float:
	if not enabled or values.size() < 4:
		return 1.0
	var weight := strength(local)
	if weight <= 0.0:
		return 1.0
	var pair: Array = blend(local)
	return lerpf(1.0, lerpf(values[pair[0]], values[pair[1]], pair[2]), weight)


## Estación astronómica (0 primavera .. 3 invierno) de una fase local.
static func season_index(phase: float) -> int:
	return int(floor(fposmod(phase, 1.0) * 4.0)) % 4


## Horas de luz de un día de 24 h en esa latitud y declinación (0 noche polar, 24 día polar).
static func daylight_hours(latitude: float, declination: float) -> float:
	var c := -tan(deg_to_rad(latitude)) * tan(deg_to_rad(declination))
	if c <= -1.0:
		return 24.0
	if c >= 1.0:
		return 0.0
	return rad_to_deg(acos(c)) / 7.5
