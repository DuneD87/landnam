extends Node3D
class_name QuadNode

@export var size: float = 20000.0
@export var planet_radius: float = 20000.0
@export var max_level: int = 5
@export var min_level: int = 0
@export var subdivision_factor: float = 2

var level: int = 0
var parent_quad: QuadNode = null
var children: Array[QuadNode] = []
var is_subdivided: bool = false
var face_normal: Vector3
var face_up: Vector3
var face_right: Vector3

func get_projected_position(planet_center: Vector3) -> Vector3:
	var quad_center_global = global_transform.origin
	var direction = (quad_center_global - planet_center).normalized()
	
	return planet_center + direction * planet_radius

func _calculate_projected_size(planet_center: Vector3) -> Dictionary:
	var half_size = size * 0.5
	
	var corner_offsets = [
		face_right * (-half_size) + face_up * (-half_size),
		face_right * (half_size) + face_up * (-half_size),
		face_right * (-half_size) + face_up * (half_size),
		face_right * (half_size) + face_up * (half_size)
	]
	
	var edge_midpoints = [
		face_up * (-half_size),              # mig inferior
		face_up * (half_size),               # mig superior
		face_right * (-half_size),           # mig esquerre
		face_right * (half_size),            # mig dret
	]
	
	var all_offsets = corner_offsets + edge_midpoints
	
	var shifted = all_offsets.map(func(offset): return offset + face_normal * (planet_radius / 2))
	var world_points = shifted.map(func(s): return global_position + s)
	var proj_points = world_points.map(func(w): return planet_center + (w - planet_center).normalized() * planet_radius)
	
	var side1 = proj_points[0].distance_to(proj_points[1])
	var side2 = proj_points[0].distance_to(proj_points[2])
	var side3 = proj_points[1].distance_to(proj_points[3])
	var side4 = proj_points[2].distance_to(proj_points[3])
	var avg_size = (side1 + side2 + side3 + side4) / 4.0
	
	var proj_center = get_projected_position(planet_center)
	var projected_points = proj_points + [proj_center]
	
	return {'size': avg_size, 'projected_points': projected_points}

func should_subdivide(camera_position: Vector3, planet_center: Vector3) -> bool:
	if level >= max_level:
		return false
	
	if level < min_level:
		return true
	
	var proj_data = _calculate_projected_size(planet_center)
	var projected_size = proj_data['size']
	var projected_points = proj_data['projected_points']

	var distances = projected_points.map(func(p): return p.distance_to(camera_position))
	var min_distance_to_camera = distances.min()
	
	var threshold_distance = projected_size * subdivision_factor
	
	return min_distance_to_camera < threshold_distance

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
		children[i].max_level = max_level
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
