# PlanetFaceNode.gd
extends Node3D
class_name PlanetFaceNode

var lod_level: int = 0
var max_lod: int = 6
var player: Node3D
var resolution: int = 16
var local_up: Vector3
var offset: Vector2 = Vector2.ZERO
var size: float = 1.0
var planet_radius: float = 10000.0

var children: Array[PlanetFaceNode] = []
var mesh_instance: MeshInstance3D

func _ready():
	update_mesh()

func _process(_delta):
	if player == null:
		return

	var center = global_transform.origin
	var distance = player.global_transform.origin.distance_to(center)
	print("distance: ", distance, "\nsplit distance: ", get_split_distance())
	if lod_level < max_lod and distance < get_split_distance():
		if children.is_empty():
			print("subdivide!")
			subdivide()
	elif not children.is_empty() and distance > get_merge_distance():
		print("merge!")
		merge()

func get_split_distance() -> float:
	return planet_radius * (1.0 + lod_level * 0.3)

func get_merge_distance() -> float:
	return get_split_distance() * 1.5

func update_mesh():
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = generate_mesh()
		add_child(mesh_instance)

func generate_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y in range(resolution):
		for x in range(resolution):
			var percent = Vector2(x, y) / float(resolution - 1)
			var point2d = offset + percent * size
			var local = (point2d * 2.0 - Vector2.ONE)
			var point3d = Vector3(local.x, local.y, 1.0)
			point3d = Basis().looking_at(local_up, Vector3.UP) * point3d
			point3d = point3d.normalized() * planet_radius
			st.add_vertex(point3d)

	for y in range(resolution - 1):
		for x in range(resolution - 1):
			var i = y * resolution + x
			st.add_index(i)
			st.add_index(i + resolution)
			st.add_index(i + resolution + 1)

			st.add_index(i)
			st.add_index(i + resolution + 1)
			st.add_index(i + 1)

	return st.commit()

func subdivide():
	if mesh_instance:
		mesh_instance.queue_free()
		mesh_instance = null

	for y in range(2):
		for x in range(2):
			var child = PlanetFaceNode.new()
			child.lod_level = lod_level + 1
			child.max_lod = max_lod
			child.player = player
			child.resolution = resolution
			child.planet_radius = planet_radius
			child.local_up = local_up
			child.offset = offset + Vector2(x, y) * (size / 2.0)
			child.size = size / 2.0
			add_child(child)
			children.append(child)

func merge():
	for child in children:
		child.queue_free()
	children.clear()
	update_mesh()
