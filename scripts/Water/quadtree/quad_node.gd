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
var planet_center: Vector3 = Vector3.ZERO
var render_radius: float = 0.0

func should_subdivide(camera_position: Vector3) -> bool:
	if level >= max_level:
		return false
	if level < min_level:
		return true

	var proj_center = planet_center + (global_position - planet_center).normalized() * planet_radius
	var player_foot = planet_center + (camera_position - planet_center).normalized() * planet_radius
	var surface_dist = maxf(0.0, player_foot.distance_to(proj_center) - size * 0.5)

	if render_radius > 0.0 and surface_dist <= render_radius:
		return true

	var dist = maxf(0.0, proj_center.distance_to(camera_position) - size * 0.5)
	return dist < size * subdivision_factor

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
		children[i].planet_center = planet_center
		children[i].render_radius = render_radius
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
	
func update_lod(camera_position: Vector3, center: Vector3):
	# El centro llega en vivo en cada pasada: el cacheado queda stale tras un rebase del FloatingOrigin.
	planet_center = center
	var should_be_subdivided = should_subdivide(camera_position)
	if should_be_subdivided and not is_subdivided:
		subdivide()
	elif not should_be_subdivided and is_subdivided:
		merge()

	if is_subdivided:
		for child in children:
			if child != null:
				child.update_lod(camera_position, center)
