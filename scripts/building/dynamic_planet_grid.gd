class_name DynamicPlanetGrid
extends GridBase

## Grid dinámica: todos los bloques viven dentro de un RigidBody3D
## que cae con gravedad planetaria. Sigue siendo editable.

var _body: DynamicGridBody = null

const MASS_PER_BLOCK := 10.0


# ============================================================
#  CONSTRUCTOR
# ============================================================

## Crea la grid dinámica desde cero.
func setup(id: String, planet: Node3D, world_transform: Transform3D) -> void:
	grid_id = id
	planet_node = planet
	_create_body(world_transform)


## Crea la grid dinámica a partir de una PlanetGrid existente (conversión).
func setup_from_static(id: String, planet: Node3D, static_grid: PlanetGrid) -> void:
	grid_id = id
	planet_node = planet
	cell_size = static_grid.cell_size
	mesh_materials = static_grid.mesh_materials

	var grid_world_xform := static_grid.get_grid_world_transform()
	_create_body(grid_world_xform)

	# Migrar bloques
	var all_blocks := static_grid.get_all_blocks()
	for grid_pos: Vector3i in all_blocks:
		var info: Dictionary = all_blocks[grid_pos]
		var old_node: Node3D = info["node"]

		# Calcular transform relativo al body
		var local_xform := Transform3D.IDENTITY
		if old_node and is_instance_valid(old_node):
			local_xform = _body.global_transform.affine_inverse() * old_node.global_transform

		# Crear wrapper con collider
		var block_data: BlockData = BlockDatabase.get_block(info["block_id"])
		if not block_data:
			continue

		var rotation_basis: Basis = info.get("rotation_basis", Basis.IDENTITY)
		var wrapper := _make_block_wrapper(grid_pos, block_data, rotation_basis, local_xform)
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

	# Limpiar grid estática (nodos, NO la mesh — la reconstruimos nosotros)
	static_grid.clear()

	# Reconstruir mesh en el body
	rebuild_mesh()


func _create_body(world_transform: Transform3D) -> void:
	_body = DynamicGridBody.new()
	_body.name = "DynGrid_%s" % grid_id
	_body.planet_node = planet_node
	_body.mass = MASS_PER_BLOCK
	_body.gravity_scale = 0.0
	_body.set_meta("grid_id", grid_id)

	# Añadir al padre del planeta (escena raíz) para que no se mueva con el planeta
	planet_node.get_tree().current_scene.add_child(_body)

	_body.global_transform = world_transform


func _update_mass() -> void:
	if _body and is_instance_valid(_body):
		_body.mass = maxf(MASS_PER_BLOCK, _blocks.size() * MASS_PER_BLOCK)


# ============================================================
#  OVERRIDES DE GridBase
# ============================================================

func get_grid_world_transform() -> Transform3D:
	if _body and is_instance_valid(_body):
		return _body.global_transform
	return Transform3D.IDENTITY


func _get_mesh_local_transform() -> Transform3D:
	# Mesh es hijo directo del body → identidad
	return Transform3D.IDENTITY


func _get_mesh_parent() -> Node3D:
	return _body


func _create_block_node(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis, world_transform: Transform3D) -> Node3D:
	var local_xform := _body.global_transform.affine_inverse() * world_transform
	var wrapper := _make_block_wrapper(grid_pos, block_data, rotation_basis, local_xform)
	_body.add_child(wrapper)
	_update_mass()
	return wrapper


func _on_block_removed_hook(_info: Dictionary) -> void:
	_update_mass()


## Crea un Node3D wrapper con CollisionShape3D (sin visual).
func _make_block_wrapper(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis, local_xform: Transform3D) -> CollisionShape3D:
	var shape: Shape3D = block_data.collision_shape.duplicate()
	var collider := CollisionShape3D.new()
	collider.name = "Block_%s_%s" % [grid_id, grid_pos]

	if shape is BoxShape3D:
		shape.size = shape.size * cell_size
	else:
		collider.scale = Vector3.ONE * cell_size

	collider.shape = shape

	# Combinar transform del wrapper + offset del collider
	var c := Vector3.ONE * cell_size * 0.5
	var col_offset := rotation_basis.inverse() * c
	var col_local := Transform3D(Basis.IDENTITY, col_offset)
	collider.transform = local_xform * col_local

	collider.set_meta("grid_id", grid_id)
	collider.set_meta("grid_pos", grid_pos)
	collider.set_meta("block_id", block_data.block_id)
	collider.set_meta("rotation_basis", rotation_basis)

	return collider


# ============================================================
#  LIMPIEZA
# ============================================================

func clear() -> void:
	super.clear()
	if _body and is_instance_valid(_body):
		_body.queue_free()
		_body = null


# ============================================================
#  SERIALIZACIÓN
# ============================================================

func serialize() -> Dictionary:
	var blocks_data: Dictionary = {}

	for grid_pos in _blocks:
		var info: Dictionary = _blocks[grid_pos]
		var key := "%d,%d,%d" % [grid_pos.x, grid_pos.y, grid_pos.z]
		var node: Node3D = info["node"]
		var t := node.transform if (node and is_instance_valid(node)) else Transform3D.IDENTITY
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

	# Guardar transform del body (posición/rotación actual en el mundo)
	var body_xform := _body.global_transform if (_body and is_instance_valid(_body)) else Transform3D.IDENTITY

	return {
		"type": "dynamic",
		"planet_path": str(planet_node.get_path()),
		"body_transform": _transform_to_array(body_xform),
		"cell_size": cell_size,
		"blocks": blocks_data,
		"materials": materials_data,
	}


func deserialize(id: String, planet: Node3D, data: Dictionary) -> void:
	grid_id = id
	planet_node = planet
	cell_size = data.get("cell_size", 1.0)

	var body_xform := _array_to_transform(data.get("body_transform", []))
	_create_body(body_xform)

	# Materiales
	var materials_data: Dictionary = data.get("materials", {})
	for mat_id in materials_data:
		var path: String = materials_data[mat_id]
		if ResourceLoader.exists(path):
			mesh_materials[mat_id] = load(path)

	# Bloques
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

	_update_mass()
	rebuild_mesh()
