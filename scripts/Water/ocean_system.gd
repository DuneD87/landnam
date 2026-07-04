extends Node3D
class_name OceanSystem

## Sistema de océano de un planeta: monta el quadtree de agua (QuadTreeManager + mesh manager) y el
## efecto Underwater, propaga sus ajustes (niebla, godrays, LOD) y muestra estadísticas opcionales.

@export_group("Underwater settings")
@export var fog_density: float = 0.5
@export var fog_color: Color = Color("00526e")
@export var absorption: float = 0.1
@export var scattering: float = 0.001
@export var noise_scale: float = 0.5
@export var noise_speed: float = 1.0
@export var scale_modifier: float = 1.0
@export var max_steps: int = 32
@export var step_size: float = 0.1
@export var sun_dir: Vector3

@export_group("Godray settings")
@export var godray_intensity: float = 1.9:
	set(value):
		godray_intensity = value
		_set_underwater_godray_parameter(&"godray_intensity", value)
@export var godray_decay: float = 0.88:
	set(value):
		godray_decay = value
		_set_underwater_godray_parameter(&"godray_decay", value)
@export var godray_exposure: float = 0.4:
	set(value):
		godray_exposure = value
		_set_underwater_godray_parameter(&"godray_exposure", value)
@export var godray_samples: int = 10:
	set(value):
		godray_samples = value
		_set_underwater_godray_parameter(&"godray_samples", value)
@export var godray_max_depth: float = 35.0:
	set(value):
		godray_max_depth = value
		_set_underwater_godray_parameter(&"godray_max_depth", value)
@export var godray_fade_start: float = 10.0:
	set(value):
		godray_fade_start = value
		_set_underwater_godray_parameter(&"godray_fade_start", value)
@export var godray_density: float = 0.12:
	set(value):
		godray_density = value
		_set_underwater_godray_parameter(&"godray_density", value)
@export var godray_surface_scale: float = 0.1:
	set(value):
		godray_surface_scale = value
		_set_underwater_godray_parameter(&"godray_surface_scale", value)
@export var godray_surface_speed: float = 0.12:
	set(value):
		godray_surface_speed = value
		_set_underwater_godray_parameter(&"godray_surface_speed", value)
@export var godray_surface_contrast: float = 3.0:
	set(value):
		godray_surface_contrast = value
		_set_underwater_godray_parameter(&"godray_surface_contrast", value)
@export var godray_light_absorption: float = 0.08:
	set(value):
		godray_light_absorption = value
		_set_underwater_godray_parameter(&"godray_light_absorption", value)
@export var godray_view_absorption: float = 0.025:
	set(value):
		godray_view_absorption = value
		_set_underwater_godray_parameter(&"godray_view_absorption", value)
@export var godray_forward_scatter_power: float = 3.0:
	set(value):
		godray_forward_scatter_power = value
		_set_underwater_godray_parameter(&"godray_forward_scatter_power", value)
@export var godray_min_phase: float = 0.15:
	set(value):
		godray_min_phase = value
		_set_underwater_godray_parameter(&"godray_min_phase", value)

@export_group("Water settings")
@export var player: CharacterBody3D
@export var radius: float = 40000;
@export var sub_divisions: int = 32
@export var subdivision_factor: float = 2.0
@export var max_lod: int = 5
@export var atmosphere_height: float = 1000.0
@export var enable_wireframe: bool = false
@export var use_gpu_compute: bool = true
@export var camera: Camera3D
@export var debug: bool = false
@export var quadtree_material: Material
@export var wireframe_material: Material
@export var show_stats: bool = false

@export var underwater: Underwater
var quadtree_manager: QuadTreeManager
var mesh_manager: QuadTreeMeshManager
var stats_label: Label
var current_water_time := 0.0
var planet: Planet

func _set_underwater_godray_parameter(parameter_name: StringName, value: Variant) -> void:
	if not underwater:
		return
	underwater.set(parameter_name, value)

func _apply_godray_settings_to_underwater() -> void:
	if not underwater:
		return
	underwater.godray_intensity = godray_intensity
	underwater.godray_decay = godray_decay
	underwater.godray_exposure = godray_exposure
	underwater.godray_samples = godray_samples
	underwater.godray_max_depth = godray_max_depth
	underwater.godray_fade_start = godray_fade_start
	underwater.godray_density = godray_density
	underwater.godray_surface_scale = godray_surface_scale
	underwater.godray_surface_speed = godray_surface_speed
	underwater.godray_surface_contrast = godray_surface_contrast
	underwater.godray_light_absorption = godray_light_absorption
	underwater.godray_view_absorption = godray_view_absorption
	underwater.godray_forward_scatter_power = godray_forward_scatter_power
	underwater.godray_min_phase = godray_min_phase

func _ready() -> void:
	if debug:
		load_watersphere(null)

func load_watersphere(_planet: Planet):
	if !Engine.is_editor_hint():
		planet = _planet
		underwater = Underwater.new()
		add_child(underwater)
		underwater.fog_density = fog_density
		underwater.fog_color = fog_color
		underwater.absorption = absorption
		underwater.scattering = scattering
		underwater.noise_scale = noise_scale
		underwater.noise_speed = noise_speed
		underwater.max_steps = max_steps
		underwater.step_size = step_size
		underwater.volume_height = radius 
		underwater.sphere_radius = radius
		_apply_godray_settings_to_underwater()
		underwater.setup_underwater()
		
	_setup_managers()
	_setup_ui()
	if !enable_wireframe:
		mesh_manager.default_material = quadtree_material
	else:
		mesh_manager.default_material = wireframe_material
	
	mesh_manager.compute_mode = (
		QuadTreeMeshManager.ComputeMode.GPU 
		if use_gpu_compute 
		else QuadTreeMeshManager.ComputeMode.CPU
	)
	
func _setup_managers():
	quadtree_manager = QuadTreeManager.new()
	mesh_manager = QuadTreeMeshManager.new()
	
	mesh_manager.sub_divisions = sub_divisions
	mesh_manager.atmosphere_height = atmosphere_height
	mesh_manager.player = player
	quadtree_manager.radius = radius
	quadtree_manager.max_lod = max_lod
	quadtree_manager.subdivision_factor = subdivision_factor
	quadtree_manager.player = player
	mesh_manager.radius = radius

	add_child(quadtree_manager)
	add_child(mesh_manager)
	
	mesh_manager.initialize(quadtree_manager)

func _setup_ui():
	if show_stats:
		var canvas_layer = CanvasLayer.new()
		add_child(canvas_layer)
		
		stats_label = Label.new()
		stats_label.position = Vector2(10, 10)
		stats_label.add_theme_font_size_override("font_size", 16)
		stats_label.add_theme_color_override("font_color", Color.WHITE)
		stats_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		stats_label.add_theme_constant_override("shadow_offset_x", 2)
		stats_label.add_theme_constant_override("shadow_offset_y", 2)
		canvas_layer.add_child(stats_label)

func _process(_delta):
	if mesh_manager && mesh_manager.default_material:
		var mat = mesh_manager.default_material as ShaderMaterial
		mat.set_shader_parameter("sun_direction", sun_dir)
		
	if underwater:
		underwater.sun_direction = sun_dir
		
	if show_stats and stats_label:
		_update_stats()

func _update_stats():
	var stats = mesh_manager.get_statistics()
	var fps = Engine.get_frames_per_second()
	
	var text = "FPS: %d\n" % fps
	text += "Mode: %s\n" % stats.compute_mode
	text += "Active Quads: %d\n" % stats.active_quads
	text += "Total Vertices: %s\n" % _format_number(stats.total_vertices)
	text += "Total Triangles: %s" % _format_number(stats.total_triangles)
	
	stats_label.text = text

func _format_number(num: int) -> String:
	if num >= 1000000:
		return "%.2fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	else:
		return str(num)
