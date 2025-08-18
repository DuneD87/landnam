extends Node3D
class_name OceanSystem
@export_group("Underwater settings")
@export var fog_density: float = 0.5
@export var fog_color: Color = Color(0.7, 0.8, 0.9, 1.0)
@export var absorption: float = 0.3
@export var scattering: float = 0.2
@export var noise_scale: float = 2.0
@export var noise_speed: float = 0.1
@export var scale_modifier: float = 1.0
@export var max_steps: int = 64
@export var step_size: float = 0.1

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
@export var show_stats: bool = true

@onready var underwater: Underwater = $Underwater

var quadtree_manager: QuadTreeManager
var mesh_manager: QuadTreeMeshManager
var stats_label: Label

func _ready() -> void:
	if debug:
		load_watersphere()

func load_watersphere():
	underwater.fog_density = fog_density
	underwater.fog_color = fog_color
	underwater.absorption = absorption
	underwater.scattering = scattering
	underwater.noise_scale = noise_scale
	underwater.noise_speed = noise_speed
	underwater.max_steps = max_steps
	underwater.step_size = step_size
	#underwater.sphere_position = global_position
	radius = radius * 0.9985

	underwater.volume_height = radius
	underwater.sphere_radius = radius
	underwater.setup_underwater()
	_setup_managers()
	_setup_ui()
	if !enable_wireframe:
		mesh_manager.default_material = quadtree_material
	else:
		mesh_manager.default_material = wireframe_material
	
	# Set compute mode
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

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_G:
				# Toggle between GPU and CPU modes
				use_gpu_compute = !use_gpu_compute
				mesh_manager.set_compute_mode(
					QuadTreeMeshManager.ComputeMode.GPU 
					if use_gpu_compute 
					else QuadTreeMeshManager.ComputeMode.CPU
				)
				print("Switched to %s mode" % ("GPU" if use_gpu_compute else "CPU"))
			
