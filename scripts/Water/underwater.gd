extends Node3D
class_name Underwater

## Efecto volumétrico bajo el agua: un quad a pantalla completa con shader de niebla, absorción,
## dispersión y godrays; los @export propagan sus valores al material en caliente.

@export var sphere_radius: float = 100000
@export var volume_height := 10.0
@export var sun_direction: Vector3
@export var planet_poisition: Vector3
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

@export_group("Godray Settings")
@export var godray_intensity: float = 1.9:
	set(value):
		godray_intensity = value
		_set_shader_parameter(&"godray_intensity", value)
@export var godray_decay: float = 0.88:
	set(value):
		godray_decay = value
		_set_shader_parameter(&"godray_decay", value)
@export var godray_exposure: float = 0.4:
	set(value):
		godray_exposure = value
		_set_shader_parameter(&"godray_exposure", value)
@export var godray_samples: int = 10:
	set(value):
		godray_samples = value
		_set_shader_parameter(&"godray_samples", value)
@export var godray_max_depth: float = 35.0:
	set(value):
		godray_max_depth = value
		_set_shader_parameter(&"godray_max_depth", value)
@export var godray_fade_start: float = 10.0:
	set(value):
		godray_fade_start = value
		_set_shader_parameter(&"godray_fade_start", value)
@export var godray_density: float = 0.12:
	set(value):
		godray_density = value
		_set_shader_parameter(&"godray_density", value)
@export var godray_surface_scale: float = 0.1:
	set(value):
		godray_surface_scale = value
		_set_shader_parameter(&"godray_surface_scale", value)
@export var godray_surface_speed: float = 0.12:
	set(value):
		godray_surface_speed = value
		_set_shader_parameter(&"godray_surface_speed", value)
@export var godray_surface_contrast: float = 3.0:
	set(value):
		godray_surface_contrast = value
		_set_shader_parameter(&"godray_surface_contrast", value)
@export var godray_light_absorption: float = 0.08:
	set(value):
		godray_light_absorption = value
		_set_shader_parameter(&"godray_light_absorption", value)
@export var godray_view_absorption: float = 0.025:
	set(value):
		godray_view_absorption = value
		_set_shader_parameter(&"godray_view_absorption", value)
@export var godray_forward_scatter_power: float = 3.0:
	set(value):
		godray_forward_scatter_power = value
		_set_shader_parameter(&"godray_forward_scatter_power", value)
@export var godray_min_phase: float = 0.15:
	set(value):
		godray_min_phase = value
		_set_shader_parameter(&"godray_min_phase", value)

@export_group("Raymarch Settings")
@export var max_steps: int = 64
@export var step_size: float = 0.1
@export var material : ShaderMaterial
var _mesh_instance: MeshInstance3D
var _water_surface_radius: float

func _set_shader_parameter(parameter_name: StringName, value: Variant) -> void:
	if material:
		material.set_shader_parameter(parameter_name, value)

func _apply_godray_shader_parameters() -> void:
	_set_shader_parameter(&"godray_intensity", godray_intensity)
	_set_shader_parameter(&"godray_decay", godray_decay)
	_set_shader_parameter(&"godray_exposure", godray_exposure)
	_set_shader_parameter(&"godray_samples", godray_samples)
	_set_shader_parameter(&"godray_max_depth", godray_max_depth)
	_set_shader_parameter(&"godray_fade_start", godray_fade_start)
	_set_shader_parameter(&"godray_density", godray_density)
	_set_shader_parameter(&"godray_surface_scale", godray_surface_scale)
	_set_shader_parameter(&"godray_surface_speed", godray_surface_speed)
	_set_shader_parameter(&"godray_surface_contrast", godray_surface_contrast)
	_set_shader_parameter(&"godray_light_absorption", godray_light_absorption)
	_set_shader_parameter(&"godray_view_absorption", godray_view_absorption)
	_set_shader_parameter(&"godray_forward_scatter_power", godray_forward_scatter_power)
	_set_shader_parameter(&"godray_min_phase", godray_min_phase)

func setup_underwater() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/Liquid/underwater.gdshader")
	material.render_priority = 0
	
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
	_apply_godray_shader_parameters()

func _process(delta: float) -> void:
	material.set_shader_parameter("sun_direction", sun_direction)
	material.set_shader_parameter(&"u_sphere_radius", _water_surface_radius + 0.1)
