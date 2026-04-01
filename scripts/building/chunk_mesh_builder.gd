class_name ChunkMeshBuilder
extends RefCounted

enum Face { FRONT, BACK, RIGHT, LEFT, TOP, BOTTOM }

const FACE_DIRS: Array[Vector3i] = [
	Vector3i( 0,  0,  1),  # FRONT  (+Z)
	Vector3i( 0,  0, -1),  # BACK   (-Z)
	Vector3i( 1,  0,  0),  # RIGHT  (+X)
	Vector3i(-1,  0,  0),  # LEFT   (-X)
	Vector3i( 0,  1,  0),  # TOP    (+Y)
	Vector3i( 0, -1,  0),  # BOTTOM (-Y)
]
const SOLID_BLOCK_IDS: Array[int] = [0]

static func _emit_from_block_type(st: SurfaceTool, block_id: int, offset: Vector3, rot: Basis, size: float) -> void:
	match block_id:
		1:  _emit_slope(st, offset, rot, size)
		2:  _emit_corner(st, offset, rot, size)
		_:
			push_warning("[ChunkMeshBuilder] Block ID %d no reconocido" % block_id)
			_emit_cube_no_cull(st, offset, rot, size)

static func build_mesh(blocks: Dictionary, cell_size: float, grid_transform: Transform3D, materials: Dictionary = {}) -> ArrayMesh:
	if blocks.is_empty():
		return null

	# Agrupar bloques por material_id
	var groups: Dictionary = {}  # material_id → Array[Vector3i]
	for grid_pos: Vector3i in blocks:
		var mat_id: String = blocks[grid_pos].get("material_id", "")
		if not groups.has(mat_id):
			groups[mat_id] = []
		groups[mat_id].append(grid_pos)

	var mesh := ArrayMesh.new()
	var grid_inv := grid_transform.affine_inverse()

	for mat_id: String in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for grid_pos: Vector3i in groups[mat_id]:
			var info: Dictionary = blocks[grid_pos]
			var block_id: int = info["block_id"]
			var node: Node3D = info["node"]
			if not node or not is_instance_valid(node):
				continue

			var local_t: Transform3D = grid_inv * node.transform
			var offset: Vector3 = local_t.origin
			var rot: Basis = local_t.basis.orthonormalized()

			if _is_solid(block_id):
				_emit_cube(st, grid_pos, offset, rot, cell_size, blocks)
			else:
				_emit_from_block_type(st, block_id, offset, rot, cell_size)

		st.generate_tangents()
		var surface_idx := mesh.get_surface_count()
		st.commit(mesh)  # append surface to existing mesh

		# Asignar material a esta surface
		if materials.has(mat_id) and materials[mat_id] != null:
			mesh.surface_set_material(surface_idx, materials[mat_id])

	return mesh
static func _emit_cube(
	st: SurfaceTool,
	grid_pos: Vector3i,
	offset: Vector3,
	rot: Basis,
	size: float,
	blocks: Dictionary
) -> void:
	var h := size
	
	var v0 := rot * Vector3(0, 0, h) + offset
	var v1 := rot * Vector3(h, 0, h) + offset
	var v2 := rot * Vector3(h, 0, 0) + offset
	var v3 := rot * Vector3(0, 0, 0) + offset
	var v4 := rot * Vector3(0, h, h) + offset
	var v5 := rot * Vector3(h, h, h) + offset
	var v6 := rot * Vector3(h, h, 0) + offset
	var v7 := rot * Vector3(0, h, 0) + offset
	
	if not _is_face_occluded(blocks, grid_pos, Face.FRONT):
		_add_quad(st, v0, v1, v5, v4)
	if not _is_face_occluded(blocks, grid_pos, Face.BACK):
		_add_quad(st, v2, v3, v7, v6)
	if not _is_face_occluded(blocks, grid_pos, Face.RIGHT):
		_add_quad(st, v1, v2, v6, v5)
	if not _is_face_occluded(blocks, grid_pos, Face.LEFT):
		_add_quad(st, v3, v0, v4, v7)
	if not _is_face_occluded(blocks, grid_pos, Face.TOP):
		_add_quad(st, v4, v5, v6, v7)
	if not _is_face_occluded(blocks, grid_pos, Face.BOTTOM):
		_add_quad(st, v3, v2, v1, v0)


static func _emit_slope(st: SurfaceTool, offset: Vector3, rot: Basis, size: float) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)
	
	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v4 := rot * (Vector3(0, h, h) - c) + c + offset
	var v5 := rot * (Vector3(h, h, h) - c) + c + offset
	
	_add_quad(st, v3, v2, v1, v0)
	_add_quad(st, v0, v1, v5, v4)
	_add_quad(st, v4, v5, v2, v3)
	_add_triangle(st, v3, v0, v4)
	_add_triangle(st, v1, v2, v5)


static func _emit_corner(st: SurfaceTool, offset: Vector3, rot: Basis, size: float) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)
	
	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v4 := rot * (Vector3(0, h, h) - c) + c + offset
	
	_add_quad(st, v3, v2, v1, v0)
	_add_triangle(st, v0, v1, v4)
	_add_triangle(st, v3, v0, v4)
	_add_triangle(st, v4, v1, v2)
	_add_triangle(st, v4, v2, v3)


static func _emit_cube_no_cull(st: SurfaceTool, offset: Vector3, rot: Basis, size: float) -> void:
	var h := size
	var v0 := rot * Vector3(0, 0, h) + offset
	var v1 := rot * Vector3(h, 0, h) + offset
	var v2 := rot * Vector3(h, 0, 0) + offset
	var v3 := rot * Vector3(0, 0, 0) + offset
	var v4 := rot * Vector3(0, h, h) + offset
	var v5 := rot * Vector3(h, h, h) + offset
	var v6 := rot * Vector3(h, h, 0) + offset
	var v7 := rot * Vector3(0, h, 0) + offset
	_add_quad(st, v0, v1, v5, v4)
	_add_quad(st, v2, v3, v7, v6)
	_add_quad(st, v1, v2, v6, v5)
	_add_quad(st, v3, v0, v4, v7)
	_add_quad(st, v4, v5, v6, v7)
	_add_quad(st, v3, v2, v1, v0)

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(d - a).normalized()
	
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)


static func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(0.5, 1)); st.add_vertex(c)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	
static func _is_face_occluded(blocks: Dictionary, grid_pos: Vector3i, face: Face) -> bool:
	return false #TODO: Revisar perque no funciona is_face_occluded
	var neighbor_pos := grid_pos + FACE_DIRS[face]
	if not blocks.has(neighbor_pos):
		return false
	var neighbor_id: int = blocks[neighbor_pos]["block_id"]
	var solid := _is_solid(neighbor_id)
	return solid


static func _is_solid(block_id: int) -> bool:
	return block_id in SOLID_BLOCK_IDS
