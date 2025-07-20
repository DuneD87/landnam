extends Node3D
class_name QuadTreeManager

signal quadtree_changed(active_quad_data: Array)

@export var root_size: float = 20000.0
@export var auto_update: bool = true

var root_quad: QuadNode
var camera: Camera3D
var last_camera_position: Vector3
var update_threshold: float = 20.0

func _ready():
	_create_root_quad()
	_find_camera()

func _create_root_quad():
	root_quad = QuadNode.new()
	root_quad.setup(
		Vector3.ZERO,           # position
		root_size,              # size
		0,                      # level
		null,                   # parent_node
		Vector3.UP,             # normal
		Vector3.FORWARD,        # up
		Vector3.RIGHT           # right
	)
	add_child(root_quad)

func _find_camera():
	camera = get_viewport().get_camera_3d()

func _process(_delta):
	if not auto_update or not camera:
		return
	
	var camera_pos = camera.global_position
	
	if camera_pos.distance_to(last_camera_position) > update_threshold:
		_update_quadtree(camera_pos)
		last_camera_position = camera_pos

func _emit_quadtree_changed():
	var active_quad_data = []
	_collect_active_quads(root_quad, active_quad_data)
	quadtree_changed.emit(active_quad_data)

func _collect_active_quads(node: QuadNode, data_array: Array):
	if not node:
		return
   
	if not node.is_subdivided:
		var quad_info = {
			"id": node.get_instance_id(),
			"position": node.global_position,
			"size": node.size,
			"level": node.level,
			"face_normal": node.face_normal,
			"face_up": node.face_up,
			"face_right": node.face_right
		}
		data_array.append(quad_info)
	else:
		for child in node.children:
			if child != null:
				_collect_active_quads(child, data_array)

func _update_quadtree(camera_position: Vector3):
	root_quad.update_lod(camera_position)
	_emit_quadtree_changed()
