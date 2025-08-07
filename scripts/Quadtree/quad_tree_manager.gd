extends Node3D
class_name QuadTreeManager

signal quadtree_changed(active_quad_data: Array)

@export var radius: float = 20000.0
@export var auto_update: bool = true

var root_quads: Array[QuadNode] = []
@export var camera: Camera3D
var last_camera_position: Vector3
var update_threshold: float = 20.0

# Definición de las 6 caras del cubo
var cube_faces = [
	{
		"name": "top",
		"normal": -Vector3.UP,
		"up": Vector3.BACK,
		"right": Vector3.RIGHT
	},
	{
		"name": "bottom", 
		"normal": -Vector3.DOWN,
		"up": Vector3.FORWARD,
		"right": Vector3.RIGHT
	},
	{
		"name": "front",
		"normal": -Vector3.FORWARD,
		"up": Vector3.UP,
		"right": Vector3.RIGHT
	},
	{
		"name": "back",
		"normal": -Vector3.BACK,
		"up": Vector3.UP,
		"right": Vector3.LEFT
	},
	{
		"name": "right",
		"normal": -Vector3.RIGHT,
		"up": Vector3.UP,
		"right": Vector3.BACK
	},
	{
		"name": "left",
		"normal": -Vector3.LEFT,
		"up": Vector3.UP,
		"right": Vector3.FORWARD
	}
]

func _ready():
	camera = get_parent().camera
	_create_root_quads()
	_find_camera()

func _create_root_quads():
	for face_data in cube_faces:
		var face_center = face_data.normal * (radius * 0.5)

		var root_quad = QuadNode.new()
		root_quad.setup(
			face_center,          # position
			radius,              # size
			0,                      # level
			null,                   # parent_node
			face_data.normal,       # normal
			face_data.up,           # up
			face_data.right,         # right
			radius
		)

		root_quad.name = "QuadRoot_" + face_data.name
		
		add_child(root_quad)
		root_quads.append(root_quad)

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
	
	# Recolectar quads activos de todas las caras
	for root_quad in root_quads:
		_collect_active_quads(root_quad, active_quad_data)
	
	quadtree_changed.emit(active_quad_data)

func _collect_active_quads(node: QuadNode, data_array: Array):
	if not node:
		return
	
	if not node.is_subdivided:
		var quad_info = {
			"id": node.get_instance_id(),
			"position": node.global_position,
			"parent": node.parent_quad,
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
	# Actualizar LOD para todas las caras
	for root_quad in root_quads:
		root_quad.update_lod(camera_position, global_position)
	
	_emit_quadtree_changed()

# Métodos auxiliares opcionales para debugging o control específico
func get_face_quad(face_name: String) -> QuadNode:
	for i in range(cube_faces.size()):
		if cube_faces[i].name == face_name:
			return root_quads[i]
	return null

func get_all_active_quads_count() -> int:
	var count = 0
	for root_quad in root_quads:
		count += _count_active_quads(root_quad)
	return count

func _count_active_quads(node: QuadNode) -> int:
	if not node:
		return 0
	
	if not node.is_subdivided:
		return 1
	else:
		var count = 0
		for child in node.children:
			count += _count_active_quads(child)
		return count
