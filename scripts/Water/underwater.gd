extends Node3D
class_name Underwater

const MODE_NEAR = 0
const MODE_FAR = 1
const SWITCH_MARGIN_RATIO = 1.5

# Core volume parameters
@export var sphere_radius: float = 10000
@export var volume_height := 10.0

# Fog parameters
@export_group("Fog Settings")
@export var fog_density: float = 0.8
@export var fog_color: Color = Color(0.7, 0.8, 0.9, 1.0)
@export var absorption: float = 0.2
@export var scattering: float = 0.4
@export var noise_scale: float = 2.0
@export var noise_speed: float = 0.1
@export var edge_softness: float = 0.3
@export var emission_strength: float = 2.0

# Raymarch parameters
@export_group("Raymarch Settings")
@export var max_steps: int = 64
@export var step_size: float = 0.1
@export var force_fullscreen := false

# Internal variables
var _far_mesh: BoxMesh
var _near_mesh: QuadMesh
var _mode := MODE_FAR
var _mesh_instance: MeshInstance3D
var _prev_volume_clip_distance: float = 0.0

# Shader parameter exclusions (handled internally)
const _api_shader_params = {
	"u_sphere_radius": true,
	"u_volume_height": true,
	"u_clip_mode": true,
	"u_world_to_model_matrix": true,
}

func setup_underwater() -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/Liquid/underwater.gdshader")
	material.render_priority = 2
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	
	# Setup near mesh (fullscreen quad)
	_near_mesh = QuadMesh.new()
	_near_mesh.orientation = PlaneMesh.FACE_Z
	_near_mesh.size = Vector2(2.0, 2.0)
	_near_mesh.flip_faces = true
	
	# Setup far mesh (inverted sphere)
	_far_mesh = BoxMesh.new()
	_far_mesh.size = Vector3(1.0, 1.0, 1.0)
	_mesh_instance.mesh = _far_mesh
	
	_update_cull_margin()
	
	# Setup defaults
	material.set_shader_parameter(&"u_clip_mode", 0.0)
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
	material.set_shader_parameter(&"u_sphere_radius", sphere_radius)
	material.set_shader_parameter(&"u_volume_height", volume_height)

func _get_material() -> ShaderMaterial:
	return _mesh_instance.material_override as ShaderMaterial

func _update_cull_margin():
	_mesh_instance.extra_cull_margin = max(sphere_radius, volume_height)

func _set_mode(mode: int):
	if mode == _mode:
		return
	_mode = mode
	
	var mat := _get_material()
	
	if _mode == MODE_NEAR:
		if OS.is_stdout_verbose():
			print("Switching underwater to near mode")
		mat.set_shader_parameter("u_clip_mode", 1.0)
		_mesh_instance.mesh = _near_mesh
		_mesh_instance.transform = Transform3D()
		
	else:
		if OS.is_stdout_verbose():
			print("Switching underwater to far mode")
		mat.set_shader_parameter(&"u_clip_mode", 0.0)
		_mesh_instance.mesh = _far_mesh

func _process(_delta):
	var cam_pos := Vector3()
	var cam_near := 0.1
	
	var cam := get_viewport().get_camera_3d()

	if cam != null:
		cam_pos = cam.global_transform.origin
		cam_near = cam.near
		
	elif Engine.is_editor_hint():
		# Getting the camera in editor is freaking awkward so let's hardcode it...
		cam_pos = global_transform.origin \
			+ Vector3(10.0 * (sphere_radius + cam_near), 0, 0)

	# 1.75 is an approximation of sqrt(3), because the far mesh is a cube and we have to take
	# the largest distance from the center into account
	var volume_clip_distance : float = 2.0 * (sphere_radius + cam_near) * SWITCH_MARGIN_RATIO	# Detect when to switch modes.
	# we always switch modes while already being slightly away from the quad, to avoid flickering
	var d := global_transform.origin.distance_to(cam_pos)
	var is_near := d < volume_clip_distance
	if is_near or force_fullscreen:
		_set_mode(MODE_NEAR)
	
	var mat := _get_material()
	
	# Update world to model matrix for view space calculations
	var world_to_model_matrix := global_transform.inverse()
	mat.set_shader_parameter(&"u_world_to_model_matrix", world_to_model_matrix)
	
	# Update other shader parameters
	'mat.set_shader_parameter(&"fog_density", fog_density)
	mat.set_shader_parameter(&"fog_color", fog_color)
	mat.set_shader_parameter(&"absorption", absorption)
	mat.set_shader_parameter(&"scattering", scattering)
	mat.set_shader_parameter(&"noise_scale", noise_scale)
	mat.set_shader_parameter(&"noise_speed", noise_speed)
	mat.set_shader_parameter(&"edge_softness", edge_softness)
	mat.set_shader_parameter(&"emission_strength", emission_strength)
	mat.set_shader_parameter(&"max_steps", max_steps)
	mat.set_shader_parameter(&"step_size", step_size)'

func set_shader_parameter(param_name: StringName, value):
	_get_material().set_shader_parameter(param_name, value)

func get_shader_parameter(param_name: StringName):
	return _get_material().get_shader_parameter(param_name)

# Expose shader parameters as properties
func _get_property_list():
	var props := []
	var mat := _get_material()
	var shader_params := RenderingServer.get_shader_parameter_list(mat.shader.get_rid())
	for p in shader_params:
		if _api_shader_params.has(p.name):
			continue
		var cp := {}
		for k in p:
			cp[k] = p[k]
		cp.name = str("shader_params/", p.name)
		props.append(cp)
	return props
