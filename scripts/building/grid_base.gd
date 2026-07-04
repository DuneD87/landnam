class_name GridBase
extends RefCounted

## Base de una grid de bloques: guarda los bloques colocados, reconstruye mesh y colisión por
## chunks (cubos macizos como cajas fusionadas; rampas/esquinas con nodo propio) y define las
## conversiones mundo↔grid. Las subclases implementan el anclaje al planeta y los nodos padre.

signal block_placed(grid_pos: Vector3i, block_id: int)
signal block_removed(grid_pos: Vector3i)

const CHUNK_SHIFT := 4

var grid_id: String = ""
var cell_size: float = 1.0
var planet_node: Node3D = null

var _blocks: Dictionary = {}
var _chunk_meshes: Dictionary = {}
var _chunk_blocks: Dictionary = {}
var _chunk_colliders: Dictionary = {}
var _total_volume: float = 0.0
var mesh_materials: Dictionary = {}
var _suppress_rebuild: bool = false


## Transform mundo de la grid (subclases deben implementarlo).
func get_grid_world_transform() -> Transform3D:
	push_warning("[GridBase] get_grid_world_transform() no implementado")
	return Transform3D.IDENTITY

## Transform local de la MeshInstance3D (subclases deben implementarlo).
func _get_mesh_local_transform() -> Transform3D:
	push_warning("[GridBase] _get_mesh_local_transform() no implementado")
	return Transform3D.IDENTITY

## Nodo padre de la MeshInstance3D (subclases deben implementarlo).
func _get_mesh_parent() -> Node3D:
	push_warning("[GridBase] _get_mesh_parent() no implementado")
	return null

## Crea y añade a la escena el nodo de colisión de un bloque no-cubo (subclases deben implementarlo).
func _create_block_node(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis,world_transform: Transform3D) -> Node3D:
	push_warning("[GridBase] _create_block_node() no implementado")
	return null

## Nodo de colisión padre de las cajas fusionadas de cubos (subclases deben implementarlo).
func _get_collision_parent() -> Node3D:
	push_warning("[GridBase] _get_collision_parent() no implementado")
	return null

## Hook tras colocar un bloque, para lógica específica de la subclase.
func _on_block_placed_hook(_grid_pos: Vector3i) -> void:
	pass

## Hook tras eliminar un bloque, para limpieza específica de la subclase.
func _on_block_removed_hook(_info: Dictionary) -> void:
	pass


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

## Celda que contiene un punto del mundo (floor; para puntos interiores, no esquinas).
func world_to_cell(world_pos: Vector3) -> Vector3i:
	var grid_space := get_grid_world_transform().affine_inverse() * world_pos
	return Vector3i(
		floori(grid_space.x / cell_size),
		floori(grid_space.y / cell_size),
		floori(grid_space.z / cell_size)
	)


func place_block(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis, world_transform: Transform3D,
	material_id: String = "", mirror_data: Dictionary = {}) -> bool:

	if _blocks.has(grid_pos):
		return false

	var node: Node3D = null
	if not ChunkMeshBuilder._is_solid(block_data.block_id):
		node = _create_block_node(grid_pos, block_data, rotation_basis, world_transform)
		if not node:
			return false

	_blocks[grid_pos] = {
		"block_id": block_data.block_id,
		"rotation_basis": rotation_basis,
		"node": node,
		"material_id": material_id,
		"mirrored": mirror_data.get("mirrored", false),
		"mirror_axis": mirror_data.get("mirror_axis", -1),
	}

	var chunk := _chunk_of(grid_pos)
	if not _chunk_blocks.has(chunk):
		_chunk_blocks[chunk] = {}
	_chunk_blocks[chunk][grid_pos] = true
	_total_volume += _cell_volume() * _block_volume_factor(block_data.block_id)

	if material_id != "" and not mesh_materials.has(material_id):
		if block_data.material_override:
			mesh_materials[material_id] = block_data.material_override

	_on_block_placed_hook(grid_pos)
	_request_rebuild(grid_pos)
	block_placed.emit(grid_pos, block_data.block_id)

	return true


func remove_block(grid_pos: Vector3i) -> Dictionary:
	if not _blocks.has(grid_pos):
		return {}

	var info: Dictionary = _blocks[grid_pos]
	var node: Node3D = info["node"]
	if node and is_instance_valid(node):
		node.queue_free()

	_blocks.erase(grid_pos)
	var chunk := _chunk_of(grid_pos)
	if _chunk_blocks.has(chunk):
		_chunk_blocks[chunk].erase(grid_pos)
	_total_volume = maxf(0.0, _total_volume - _cell_volume() * _block_volume_factor(info["block_id"]))

	_on_block_removed_hook(info)
	_request_rebuild(grid_pos)
	block_removed.emit(grid_pos)
	return info


## Suspende los rebuilds de mesh durante una edición masiva de bloques.
func begin_bulk_edit() -> void:
	_suppress_rebuild = true

## Termina la edición masiva y reconstruye todos los chunks de una vez.
func end_bulk_edit() -> void:
	_suppress_rebuild = false
	rebuild_mesh()


## Chunk (coordenadas de chunk) al que pertenece una celda.
static func _chunk_of(grid_pos: Vector3i) -> Vector3i:
	return Vector3i(grid_pos.x >> CHUNK_SHIFT, grid_pos.y >> CHUNK_SHIFT, grid_pos.z >> CHUNK_SHIFT)


func _cell_volume() -> float:
	return cell_size * cell_size * cell_size

## Fracción de la celda que ocupa el bloque (cubo entero; rampas/esquinas aproximadas a la mitad).
static func _block_volume_factor(block_id: int) -> float:
	return 1.0 if ChunkMeshBuilder._is_solid(block_id) else 0.5

## Volumen total (m³) de los bloques de la grid, para masa y flotación.
func get_total_volume() -> float:
	return _total_volume


## Reconstruye solo los chunks afectados por la edición de una celda (el suyo y los
## vecinos con bloques adyacentes, cuyas caras de frontera pueden cambiar).
func _request_rebuild(grid_pos: Vector3i) -> void:
	if _suppress_rebuild:
		return

	var dirty: Dictionary = {_chunk_of(grid_pos): true}
	for neighbor in get_neighbors_of(grid_pos):
		if _blocks.has(neighbor):
			dirty[_chunk_of(neighbor)] = true

	for chunk: Vector3i in dirty:
		_rebuild_chunk(chunk)


## Rebuild completo: resincroniza el índice de chunks y el volumen desde _blocks y reconstruye todos.
func rebuild_mesh() -> void:
	_chunk_blocks.clear()
	_total_volume = 0.0
	for grid_pos: Vector3i in _blocks:
		var chunk := _chunk_of(grid_pos)
		if not _chunk_blocks.has(chunk):
			_chunk_blocks[chunk] = {}
		_chunk_blocks[chunk][grid_pos] = true
		_total_volume += _cell_volume() * _block_volume_factor(_blocks[grid_pos]["block_id"])

	for chunk: Vector3i in _chunk_meshes.keys():
		if not _chunk_blocks.has(chunk):
			_free_chunk_mesh(chunk)

	for chunk: Vector3i in _chunk_blocks:
		_rebuild_chunk(chunk)


func _rebuild_chunk(chunk: Vector3i) -> void:
	var positions: Dictionary = _chunk_blocks.get(chunk, {})
	if positions.is_empty():
		_chunk_blocks.erase(chunk)
		_free_chunk_mesh(chunk)
		return

	var mesh := ChunkMeshBuilder.build_mesh(_blocks, cell_size, _get_mesh_local_transform(), mesh_materials, positions)
	var instance := _ensure_chunk_mesh_node(chunk)
	instance.mesh = mesh
	instance.material_override = null

	_rebuild_chunk_colliders(chunk, positions)


## Regenera las cajas de colisión fusionadas de los cubos macizos de un chunk.
func _rebuild_chunk_colliders(chunk: Vector3i, positions: Dictionary) -> void:
	_free_chunk_colliders(chunk)

	var cubes: Dictionary = {}
	for grid_pos: Vector3i in positions:
		if ChunkMeshBuilder._is_solid(_blocks[grid_pos]["block_id"]):
			cubes[grid_pos] = true

	if cubes.is_empty():
		return

	var parent := _get_collision_parent()
	if not parent:
		return

	var shapes: Array = []
	for box: Dictionary in GridColliderBuilder.merge_boxes(cubes):
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(box["size"]) * cell_size
		collider.shape = shape
		collider.position = (Vector3(box["pos"]) + Vector3(box["size"]) * 0.5) * cell_size
		collider.set_meta("grid_id", grid_id)
		parent.add_child(collider)
		shapes.append(collider)

	_chunk_colliders[chunk] = shapes


func _free_chunk_colliders(chunk: Vector3i) -> void:
	for collider: CollisionShape3D in _chunk_colliders.get(chunk, []):
		if is_instance_valid(collider):
			collider.queue_free()
	_chunk_colliders.erase(chunk)


func _ensure_chunk_mesh_node(chunk: Vector3i) -> MeshInstance3D:
	var existing: MeshInstance3D = _chunk_meshes.get(chunk, null)
	if existing and is_instance_valid(existing):
		return existing

	var instance := MeshInstance3D.new()
	instance.name = "GridMesh_%s_%d_%d_%d" % [grid_id, chunk.x, chunk.y, chunk.z]
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	instance.transform = _get_mesh_local_transform()

	var parent := _get_mesh_parent()
	if parent:
		parent.add_child(instance)

	_chunk_meshes[chunk] = instance
	return instance


func _free_chunk_mesh(chunk: Vector3i) -> void:
	var instance: MeshInstance3D = _chunk_meshes.get(chunk, null)
	if instance and is_instance_valid(instance):
		instance.queue_free()
	_chunk_meshes.erase(chunk)
	_free_chunk_colliders(chunk)


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

	for chunk: Vector3i in _chunk_meshes.keys():
		_free_chunk_mesh(chunk)
	_chunk_blocks.clear()
	_total_volume = 0.0

func is_same_origin_basis(other: GridBase) -> bool:
	return false


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
