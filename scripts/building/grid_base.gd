class_name GridBase
extends RefCounted

## Base abstracta para grids de construcción.
## Subclases: PlanetGrid (estática), DynamicPlanetGrid (futura).

signal block_placed(grid_pos: Vector3i, block_id: int)
signal block_removed(grid_pos: Vector3i)

var grid_id: String = ""
var cell_size: float = 1.0
var planet_node: Node3D = null

## Bloques colocados: Vector3i → { block_id, rotation_basis, node, material_id, mirrored, mirror_axis }
var _blocks: Dictionary = {}

## MeshInstance3D combinada.
var _combined_mesh_instance: MeshInstance3D = null

## Materiales por surface.
var mesh_materials: Dictionary = {}  # material_id → Material

## Suprime rebuilds durante operaciones bulk.
var _suppress_rebuild: bool = false


# ============================================================
#  MÉTODOS "VIRTUALES" — subclases DEBEN sobreescribir
# ============================================================

## Transform mundo de la grid (para coordenadas).
func get_grid_world_transform() -> Transform3D:
	push_warning("[GridBase] get_grid_world_transform() no implementado")
	return Transform3D.IDENTITY

## Transform local para posicionar la MeshInstance3D.
func _get_mesh_local_transform() -> Transform3D:
	push_warning("[GridBase] _get_mesh_local_transform() no implementado")
	return Transform3D.IDENTITY

## Nodo padre donde añadir la MeshInstance3D.
func _get_mesh_parent() -> Node3D:
	push_warning("[GridBase] _get_mesh_parent() no implementado")
	return null

## Crea el nodo de colisión para un bloque y lo añade a la escena.
## Retorna el nodo creado.
func _create_block_node(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis,
						world_transform: Transform3D) -> Node3D:
	push_warning("[GridBase] _create_block_node() no implementado")
	return null

## Llamado tras eliminar un bloque (para limpieza específica de subclase).
func _on_block_removed_hook(_info: Dictionary) -> void:
	pass


# ============================================================
#  CONVERSIONES WORLD <-> GRID
# ============================================================

func get_origin_world() -> Vector3:
	return get_grid_world_transform().origin

func get_basis_world() -> Basis:
	return get_grid_world_transform().basis

func world_to_grid(world_pos: Vector3) -> Vector3i:
	var grid_space := get_grid_world_transform().affine_inverse() * world_pos
	return Vector3i(
		roundi(grid_space.x / cell_size),
		roundi(grid_space.y / cell_size),
		roundi(grid_space.z / cell_size)
	)

func grid_to_world(grid_pos: Vector3i) -> Vector3:
	var grid_space := Vector3(grid_pos.x, grid_pos.y, grid_pos.z) * cell_size
	return get_grid_world_transform() * grid_space


# ============================================================
#  COLOCACIÓN / ELIMINACIÓN
# ============================================================

func place_block(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis,
				 world_transform: Transform3D, material_id: String = "", mirror_data: Dictionary = {}) -> Node3D:
	if _blocks.has(grid_pos):
		return null

	var node := _create_block_node(grid_pos, block_data, rotation_basis, world_transform)
	if not node:
		return null

	_blocks[grid_pos] = {
		"block_id": block_data.block_id,
		"rotation_basis": rotation_basis,
		"node": node,
		"material_id": material_id,
		"mirrored": mirror_data.get("mirrored", false),
		"mirror_axis": mirror_data.get("mirror_axis", -1),
	}

	if material_id != "" and not mesh_materials.has(material_id):
		if block_data.material_override:
			mesh_materials[material_id] = block_data.material_override

	_request_rebuild()
	block_placed.emit(grid_pos, block_data.block_id)
	return node


func remove_block(grid_pos: Vector3i) -> Dictionary:
	if not _blocks.has(grid_pos):
		return {}

	var info: Dictionary = _blocks[grid_pos]
	var node: Node3D = info["node"]
	if node and is_instance_valid(node):
		node.queue_free()

	_blocks.erase(grid_pos)
	_on_block_removed_hook(info)
	_request_rebuild()
	block_removed.emit(grid_pos)
	return info


# ============================================================
#  MESH COMBINADA
# ============================================================

func _request_rebuild() -> void:
	if _suppress_rebuild:
		return
	rebuild_mesh()


func rebuild_mesh() -> void:
	_ensure_mesh_node()

	if _blocks.is_empty():
		_combined_mesh_instance.mesh = null
		return

	var grid_transform := _get_mesh_local_transform()
	var mesh := ChunkMeshBuilder.build_mesh(_blocks, cell_size, grid_transform, mesh_materials)
	_combined_mesh_instance.mesh = mesh
	_combined_mesh_instance.material_override = null


func _ensure_mesh_node() -> void:
	if _combined_mesh_instance and is_instance_valid(_combined_mesh_instance):
		return

	_combined_mesh_instance = MeshInstance3D.new()
	_combined_mesh_instance.name = "GridMesh_%s" % grid_id
	_combined_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_combined_mesh_instance.transform = _get_mesh_local_transform()

	var parent := _get_mesh_parent()
	if parent:
		parent.add_child(_combined_mesh_instance)


# ============================================================
#  CONSULTAS
# ============================================================

func has_block(grid_pos: Vector3i) -> bool:
	return _blocks.has(grid_pos)

func get_block(grid_pos: Vector3i) -> Dictionary:
	return _blocks.get(grid_pos, {})

func get_block_count() -> int:
	return _blocks.size()

func get_all_blocks() -> Dictionary:
	return _blocks

func get_neighbors_of(grid_pos: Vector3i) -> Array[Vector3i]:
	return [
		grid_pos + Vector3i(1, 0, 0),
		grid_pos + Vector3i(-1, 0, 0),
		grid_pos + Vector3i(0, 1, 0),
		grid_pos + Vector3i(0, -1, 0),
		grid_pos + Vector3i(0, 0, 1),
		grid_pos + Vector3i(0, 0, -1),
	]

func get_connected_blocks(start_pos: Vector3i) -> Array[Vector3i]:
	if not _blocks.has(start_pos):
		return []

	var visited: Dictionary = {}
	var queue: Array[Vector3i] = [start_pos]
	var result: Array[Vector3i] = []

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		result.append(current)

		for neighbor in get_neighbors_of(current):
			if _blocks.has(neighbor) and not visited.has(neighbor):
				queue.append(neighbor)

	return result

func distance_to(world_pos: Vector3) -> float:
	return get_origin_world().distance_to(world_pos)


func clear() -> void:
	for grid_pos in _blocks.keys():
		var info: Dictionary = _blocks[grid_pos]
		var node: Node3D = info["node"]
		if node and is_instance_valid(node):
			node.queue_free()
	_blocks.clear()

	if _combined_mesh_instance and is_instance_valid(_combined_mesh_instance):
		_combined_mesh_instance.queue_free()
		_combined_mesh_instance = null

func is_same_origin_basis(other: GridBase) -> bool:
	return false
# ============================================================
#  SERIALIZACIÓN — helpers estáticos
# ============================================================

static func _transform_to_array(t: Transform3D) -> Array:
	var b := t.basis
	var o := t.origin
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]

static func _array_to_transform(a: Array) -> Transform3D:
	if a.size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11])
	)

static func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _array_to_vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

static func _vec3i_to_array(v: Vector3i) -> Array:
	return [v.x, v.y, v.z]

static func _array_to_vec3i(a: Array) -> Vector3i:
	if a.size() < 3:
		return Vector3i.ZERO
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))

static func _basis_to_array(b: Basis) -> Array:
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]

static func _array_to_basis(a: Array) -> Basis:
	return Basis(
		Vector3(a[0], a[1], a[2]),
		Vector3(a[3], a[4], a[5]),
		Vector3(a[6], a[7], a[8])
	)
