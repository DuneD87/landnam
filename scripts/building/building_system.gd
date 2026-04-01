class_name BuildingSystem
extends Node3D

const config_ref = preload("res://scripts/config.gd")

const CELL_SIZES: Array[float] = [0.25, 0.5, 1.0, 2.0]

signal build_mode_changed(active: bool)
signal selected_block_changed(block_data: BlockData)
signal rotation_changed()
signal cell_size_changed(new_size: float)
signal material_changed(material: BuildMaterial)

@export var current_planet: Node3D = null
@export var cell_size: float = 1.0
@export var max_build_distance: float = 8.0

var build_materials: Array[BuildMaterial] = []
var current_material_index: int = 0

var current_rotation_basis: Basis = Basis.IDENTITY
var build_mode: bool = false
var selected_block_id: int = 0
var cell_size_index: int = 2

var _player: Node3D = null
var _build_preview: BuildPreview = null
var _inventory: Inventory = null

# --- Computed target state (from raycast) ---
var _target_world_pos: Vector3 = Vector3.ZERO
var _target_basis: Basis = Basis.IDENTITY
var _target_grid: PlanetGrid = null
var _target_grid_pos: Vector3i = Vector3i.ZERO
var _can_place: bool = false
var _can_afford: bool = false
var _is_aiming_at_block: bool = false
var _has_target: bool = false

func _register_default_materials() -> void:
	var stone := BuildMaterial.new()
	stone.material_id = "stone"
	stone.display_name = "Stone"
	stone.item = config_ref.get_item(&"stone_01")
	stone.base_cost = 1
	stone.surface_material = stone.item.surface_material
	# ↑ assign your actual material resource here
	build_materials.append(stone)

	var wood := BuildMaterial.new()
	wood.material_id = "wood"
	wood.display_name = "Wood"
	wood.item = config_ref.get_item(&"wood_01")
	wood.base_cost = 1
	wood.surface_material = wood.item.surface_material
	build_materials.append(wood)

	print("[BuildingSystem] Registered %d materials." % build_materials.size())
	
func _ready() -> void:
	selected_block_id = BlockDatabase.BLOCK_CUBE_ID
	_player = get_parent() as Node3D
	if not _player:
		push_warning("[BuildingSystem] Parent is not a Node3D.")

	_build_preview = _find_sibling(BuildPreview) as BuildPreview
	if _build_preview:
		_build_preview.setup(self)
	else:
		push_warning("[BuildingSystem] No BuildPreview sibling found.")

	_inventory = _find_sibling(Inventory) as Inventory
	if not _inventory:
		push_warning("[BuildingSystem] No Inventory sibling found.")
	_register_default_materials()

func get_current_material() -> BuildMaterial:
	if build_materials.is_empty():
		return null
	return build_materials[current_material_index]

func cycle_material() -> void:
	if build_materials.size() <= 1:
		return
	current_material_index = (current_material_index + 1) % build_materials.size()
	material_changed.emit(get_current_material())

# ==========================================================================
#  Block selection
# ==========================================================================

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


# ==========================================================================
#  Rotation
# ==========================================================================

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


# ==========================================================================
#  Cell size
# ==========================================================================

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


# ==========================================================================
#  Build mode
# ==========================================================================

func toggle_build_mode() -> void:
	build_mode = !build_mode
	build_mode_changed.emit(build_mode)

func set_build_mode(active: bool) -> void:
	if build_mode != active:
		build_mode = active
		build_mode_changed.emit(build_mode)


# ==========================================================================
#  Player helpers
# ==========================================================================

func get_player() -> Node3D:
	return _player

func get_player_basis() -> Basis:
	if _player:
		return _player.global_transform.basis.orthonormalized()
	return Basis.IDENTITY


# ==========================================================================
#  Cost / Inventory
# ==========================================================================

func can_afford_block(block_data: BlockData = null) -> bool:
	if not _inventory:
		return true

	var mat := get_current_material()
	if not mat or not mat.item:
		return true  # no material system → free build

	var cost := mat.get_cost_for_size(cell_size)
	return _inventory.get_item_count(mat.item) >= cost


func _consume_block_cost(block_data: BlockData) -> bool:
	if not _inventory:
		return true

	var mat := get_current_material()
	if not mat or not mat.item:
		return true

	var cost := mat.get_cost_for_size(cell_size)
	if _inventory.get_item_count(mat.item) < cost:
		return false

	_inventory.remove_item(mat.item, cost)
	return true


func get_missing_materials(block_data: BlockData = null) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	if not _inventory:
		return missing

	var mat := get_current_material()
	if not mat or not mat.item:
		return missing

	var cost := mat.get_cost_for_size(cell_size)
	var have := _inventory.get_item_count(mat.item)
	if have < cost:
		missing.append({ "item": mat.item, "have": have, "need": cost })
	return missing


# ==========================================================================
#  Raycast processing  (called by Player every frame in build mode)
# ==========================================================================

func process_raycast(hit_collider: Object, hit_normal: Vector3, hit_pos: Vector3, ray_hit: Dictionary) -> void:
	_has_target = true
	_is_aiming_at_block = hit_collider is StaticBody3D and hit_collider.has_meta("grid_id")

	if _is_aiming_at_block:
		_process_aim_at_block(hit_collider, hit_normal, hit_pos)
	else:
		_process_aim_at_terrain(hit_normal, hit_pos)

	# Distance check
	if _player and _player.global_position.distance_to(_target_world_pos) > max_build_distance:
		_can_place = false

	# Affordability check
	_can_afford = can_afford_block()

	# Update preview — valid only if both placement and cost are OK
	if _build_preview:
		var is_valid := _can_place and _can_afford
		_build_preview.update_preview(_target_world_pos, _target_basis, is_valid, ray_hit)


func clear_target() -> void:
	_has_target = false
	_can_place = false
	_can_afford = false
	if _build_preview:
		_build_preview.hide_preview()


func _process_aim_at_block(hit_collider: Object, hit_normal: Vector3, hit_pos: Vector3) -> void:
	var hit_grid := GridManager.get_grid_for_block(hit_collider as Node3D)
	if not hit_grid:
		_can_place = false
		return

	var planet := current_planet
	if not planet:
		_can_place = false
		return

	var block_transform := (hit_collider as Node3D).global_transform
	var block_basis := block_transform.basis
	var hit_grid_pos: Vector3i = hit_collider.get_meta("grid_pos")
	var hit_cell := hit_grid.cell_size
	var target_cell := cell_size

	var local_normal := block_basis.inverse() * hit_normal
	var abs_n := Vector3(abs(local_normal.x), abs(local_normal.y), abs(local_normal.z))
	var face_dir := Vector3.ZERO
	if abs_n.x >= abs_n.y and abs_n.x >= abs_n.z:
		face_dir.x = 1.0 if local_normal.x > 0 else -1.0
	elif abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		face_dir.y = 1.0 if local_normal.y > 0 else -1.0
	else:
		face_dir.z = 1.0 if local_normal.z > 0 else -1.0

	var hit_rot_basis: Basis = hit_collider.get_meta("rotation_basis")
	var grid_face_f := hit_rot_basis * face_dir
	var grid_face := Vector3i(
		roundi(grid_face_f.x),
		roundi(grid_face_f.y),
		roundi(grid_face_f.z)
	)

	if is_equal_approx(target_cell, hit_cell):
		_target_grid_pos = hit_grid_pos + grid_face
		_target_grid = hit_grid
		_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
		_target_basis = _target_grid.get_basis_world()
		_can_place = not _target_grid.has_block(_target_grid_pos)
	else:
		_process_cross_size_placement(hit_grid, hit_grid_pos, hit_cell, target_cell, grid_face, hit_pos, planet)


func _process_cross_size_placement(
	hit_grid: PlanetGrid, hit_grid_pos: Vector3i,
	hit_cell: float, target_cell: float,
	grid_face: Vector3i, hit_pos: Vector3, planet: Node3D
) -> void:
	var face_axis: int = 0
	var face_sign: int = 1
	if abs(grid_face.x) > 0:
		face_axis = 0; face_sign = grid_face.x
	elif abs(grid_face.y) > 0:
		face_axis = 1; face_sign = grid_face.y
	else:
		face_axis = 2; face_sign = grid_face.z

	var planet_inv := planet.global_transform.affine_inverse()
	var hit_local := planet_inv * hit_pos
	var hit_continuous := hit_grid.basis_local.inverse() * (hit_local - hit_grid.origin_local)

	var block_min := Vector3(hit_grid_pos) * hit_cell
	var block_max := block_min + Vector3.ONE * hit_cell

	var target_continuous := Vector3.ZERO
	for i in 3:
		if i == face_axis:
			if face_sign > 0:
				target_continuous[i] = block_max[i]
			else:
				target_continuous[i] = block_min[i] - target_cell
		else:
			target_continuous[i] = floor(hit_continuous[i] / target_cell) * target_cell

	_target_grid_pos = Vector3i(
		roundi(target_continuous.x / target_cell),
		roundi(target_continuous.y / target_cell),
		roundi(target_continuous.z / target_cell)
	)

	var snapped_local := hit_grid.origin_local + hit_grid.basis_local * target_continuous
	_target_world_pos = planet.global_transform * snapped_local
	_target_basis = hit_grid.get_basis_world()
	_target_grid = GridManager.find_nearest_grid(planet, _target_world_pos, target_cell)

	_can_place = true
	if _target_grid and _target_grid.has_block(_target_grid_pos):
		_can_place = false
	if _can_place:
		var overlap_grid := _target_grid if _target_grid else hit_grid
		if GridManager.check_overlap(planet, _target_grid_pos, target_cell, overlap_grid):
			_can_place = false


func _process_aim_at_terrain(hit_normal: Vector3, hit_pos: Vector3) -> void:
	var player_basis := get_player_basis()
	var adjusted_pos := hit_pos + hit_normal * (cell_size * 0.5)
	var planet := current_planet

	if planet:
		_target_grid = GridManager.find_nearest_grid(planet, adjusted_pos, cell_size)

	if _target_grid:
		_target_grid_pos = _target_grid.world_to_grid(adjusted_pos)
		_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
		_target_basis = _target_grid.get_basis_world()
		_can_place = not _target_grid.has_block(_target_grid_pos)
	else:
		_target_basis = player_basis
		var relative := adjusted_pos - (planet.global_position if planet else Vector3.ZERO)
		var local_pos := _target_basis.inverse() * relative
		local_pos.x = snapped(local_pos.x, cell_size)
		local_pos.y = snapped(local_pos.y, cell_size)
		local_pos.z = snapped(local_pos.z, cell_size)
		_target_world_pos = (planet.global_position if planet else Vector3.ZERO) + _target_basis * local_pos
		_can_place = true


# ==========================================================================
#  Actions (called by Player on input)
# ==========================================================================

func try_place_block() -> bool:
	if not _can_place or not _has_target:
		return false
	if not _can_afford:
		return false

	var planet := current_planet
	if not planet:
		return false

	var block_data := get_selected_block()
	if not block_data:
		return false

	# Consume resources first
	if not _consume_block_cost(block_data):
		return false

	var grid := _target_grid
	if not grid:
		grid = GridManager.create_grid(
			planet,
			_target_world_pos,
			_target_basis,
			cell_size
		)
		_target_grid_pos = grid.world_to_grid(_target_world_pos)


	var rot_basis := get_rotation_basis()
	var place_transform := Transform3D(_target_basis * rot_basis, _target_world_pos)

	var mat := get_current_material()
	var mat_id := mat.material_id if mat else ""

	# Registrar el surface material en la grid
	if mat and mat.surface_material and not grid.mesh_materials.has(mat_id):
		grid.mesh_materials[mat_id] = mat.surface_material

	var block := grid.place_block(
		_target_grid_pos, block_data, current_rotation_basis,
		place_transform, mat_id
	)

	if not block:
		push_error("[BuildingSystem] Failed to place block after consuming resources.")
		# TODO: refund materials on failure
		return false

	return true


func try_remove_block(ray_hit: Dictionary) -> bool:
	if ray_hit.is_empty():
		return false

	var hit_collider := ray_hit.get("collider") as Node3D
	if not hit_collider:
		return false

	if not (hit_collider is StaticBody3D and hit_collider.has_meta("grid_id")):
		return false

	var grid := GridManager.get_grid_for_block(hit_collider)
	if not grid:
		return false

	var grid_pos: Vector3i = hit_collider.get_meta("grid_pos")
	# TODO: optionally refund materials to inventory here
	grid.remove_block(grid_pos)
	return true


# ==========================================================================
#  Utility
# ==========================================================================

func _find_sibling(type: Variant) -> Node:
	var par := get_parent()
	if not par:
		return null
	for child in par.get_children():
		if is_instance_of(child, type):
			return child
	return null
