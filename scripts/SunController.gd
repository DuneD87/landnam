extends Node3D
## Arrastra este script a cualquier nodo vacío.
## Asigna en el inspector la DirectionalLight3D.
## La SkyMaterial se busca sola si hay un WorldEnvironment hijo.

@export var sun_light : DirectionalLight3D
@export var sun_azimuth_deg : float  = 0.0
@export var sun_elevation_deg: float = 25.0
	
@export var auto_rotate        : bool  = true        # activar o desactivar
@export var rotation_speed_deg : float = 10.0        # ° por segundo (positivo = Este→Oeste)

var sky_material : ShaderMaterial      # se resuelve en _ready

func _ready() -> void:
	var env := $WorldEnvironment
	if env:
		sky_material = env.environment.sky.sky_material as ShaderMaterial
	sun_azimuth_deg = 0.0
	sun_elevation_deg = 25.0
	set_process(true)   # _process corre en editor (por @tool)
	_update_sun()

func _process(delta: float) -> void:
	if auto_rotate:
		sun_azimuth_deg = wrapf(sun_azimuth_deg + rotation_speed_deg * delta, -180.0, 180.0)
	_update_sun()       # actualiza cada frame por si animas los ángulos

func _set_azimuth(value: float) -> void:
	sun_azimuth_deg = wrapf(value, -180.0, 180.0)
	_update_sun()

func _set_elevation(value: float) -> void:
	sun_elevation_deg = clamp(value, -10.0, 90.0)
	_update_sun()

func _update_sun() -> void:
	if not sky_material or not sun_light:
		return

	# --- 1. Calcula la dirección con los mismos ángulos que el shader ----
	var az := deg_to_rad(sun_azimuth_deg)
	var el := deg_to_rad(sun_elevation_deg)
	var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()

	# --- 2. Pasa los parámetros al shader -------------------------------
	sky_material.set_shader_parameter("sun_azimuth_deg",   sun_azimuth_deg)
	sky_material.set_shader_parameter("sun_elevation_deg", sun_elevation_deg)

	# --- 3. Alinea la DirectionalLight (mira hacia -dir) ----------------
	sun_light.transform = Transform3D.IDENTITY.looking_at(-dir, Vector3.UP)
	sun_light.position = Vector3(-20000000.0, 0.0, 0.0)
