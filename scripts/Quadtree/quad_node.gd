extends Node3D
class_name QuadNode

@export var size: float = 20000.0
@export var planet_radius: float = 20000.0
@export var max_level: int = 5
@export var min_level: int = 0
@export var subdivision_factor: float = 1

var level: int = 0
var parent_quad: QuadNode = null
var children: Array[QuadNode] = []
var is_subdivided: bool = false
var face_normal: Vector3
var face_up: Vector3
var face_right: Vector3

# Cache para la posición proyectada
var _cached_projected_position: Vector3
var _projected_position_valid: bool = false

func get_projected_position() -> Vector3:
	if not _projected_position_valid:
		_calculate_projected_position()
		_projected_position_valid = true
	return _cached_projected_position

func _calculate_projected_position():
	var center_offset_local = Vector3.ZERO 
	var plane_position = face_right * center_offset_local.x + face_up * center_offset_local.y + face_normal * (planet_radius / 2)
	
	var world_position = global_position + plane_position
	
	_cached_projected_position = world_position.normalized() * planet_radius

func _invalidate_projected_position():
	_projected_position_valid = false
	for child in children:
		if child != null:
			child._invalidate_projected_position()

func _calculate_projected_size() -> float:
	var half_size = size * 2
	
	var corner1 = face_right * (-half_size) + face_up * (-half_size) + face_normal * (planet_radius / 2)
	var corner2 = face_right * (half_size) + face_up * (-half_size) + face_normal * (planet_radius / 2)
	var corner3 = face_right * (-half_size) + face_up * (half_size) + face_normal * (planet_radius / 2)
	
	var world_corner1 = global_position + corner1
	var world_corner2 = global_position + corner2
	var world_corner3 = global_position + corner3
	
	var proj_corner1 = world_corner1.normalized() * planet_radius
	var proj_corner2 = world_corner2.normalized() * planet_radius
	var proj_corner3 = world_corner3.normalized() * planet_radius
	
	var size_x = proj_corner1.distance_to(proj_corner2)
	var size_y = proj_corner1.distance_to(proj_corner3)
	
	return (size_x + size_y) * 0.5
	
func should_subdivide(camera_position: Vector3) -> bool:
	if level >= max_level:
		return false
	
	if level < min_level:
		return true
	
	var projected_pos = get_projected_position()
	var distance_to_camera = projected_pos.distance_to(camera_position)
	
	var projected_size = _calculate_projected_size()
	var threshold_distance = projected_size * subdivision_factor
	
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
	children[0].planet_radius = planet_radius
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
	children[1].planet_radius = planet_radius
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
	children[2].planet_radius = planet_radius
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
	children[3].planet_radius = planet_radius
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
	
	# Invalidar la posición proyectada cuando se cambia la configuración
	#_invalidate_projected_position()
	
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

# Función auxiliar para debug - obtener información del quad
func get_debug_info() -> Dictionary:
	return {
		"level": level,
		"size": size,
		"projected_size": _calculate_projected_size(),
		"position": global_position,
		"projected_position": get_projected_position(),
		"is_subdivided": is_subdivided
	}
