extends Node3D

class_name WaterSphere

## Esfera de agua simple (mesh con shader de agua) usada como alternativa básica al quadtree.

@export var planet_radius: float = 10000
@export var player: Node3D
func _ready():
	var water_sphere = create_water_sphere(9950)
	add_child(water_sphere)

func create_water_sphere(radius):
	var sphere = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2
	sphere_mesh.radial_segments = 128
	sphere_mesh.rings = 64
	
	var water_material = ShaderMaterial.new()
	water_material.shader = preload("res://shaders/Liquid/water.gdshader")
	
	water_material.set_shader_parameter("wave_height", 2.0)
	water_material.set_shader_parameter("wave_speed", 0.5)
	water_material.set_shader_parameter("water_color", Color(0.1, 0.3, 0.5, 0.8))
	
	sphere.mesh = sphere_mesh
	sphere.material_override = water_material
	
	return sphere
