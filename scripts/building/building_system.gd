class_name BuildingSystem
extends Node3D
const CELL_SIZES: Array[float] = [0.25, 0.5, 1.0, 2.0]

signal build_mode_changed(active: bool)
signal selected_block_changed(block_data: BlockData)
signal rotation_changed()
signal cell_size_changed(new_size: float)

@export var current_planet: Node3D = null
@export var cell_size: float = 1.0
@export var max_build_distance: float = 8.0

var current_rotation_basis: Basis = Basis.IDENTITY
var build_mode: bool = false
var selected_block_id: int = 0
var cell_size_index: int = 2  # default 1.0
var current_rotation: Vector3i = Vector3i.ZERO

var _player: Node3D = null

func _ready() -> void:
	selected_block_id = BlockDatabase.BLOCK_CUBE_ID
	_player = get_parent() as Node3D
	if not _player:
		push_warning("[BuildingSystem] El padre no es un Node3D.")
		
func get_selected_block() -> BlockData:
	return BlockDatabase.get_block(selected_block_id)
	
func select_next_block() -> void:
	var ids: Array[int] = BlockDatabase.get_all_ids()
	var idx := ids.find(selected_block_id)
	selected_block_id = ids[(idx + 1) % ids.size()]
	current_rotation_basis = Basis.IDENTITY
	selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))

func select_previous_block() -> void:
	var ids: Array[int] = BlockDatabase.get_all_ids()
	var idx := ids.find(selected_block_id)
	selected_block_id = ids[(idx - 1 + ids.size()) % ids.size()]
	current_rotation_basis = Basis.IDENTITY
	selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))

func select_block(block_id: int) -> void:
	if BlockDatabase.get_block(block_id):
		selected_block_id = block_id
		current_rotation_basis = Basis.IDENTITY
		selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))

func rotate_block_x() -> void:
	if _can_rotate():
		current_rotation_basis *= Basis(Vector3.RIGHT, deg_to_rad(90.0))
		_snap_rotation()
		rotation_changed.emit()

func rotate_block_y() -> void:
	if _can_rotate():
		current_rotation_basis *= Basis(Vector3.UP, deg_to_rad(90.0))
		_snap_rotation()
		rotation_changed.emit()

func rotate_block_z() -> void:
	if _can_rotate():
		current_rotation_basis *= Basis(Vector3.BACK, deg_to_rad(90.0))
		_snap_rotation()
		rotation_changed.emit()

func get_rotation_basis() -> Basis:
	if not _can_rotate():
		return Basis.IDENTITY
	return current_rotation_basis

func _can_rotate() -> bool:
	var bd := get_selected_block()
	return bd != null and bd.can_rotate

func _snap_rotation() -> void:
	for i in 3:
		for j in 3:
			current_rotation_basis[i][j] = roundf(current_rotation_basis[i][j])

func increase_cell_size() -> void:
	if cell_size_index < CELL_SIZES.size() - 1:
		cell_size_index += 1
		cell_size = CELL_SIZES[cell_size_index]
		cell_size_changed.emit(cell_size)

func decrease_cell_size() -> void:
	if cell_size_index > 0:
		cell_size_index -= 1
		cell_size = CELL_SIZES[cell_size_index]
		cell_size_changed.emit(cell_size)

func toggle_build_mode() -> void:
	build_mode = !build_mode
	build_mode_changed.emit(build_mode)

func set_build_mode(active: bool) -> void:
	if build_mode != active:
		build_mode = active
		build_mode_changed.emit(build_mode)

func get_player() -> Node3D:
	return _player

func get_player_basis() -> Basis:
	if _player:
		return _player.global_transform.basis.orthonormalized()
	return Basis.IDENTITY
