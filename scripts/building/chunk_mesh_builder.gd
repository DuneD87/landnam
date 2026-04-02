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


static func build_mesh(blocks: Dictionary, cell_size: float, grid_transform: Transform3D, materials: Dictionary = {}) -> ArrayMesh:
	if blocks.is_empty():
		return null

	var groups: Dictionary = {}
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
			if block_id == 2:
				print("[CMB] corner @ %s | mirrored=%s | axis=%s | rot_basis=%s" % [
					grid_pos,
					info.get("mirrored", false),
					info.get("mirror_axis", -1),
					info.get("rotation_basis", Basis.IDENTITY)
				])
			# No depender del nodo en absoluto
			var offset := Vector3(grid_pos) * cell_size
			var rot: Basis = info.get("rotation_basis", Basis.IDENTITY)

			if _is_solid(block_id):
				_emit_cube(st, grid_pos, offset, rot, cell_size, blocks, false)
			else:
				var actual_rot := rot
				var actual_flip := false
				if info.get("mirrored", false):
					var m_axis: int = info.get("mirror_axis", 0)
					var ms := Vector3.ONE
					ms[m_axis] = -1.0
					actual_rot = rot * Basis.from_scale(ms)
					actual_flip = true
				_emit_from_block_type(st, block_id, offset, actual_rot, cell_size, actual_flip)

		st.generate_tangents()
		var surface_idx := mesh.get_surface_count()
		st.commit(mesh)

		if materials.has(mat_id) and materials[mat_id] != null:
			mesh.surface_set_material(surface_idx, materials[mat_id])

	return mesh


static func _emit_from_block_type(st: SurfaceTool, block_id: int, offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	match block_id:
		1:  _emit_slope(st, offset, rot, size, flip)
		2:  _emit_corner(st, offset, rot, size, flip)
		3:  _emit_inv_corner(st, offset, rot, size, flip) # <--- AÑADIDO
		_:
			push_warning("[ChunkMeshBuilder] Block ID %d no reconocido" % block_id)
			_emit_cube_no_cull(st, offset, rot, size, flip)

static func _emit_inv_corner(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)

	# Todos los vértices del cubo EXCEPTO v4
	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v5 := rot * (Vector3(h, h, h) - c) + c + offset
	var v6 := rot * (Vector3(h, h, 0) - c) + c + offset
	var v7 := rot * (Vector3(0, h, 0) - c) + c + offset

	# Caras completas
	_add_quad(st, v3, v2, v1, v0, flip) # Bottom
	_add_quad(st, v2, v3, v7, v6, flip) # Back
	_add_quad(st, v1, v2, v6, v5, flip) # Right
	
	# Caras triangulares
	_add_triangle(st, v5, v6, v7, flip) # Top
	_add_triangle(st, v3, v0, v7, flip) # Left
	_add_triangle(st, v0, v1, v5, flip) # Front
	
	# Pendiente cóncava
	_add_triangle(st, v0, v5, v7, flip) # Inner slope
	
static func _emit_cube(
	st: SurfaceTool,
	grid_pos: Vector3i,
	offset: Vector3,
	rot: Basis,
	size: float,
	blocks: Dictionary,
	flip: bool
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
		_add_quad(st, v0, v1, v5, v4, flip)
	if not _is_face_occluded(blocks, grid_pos, Face.BACK):
		_add_quad(st, v2, v3, v7, v6, flip)
	if not _is_face_occluded(blocks, grid_pos, Face.RIGHT):
		_add_quad(st, v1, v2, v6, v5, flip)
	if not _is_face_occluded(blocks, grid_pos, Face.LEFT):
		_add_quad(st, v3, v0, v4, v7, flip)
	if not _is_face_occluded(blocks, grid_pos, Face.TOP):
		_add_quad(st, v4, v5, v6, v7, flip)
	if not _is_face_occluded(blocks, grid_pos, Face.BOTTOM):
		_add_quad(st, v3, v2, v1, v0, flip)


static func _emit_slope(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)

	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v4 := rot * (Vector3(0, h, h) - c) + c + offset
	var v5 := rot * (Vector3(h, h, h) - c) + c + offset

	_add_quad(st, v3, v2, v1, v0, flip)
	_add_quad(st, v0, v1, v5, v4, flip)
	_add_quad(st, v4, v5, v2, v3, flip)
	_add_triangle(st, v3, v0, v4, flip)
	_add_triangle(st, v1, v2, v5, flip)


static func _emit_corner(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)

	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v4 := rot * (Vector3(0, h, h) - c) + c + offset

	_add_quad(st, v3, v2, v1, v0, flip)
	_add_triangle(st, v0, v1, v4, flip)
	_add_triangle(st, v3, v0, v4, flip)
	_add_triangle(st, v4, v1, v2, flip)
	_add_triangle(st, v4, v2, v3, flip)


static func _emit_cube_no_cull(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	var h := size
	var v0 := rot * Vector3(0, 0, h) + offset
	var v1 := rot * Vector3(h, 0, h) + offset
	var v2 := rot * Vector3(h, 0, 0) + offset
	var v3 := rot * Vector3(0, 0, 0) + offset
	var v4 := rot * Vector3(0, h, h) + offset
	var v5 := rot * Vector3(h, h, h) + offset
	var v6 := rot * Vector3(h, h, 0) + offset
	var v7 := rot * Vector3(0, h, 0) + offset
	_add_quad(st, v0, v1, v5, v4, flip)
	_add_quad(st, v2, v3, v7, v6, flip)
	_add_quad(st, v1, v2, v6, v5, flip)
	_add_quad(st, v3, v0, v4, v7, flip)
	_add_quad(st, v4, v5, v6, v7, flip)
	_add_quad(st, v3, v2, v1, v0, flip)


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: bool = false) -> void:
	if flip:
		var normal := (d - a).cross(b - a).normalized()
		st.set_normal(normal)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)

		st.set_normal(normal)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)
		st.set_uv(Vector2(0, 1)); st.add_vertex(d)
	else:
		var normal := (b - a).cross(d - a).normalized()
		st.set_normal(normal)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)

		st.set_normal(normal)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(0, 1)); st.add_vertex(d)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)


static func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, flip: bool = false) -> void:
	if flip:
		var normal := (c - a).cross(b - a).normalized()
		st.set_normal(normal)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)
		st.set_uv(Vector2(0.5, 1)); st.add_vertex(c)
	else:
		var normal := (b - a).cross(c - a).normalized()
		st.set_normal(normal)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(0.5, 1)); st.add_vertex(c)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)


static func _is_face_occluded(blocks: Dictionary, grid_pos: Vector3i, face: Face) -> bool:
	return false
	var neighbor_pos := grid_pos + FACE_DIRS[face]
	if not blocks.has(neighbor_pos):
		return false
	var neighbor_id: int = blocks[neighbor_pos]["block_id"]
	return _is_solid(neighbor_id)


static func _is_solid(block_id: int) -> bool:
	return block_id in SOLID_BLOCK_IDS
