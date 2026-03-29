extends Node3D
class_name Underwater

# Core volume parameters
@export var sphere_radius: float = 10000
@export var volume_height := 10.0
@export var sun_direction: Vector3
@export var planet_poisition: Vector3
# Fog parameters
@export_group("Fog Settings")
@export var fog_density: float = 1.8
@export var fog_color: Color = Color(0.7, 0.8, 0.9, 1.0)
@export var absorption: float = 0.2
@export var scattering: float = 0.4
@export var noise_scale: float = 2.0
@export var noise_speed: float = 0.1
@export var edge_softness: float = 0.3
@export var emission_strength: float = 2.0
@export var sun_dir: Vector3
# Raymarch parameters
@export_group("Raymarch Settings")
@export var max_steps: int = 64
@export var step_size: float = 0.1
@export var material : ShaderMaterial
var _mesh_instance: MeshInstance3D
var _water_surface_radius: float

func setup_underwater() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/Liquid/underwater.gdshader")
	material.render_priority = 3
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	
	var quad_mesh = QuadMesh.new()
	quad_mesh.orientation = PlaneMesh.FACE_Z
	quad_mesh.size = Vector2(2.0, 2.0)
	quad_mesh.flip_faces = true

	_mesh_instance.extra_cull_margin = max(sphere_radius, volume_height)
	_mesh_instance.mesh = quad_mesh
	_mesh_instance.transform = Transform3D()

	material.set_shader_parameter(&"fog_density", fog_density)
	material.set_shader_parameter(&"fog_color", fog_color)
	material.set_shader_parameter(&"absorption", absorption)
	material.set_shader_parameter(&"scattering", scattering)
	material.set_shader_parameter(&"noise_scale", noise_scale)
	material.set_shader_parameter(&"noise_speed", noise_speed)
	material.set_shader_parameter(&"edge_softness", edge_softness)
	material.set_shader_parameter(&"emission_strength", emission_strength)
	material.set_shader_parameter(&"max_steps", max_steps)
	material.set_shader_parameter(&"step_size", step_size)
	material.set_shader_parameter(&"u_sphere_radius", sphere_radius + 0.5)
	material.set_shader_parameter(&"u_volume_height", volume_height)
	material.set_shader_parameter(&"sun_direction", sun_direction)
	material.set_shader_parameter("planet_position", global_position)

func _process(delta: float) -> void:
	material.set_shader_parameter("sun_direction", sun_direction)
	material.set_shader_parameter(&"u_sphere_radius", _water_surface_radius + 0.1)
