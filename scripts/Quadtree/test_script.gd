extends Node3D
class_name OceanSystemUpdated
@export var radius: float = 40000;

@export var enable_wireframe: bool = false
@export var use_gpu_compute: bool = true
@export var camera: Camera3D

@export var quadtree_material: Material
@export var wireframe_material: Material
@export var show_stats: bool = true

var quadtree_manager: QuadTreeManager
var mesh_manager: QuadTreeMeshManager
var stats_label: Label

func _ready():
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
	quadtree_manager.radius = radius
	mesh_manager.radius = radius
	print(global_position)
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
			
