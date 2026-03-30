class_name PlanetGrid
extends RefCounted

## Grid individual de construcción anclada a un planeta.
## Tiene su propio sistema de coordenadas (origin + basis) almacenado
## en espacio LOCAL del planeta, por lo que es estable aunque el player se mueva.
##
## RENDERING: Todos los bloques se renderizan en un solo MeshInstance3D
## combinado (via ChunkMeshBuilder). Los StaticBody3D individuales se
## mantienen para colisión y raycast, pero SIN MeshInstance3D propias.
##
## ChunkMeshBuilder lee los transforms reales de los bodies — no recalcula
## posiciones — así la mesh visual coincide exactamente con los colliders.

signal block_placed(grid_pos: Vector3i, block_id: int)
signal block_removed(grid_pos: Vector3i)

# ============================================================
#  PROPIEDADES
# ============================================================

var grid_id: String = ""
var planet_node: Node3D = null
var origin_local: Vector3 = Vector3.ZERO
var basis_local: Basis = Basis.IDENTITY
var cell_size: float = 1.0

## Bloques colocados: Vector3i → { block_id, rotation_step, node }
var _blocks: Dictionary = {}

## MeshInstance3D combinada (hijo del planeta).
var _combined_mesh_instance: MeshInstance3D = null

## Material para la mesh combinada.
var mesh_material: Material = null

## Suprime rebuilds durante operaciones bulk (deserialize).
var _suppress_rebuild: bool = false


# ============================================================
#  SERIALIZACIÓN
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

func serialize() -> Dictionary:
	var blocks_data: Dictionary = {}
	
	for grid_pos in _blocks:
		var info: Dictionary = _blocks[grid_pos]
		var key := "%d,%d,%d" % [grid_pos.x, grid_pos.y, grid_pos.z]
		var node: Node3D = info["node"]
		var t := node.transform if (node and is_instance_valid(node)) else Transform3D.IDENTITY
		blocks_data[key] = {
			"block_id": info["block_id"],
			"rotation_step": info["rotation_step"],
			"transform": _transform_to_array(t),
		}
	
	return {
		"planet_path": str(planet_node.get_path()),
		"origin_local": _vec3_to_array(origin_local),
		"basis_local": _basis_to_array(basis_local),
		"cell_size": cell_size,
		"blocks": blocks_data,
	}


func deserialize(id: String, planet: Node3D, data: Dictionary) -> void:
	grid_id = id
	planet_node = planet
	cell_size = data.get("cell_size", 1.0)
	origin_local = _array_to_vec3(data.get("origin_local", [0, 0, 0]))
	basis_local = _array_to_basis(data.get("basis_local", [1,0,0, 0,1,0, 0,0,1]))
	
	_suppress_rebuild = true
	var blocks_data: Dictionary = data.get("blocks", {})
	for key in blocks_data:
		var parts := (key as String).split(",")
		var grid_pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var block_info: Dictionary = blocks_data[key]
		
		var block_id: int = block_info.get("block_id", 0)
		var rotation_step: int = block_info.get("rotation_step", 0)
		
		var block_data: BlockData = BlockDatabase.get_block(block_id)
		if not block_data:
			push_warning("[PlanetGrid] Block ID %d no encontrado al cargar" % block_id)
			continue
		
		var saved_transform := _array_to_transform(block_info.get("transform", []))
		var world_transform := planet_node.global_transform * saved_transform
		place_block(grid_pos, block_data, rotation_step, world_transform)
	_suppress_rebuild = false
	
	rebuild_mesh()


static func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _array_to_vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

static func _basis_to_array(b: Basis) -> Array:
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]

static func _array_to_basis(a: Array) -> Basis:
	return Basis(
		Vector3(a[0], a[1], a[2]),
		Vector3(a[3], a[4], a[5]),
		Vector3(a[6], a[7], a[8])
	)


# ============================================================
#  CONSTRUCTOR
# ============================================================

func setup(id: String, planet: Node3D, origin_world: Vector3, basis_world: Basis, size: float = 1.0) -> void:
	grid_id = id
	planet_node = planet
	cell_size = size
	
	var planet_inv := planet.global_transform.affine_inverse()
	origin_local = planet_inv * origin_world
	basis_local = planet_inv.basis * basis_world


# ============================================================
#  CONVERSIONES WORLD <-> GRID
# ============================================================

func get_origin_world() -> Vector3:
	return planet_node.global_transform * origin_local

func get_basis_world() -> Basis:
	return planet_node.global_transform.basis * basis_local

func world_to_grid(world_pos: Vector3) -> Vector3i:
	var planet_inv := planet_node.global_transform.affine_inverse()
	var local_pos := planet_inv * world_pos
	var relative := local_pos - origin_local
	var grid_space := basis_local.inverse() * relative
	return Vector3i(
		floori(grid_space.x / cell_size),
		floori(grid_space.y / cell_size),
		floori(grid_space.z / cell_size)
	)

func grid_to_world(grid_pos: Vector3i) -> Vector3:
	var grid_space := Vector3(
		grid_pos.x * cell_size,
		grid_pos.y * cell_size,
		grid_pos.z * cell_size
	)
	var local_pos := origin_local + basis_local * grid_space
	return planet_node.global_transform * local_pos


# ============================================================
#  COLOCACIÓN / ELIMINACIÓN — LÓGICA ORIGINAL PRESERVADA
# ============================================================

## Coloca un bloque. Retorna el nodo creado o null.
## El body usa el world_transform del ghost (exacto). Sin MeshInstance3D.
func place_block(grid_pos: Vector3i, block_data: BlockData, rotation_step: int, world_transform: Transform3D) -> Node3D:
	if _blocks.has(grid_pos):
		return null
	
	# Crear nodo de colisión (SIN visual — la visual va en la mesh combinada)
	var body := StaticBody3D.new()
	body.name = "Block_%s_%s" % [grid_id, grid_pos]
	
	# Convertir world transform a local del planeta
	var local_transform := planet_node.global_transform.affine_inverse() * world_transform
	body.transform = local_transform
	
	# Collider
	var collider := CollisionShape3D.new()
	collider.shape = block_data.collision_shape
	if block_data.collision_shape is BoxShape3D:
		collider.position.y = cell_size * 0.5
	body.add_child(collider)
	
	# Metadata para identificar el bloque
	body.set_meta("grid_id", grid_id)
	body.set_meta("grid_pos", grid_pos)
	body.set_meta("block_id", block_data.block_id)
	body.set_meta("rotation_step", rotation_step)
	
	# Añadir como hijo del planeta
	planet_node.add_child(body)
	
	# Registrar
	_blocks[grid_pos] = {
		"block_id": block_data.block_id,
		"rotation_step": rotation_step,
		"node": body,
	}
	
	# Detectar material del primer bloque
	if mesh_material == null and block_data.material_override:
		mesh_material = block_data.material_override
	
	_request_rebuild()
	block_placed.emit(grid_pos, block_data.block_id)
	return body


## Elimina el bloque en grid_pos.
func remove_block(grid_pos: Vector3i) -> bool:
	if not _blocks.has(grid_pos):
		return false
	
	var info: Dictionary = _blocks[grid_pos]
	var node: Node3D = info["node"]
	if node and is_instance_valid(node):
		node.queue_free()
	
	_blocks.erase(grid_pos)
	_request_rebuild()
	block_removed.emit(grid_pos)
	return true


# ============================================================
#  MESH COMBINADA
# ============================================================

func _request_rebuild() -> void:
	if _suppress_rebuild:
		return
	rebuild_mesh()


## Reconstruye la mesh combinada.
## ChunkMeshBuilder lee los transforms reales de los bodies.
func rebuild_mesh() -> void:
	_ensure_mesh_node()
	
	if _blocks.is_empty():
		_combined_mesh_instance.mesh = null
		return
	
	# El transform de la grid mesh en espacio del planeta
	var grid_transform := Transform3D(basis_local, origin_local)
	
	var mesh := ChunkMeshBuilder.build_mesh(_blocks, cell_size, grid_transform)
	_combined_mesh_instance.mesh = mesh
	
	if mesh_material:
		_combined_mesh_instance.material_override = mesh_material


func _ensure_mesh_node() -> void:
	if _combined_mesh_instance and is_instance_valid(_combined_mesh_instance):
		return
	
	_combined_mesh_instance = MeshInstance3D.new()
	_combined_mesh_instance.name = "GridMesh_%s" % grid_id
	
	# Posicionar en el origin/basis de la grid (espacio local del planeta)
	_combined_mesh_instance.transform = Transform3D(basis_local, origin_local)
	
	_combined_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	planet_node.add_child(_combined_mesh_instance)


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
