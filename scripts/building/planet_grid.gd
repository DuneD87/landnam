class_name PlanetGrid
extends GridBase

## Grid estática de construcción anclada a un planeta. Los cubos macizos colisionan mediante
## cajas fusionadas en un StaticBody3D único de la grid; los bloques con forma propia
## (rampas, esquinas) mantienen su StaticBody3D individual hijo del planeta.

## Hasta dónde busca suelo el sondeo por debajo de la cara inferior de un bloque.
const ANCHOR_PROBE := 0.35

var origin_local: Vector3 = Vector3.ZERO
var basis_local: Basis = Basis.IDENTITY

var _collision_body: StaticBody3D = null


## Celdas que se apoyan en algo firme: el terreno u otra grid estática, nunca un cuerpo dinámico
## (una casa apoyada en un barco no está en suelo firme). Solo se sondean las celdas sin bloque
## debajo, y el rayo va hacia el ABAJO GRAVITACIONAL —no el -Y de la grid, que solo coincide si
## se construyó alineada a la superficie— y de fuera hacia dentro: el trimesh del terreno ignora
## las caras traseras, así que sondear hacia arriba no detectaría nada.
func compute_anchor_cells() -> Dictionary:
	var anchors: Dictionary = {}
	if _blocks.is_empty() or not planet_node or not planet_node.is_inside_tree():
		return anchors

	var xform := get_grid_world_transform()
	var down_world : Vector3 = (planet_node.global_pos - xform.origin).normalized()
	if down_world.is_zero_approx():
		return anchors
	var down_cell := _dominant_axis(xform.basis.inverse() * down_world)
	var space := planet_node.get_world_3d().direct_space_state

	for cell: Vector3i in _blocks:
		if _blocks.has(cell + down_cell):
			continue
		var face_local := (Vector3(cell) + Vector3.ONE * 0.5 + Vector3(down_cell) * 0.5) * cell_size
		var from := xform * face_local + down_world * 0.02
		var query := PhysicsRayQueryParameters3D.create(from, from + down_world * ANCHOR_PROBE)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		if _is_firm_ground(hit.get("collider")):
			anchors[cell] = true

	return anchors


## Celda vecina en la dirección dominante de un vector en espacio de grid.
static func _dominant_axis(v: Vector3) -> Vector3i:
	var a := v.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector3i(1 if v.x > 0.0 else -1, 0, 0)
	if a.y >= a.z:
		return Vector3i(0, 1 if v.y > 0.0 else -1, 0)
	return Vector3i(0, 0, 1 if v.z > 0.0 else -1)


## Terreno u otra grid estática cuentan como suelo; esta misma grid y los cuerpos dinámicos no.
func _is_firm_ground(collider: Object) -> bool:
	if not collider or collider is DynamicGridBody:
		return false
	if collider is Node and (collider as Node).has_meta("grid_id"):
		return (collider as Node).get_meta("grid_id") != grid_id
	return true


func setup(id: String, planet: Node3D, origin_world: Vector3, basis_world: Basis, size: float = 1.0) -> void:
	grid_id = id
	planet_node = planet
	cell_size = size

	var planet_inv := planet.global_transform.affine_inverse()
	origin_local = planet_inv * origin_world
	basis_local = planet_inv.basis * basis_world

func is_same_origin_basis(other: GridBase) -> bool:
	if other is PlanetGrid:
		return origin_local.is_equal_approx(other.origin_local) \
			and basis_local.is_equal_approx(other.basis_local)
	return false
	
func setup_aligned(id: String, planet: Node3D, ref_origin_local: Vector3, ref_basis_local: Basis, size: float) -> void:
	grid_id = id
	planet_node = planet
	cell_size = size
	origin_local = ref_origin_local
	basis_local = ref_basis_local


func get_grid_world_transform() -> Transform3D:
	return planet_node.global_transform * Transform3D(basis_local, origin_local)


func _get_mesh_local_transform() -> Transform3D:
	return Transform3D(basis_local, origin_local)


func _get_mesh_parent() -> Node3D:
	return planet_node


func _get_collision_parent() -> Node3D:
	if _collision_body and is_instance_valid(_collision_body):
		return _collision_body

	_collision_body = StaticBody3D.new()
	_collision_body.name = "GridBody_%s" % grid_id
	_collision_body.transform = Transform3D(basis_local, origin_local)
	_collision_body.set_meta("grid_id", grid_id)
	planet_node.add_child(_collision_body)
	return _collision_body


## Quitar un bloque puede dejar parte de la estructura sin apoyo; colocarlo nunca.
func _on_block_removed_hook(_info: Dictionary) -> void:
	GridManager.mark_collapse_check(self)


func clear() -> void:
	super.clear()
	if _collision_body and is_instance_valid(_collision_body):
		_collision_body.queue_free()
		_collision_body = null


func _create_block_node(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis, world_transform: Transform3D) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Block_%s_%s" % [grid_id, grid_pos]
	body.transform = planet_node.global_transform.affine_inverse() * world_transform

	var collider := CollisionShape3D.new()
	var shape: Shape3D = block_data.collision_shape.duplicate()

	if shape is BoxShape3D:
		shape.size = shape.size * cell_size
	else:
		collider.scale = Vector3.ONE * cell_size

	collider.shape = shape
	var c := Vector3.ONE * cell_size * 0.5
	collider.position = rotation_basis.inverse() * c
	body.add_child(collider)

	body.set_meta("grid_id", grid_id)
	body.set_meta("grid_pos", grid_pos)
	body.set_meta("block_id", block_data.block_id)
	body.set_meta("rotation_basis", rotation_basis)

	planet_node.add_child(body)
	return body


func _create_prop_anchor(key: String, anchor_local: Transform3D, collider_size: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Prop_%s_%s" % [grid_id, key]
	body.transform = Transform3D(basis_local, origin_local) * anchor_local

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collider_size
	collider.shape = shape
	body.add_child(collider)

	body.set_meta("grid_id", grid_id)
	body.set_meta("prop_key", key)
	planet_node.add_child(body)
	return body


func serialize() -> Dictionary:
	var blocks_data: Dictionary = {}

	for grid_pos in _blocks:
		var info: Dictionary = _blocks[grid_pos]
		var key := "%d,%d,%d" % [grid_pos.x, grid_pos.y, grid_pos.z]
		var node: Node3D = info["node"]

		var t: Transform3D
		if node and is_instance_valid(node):
			t = node.transform
		else:
			var rot: Basis = info.get("rotation_basis", Basis.IDENTITY)
			t = Transform3D(basis_local * rot, origin_local + basis_local * (Vector3(grid_pos) * cell_size))

		blocks_data[key] = {
			"block_id": info["block_id"],
			"rotation_basis": _basis_to_array(info["rotation_basis"]),
			"transform": _transform_to_array(t),
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}

	var materials_data: Dictionary = {}
	for mat_id in mesh_materials:
		var mat: Material = mesh_materials[mat_id]
		if mat and mat.resource_path != "":
			materials_data[mat_id] = mat.resource_path

	return {
		"type": "static",
		"planet_path": str(planet_node.get_path()),
		"origin_local": _vec3_to_array(origin_local),
		"basis_local": _basis_to_array(basis_local),
		"cell_size": cell_size,
		"blocks": blocks_data,
		"materials": materials_data,
		"props": _serialize_props(),
	}


func deserialize(id: String, planet: Node3D, data: Dictionary) -> void:
	grid_id = id
	planet_node = planet
	cell_size = data.get("cell_size", 1.0)
	origin_local = _array_to_vec3(data.get("origin_local", [0, 0, 0]))
	basis_local = _array_to_basis(data.get("basis_local", [1,0,0, 0,1,0, 0,0,1]))

	var materials_data: Dictionary = data.get("materials", {})
	for mat_id in materials_data:
		var path: String = materials_data[mat_id]
		if ResourceLoader.exists(path):
			mesh_materials[mat_id] = load(path)
		else:
			push_warning("[PlanetGrid] Material resource not found: %s" % path)

	_suppress_rebuild = true
	var blocks_data: Dictionary = data.get("blocks", {})
	for key in blocks_data:
		var parts := (key as String).split(",")
		var grid_pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var block_info: Dictionary = blocks_data[key]

		var block_id: int = block_info.get("block_id", 0)
		var block_data: BlockData = BlockDatabase.get_block(block_id)
		if not block_data:
			push_warning("[PlanetGrid] Block ID %d no encontrado al cargar" % block_id)
			continue

		var saved_transform := _array_to_transform(block_info.get("transform", []))
		var world_transform := planet_node.global_transform * saved_transform
		var rotation_basis := _array_to_basis(block_info.get("rotation_basis", [1,0,0, 0,1,0, 0,0,1]))
		var material_id: String = block_info.get("material_id", "")

		var mirror_data := {
			"mirrored": block_info.get("mirrored", false),
			"mirror_axis": block_info.get("mirror_axis", -1),
		}

		place_block(grid_pos, block_data, rotation_basis, world_transform, material_id, mirror_data)
	_suppress_rebuild = false

	_deserialize_props(data.get("props", {}))
	rebuild_mesh()
