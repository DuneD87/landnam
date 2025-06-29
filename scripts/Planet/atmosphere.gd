class_name Atmosphere extends Node3D

@export var planet_radius: float
@export var atmosphere_radius: float
@export var atmosphere_density: float
@export var atmosphere_height: float

@export var sun: DirectionalLight3D
var atmosphere_node : Node3D
var delimiters: Array[NodePath] = []

var sun_path: NodePath

func _init(
	_planet_radius: float,
	_atmosphere_radius: float,
	_atmosphere_density: float,
	_atmosphere_height: float,
	_sun: DirectionalLight3D,
	_atmosphere_node : Node3D
) -> void:
	planet_radius = _planet_radius
	atmosphere_radius = _atmosphere_radius
	atmosphere_density = _atmosphere_density
	atmosphere_height = _atmosphere_height
	sun = _sun
	sun_path = sun.get_path() if sun else NodePath()
	atmosphere_node = _atmosphere_node


func setup_shader_parameters() -> void:
	atmosphere_node.planet_radius = planet_radius
	atmosphere_node.sun_path = sun.get_path()
	atmosphere_node.set_shader_parameter("u_density", atmosphere_density)
	atmosphere_node.set_atmosphere_height(atmosphere_radius)
