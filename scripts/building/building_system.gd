class_name BuildingSystem
extends Node3D

## Sistema de construcción. Añadir como hijo del Player.
##
## Aprovecha que el player YA se orienta con la gravedad esférica:
##   - player.basis.y = normal de la superficie (local up)
##   - No necesitamos recalcular la orientación desde el centro del planeta
##
## Para soporte multi-planeta:
##   - Asignar current_planet al planeta donde está el player
##   - El sistema usa player.basis para la grid, no el centro del planeta

signal block_placed(block_data: BlockData, grid_pos: Vector3i, block_transform: Transform3D)
signal block_removed(grid_pos: Vector3i)
signal build_mode_changed(active: bool)
signal selected_block_changed(block_data: BlockData)

# ============================================================
#  CONFIGURACIÓN
# ============================================================

## Referencia al planeta actual donde está el player.
## Se usa para obtener el centro y como parent de los bloques.
## Puede cambiar en runtime cuando el player viaja entre planetas.
@export var current_planet: Node3D = null

## Tamaño de celda de la grid.
@export var cell_size: float = 1.0

## Distancia máxima de construcción desde el player.
@export var max_build_distance: float = 8.0

# ============================================================
#  ESTADO
# ============================================================

var build_mode: bool = false
var selected_block_id: int = 0
var current_rotation_step: int = 0

## Bloques colocados. Key = Vector3i (grid pos), Value = info dict.
var _placed_blocks: Dictionary = {}

## Basis y origin de la grid (actualizados cada frame en build mode).
var _local_basis: Basis = Basis.IDENTITY
var _grid_origin: Vector3 = Vector3.ZERO

## Referencia al nodo padre (player).
var _player: Node3D = null


# ============================================================
#  LIFECYCLE
# ============================================================

func _ready() -> void:
	selected_block_id = BlockDatabase.BLOCK_CUBE_ID
	
	# El padre debería ser el player
	_player = get_parent() as Node3D
	if not _player:
		push_warning("[BuildingSystem] El padre no es un Node3D. Asegúrate de que sea hijo del player.")


func _process(_delta: float) -> void:
	if not build_mode or not _player:
		return
	_update_grid_from_player()


# ============================================================
#  GRID CALCULATIONS (basado en el transform del player)
# ============================================================

## Recalcula la grid usando el basis del player directamente.
## Como el player ya se alinea a la superficie, su basis.y = local up.
func _update_grid_from_player() -> void:
	var player_basis := _player.global_transform.basis
	var player_pos := _player.global_position
	
	# El basis del player ya está alineado a la superficie:
	#   Y = normal (hacia fuera del planeta)
	#   X = right tangente
	#   Z = forward tangente
	_local_basis = player_basis.orthonormalized()
	
	# Grid origin snapeado para estabilidad
	_grid_origin = _calculate_stable_grid_origin(player_pos)


func _calculate_stable_grid_origin(player_pos: Vector3) -> Vector3:
	# Usamos el centro del planeta como ancla fija para que la grid
	# no se mueva con micro-movimientos del player.
	var planet_center := get_planet_center()
	
	# Posición relativa al planeta, en espacio local de la grid
	var relative := player_pos - planet_center
	var local_pos := _local_basis.inverse() * relative
	
	# Snapear cada componente al cell_size
	local_pos.x = snapped(local_pos.x, cell_size)
	local_pos.y = snapped(local_pos.y, cell_size)
	local_pos.z = snapped(local_pos.z, cell_size)
	
	return planet_center + _local_basis * local_pos


## Obtiene el centro del planeta actual.
func get_planet_center() -> Vector3:
	if current_planet:
		return current_planet.global_position
	push_warning("[BuildingSystem] No hay planeta asignado, usando Vector3.ZERO")
	return Vector3.ZERO


# ============================================================
#  SNAP & TRANSFORM
# ============================================================

func snap_position(world_pos: Vector3) -> Vector3:
	return BuildGridHelper.snap_to_grid(world_pos, _local_basis, _grid_origin, cell_size)


func world_to_grid(world_pos: Vector3) -> Vector3i:
	return BuildGridHelper.world_to_grid(world_pos, _local_basis, _grid_origin, cell_size)


func grid_to_world(grid_pos: Vector3i) -> Vector3:
	return BuildGridHelper.grid_to_world(grid_pos, _local_basis, _grid_origin, cell_size)


func get_block_transform(world_pos: Vector3) -> Transform3D:
	var block_data := BlockDatabase.get_block(selected_block_id)
	var rotation_deg := 0.0
	if block_data and block_data.can_rotate:
		rotation_deg = block_data.get_rotation_angle_deg() * current_rotation_step
	
	return BuildGridHelper.get_block_transform(
		world_pos, _local_basis, _grid_origin, cell_size, rotation_deg
	)


func get_adjacent_cell(grid_pos: Vector3i, hit_normal: Vector3) -> Vector3i:
	return BuildGridHelper.get_adjacent_cell_from_normal(grid_pos, hit_normal, _local_basis)


# ============================================================
#  BUILD ACTIONS
# ============================================================

func place_block(world_pos: Vector3) -> Node3D:
	var grid_pos := world_to_grid(world_pos)
	
	if _placed_blocks.has(grid_pos):
		return null
	
	var distance := _player.global_position.distance_to(world_pos)
	if distance > max_build_distance:
		return null
	
	var block_data := BlockDatabase.get_block(selected_block_id)
	if not block_data:
		return null
	
	var block_transform := get_block_transform(world_pos)
	
	# Añadir al planeta actual (así se mueve con él si es necesario)
	var parent_node: Node3D = current_planet if current_planet else get_tree().current_scene
	
	# IMPORTANTE: el transform está en world space, pero al ser hijo del planeta
	# necesitamos convertirlo a local space del padre.
	var local_transform := parent_node.global_transform.affine_inverse() * block_transform
	var block_node := _create_block_node(block_data, local_transform)
	
	parent_node.add_child(block_node)
	
	_placed_blocks[grid_pos] = {
		"block_id": selected_block_id,
		"rotation": current_rotation_step,
		"node": block_node,
		"planet": current_planet,
	}
	
	block_placed.emit(block_data, grid_pos, block_transform)
	return block_node


func remove_block(world_pos: Vector3) -> bool:
	var grid_pos := world_to_grid(world_pos)
	
	if not _placed_blocks.has(grid_pos):
		return false
	
	var block_info: Dictionary = _placed_blocks[grid_pos]
	var node: Node3D = block_info["node"]
	if node and is_instance_valid(node):
		node.queue_free()
	
	_placed_blocks.erase(grid_pos)
	block_removed.emit(grid_pos)
	return true


func has_block_at(grid_pos: Vector3i) -> bool:
	return _placed_blocks.has(grid_pos)


func _create_block_node(block_data: BlockData, block_transform: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "PlacedBlock_%s" % block_data.block_name
	body.transform = block_transform
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = block_data.mesh
	if block_data.material_override:
		mesh_instance.material_override = block_data.material_override
	body.add_child(mesh_instance)
	
	var collider := CollisionShape3D.new()
	collider.shape = block_data.collision_shape
	if block_data.collision_shape is BoxShape3D:
		collider.position.y = block_data.cell_size * 0.5
	body.add_child(collider)
	
	body.set_meta("block_id", block_data.block_id)
	body.set_meta("grid_pos", world_to_grid(block_transform.origin))
	body.set_meta("rotation_step", current_rotation_step)
	
	return body


# ============================================================
#  BLOCK SELECTION & ROTATION
# ============================================================

func select_next_block() -> void:
	var ids := BlockDatabase.get_all_ids()
	var idx := ids.find(selected_block_id)
	selected_block_id = ids[(idx + 1) % ids.size()]
	current_rotation_step = 0
	selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))


func select_previous_block() -> void:
	var ids := BlockDatabase.get_all_ids()
	var idx := ids.find(selected_block_id)
	selected_block_id = ids[(idx - 1 + ids.size()) % ids.size()]
	current_rotation_step = 0
	selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))


func select_block(block_id: int) -> void:
	if BlockDatabase.get_block(block_id):
		selected_block_id = block_id
		current_rotation_step = 0
		selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))


func rotate_block() -> void:
	var block_data := BlockDatabase.get_block(selected_block_id)
	if block_data and block_data.can_rotate:
		current_rotation_step = (current_rotation_step + 1) % block_data.rotation_steps


func get_current_rotation_deg() -> float:
	var block_data := BlockDatabase.get_block(selected_block_id)
	if block_data and block_data.can_rotate:
		return block_data.get_rotation_angle_deg() * current_rotation_step
	return 0.0


# ============================================================
#  BUILD MODE
# ============================================================

func toggle_build_mode() -> void:
	build_mode = !build_mode
	if build_mode:
		_update_grid_from_player()
	build_mode_changed.emit(build_mode)


func set_build_mode(active: bool) -> void:
	if build_mode != active:
		build_mode = active
		if build_mode:
			_update_grid_from_player()
		build_mode_changed.emit(build_mode)
func place_block_at_transform(grid_pos: Vector3i, world_transform: Transform3D) -> Node3D:
	if _placed_blocks.has(grid_pos):
		return null
	
	var distance := _player.global_position.distance_to(world_transform.origin)
	if distance > max_build_distance:
		return null
	
	var block_data := BlockDatabase.get_block(selected_block_id)
	if not block_data:
		return null
	
	var parent_node: Node3D = current_planet if current_planet else get_tree().current_scene
	var local_transform := parent_node.global_transform.affine_inverse() * world_transform
	var block_node := _create_block_node(block_data, local_transform)
	parent_node.add_child(block_node)
	
	_placed_blocks[grid_pos] = {
		"block_id": selected_block_id,
		"rotation": current_rotation_step,
		"node": block_node,
		"planet": current_planet,
	}
	
	block_placed.emit(block_data, grid_pos, world_transform)
	return block_node

# ============================================================
#  ACCESSORS
# ============================================================

func get_local_basis() -> Basis:
	return _local_basis

func get_local_up() -> Vector3:
	return _local_basis.y

func get_grid_origin() -> Vector3:
	return _grid_origin

func get_selected_block() -> BlockData:
	return BlockDatabase.get_block(selected_block_id)

func get_placed_blocks() -> Dictionary:
	return _placed_blocks
