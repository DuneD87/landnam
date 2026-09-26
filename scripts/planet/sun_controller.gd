extends Node3D
## Controla la posición del sol (azimut/elevación) y la propaga a los planetas y a la SkyMaterial.

@export var sun_light : DirectionalLight3D
@export var sun_azimuth_deg : float  = 150.0
@export var sun_elevation_deg: float = 25.0

@export var auto_rotate        : bool  = true
@export var rotation_speed_deg : float = 0.1
@export var sun_distance : float = 100000.0
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
	sun_elevation_deg = 0.0
	sun_light.position = Vector3(0.0, 0.0, 0.0)

	set_process(true)
	_update_sun()

func _process(delta: float) -> void:
	if auto_rotate:
		sun_azimuth_deg = wrapf(sun_azimuth_deg + rotation_speed_deg * delta, -180.0, 180.0)
	_update_sun()

func _set_azimuth(value: float) -> void:
	sun_azimuth_deg = wrapf(value, -180.0, 180.0)
	_update_sun()

func _set_elevation(value: float) -> void:
	sun_elevation_deg = clamp(value, -10.0, 90.0)
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


func get_save_data() -> Dictionary:
	return {"azimuth_deg": sun_azimuth_deg, "elevation_deg": sun_elevation_deg}


func restore_save_data(data: Dictionary) -> void:
	sun_azimuth_deg = wrapf(float(data.get("azimuth_deg", sun_azimuth_deg)), -180.0, 180.0)
	sun_elevation_deg = clampf(float(data.get("elevation_deg", sun_elevation_deg)), -10.0, 90.0)
	_update_sun()
