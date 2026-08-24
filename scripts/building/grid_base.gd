class_name GridBase
extends RefCounted

## Base de una grid de bloques: guarda los bloques colocados, reconstruye mesh y colisión por
## chunks (cubos macizos como cajas fusionadas; rampas/esquinas con nodo propio) y define las
## conversiones mundo↔grid. Las subclases implementan el anclaje al planeta y los nodos padre.

signal block_placed(grid_pos: Vector3i, block_id: int)
signal block_removed(grid_pos: Vector3i)

const config_ref = preload("res://scripts/config.gd")

const CHUNK_SHIFT := 4

## Energía (J) que absorbe un bloque de 1 m³ antes de romperse, si su BlockData no la define.
const DEFAULT_IMPACT_TOUGHNESS := 60.0
## Tope de alcance de un impacto, en celdas de radio: sin él una caída fuerte borraría la nave entera.
const IMPACT_MAX_RADIUS_CELLS := 50
## Tope de bloques destruidos por impacto. El radio acota la forma, esto acota el COSTE: a
## velocidad de embestida la energía da para borrar el casco entero, y reconstruir todos sus
## chunks en un frame es un parón de cientos de ms por mucho que se optimice cada fase.
const IMPACT_MAX_BLOCKS := 250

var grid_id: String = ""
var cell_size: float = 1.0
var planet_node: Node3D = null

var _blocks: Dictionary = {}
var _props: Dictionary = {}
var _chunk_meshes: Dictionary = {}
var _chunk_blocks: Dictionary = {}
var _chunk_colliders: Dictionary = {}
var _total_volume: float = 0.0
var mesh_materials: Dictionary = {}
var _suppress_rebuild: bool = false
var _batch_depth: int = 0
var _dirty_chunks: Dictionary = {}

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

## Ancla física de un prop, con collider y metas grid_id/prop_key; anchor_local está en espacio
## de grid centrado en el collider (subclases deben implementarlo).
func _create_prop_anchor(_key: String, _anchor_local: Transform3D, _collider_size: Vector3) -> Node3D:
	push_warning("[GridBase] _create_prop_anchor() no implementado")
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

	var detached: Array = []
	for key: String in _props.keys():
		if _props[key]["cell"] == grid_pos:
			var prop_info := remove_prop(key)
			detached.append(prop_info["item_id"])
	info["detached_props"] = detached

	_blocks.erase(grid_pos)
	var chunk := _chunk_of(grid_pos)
	if _chunk_blocks.has(chunk):
		_chunk_blocks[chunk].erase(grid_pos)
	_total_volume = maxf(0.0, _total_volume - _cell_volume() * _block_volume_factor(info["block_id"]))

	_on_block_removed_hook(info)
	_request_rebuild(grid_pos)
	block_removed.emit(grid_pos)
	return info


## Saca un bloque de la grid SIN destruir su nodo de colisión ni desanclar sus props, para
## moverlo a otra grid (separación en piezas). El nodo, si lo hay, queda vivo y a cargo del
## llamante, que debe re-emparentarlo. Devuelve la info del bloque, lista para attach_block.
func detach_block(grid_pos: Vector3i) -> Dictionary:
	if not _blocks.has(grid_pos):
		return {}

	var info: Dictionary = _blocks[grid_pos]
	_blocks.erase(grid_pos)
	var chunk := _chunk_of(grid_pos)
	if _chunk_blocks.has(chunk):
		_chunk_blocks[chunk].erase(grid_pos)
	_total_volume = maxf(0.0, _total_volume - _cell_volume() * _block_volume_factor(info["block_id"]))

	_on_block_removed_hook(info)
	_request_rebuild(grid_pos)
	block_removed.emit(grid_pos)
	return info


## Inserta un bloque ya construido (el que devuelve detach_block) conservando su nodo.
func attach_block(grid_pos: Vector3i, info: Dictionary) -> void:
	if info.is_empty() or _blocks.has(grid_pos):
		return

	_blocks[grid_pos] = info
	var chunk := _chunk_of(grid_pos)
	if not _chunk_blocks.has(chunk):
		_chunk_blocks[chunk] = {}
	_chunk_blocks[chunk][grid_pos] = true
	_total_volume += _cell_volume() * _block_volume_factor(info["block_id"])

	_on_block_placed_hook(grid_pos)
	_request_rebuild(grid_pos)
	block_placed.emit(grid_pos, info["block_id"])


## Claves de los props anclados a cualquiera de las celdas dadas (Dictionary[Vector3i, true]).
## De una pasada sobre los props, no una por celda.
func get_prop_keys_in_cells(cells: Dictionary) -> Array:
	var out: Array = []
	for key: String in _props:
		if cells.has(_props[key]["cell"]):
			out.append(key)
	return out


## Saca un prop sin destruir su nodo, para moverlo a otra grid. Ver detach_block.
func detach_prop(key: String) -> Dictionary:
	if not _props.has(key):
		return {}
	var info: Dictionary = _props[key]
	_props.erase(key)
	return info


## Inserta un prop ya construido (el que devuelve detach_prop) conservando su nodo.
func attach_prop(key: String, info: Dictionary) -> void:
	if not info.is_empty():
		_props[key] = info


static func prop_key(cell: Vector3i, face: Vector3i) -> String:
	return "%d,%d,%d|%d,%d,%d" % [cell.x, cell.y, cell.z, face.x, face.y, face.z]


func has_prop(cell: Vector3i, face: Vector3i) -> bool:
	return _props.has(prop_key(cell, face))


## Coloca un prop (escena de item) anclado a la cara de un bloque. local_transform está en
## espacio de grid, con el origen en el punto de apoyo y +Y a lo largo del prop.
func place_prop(cell: Vector3i, face: Vector3i, item_id: StringName, local_transform: Transform3D) -> bool:
	var key := prop_key(cell, face)
	if _props.has(key):
		return false

	var item: ItemData = config_ref.get_item(item_id)
	if not item or item.scene_path == "":
		return false

	var center_offset := Vector3(0, item.placed_collider_size.y * 0.5, 0)
	var anchor_local := local_transform * Transform3D(Basis.IDENTITY, center_offset)
	var anchor := _create_prop_anchor(key, anchor_local, item.placed_collider_size)
	if not anchor:
		return false

	var visual := (load(item.scene_path) as PackedScene).instantiate() as Node3D
	visual.position = -center_offset
	anchor.add_child(visual)

	_props[key] = {
		"item_id": item_id,
		"cell": cell,
		"face": face,
		"local_transform": local_transform,
		"node": anchor,
	}
	return true


## Elimina un prop por su clave; devuelve su info (con item_id) o {} si no existe.
func remove_prop(key: String) -> Dictionary:
	if not _props.has(key):
		return {}
	var info: Dictionary = _props[key]
	var node: Node3D = info["node"]
	if node and is_instance_valid(node):
		node.queue_free()
	_props.erase(key)
	return info


func get_all_props() -> Dictionary:
	return _props


func _serialize_props() -> Dictionary:
	var out: Dictionary = {}
	for key: String in _props:
		var info: Dictionary = _props[key]
		out[key] = {
			"item_id": str(info["item_id"]),
			"cell": _vec3i_to_array(info["cell"]),
			"face": _vec3i_to_array(info["face"]),
			"local_transform": _transform_to_array(info["local_transform"]),
		}
	return out


func _deserialize_props(props_data: Dictionary) -> void:
	for key in props_data:
		var pd: Dictionary = props_data[key]
		place_prop(
			_array_to_vec3i(pd.get("cell", [])),
			_array_to_vec3i(pd.get("face", [])),
			StringName(pd.get("item_id", "")),
			_array_to_transform(pd.get("local_transform", []))
		)


## Suspende los rebuilds de mesh durante una edición masiva de bloques.
func begin_bulk_edit() -> void:
	_suppress_rebuild = true

## Termina la edición masiva y reconstruye todos los chunks de una vez.
func end_bulk_edit() -> void:
	_suppress_rebuild = false
	rebuild_mesh()


## Acumula los rebuilds de las ediciones siguientes en vez de ejecutarlos uno a uno. A diferencia
## de begin_bulk_edit, al cerrar solo se reconstruyen los chunks tocados, no la grid entera.
func begin_batch_edit() -> void:
	_batch_depth += 1

## Cierra el batch y reconstruye de una vez los chunks marcados.
func end_batch_edit() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth > 0:
		return
	var dirty := _dirty_chunks
	_dirty_chunks = {}
	for chunk: Vector3i in dirty:
		_rebuild_chunk(chunk)


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
## vecinos con bloques adyacentes, cuyas caras de frontera pueden cambiar). Dentro de un
## batch solo los marca, y los reconstruye end_batch_edit.
func _request_rebuild(grid_pos: Vector3i) -> void:
	if _suppress_rebuild:
		return

	var dirty: Dictionary = _dirty_chunks if _batch_depth > 0 else {}
	dirty[_chunk_of(grid_pos)] = true
	for neighbor in get_neighbors_of(grid_pos):
		if _blocks.has(neighbor):
			dirty[_chunk_of(neighbor)] = true

	if _batch_depth > 0:
		return

	for chunk: Vector3i in dirty:
		_rebuild_chunk(chunk)


## Rebuild completo: resincroniza el índice de chunks y el volumen desde _blocks y reconstruye todos.
func rebuild_mesh() -> void:
	_dirty_chunks.clear()
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


## Regenera las cajas de colisión fusionadas de los cubos macizos de un chunk. Los CollisionShape3D
## que ya existían se reaprovechan cambiándoles tamaño y posición: liberarlos y crearlos de nuevo
## obliga al servidor de física a dar de baja y de alta cada forma del cuerpo, y eso era la mayor
## parte del coste de colisión de un impacto.
func _rebuild_chunk_colliders(chunk: Vector3i, positions: Dictionary) -> void:
	var cubes: Dictionary = {}
	for grid_pos: Vector3i in positions:
		if ChunkMeshBuilder._is_solid(_blocks[grid_pos]["block_id"]):
			cubes[grid_pos] = true

	var parent := _get_collision_parent()
	if cubes.is_empty() or not parent:
		_free_chunk_colliders(chunk)
		return

	var existing: Array = _chunk_colliders.get(chunk, [])
	var shapes: Array = []

	for box: Dictionary in GridColliderBuilder.merge_boxes(cubes):
		var collider: CollisionShape3D = null
		if shapes.size() < existing.size() and is_instance_valid(existing[shapes.size()]):
			collider = existing[shapes.size()]
		else:
			collider = CollisionShape3D.new()
			collider.shape = BoxShape3D.new()
			collider.set_meta("grid_id", grid_id)
			parent.add_child(collider)

		(collider.shape as BoxShape3D).size = Vector3(box["size"]) * cell_size
		collider.position = (Vector3(box["pos"]) + Vector3(box["size"]) * 0.5) * cell_size
		shapes.append(collider)

	for i in range(shapes.size(), existing.size()):
		if is_instance_valid(existing[i]):
			existing[i].queue_free()

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


## Energía que cuesta romper un bloque: su dureza (o la nominal) por el volumen que ocupa.
func _impact_cost(block_id: int) -> float:
	var toughness := DEFAULT_IMPACT_TOUGHNESS
	var block_data: BlockData = BlockDatabase.get_block(block_id)
	if block_data and block_data.impact_toughness > 0.0:
		toughness = block_data.impact_toughness
	return toughness * _cell_volume() * _block_volume_factor(block_id)


## Destruye bloques alrededor de un punto del mundo gastando hasta 'energy' julios, de dentro
## hacia fuera; un bloque que no se pueda pagar detiene la propagación. Devuelve
## {spent, destroyed: [{grid_pos, block_id, world_pos}]}. Conviene envolverla en
## begin_batch_edit/end_batch_edit: si no, cada bloque dispara su propio rebuild de chunk.
func damage_sphere(world_center: Vector3, energy: float) -> Dictionary:
	var destroyed: Array = []
	if energy <= 0.0 or _blocks.is_empty():
		return {"spent": 0.0, "destroyed": destroyed}

	var xform := get_grid_world_transform()
	var center := (xform.affine_inverse() * world_center) / cell_size

	# El radio sale del presupuesto —una esfera con tantas celdas como el impacto puede pagar a
	# dureza nominal—, así un golpe pequeño no barre igualmente el radio máximo.
	var affordable := maxf(energy / maxf(DEFAULT_IMPACT_TOUGHNESS * _cell_volume(), 0.001), 1.0)
	var radius := clampf(pow(affordable * 0.75 / PI, 1.0 / 3.0) + 0.5, 1.0, float(IMPACT_MAX_RADIUS_CELLS))
	var radius_sq := radius * radius

	var lo := Vector3i((center - Vector3.ONE * radius).floor())
	var hi := Vector3i((center + Vector3.ONE * radius).ceil())

	# Se recorre la caja envolvente o el diccionario de bloques, lo que sea menor. Con radios
	# grandes la caja son cientos de miles de celdas casi todas vacías (101³ a radio 50), mientras
	# que un barco entero son unos miles de bloques.
	var box_cells := (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1)
	var candidates := PackedVector4Array()
	if box_cells <= _blocks.size():
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var cell := Vector3i(x, y, z)
					if not _blocks.has(cell):
						continue
					var dist_sq := (Vector3(cell) + Vector3.ONE * 0.5 - center).length_squared()
					if dist_sq <= radius_sq:
						candidates.append(Vector4(dist_sq, cell.x, cell.y, cell.z))
	else:
		for cell: Vector3i in _blocks:
			var dist_sq := (Vector3(cell) + Vector3.ONE * 0.5 - center).length_squared()
			if dist_sq <= radius_sq:
				candidates.append(Vector4(dist_sq, cell.x, cell.y, cell.z))

	# Orden nativo: Vector4 compara lexicográficamente, así que la distancia (componente x) manda.
	# Un sort_custom con lambda cuesta una llamada de GDScript por comparación.
	candidates.sort()

	var budget := energy
	for entry: Vector4 in candidates:
		# El tope acota el coste del frame pase lo que pase con la energía.
		if destroyed.size() >= IMPACT_MAX_BLOCKS:
			break
		var cell := Vector3i(int(entry.y), int(entry.z), int(entry.w))
		var block_id: int = _blocks[cell]["block_id"]
		var cost := _impact_cost(block_id)
		if cost > budget:
			break
		var world_pos := xform * ((Vector3(cell) + Vector3.ONE * 0.5) * cell_size)
		if remove_block(cell).is_empty():
			continue
		budget -= cost
		destroyed.append({"grid_pos": cell, "block_id": block_id, "world_pos": world_pos})

	return {"spent": energy - budget, "destroyed": destroyed}


func distance_to(world_pos: Vector3) -> float:
	return get_origin_world().distance_to(world_pos)


func clear() -> void:
	for grid_pos in _blocks.keys():
		var info: Dictionary = _blocks[grid_pos]
		var node: Node3D = info["node"]
		if node and is_instance_valid(node):
			node.queue_free()
	_blocks.clear()

	for key: String in _props:
		var prop_node: Node3D = _props[key]["node"]
		if prop_node and is_instance_valid(prop_node):
			prop_node.queue_free()
	_props.clear()

	for chunk: Vector3i in _chunk_meshes.keys():
		_free_chunk_mesh(chunk)
	_chunk_blocks.clear()
	_dirty_chunks.clear()
	_batch_depth = 0
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
