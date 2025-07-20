extends Node3D
class_name QuadNode

@export var size: float = 100.0
@export var max_level: int = 8
@export var min_level: int = 0
@export var subdivision_factor: float = 4.0

var level: int = 0
var parent_quad: QuadNode = null
var children: Array[QuadNode] = []
var is_subdivided: bool = false

var face_normal: Vector3
var face_up: Vector3
var face_right: Vector3

func init_root_face(normal: Vector3, up: Vector3):
	face_normal = normal.normalized()
	face_up = up.normalized()
	face_right = face_normal.cross(face_up).normalized()
	level = 0

func should_subdivide(camera_position: Vector3) -> bool:
	if level >= max_level:
		return false
	
	if level < min_level:
		return true
	
	var distance_to_camera = global_position.distance_to(camera_position)
	var threshold_distance = size * subdivision_factor
	
	return distance_to_camera < threshold_distance

func subdivide():
	if is_subdivided:
		return
	
	var child_size = size * 0.5
	var offset = size * 0.25
	
	children.resize(4)
	
	# IMPORTANTE: Usar posiciones locales para los hijos
	# Los 4 cuadrantes:
	# [2] [3]
	# [0] [1]
	
	children[0] = QuadNode.new()
	children[0].setup(
		(-face_right - face_up) * offset,
		child_size, 
		level + 1, 
		self, 
		face_normal, 
		face_up, 
		face_right
	)
	
	children[1] = QuadNode.new()
	children[1].setup(
		(face_right - face_up) * offset,
		child_size, 
		level + 1, 
		self, 
		face_normal, 
		face_up, 
		face_right
	)
	
	children[2] = QuadNode.new()
	children[2].setup(
		(-face_right + face_up) * offset,
		child_size, 
		level + 1, 
		self, 
		face_normal, 
		face_up, 
		face_right
	)
	
	children[3] = QuadNode.new()
	children[3].setup(
		(face_right + face_up) * offset,
		child_size, 
		level + 1, 
		self, 
		face_normal, 
		face_up, 
		face_right
	)
	
	for child in children:
		add_child(child)
	
	is_subdivided = true

func setup(pos: Vector3, node_size: float, node_level: int, parent_node: QuadNode, normal: Vector3, up: Vector3, right: Vector3):

	if parent_node == null:
		global_position = pos
	else:
		position = pos
	
	size = node_size
	level = node_level
	parent_quad = parent_node
	face_normal = normal.normalized()
	face_up = up.normalized()
	face_right = right.normalized()
	
func merge():
	if not is_subdivided:
		return
	
	for child in children:
		if child != null:
			child.queue_free()
	
	children.clear()
	is_subdivided = false
	
func update_lod(camera_position: Vector3):
	var should_be_subdivided = should_subdivide(camera_position)
	
	if should_be_subdivided and not is_subdivided:
		subdivide()
	elif not should_be_subdivided and is_subdivided:
		merge()
	
	if is_subdivided:
		for child in children:
			if child != null:
				child.update_lod(camera_position)
