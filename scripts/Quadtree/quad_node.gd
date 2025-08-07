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

var _cached_projected_position: Vector3
var _projected_position_valid: bool = false

func get_projected_position(planet_center: Vector3) -> Vector3:
	if not _projected_position_valid:
		_calculate_projected_position(planet_center)
		_projected_position_valid = true
	return _cached_projected_position

func _calculate_projected_position(planet_center: Vector3):
	# Calcula posición global CORRECTA del centro del quad
	var quad_center_global = global_transform.origin

	# Dirección desde el centro planetario hasta el quad
	var direction = (quad_center_global - planet_center).normalized()

	# Proyecta sobre la superficie planetaria
	_cached_projected_position = planet_center + direction * planet_radius


func _invalidate_projected_position():
	_projected_position_valid = false
	for child in children:
		if child != null:
			child._invalidate_projected_position()

func _calculate_projected_size(planet_center: Vector3) -> float:
	var half_size = size * 1
	
	var corner1 = face_right * (-half_size) + face_up * (-half_size) + face_normal * (planet_radius / 2)
	var corner2 = face_right * (half_size) + face_up * (-half_size) + face_normal * (planet_radius / 2)
	var corner3 = face_right * (-half_size) + face_up * (half_size) + face_normal * (planet_radius / 2)
	
	var world_corner1 = global_position + corner1
	var world_corner2 = global_position + corner2
	var world_corner3 = global_position + corner3
	
	var proj_corner1 = planet_center + (world_corner1 - planet_center).normalized() * planet_radius
	var proj_corner2 = planet_center + (world_corner2 - planet_center).normalized() * planet_radius
	var proj_corner3 = planet_center + (world_corner3 - planet_center).normalized() * planet_radius
	
	var size_x = proj_corner1.distance_to(proj_corner2)
	var size_y = proj_corner1.distance_to(proj_corner3)
	
	return (size_x + size_y) * 0.5
	
func should_subdivide(camera_position: Vector3, planet_center: Vector3) -> bool:
	if level >= max_level:
		return false
	
	if level < min_level:
		return true
	
	var projected_pos = get_projected_position(planet_center)
	var distance_to_camera = projected_pos.distance_to(camera_position)
	
	var projected_size = _calculate_projected_size(planet_center)
	var threshold_distance = projected_size * subdivision_factor
	
	return distance_to_camera < threshold_distance


func subdivide():
	if is_subdivided:
		return
	
	var child_size = size * 0.5
	var offset = size * 0.25
	
	children.resize(4)
	
	for i in range(4):
		children[i] = QuadNode.new()
		children[i].planet_radius = planet_radius
		
		var child_offset: Vector3
		match i:
			0: child_offset = (-face_right - face_up) * offset
			1: child_offset = (face_right - face_up) * offset
			2: child_offset = (-face_right + face_up) * offset
			3: child_offset = (face_right + face_up) * offset
		
		children[i].setup(
			child_offset,
			child_size,
			level + 1,
			self,
			face_normal,
			face_up,
			face_right,
			planet_radius,
		)
		
		add_child(children[i])
	
	is_subdivided = true

func setup(pos: Vector3, node_size: float, node_level: int, parent_node: QuadNode, normal: Vector3, up: Vector3, right: Vector3, radius: float):

	position = pos
	size = node_size
	level = node_level
	parent_quad = parent_node
	face_normal = normal.normalized()
	face_up = up.normalized()
	face_right = right.normalized()
	planet_radius = radius
	
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
	
func update_lod(camera_position: Vector3, planet_center: Vector3):
	var should_be_subdivided = should_subdivide(camera_position, planet_center)
	
	if should_be_subdivided and not is_subdivided:
		subdivide()
	elif not should_be_subdivided and is_subdivided:
		merge()
	
	if is_subdivided:
		for child in children:
			if child != null:
				child.update_lod(camera_position, planet_center)
