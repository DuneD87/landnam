class_name PlanetGrid
extends GridBase

## Grid estática de construcción anclada a un planeta. Los cubos macizos colisionan mediante
## cajas fusionadas en un StaticBody3D único de la grid; los bloques con forma propia
## (rampas, esquinas) mantienen su StaticBody3D individual hijo del planeta.

var origin_local: Vector3 = Vector3.ZERO
var basis_local: Basis = Basis.IDENTITY

var _collision_body: StaticBody3D = null


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
