class_name Atmosphere extends Node3D

@export var planet_radius: float
@export var atmosphere_radius: float
@export var atmosphere_density: float
@export var atmosphere_height: float
@export var atmosphere_scattering: Vector3
@export var atmosphere_modulate: Vector3
@export var has_clouds: bool

@export var sun: DirectionalLight3D
var atmosphere_node : Node3D
var delimiters: Array[NodePath] = []

var sun_path: NodePath

func _init(
	_planet_radius: float,
	_atmosphere_radius: float,
	_atmosphere_density: float,
	_atmosphere_height: float,
	_atmosphere_scattering: Vector3,
	_atmosphere_modulate: Vector3,
	_has_clouds: bool,
	_sun: DirectionalLight3D,
	_atmosphere_node : Node3D
) -> void:
	planet_radius = _planet_radius
	atmosphere_radius = _atmosphere_radius
	atmosphere_density = _atmosphere_density
	atmosphere_height = _atmosphere_height
	atmosphere_scattering = _atmosphere_scattering
	atmosphere_modulate = _atmosphere_modulate
	has_clouds = _has_clouds
	sun = _sun
	sun_path = sun.get_path() if sun else NodePath()
	atmosphere_node = _atmosphere_node


func setup_shader_parameters() -> void:
	if !has_clouds:
		atmosphere_node.custom_shader = preload("res://addons/zylann.atmosphere/shaders/planet_atmosphere_no_clouds.gdshader")
	else:
		atmosphere_node.custom_shader = preload("res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds.gdshader")

	atmosphere_node.planet_radius = planet_radius
	atmosphere_node.sun_path = sun.get_path()
	atmosphere_node.set_shader_parameter("u_density", atmosphere_density)
	atmosphere_node.set_shader_parameter("u_scattering_wavelengths", atmosphere_scattering)
	atmosphere_node.set_shader_parameter("u_atmosphere_modulate", atmosphere_modulate)

	atmosphere_node.set_atmosphere_height(atmosphere_height)
