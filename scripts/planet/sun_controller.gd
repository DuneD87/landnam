extends Node3D
## Controla la posición del sol (azimut/elevación) y la propaga a los planetas y a la SkyMaterial.
## También es el calendario (Seasons): cada vuelta del sol es un día y, con la rotación automática,
## la elevación sigue la declinación del día del año (el sol sube y baja con las estaciones).

@export var sun_light : DirectionalLight3D
@export var sun_azimuth_deg : float  = 150.0
@export var sun_elevation_deg: float = 25.0

@export var auto_rotate        : bool  = true
@export var rotation_speed_deg : float = 0.1
@export var sun_distance : float = 100000.0

@export_group("Seasons")
## Días (vueltas del sol) por estación.
@export var days_per_season : float = 8.0
## Inclinación del eje del planeta: la declinación máxima del sol en los solsticios.
@export_range(0.0, 45.0, 0.01) var axial_tilt_deg : float = 23.44
## Día del año de una partida nueva (0 = equinoccio de primavera del norte): principio del verano
## del norte, donde está el SpawnPoint (17° N).
@export var start_day : float = 8.5

## Día del año, de 0 a 4 · days_per_season. Avanza con la rotación automática del sol.
var day_of_year : float = 0.0
## Multiplicador del avance de la fecha (consola, para ver pasar las estaciones). No se guarda.
var season_speed : float = 1.0

@onready var planets = $Planets
var sky_material : ShaderMaterial

## Guardado: la hora del día es la posición del sol. GameManager la restaura por este id.
var entity_id: String = "sun"
var save_category: String = "planet"

func _ready() -> void:
	add_to_group("sun_controller")
	add_to_group(GameManager.SAVEABLE_GROUP)
	var env := $WorldEnvironment
	'for planet in planets.planets:
		planet.sun = $DirectionalLight3'
	if env:
		sky_material = env.environment.sky.sky_material as ShaderMaterial
	sun_azimuth_deg = 150.0
	day_of_year = start_day
	sun_elevation_deg = declination_deg()
	sun_light.position = Vector3(0.0, 0.0, 0.0)

	set_process(true)
	_update_sun()

func _process(delta: float) -> void:
	if auto_rotate:
		var step := rotation_speed_deg * delta
		sun_azimuth_deg = wrapf(sun_azimuth_deg + step, -180.0, 180.0)
		set_day_of_year(day_of_year + step / 360.0 * season_speed)
	_update_sun()


func year_days() -> float:
	return days_per_season * 4.0


## Fase del año (0..1) desde el equinoccio de primavera del norte.
func year_phase() -> float:
	return day_of_year / year_days()


func declination_deg() -> float:
	return Seasons.declination_deg(year_phase(), axial_tilt_deg)


## Pone la fecha y lleva el sol a la declinación de ese día.
func set_day_of_year(day: float) -> void:
	day_of_year = fposmod(day, year_days())
	sun_elevation_deg = declination_deg()

func _set_azimuth(value: float) -> void:
	sun_azimuth_deg = wrapf(value, -180.0, 180.0)
	_update_sun()

func _set_elevation(value: float) -> void:
	sun_elevation_deg = clamp(value, -90.0, 90.0)
	_update_sun()

func _update_sun() -> void:
	if not sky_material or not sun_light:
		return
		
	if Input.is_action_pressed("move_sun_plus"):
		sun_azimuth_deg += 0.3
	if Input.is_action_pressed("move_sun_minus"):
		sun_azimuth_deg -= 0.3

	var az := deg_to_rad(sun_azimuth_deg)
	var el := deg_to_rad(sun_elevation_deg)

	var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
	for planet in planets.get_children():
		planet.sun_dir = dir
	sun_light.position = dir * sun_distance

	sun_light.look_at(Vector3.ZERO, Vector3.UP)

	sky_material.set_shader_parameter("sun_azimuth_deg",   sun_azimuth_deg)
	sky_material.set_shader_parameter("sun_elevation_deg", sun_elevation_deg)
	Seasons.push_globals(year_phase(), axial_tilt_deg)
	Seasons.sun_direction = dir
	Seasons.has_sun = true


func get_save_data() -> Dictionary:
	return {"azimuth_deg": sun_azimuth_deg, "elevation_deg": sun_elevation_deg, "day_of_year": day_of_year}


## Las partidas de antes del calendario no tienen día: siguen en el de partida nueva.
func restore_save_data(data: Dictionary) -> void:
	sun_azimuth_deg = wrapf(float(data.get("azimuth_deg", sun_azimuth_deg)), -180.0, 180.0)
	day_of_year = fposmod(float(data.get("day_of_year", day_of_year)), year_days())
	sun_elevation_deg = clampf(float(data.get("elevation_deg", sun_elevation_deg)), -90.0, 90.0)
	_update_sun()
