extends Node3D
class_name QuadNode

@export var size: float = 20000.0
@export var planet_radius: float = 20000.0
@export var max_level: int = 6
@export var min_level: int = 0
@export var subdivision_factor: float = 2.0

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

func get_sphere_center_position() -> Vector3:
	"""Calcula la posición real del centro del quad proyectado sobre la esfera"""
	# Para el quad raíz
	if parent_quad == null:
		return face_normal * planet_radius
	
	# Para quads hijos, necesitamos calcular su posición en la esfera
	var local_pos = position
	var parent_sphere_pos = parent_quad.get_sphere_center_position()
	
	# Convertir la posición local a una posición en la esfera
	# Primero, obtener la posición en el plano tangente
	var plane_pos = parent_sphere_pos + local_pos
	
	# Proyectar sobre la esfera
	var direction = plane_pos.normalized()
	return direction * planet_radius

func get_projected_position() -> Vector3:
	"""Calcula la posición del centro del quad proyectado en la esfera"""
	# Para el nodo raíz
	if parent_quad == null:
		return face_normal * planet_radius
	
	# Para nodos hijos, necesitamos calcular recursivamente
	var parent_projected = parent_quad.get_projected_position()
	
	# La posición local está en el plano tangente del padre
	# Necesitamos proyectarla sobre la esfera
	var plane_pos = parent_projected + position
	
	# Proyectar sobre la esfera
	return plane_pos.normalized() * planet_radius

func should_subdivide(camera_position: Vector3) -> bool:
	if level >= max_level:
		return false
	
	if level < min_level:
		return true
	
	var projected_pos = get_projected_position()
	var distance_to_camera = projected_pos.distance_to(camera_position)
	
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
	children[0].planet_radius = planet_radius  # Heredar radio del planeta
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
