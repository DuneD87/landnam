class_name BuildingSystem
extends Node3D

## Sistema de construcción. Hijo del Player.
## Gestiona el estado del jugador (modo, selección, rotación).
## Delega la colocación real a PlanetGrid vía GridManager.

signal build_mode_changed(active: bool)
signal selected_block_changed(block_data: BlockData)

# ============================================================
#  CONFIGURACIÓN
# ============================================================

## Planeta actual donde está el player.
@export var current_planet: Node3D = null
@export var cell_size: float = 1.0
@export var max_build_distance: float = 8.0

# ============================================================
#  ESTADO
# ============================================================

var build_mode: bool = false
var selected_block_id: int = 0
var current_rotation_step: int = 0

var _player: Node3D = null


# ============================================================
#  LIFECYCLE
# ============================================================

func _ready() -> void:
	selected_block_id = BlockDatabase.BLOCK_CUBE_ID
	_player = get_parent() as Node3D
	if not _player:
		push_warning("[BuildingSystem] El padre no es un Node3D.")


# ============================================================
#  BLOCK SELECTION & ROTATION
# ============================================================

func select_next_block() -> void:
	var ids: Array[int] = BlockDatabase.get_all_ids()
	var idx := ids.find(selected_block_id)
	selected_block_id = ids[(idx + 1) % ids.size()]
	current_rotation_step = 0
	selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))


func select_previous_block() -> void:
	var ids: Array[int] = BlockDatabase.get_all_ids()
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
	var block_data: BlockData = BlockDatabase.get_block(selected_block_id)
	if block_data and block_data.can_rotate:
		current_rotation_step = (current_rotation_step + 1) % block_data.rotation_steps


func get_current_rotation_deg() -> float:
	var block_data: BlockData = BlockDatabase.get_block(selected_block_id)
	if block_data and block_data.can_rotate:
		return block_data.get_rotation_angle_deg() * current_rotation_step
	return 0.0


func get_selected_block() -> BlockData:
	return BlockDatabase.get_block(selected_block_id)


# ============================================================
#  BUILD MODE
# ============================================================

func toggle_build_mode() -> void:
	build_mode = !build_mode
	build_mode_changed.emit(build_mode)


func set_build_mode(active: bool) -> void:
	if build_mode != active:
		build_mode = active
		build_mode_changed.emit(build_mode)


# ============================================================
#  ACCESSORS
# ============================================================

func get_player() -> Node3D:
	return _player


func get_player_basis() -> Basis:
	if _player:
		return _player.global_transform.basis.orthonormalized()
	return Basis.IDENTITY
