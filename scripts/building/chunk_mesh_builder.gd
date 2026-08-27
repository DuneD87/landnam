class_name ChunkMeshBuilder
extends RefCounted

## Construye la mesh combinada de una grid de bloques con SurfaceTool, agrupando por material y
## emitiendo la geometría de cada tipo de bloque (cubo, rampa, esquina, esquina invertida).

enum Face { FRONT, BACK, RIGHT, LEFT, TOP, BOTTOM }

const FACE_DIRS: Array[Vector3i] = [
	Vector3i( 0,  0,  1),
	Vector3i( 0,  0, -1),
	Vector3i( 1,  0,  0),
	Vector3i(-1,  0,  0),
	Vector3i( 0,  1,  0),
	Vector3i( 0, -1,  0),
]
const SOLID_BLOCK_IDS: Array[int] = [0]

## Escalones de daño visibles. La malla solo se reconstruye cuando un bloque cambia de escalón, así
## que el tinte tiene que ser función del ESCALÓN y no de la vida continua: si no, el color que se
## ve y el que corresponde se desincronizan entre reconstrucciones.
const DAMAGE_STEPS := 4
## Color al que tiende un bloque a punto de romperse. Va por el canal de color de vértice, que los
## materiales de bloque consumen con vertex_color_use_as_albedo.
const DAMAGE_TINT := Color(0.30, 0.26, 0.24)

## Ids de material que dejan ver lo que hay detrás. Los publica BlockDatabase al arrancar: la
## opacidad de un ShaderMaterial (el cristal) no se puede leer del recurso y el culling depende
## de ella. Un id que no esté aquí se juzga por su BaseMaterial3D, y si tampoco, es opaco.
static var translucent_material_ids: Dictionary = {}


## Escalón de daño de una vida normalizada. Intacto = DAMAGE_STEPS.
static func damage_step(hp: float) -> int:
	return clampi(int(ceil(clampf(hp, 0.0, 1.0) * DAMAGE_STEPS)), 0, DAMAGE_STEPS)


## Tinte de vértice de una vida normalizada, cuantizado al escalón.
static func damage_tint(hp: float) -> Color:
	var step := damage_step(hp)
	if step >= DAMAGE_STEPS:
		return Color.WHITE
	return Color.WHITE.lerp(DAMAGE_TINT, 1.0 - float(step) / float(DAMAGE_STEPS))


## Construye la ArrayMesh de los bloques (todos, o solo las celdas de `subset` si se pasa),
## con una surface por material. La oclusión de caras consulta siempre el diccionario completo, y
## depende del material: un vecino traslúcido no tapa la cara de al lado.
static func build_mesh(blocks: Dictionary, cell_size: float, grid_transform: Transform3D, materials: Dictionary = {}, subset: Dictionary = {}) -> ArrayMesh:
	var source: Dictionary = subset if not subset.is_empty() else blocks
	if source.is_empty():
		return null

	var groups: Dictionary = {}
	for grid_pos: Vector3i in source:
		var mat_id: String = blocks[grid_pos].get("material_id", "")
		if not groups.has(mat_id):
			groups[mat_id] = []
		groups[mat_id].append(grid_pos)

	var mesh := ArrayMesh.new()
	var grid_inv := grid_transform.affine_inverse()
	var opaque := _opaque_materials(materials)

	for mat_id: String in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted := false

		for grid_pos: Vector3i in groups[mat_id]:
			var info: Dictionary = blocks[grid_pos]
			var block_id: int = info["block_id"]

			var offset := Vector3(grid_pos) * cell_size
			var rot: Basis = info.get("rotation_basis", Basis.IDENTITY)

			# SurfaceTool arrastra el último atributo puesto a todos los vértices siguientes, así
			# que basta fijar el tinte una vez por bloque, antes de emitir su geometría.
			st.set_color(damage_tint(info.get("hp", 1.0)))

			if _is_solid(block_id):
				emitted = _emit_cube(st, grid_pos, offset, rot, cell_size, blocks, false, mat_id, opaque) or emitted
			else:
				var actual_rot := rot
				var actual_flip := false
				if info.get("mirrored", false):
					var m_axis: int = info.get("mirror_axis", 0)
					var ms := Vector3.ONE
					ms[m_axis] = -1.0
					actual_rot = rot * Basis.from_scale(ms)
					actual_flip = true
				var hidden := _hidden_local_faces(blocks, grid_pos, actual_rot, mat_id, opaque)
				emitted = _emit_from_block_type(st, block_id, offset, actual_rot, cell_size, actual_flip, hidden) or emitted

		# Un grupo puede quedarse sin una sola cara: bloques enterrados del todo, o una ventana
		# empotrada en un muro macizo. generate_tangents() sobre una superficie vacía es un error.
		if not emitted:
			continue

		st.generate_tangents()
		var surface_idx := mesh.get_surface_count()
		st.commit(mesh)

		if materials.has(mat_id) and materials[mat_id] != null:
			mesh.surface_set_material(surface_idx, materials[mat_id])

	return mesh


## Caras de la celda tapadas por el vecino, en el marco LOCAL del bloque (la rotación se aplica a
## la dirección antes de buscar al vecino). Rampas y esquinas apoyan varias caras sobre caras
## completas de su celda, y esas se quitan igual que las de un cubo.
static func _hidden_local_faces(blocks: Dictionary, grid_pos: Vector3i, rot: Basis, mat_id: String,
		opaque: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for face_dir: Vector3i in FACE_DIRS:
		var world_dir := (rot * Vector3(face_dir)).round()
		out[face_dir] = _neighbor_occludes(blocks, grid_pos + Vector3i(world_dir), mat_id, opaque)
	return out


## Devuelve si el bloque ha llegado a emitir alguna cara.
static func _emit_from_block_type(st: SurfaceTool, block_id: int, offset: Vector3, rot: Basis, size: float, flip: bool, hidden: Dictionary) -> bool:
	match block_id:
		1:  _emit_slope(st, offset, rot, size, flip, hidden)
		2:  _emit_corner(st, offset, rot, size, flip, hidden)
		3:  _emit_inv_corner(st, offset, rot, size, flip, hidden)
		4:  return _emit_pane(st, offset, rot, size, flip, hidden)
		5:  _emit_pane_slope(st, offset, rot, size, flip)
		_:
			push_warning("[ChunkMeshBuilder] Block ID %d no reconocido" % block_id)
			_emit_cube_no_cull(st, offset, rot, size, flip)
	# Rampas y esquinas siempre conservan su cara diagonal, que ningún vecino puede tapar.
	return true

static func _emit_inv_corner(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool, hidden: Dictionary = {}) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)

	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v5 := rot * (Vector3(h, h, h) - c) + c + offset
	var v6 := rot * (Vector3(h, h, 0) - c) + c + offset
	var v7 := rot * (Vector3(0, h, 0) - c) + c + offset

	if not hidden.get(Vector3i(0, -1, 0), false):
		_add_quad(st, v3, v2, v1, v0, flip)
	if not hidden.get(Vector3i(0, 0, -1), false):
		_add_quad(st, v2, v3, v7, v6, flip)
	if not hidden.get(Vector3i(1, 0, 0), false):
		_add_quad(st, v1, v2, v6, v5, flip)

	if not hidden.get(Vector3i(0, 1, 0), false):
		_add_triangle(st, v5, v6, v7, flip)
	if not hidden.get(Vector3i(-1, 0, 0), false):
		_add_triangle(st, v3, v0, v7, flip)
	if not hidden.get(Vector3i(0, 0, 1), false):
		_add_triangle(st, v0, v1, v5, flip)

	_add_triangle(st, v0, v5, v7, flip)  # la cara diagonal, nunca tapada

static func _emit_cube(
	st: SurfaceTool,
	grid_pos: Vector3i,
	offset: Vector3,
	rot: Basis,
	size: float,
	blocks: Dictionary,
	flip: bool,
	mat_id: String,
	opaque: Dictionary
) -> bool:
	var h := size

	var v0 := rot * Vector3(0, 0, h) + offset
	var v1 := rot * Vector3(h, 0, h) + offset
	var v2 := rot * Vector3(h, 0, 0) + offset
	var v3 := rot * Vector3(0, 0, 0) + offset
	var v4 := rot * Vector3(0, h, h) + offset
	var v5 := rot * Vector3(h, h, h) + offset
	var v6 := rot * Vector3(h, h, 0) + offset
	var v7 := rot * Vector3(0, h, 0) + offset

	var emitted := false
	if not _is_face_occluded(blocks, grid_pos, Face.FRONT, mat_id, opaque):
		_add_quad(st, v0, v1, v5, v4, flip)
		emitted = true
	if not _is_face_occluded(blocks, grid_pos, Face.BACK, mat_id, opaque):
		_add_quad(st, v2, v3, v7, v6, flip)
		emitted = true
	if not _is_face_occluded(blocks, grid_pos, Face.RIGHT, mat_id, opaque):
		_add_quad(st, v1, v2, v6, v5, flip)
		emitted = true
	if not _is_face_occluded(blocks, grid_pos, Face.LEFT, mat_id, opaque):
		_add_quad(st, v3, v0, v4, v7, flip)
		emitted = true
	if not _is_face_occluded(blocks, grid_pos, Face.TOP, mat_id, opaque):
		_add_quad(st, v4, v5, v6, v7, flip)
		emitted = true
	if not _is_face_occluded(blocks, grid_pos, Face.BOTTOM, mat_id, opaque):
		_add_quad(st, v3, v2, v1, v0, flip)
		emitted = true
	return emitted


## Lámina pegada a la cara -Z local de la celda. Va al borde y no al centro para que sus aristas
## coincidan con las del panel inclinado, que por ser un plano a 45° solo puede ir de esquina a
## esquina. Las dos caras se emiten con giro opuesto en vez de quitar el culling en el material,
## que la forma la comparten materiales opacos. Cada lado se quita si su vecino lo tapa.
static func _emit_pane(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool, hidden: Dictionary = {}) -> bool:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)
	var z := size * BlockMeshGenerator.PANE_INSET

	var p0 := rot * (Vector3(0, 0, z) - c) + c + offset
	var p1 := rot * (Vector3(h, 0, z) - c) + c + offset
	var p2 := rot * (Vector3(h, h, z) - c) + c + offset
	var p3 := rot * (Vector3(0, h, z) - c) + c + offset

	var emitted := false
	if not hidden.get(Vector3i(0, 0, 1), false):
		_add_quad(st, p0, p1, p2, p3, flip)
		emitted = true
	if not hidden.get(Vector3i(0, 0, -1), false):
		_add_quad(st, p3, p2, p1, p0, flip)
		emitted = true
	return emitted


## Lámina en el plano de la cara inclinada de la rampa, para cerrar techos y proas. Sus dos caras
## no se cullean nunca: la diagonal solo toca la celda por dos aristas y nadie puede taparla.
static func _emit_pane_slope(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)

	var q0 := rot * (Vector3(0, h, h) - c) + c + offset
	var q1 := rot * (Vector3(h, h, h) - c) + c + offset
	var q2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var q3 := rot * (Vector3(0, 0, 0) - c) + c + offset

	_add_quad(st, q0, q1, q2, q3, flip)
	_add_quad(st, q3, q2, q1, q0, flip)


static func _emit_slope(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool, hidden: Dictionary = {}) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)

	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v4 := rot * (Vector3(0, h, h) - c) + c + offset
	var v5 := rot * (Vector3(h, h, h) - c) + c + offset

	if not hidden.get(Vector3i(0, -1, 0), false):
		_add_quad(st, v3, v2, v1, v0, flip)
	if not hidden.get(Vector3i(0, 0, 1), false):
		_add_quad(st, v0, v1, v5, v4, flip)
	_add_quad(st, v4, v5, v2, v3, flip)  # la cara inclinada no la tapa ningún vecino
	if not hidden.get(Vector3i(-1, 0, 0), false):
		_add_triangle(st, v3, v0, v4, flip)
	if not hidden.get(Vector3i(1, 0, 0), false):
		_add_triangle(st, v1, v2, v5, flip)


static func _emit_corner(st: SurfaceTool, offset: Vector3, rot: Basis, size: float, flip: bool, hidden: Dictionary = {}) -> void:
	var h := size
	var c := Vector3(h * 0.5, h * 0.5, h * 0.5)

	var v0 := rot * (Vector3(0, 0, h) - c) + c + offset
	var v1 := rot * (Vector3(h, 0, h) - c) + c + offset
	var v2 := rot * (Vector3(h, 0, 0) - c) + c + offset
	var v3 := rot * (Vector3(0, 0, 0) - c) + c + offset
	var v4 := rot * (Vector3(0, h, h) - c) + c + offset

	if not hidden.get(Vector3i(0, -1, 0), false):
		_add_quad(st, v3, v2, v1, v0, flip)
	if not hidden.get(Vector3i(0, 0, 1), false):
		_add_triangle(st, v0, v1, v4, flip)
	if not hidden.get(Vector3i(-1, 0, 0), false):
		_add_triangle(st, v3, v0, v4, flip)
	# Las dos caras diagonales no caen sobre ninguna cara de la celda.
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


## Materiales que tapan lo que tienen detrás. Un material sin entrada, o que no sea BaseMaterial3D,
## se da por opaco: es como se comportaba la oclusión antes de que hubiera materiales traslúcidos.
static func _opaque_materials(materials: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for mat_id: String in materials:
		var base := materials[mat_id] as BaseMaterial3D
		out[mat_id] = base == null or base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	# Los declarados traslúcidos mandan sobre lo que diga el recurso, y entran aunque la grid no
	# tenga su material cargado: si no, un cristal sin entrada volvería a contar como opaco.
	for mat_id: String in translucent_material_ids:
		out[mat_id] = false
	return out


## Si la cara de un cubo se puede quitar por tenerla tapada el vecino. Un vecino traslúcido solo
## tapa la cara si es de su mismo material: así el cristal contra cristal no apila dos capas de
## alpha en la cara interior común, pero la piedra pegada al cristal conserva su cara y no se ve
## un agujero al mirar a través.
static func _is_face_occluded(blocks: Dictionary, grid_pos: Vector3i, face: Face, mat_id: String, opaque: Dictionary) -> bool:
	return _neighbor_occludes(blocks, grid_pos + FACE_DIRS[face], mat_id, opaque)


static func _neighbor_occludes(blocks: Dictionary, neighbor_pos: Vector3i, mat_id: String,
		opaque: Dictionary) -> bool:
	if not blocks.has(neighbor_pos):
		return false
	var neighbor: Dictionary = blocks[neighbor_pos]
	if not _is_solid(neighbor["block_id"]):
		return false
	var neighbor_mat: String = neighbor.get("material_id", "")
	if opaque.get(neighbor_mat, true):
		return true
	return neighbor_mat == mat_id


static func _is_solid(block_id: int) -> bool:
	return block_id in SOLID_BLOCK_IDS
