## atmosphere.gd
## Añadir como hijo del nodo raíz del planeta (MeshInstance3D).
## Asignar el shader desde el inspector en "Shader Resource".

@tool
extends MeshInstance3D

@export var planet_radius: float = 30000.0:
	set(value):
		planet_radius = value
		_update_mesh()

@export_range(1.001, 1.3, 0.001) var atmosphere_scale: float = 1.04:
	set(value):
		atmosphere_scale = value
		_update_mesh()

@export_range(16, 128, 1) var sphere_segments: int = 64:
	set(value):
		sphere_segments = value
		_update_mesh()

## Asignar el .gdshader desde el inspector (sin preload hardcoded)
@export var shader_resource: Shader:
	set(value):
		shader_resource = value
		_setup_material()

## DirectionalLight3D que actúa como sol
@export var sun_light: DirectionalLight3D

@export_group("Atmosphere")
@export var atmosphere_color: Color = Color(0.25, 0.52, 1.0):
	set(v): atmosphere_color = v; _set_param("atmosphere_color", Vector3(v.r, v.g, v.b))
@export var sunset_color: Color = Color(1.0, 0.35, 0.05):
	set(v): sunset_color = v; _set_param("sunset_color", Vector3(v.r, v.g, v.b))
@export_range(0.0, 5.0) var intensity: float = 1.5:
	set(v): intensity = v; _set_param("atmosphere_intensity", v)
@export_range(0.5, 10.0) var density: float = 3.0:
	set(v): density = v; _set_param("atmosphere_density", v)
@export_range(0.5, 10.0) var falloff: float = 4.0:
	set(v): falloff = v; _set_param("atmosphere_falloff", v)

@export_group("Mie Scattering")
@export_range(0.0, 2.0) var mie_strength: float = 0.5:
	set(v): mie_strength = v; _set_param("mie_strength", v)
@export_range(0.0, 0.999) var mie_directionality: float = 0.76:
	set(v): mie_directionality = v; _set_param("mie_directionality", v)

@export_group("Depth Fade")
@export var use_depth_fade: bool = true:
	set(v): use_depth_fade = v; _set_param("use_depth_fade", v)
@export_range(0.0, 500.0) var depth_fade_distance: float = 150.0:
	set(v): depth_fade_distance = v; _set_param("depth_fade_distance", v)


var _material: ShaderMaterial


func _ready() -> void:
	_setup_material()
	_update_mesh()
	_sync_all_params()


func _process(_delta: float) -> void:
	if sun_light and is_instance_valid(sun_light) and _material:
		var dir := -sun_light.global_transform.basis.z.normalized()
		_material.set_shader_parameter("sun_direction", dir)


func _setup_material() -> void:
	if not shader_resource:
		return
	_material = ShaderMaterial.new()
	_material.shader = shader_resource
	material_override = _material
	_sync_all_params()


func _update_mesh() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius * atmosphere_scale
	sphere.height = planet_radius * atmosphere_scale * 2.0
	sphere.radial_segments = sphere_segments
	sphere.rings = sphere_segments / 2
	self.mesh = sphere


func _set_param(param_name: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(param_name, value)


func _sync_all_params() -> void:
	if not _material:
		return
	_set_param("atmosphere_color", Vector3(atmosphere_color.r, atmosphere_color.g, atmosphere_color.b))
	_set_param("sunset_color", Vector3(sunset_color.r, sunset_color.g, sunset_color.b))
	_set_param("atmosphere_intensity", intensity)
	_set_param("atmosphere_density", density)
	_set_param("atmosphere_falloff", falloff)
	_set_param("mie_strength", mie_strength)
	_set_param("mie_directionality", mie_directionality)
	_set_param("use_depth_fade", use_depth_fade)
	_set_param("depth_fade_distance", depth_fade_distance)
