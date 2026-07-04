class_name DynamicPlanetGrid
extends GridBase

## Grid dinámica: todos los bloques viven dentro de un RigidBody3D que cae con gravedad
## planetaria y sigue siendo editable. Puede crearse desde cero o convirtiendo una PlanetGrid.

var _body: DynamicGridBody = null
var body_id: String = ""
var _owns_body: bool = false

const MASS_PER_BLOCK := 10.0


## Crea la grid dinámica desde cero.
func setup(id: String, planet: Node3D, world_transform: Transform3D) -> void:
	grid_id = id
	planet_node = planet
	_create_body(world_transform)

## Setup reutilizando un body existente (multi-size).
func setup_from_static_shared(id: String, planet: Node3D, static_grid: PlanetGrid, shared_body: DynamicGridBody) -> void:
	grid_id = id
	planet_node = planet
	cell_size = static_grid.cell_size
	mesh_materials = static_grid.mesh_materials
	_body = shared_body
	_owns_body = false
	body_id = shared_body.get_meta("grid_id")

	var all_blocks := static_grid.get_all_blocks()
	for grid_pos: Vector3i in all_blocks:
		var info: Dictionary = all_blocks[grid_pos]
		var old_node: Node3D = info["node"]

		var local_xform := Transform3D.IDENTITY
		if old_node and is_instance_valid(old_node):
			local_xform = _body.global_transform.affine_inverse() * old_node.global_transform

		var block_data: BlockData = BlockDatabase.get_block(info["block_id"])
		if not block_data:
			continue

		var rotation_basis: Basis = info.get("rotation_basis", Basis.IDENTITY)
		var col: Node3D = null
		if not ChunkMeshBuilder._is_solid(block_data.block_id):
			col = _make_block_wrapper(grid_pos, block_data, rotation_basis, local_xform)
			_body.add_child(col)

		_blocks[grid_pos] = {
			"block_id": info["block_id"],
			"rotation_basis": rotation_basis,
			"node": col,
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}

	static_grid.clear()
	_update_mass()
	rebuild_mesh()
	_body.register_grid(self)
	block_placed.connect(_body.on_block_placed)
	block_removed.connect(_body.on_block_removed)

## Crea la grid dinámica a partir de una PlanetGrid existente (conversión).
func setup_from_static(id: String, planet: Node3D, static_grid: PlanetGrid) -> void:
	grid_id = id
	planet_node = planet
	cell_size = static_grid.cell_size
	mesh_materials = static_grid.mesh_materials

	var grid_world_xform := static_grid.get_grid_world_transform()
	_create_body(grid_world_xform)

	var all_blocks := static_grid.get_all_blocks()
	for grid_pos: Vector3i in all_blocks:
		var info: Dictionary = all_blocks[grid_pos]
		var old_node: Node3D = info["node"]

		var local_xform := Transform3D.IDENTITY
		if old_node and is_instance_valid(old_node):
			local_xform = _body.global_transform.affine_inverse() * old_node.global_transform

		var block_data: BlockData = BlockDatabase.get_block(info["block_id"])
		if not block_data:
			continue

		var rotation_basis: Basis = info.get("rotation_basis", Basis.IDENTITY)
		var wrapper: Node3D = null
		if not ChunkMeshBuilder._is_solid(block_data.block_id):
			wrapper = _make_block_wrapper(grid_pos, block_data, rotation_basis, local_xform)
			_body.add_child(wrapper)

		_blocks[grid_pos] = {
			"block_id": info["block_id"],
			"rotation_basis": rotation_basis,
			"node": wrapper,
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}

	_update_mass()
	static_grid.clear()
	rebuild_mesh()


func _create_body(world_transform: Transform3D) -> void:
	_body = DynamicGridBody.new()
	_body.name = "DynGrid_%s" % grid_id
	_body.planet_node = planet_node
	_body.mass = MASS_PER_BLOCK
	_body.gravity_scale = 0.0
	_body.set_meta("grid_id", grid_id)
	_owns_body = true
	body_id = grid_id

	planet_node.get_tree().current_scene.add_child(_body)
	_body.global_transform = world_transform
	_body.register_grid(self)
	block_placed.connect(_body.on_block_placed)
	block_removed.connect(_body.on_block_removed)

func _update_mass() -> void:
	if _body and is_instance_valid(_body):
		_body.mass = maxf(MASS_PER_BLOCK, _blocks.size() * MASS_PER_BLOCK)


func is_same_origin_basis(other: GridBase) -> bool:
	if other is DynamicPlanetGrid:
		return _body == (other as DynamicPlanetGrid)._body
	return false

func get_grid_world_transform() -> Transform3D:
	if _body and is_instance_valid(_body):
		return _body.global_transform
	return Transform3D.IDENTITY


func _get_mesh_local_transform() -> Transform3D:
	return Transform3D.IDENTITY


func _get_mesh_parent() -> Node3D:
	return _body


func _get_collision_parent() -> Node3D:
	return _body


func _create_block_node(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis, world_transform: Transform3D) -> Node3D:
	var local_xform := _body.global_transform.affine_inverse() * world_transform
	var wrapper := _make_block_wrapper(grid_pos, block_data, rotation_basis, local_xform)
	_body.add_child(wrapper)
	return wrapper


func _on_block_placed_hook(_grid_pos: Vector3i) -> void:
	_update_mass()


func _on_block_removed_hook(_info: Dictionary) -> void:
	_update_mass()


## Crea un CollisionShape3D wrapper para un bloque (sin visual).
func _make_block_wrapper(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis, local_xform: Transform3D) -> CollisionShape3D:
	var shape: Shape3D = block_data.collision_shape.duplicate()
	var collider := CollisionShape3D.new()
	collider.name = "Block_%s_%s" % [grid_id, grid_pos]

	if shape is BoxShape3D:
		shape.size = shape.size * cell_size
	else:
		collider.scale = Vector3.ONE * cell_size

	collider.shape = shape

	var c := Vector3.ONE * cell_size * 0.5
	var col_offset := rotation_basis.inverse() * c
	var col_local := Transform3D(Basis.IDENTITY, col_offset)
	collider.transform = local_xform * col_local

	collider.set_meta("grid_id", grid_id)
	collider.set_meta("grid_pos", grid_pos)
	collider.set_meta("block_id", block_data.block_id)
	collider.set_meta("rotation_basis", rotation_basis)

	return collider


func clear() -> void:
	if _body and is_instance_valid(_body):
		_body.unregister_grid(self)
	super.clear()
	if _owns_body and _body and is_instance_valid(_body):
		_body.queue_free()
		_body = null


func serialize() -> Dictionary:
	var blocks_data: Dictionary = {}

	for grid_pos in _blocks:
		var info: Dictionary = _blocks[grid_pos]
		var key := "%d,%d,%d" % [grid_pos.x, grid_pos.y, grid_pos.z]
		var node: Node3D = info["node"]
		var rot_basis: Basis = info.get("rotation_basis", Basis.IDENTITY)

		var block_local: Transform3D
		if node and is_instance_valid(node):
			var t := node.transform
			var c := Vector3.ONE * cell_size * 0.5
			var col_offset := rot_basis.inverse() * c
			block_local = Transform3D(t.basis, t.origin - t.basis * col_offset)
		else:
			block_local = Transform3D(rot_basis, Vector3(grid_pos) * cell_size)

		blocks_data[key] = {
			"block_id": info["block_id"],
			"rotation_basis": _basis_to_array(rot_basis),
			"transform": _transform_to_array(block_local),
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}

	var materials_data: Dictionary = {}
	for mat_id in mesh_materials:
		var mat: Material = mesh_materials[mat_id]
		if mat and mat.resource_path != "":
			materials_data[mat_id] = mat.resource_path

	var body_xform := _body.global_transform if (_body and is_instance_valid(_body)) else Transform3D.IDENTITY

	return {
		"type": "dynamic",
		"planet_path": str(planet_node.get_path()),
		"body_id": body_id,
		"body_transform": _transform_to_array(body_xform),
		"cell_size": cell_size,
		"blocks": blocks_data,
		"materials": materials_data,
	}


func deserialize(id: String, planet: Node3D, data: Dictionary, shared_body: DynamicGridBody = null) -> void:
	grid_id = id
	planet_node = planet
	cell_size = data.get("cell_size", 1.0)
	body_id = data.get("body_id", id)

	if shared_body:
		_body = shared_body
		_owns_body = false
	else:
		var body_xform := _array_to_transform(data.get("body_transform", []))
		_create_body(body_xform)
		body_id = data.get("body_id", grid_id)

	var materials_data: Dictionary = data.get("materials", {})
	for mat_id in materials_data:
		var path: String = materials_data[mat_id]
		if ResourceLoader.exists(path):
			mesh_materials[mat_id] = load(path)

	_suppress_rebuild = true
	var blocks_data: Dictionary = data.get("blocks", {})
	for key in blocks_data:
		var parts := (key as String).split(",")
		var grid_pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var block_info: Dictionary = blocks_data[key]

		var block_id: int = block_info.get("block_id", 0)
		var block_data: BlockData = BlockDatabase.get_block(block_id)
		if not block_data:
			continue

		var saved_local := _array_to_transform(block_info.get("transform", []))
		var world_transform := _body.global_transform * saved_local
		var rotation_basis := _array_to_basis(block_info.get("rotation_basis", [1,0,0, 0,1,0, 0,0,1]))
		var material_id: String = block_info.get("material_id", "")

		var mirror_data := {
			"mirrored": block_info.get("mirrored", false),
			"mirror_axis": block_info.get("mirror_axis", -1),
		}

		place_block(grid_pos, block_data, rotation_basis, world_transform, material_id, mirror_data)
	_suppress_rebuild = false

	_body.register_grid(self)
	block_placed.connect(_body.on_block_placed)
	block_removed.connect(_body.on_block_removed)
	_update_mass()
	rebuild_mesh()
