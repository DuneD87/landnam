class_name BuildingSystem
extends Node3D

## Sistema de construcción: gestiona el modo build (targeting por raycast, colocación y borrado
## de bloques, rotación, tamaño de celda, materiales/coste y simetría de espejo), delegando el
## almacenamiento en GridManager y las grids.

const config_ref = preload("res://scripts/config.gd")

const CELL_SIZES: Array[float] = [0.25, 0.5, 1.0, 2.0]
const PROP_WALL_TILT_DEG := 20.0
enum MirrorAxis { NONE, X, Y, Z }
enum ActionMode { BUILD, DESTROY }

signal build_mode_changed(active: bool)
signal selected_block_changed(block_data: BlockData)
signal placeable_changed(item: ItemData)
signal rotation_changed()
signal cell_size_changed(new_size: float)
signal material_changed(material: BuildMaterial)
signal mirror_changed()
signal action_mode_changed(mode: ActionMode)

@export var current_planet: Node3D = null
@export var cell_size: float = 1.0
@export var max_build_distance: float = 8.0

var _icon_generator: BlockIconGenerator
var _mirror_visual: MirrorPlaneVisual = null

var mirror_axis: MirrorAxis = MirrorAxis.NONE
var mirror_center_world: Vector3 = Vector3.ZERO
var mirror_grid: GridBase = null
var _mirror_active: bool = false

var current_material_index: int = 0

var current_rotation_basis: Basis = Basis.IDENTITY
var build_mode: bool = false
var selected_block_id: int = 0
var cell_size_index: int = 2

var _player: Node3D = null
var _build_preview: BuildPreview = null
var _inventory: Inventory = null

var _target_world_pos: Vector3 = Vector3.ZERO
var _target_basis: Basis = Basis.IDENTITY
var _target_grid: GridBase = null
var _target_grid_pos: Vector3i = Vector3i.ZERO
var _can_place: bool = false
var _can_afford: bool = false
var _is_aiming_at_block: bool = false
var _has_target: bool = false

var selected_placeable: ItemData = null
var _equipped_item_getter: Callable = Callable()
var _equipped_item_consumer: Callable = Callable()
var _has_prop_target: bool = false
var _target_prop_grid: GridBase = null
var _target_prop_cell: Vector3i = Vector3i.ZERO
var _target_prop_face: Vector3i = Vector3i.ZERO
var _target_prop_local: Transform3D = Transform3D.IDENTITY
var _target_prop_world: Transform3D = Transform3D.IDENTITY
var _cached_grid_for_placement: GridBase = null
var _hit_grid_for_alignment: GridBase = null
var current_action_mode: ActionMode = ActionMode.BUILD

func set_material_by_id(mat_id: String) -> void:
	for i in BlockDatabase.build_materials.size():
		if BlockDatabase.build_materials[i].material_id == mat_id:
			current_material_index = i
			material_changed.emit(get_current_material())
			return

func _add_mirror_visual_to_scene() -> void:
	get_tree().current_scene.add_child(_mirror_visual)

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
	_mirror_visual = MirrorPlaneVisual.new()
	call_deferred("_add_mirror_visual_to_scene")


func get_current_material() -> BuildMaterial:
	return BlockDatabase.get_material_at(current_material_index)


func get_selected_block() -> BlockData:
	return BlockDatabase.get_block(selected_block_id)

func select_block(block_id: int) -> void:
	if BlockDatabase.get_block(block_id):
		selected_block_id = block_id
		current_rotation_basis = Basis.IDENTITY
		if selected_placeable:
			select_placeable(null)
		selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))


func is_prop_mode() -> bool:
	return selected_placeable != null


## Selecciona el item placeable activo (null para volver al modo bloques).
func select_placeable(item: ItemData) -> void:
	selected_placeable = item
	_has_prop_target = false
	placeable_changed.emit(item)


## Hooks para contar/consumir el item equipado en mano al colocar props (el equipamiento
## saca el item del inventario, así que el inventario solo no basta).
func set_equipped_item_hooks(getter: Callable, consumer: Callable) -> void:
	_equipped_item_getter = getter
	_equipped_item_consumer = consumer


func _equipped_matches_placeable() -> bool:
	if not selected_placeable or not _equipped_item_getter.is_valid():
		return false
	var item: ItemData = _equipped_item_getter.call()
	return item != null and item.id == selected_placeable.id


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
	if is_prop_mode():
		return false
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
	if !build_mode:
		clear_target()
		_on_build_mode_off()


func set_build_mode(active: bool) -> void:
	if build_mode != active:
		build_mode = active
		build_mode_changed.emit(build_mode)
		if not active:
			_on_build_mode_off()

func toggle_action_mode() -> void:
	if current_action_mode == ActionMode.BUILD:
		current_action_mode = ActionMode.DESTROY
	else:
		current_action_mode = ActionMode.BUILD

	clear_target()
	action_mode_changed.emit(current_action_mode)

func execute_primary_action(ray_hit: Dictionary) -> void:
	if current_action_mode == ActionMode.BUILD:
		try_place_block()
	else:
		try_remove_block(ray_hit)


func get_player() -> Node3D:
	return _player

func get_player_basis() -> Basis:
	if _player:
		return _player.global_transform.basis.orthonormalized()
	return Basis.IDENTITY


func can_afford_block(block_data: BlockData = null) -> bool:
	if not _inventory:
		return true

	if is_prop_mode():
		return _inventory.get_item_count(selected_placeable) >= 1 or _equipped_matches_placeable()

	var mat := get_current_material()
	if not mat or not mat.item:
		return true

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


## Procesa el raycast del jugador cada frame en modo build: resuelve objetivo y actualiza el preview.
func process_raycast(hit_collider: Object, hit_normal: Vector3, hit_pos: Vector3, ray_hit: Dictionary) -> void:
	_has_target = true

	var resolved_node := _get_hit_shape_node(ray_hit)
	if not resolved_node:
		resolved_node = hit_collider as Node3D

	_is_aiming_at_block = resolved_node.has_meta("grid_id") and not resolved_node.has_meta("prop_key")
	_has_prop_target = false

	if _is_aiming_at_block:
		if is_prop_mode() and current_action_mode == ActionMode.BUILD:
			_process_aim_prop(resolved_node, hit_normal, hit_pos)
		else:
			_process_aim_at_block(resolved_node, hit_normal, hit_pos)

		var hit_grid := GridManager.get_grid_for_block(resolved_node)
		if hit_grid and _build_preview:
			if current_action_mode == ActionMode.DESTROY:
				var grid_pos := _resolve_grid_pos(resolved_node, hit_grid, hit_pos, hit_normal)
				if hit_grid.has_block(grid_pos):
					var cell_world_pos := hit_grid.grid_to_world(grid_pos)
					var grid_basis := hit_grid.get_basis_world()

					_build_preview.show_highlight(cell_world_pos, grid_basis, hit_grid.cell_size)

					var mirror_shown := false
					if _mirror_active and mirror_axis != MirrorAxis.NONE and mirror_grid \
					   and (hit_grid == mirror_grid or _basis_compatible(hit_grid.get_basis_world(), mirror_grid.get_basis_world())):
						var mirror_pos := _get_mirror_pos(grid_pos, hit_grid)
						if mirror_pos != grid_pos and hit_grid.has_block(mirror_pos):
							var mirror_world_pos := hit_grid.grid_to_world(mirror_pos)
							_build_preview.show_mirror_highlight(mirror_world_pos, grid_basis, hit_grid.cell_size)
							mirror_shown = true

					if not mirror_shown:
						_build_preview.hide_mirror_highlight()
				else:
					_build_preview.hide_highlight()
			else:
				_build_preview.hide_highlight()
	else:
		if is_prop_mode():
			_can_place = false
		else:
			_process_aim_at_terrain(hit_normal, hit_pos)
		if _build_preview:
			_build_preview.hide_highlight()

	if _player and _player.global_position.distance_to(_target_world_pos) > max_build_distance:
		_can_place = false

	_can_afford = can_afford_block()
	_cached_grid_for_placement = _target_grid

	if _build_preview:
		if current_action_mode == ActionMode.BUILD:
			var is_valid := _can_place and _can_afford
			if is_prop_mode():
				_build_preview.hide_preview()
				if _has_prop_target:
					_build_preview.update_prop_preview(_target_prop_world, is_valid)
				else:
					_build_preview.hide_prop_preview()
			else:
				_build_preview.update_preview(_target_world_pos, _target_basis, is_valid, ray_hit)
		else:
			_build_preview.hide_preview()


func clear_target() -> void:
	_has_target = false
	_can_place = false
	_can_afford = false
	_has_prop_target = false
	if _build_preview:
		_build_preview.hide_preview()
		_build_preview.hide_prop_preview()
		_build_preview.hide_highlight()


func _process_aim_at_block(hit_collider: Object, hit_normal: Vector3, hit_pos: Vector3) -> void:
	_hit_grid_for_alignment = null
	var hit_grid := GridManager.get_grid_for_block(hit_collider as Node3D)
	if not hit_grid:
		_can_place = false
		return

	var planet := current_planet
	if not planet:
		_can_place = false
		return

	var hit_grid_pos: Vector3i = _resolve_grid_pos(hit_collider as Node3D, hit_grid, hit_pos, hit_normal)
	var hit_cell := hit_grid.cell_size
	var target_cell := cell_size
	var grid_face := _compute_grid_face(hit_collider as Node3D, hit_grid, hit_normal)

	if is_equal_approx(target_cell, hit_cell):
		_target_grid_pos = hit_grid_pos + grid_face
		_target_grid = hit_grid
		_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
		_target_basis = _target_grid.get_basis_world()
		_can_place = not _target_grid.has_block(_target_grid_pos)
	else:
		_process_cross_size_placement(hit_grid, hit_grid_pos, hit_cell, target_cell, grid_face, hit_pos, planet)

## Cara del bloque impactado, en coordenadas de grid, a partir de la normal del hit.
func _compute_grid_face(hit_collider: Node3D, hit_grid: GridBase, hit_normal: Vector3) -> Vector3i:
	var hit_rot_basis: Basis = hit_collider.get_meta("rotation_basis") if hit_collider.has_meta("rotation_basis") else Basis.IDENTITY

	var block_basis: Basis
	if hit_grid is DynamicPlanetGrid:
		block_basis = hit_grid.get_basis_world() * hit_rot_basis
	else:
		block_basis = hit_collider.global_transform.basis

	var local_normal := block_basis.inverse() * hit_normal
	var abs_n := Vector3(abs(local_normal.x), abs(local_normal.y), abs(local_normal.z))
	var face_dir := Vector3.ZERO
	if abs_n.x >= abs_n.y and abs_n.x >= abs_n.z:
		face_dir.x = 1.0 if local_normal.x > 0 else -1.0
	elif abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		face_dir.y = 1.0 if local_normal.y > 0 else -1.0
	else:
		face_dir.z = 1.0 if local_normal.z > 0 else -1.0

	var grid_face_f := hit_rot_basis * face_dir
	return Vector3i(
		roundi(grid_face_f.x),
		roundi(grid_face_f.y),
		roundi(grid_face_f.z)
	)


## Targeting del modo prop: ancla el prop al centro de la cara apuntada, vertical en suelo
## e inclinado PROP_WALL_TILT_DEG grados hacia fuera en paredes.
func _process_aim_prop(hit_collider: Node3D, hit_normal: Vector3, hit_pos: Vector3) -> void:
	_hit_grid_for_alignment = null
	_can_place = false

	var hit_grid := GridManager.get_grid_for_block(hit_collider)
	if not hit_grid:
		return

	var cell := _resolve_grid_pos(hit_collider, hit_grid, hit_pos, hit_normal)
	var face := _compute_grid_face(hit_collider, hit_grid, hit_normal)

	var attach := (Vector3(cell) + Vector3.ONE * 0.5 + Vector3(face) * 0.5) * hit_grid.cell_size

	var prop_basis := Basis.IDENTITY
	var face_allowed := false
	if face.y == 1:
		face_allowed = selected_placeable.placeable_on_floor
	elif face.y == -1:
		face_allowed = selected_placeable.placeable_on_ceiling
		prop_basis = Basis(Vector3.RIGHT, PI)
	else:
		face_allowed = selected_placeable.placeable_on_wall
		var out := Vector3(face)
		var right := Vector3.UP.cross(out).normalized()
		prop_basis = Basis(right, deg_to_rad(PROP_WALL_TILT_DEG)) * Basis(right, Vector3.UP, out)

	_target_prop_grid = hit_grid
	_target_prop_cell = cell
	_target_prop_face = face
	_target_prop_local = Transform3D(prop_basis, attach)
	_target_prop_world = hit_grid.get_grid_world_transform() * _target_prop_local
	_target_world_pos = _target_prop_world.origin
	_has_prop_target = true

	_can_place = face_allowed and not hit_grid.has_prop(cell, face)


func _process_cross_size_placement(hit_grid: GridBase, hit_grid_pos: Vector3i, hit_cell: float, target_cell: float,
	grid_face: Vector3i, hit_pos: Vector3, planet: Node3D) -> void:
	var face_axis: int = 0
	var face_sign: int = 1
	if abs(grid_face.x) > 0:
		face_axis = 0; face_sign = grid_face.x
	elif abs(grid_face.y) > 0:
		face_axis = 1; face_sign = grid_face.y
	else:
		face_axis = 2; face_sign = grid_face.z

	var grid_xform := hit_grid.get_grid_world_transform()
	var grid_inv := grid_xform.affine_inverse()
	var hit_continuous: Vector3 = grid_inv * hit_pos

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

	_target_world_pos = grid_xform * target_continuous
	_target_basis = hit_grid.get_basis_world()

	_target_grid = GridManager.find_aligned_grid(planet, target_cell, hit_grid)
	_hit_grid_for_alignment = hit_grid

	if _target_grid:
		_target_grid_pos = _target_grid.world_to_grid(_target_world_pos)
		_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
	else:
		_target_grid_pos = Vector3i(
			roundi(target_continuous.x / target_cell),
			roundi(target_continuous.y / target_cell),
			roundi(target_continuous.z / target_cell)
		)

	_can_place = true
	if _target_grid and _target_grid.has_block(_target_grid_pos):
		_can_place = false
	if _can_place:
		var overlap_grid := _target_grid if _target_grid else hit_grid
		if GridManager.check_overlap(planet, _target_grid_pos, target_cell, overlap_grid):
			_can_place = false


func _process_aim_at_terrain(hit_normal: Vector3, hit_pos: Vector3) -> void:
	_hit_grid_for_alignment = null
	var player_basis := get_player_basis()
	var adjusted_pos := hit_pos + hit_normal * (cell_size * 0.5)
	var planet := current_planet

	if planet:
		_target_grid = GridManager.find_nearest_grid(planet, adjusted_pos, cell_size,player_basis, true)

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


func try_place_block() -> bool:
	if is_prop_mode():
		return try_place_prop()

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

	if not _consume_block_cost(block_data):
		return false

	var grid := _cached_grid_for_placement
	if not grid:
		var will_mirror := _should_mirror()
		if will_mirror and mirror_grid and is_equal_approx(mirror_grid.cell_size, cell_size):
			grid = mirror_grid
			_target_grid_pos = grid.world_to_grid(_target_world_pos)
		elif _hit_grid_for_alignment:
			grid = GridManager.create_grid_aligned(planet, _hit_grid_for_alignment, cell_size)
			_target_grid_pos = grid.world_to_grid(_target_world_pos)
		else:
			grid = GridManager.create_grid(planet, _target_world_pos, _target_basis, cell_size)
			_target_grid_pos = grid.world_to_grid(_target_world_pos)

	_hit_grid_for_alignment = null

	var mat := get_current_material()
	var mat_id := mat.material_id if mat else ""
	if mat and mat.surface_material and not grid.mesh_materials.has(mat_id):
		grid.mesh_materials[mat_id] = mat.surface_material

	var rot_basis := get_rotation_basis()
	var place_transform := Transform3D(_target_basis * rot_basis, _target_world_pos)

	var m_data := {
		"mirrored": false,
		"mirror_axis": -1
	}
	var placed := grid.place_block(_target_grid_pos, block_data, current_rotation_basis, place_transform, mat_id, m_data)

	if not placed:
		push_error("[BuildingSystem] Failed to place block.")
		return false

	if _should_mirror():
		var mirror_pos := _get_mirror_pos(_target_grid_pos, grid)
		if mirror_pos != _target_grid_pos and not grid.has_block(mirror_pos):
			if _consume_block_cost(block_data):
				var mirror_world := grid.grid_to_world(mirror_pos)
				var mirror_rot := _get_mirror_rotation(current_rotation_basis)
				var mirror_transform := Transform3D(_target_basis * mirror_rot, mirror_world)

				var mirror_info := {
					"mirrored": true,
					"mirror_axis": _get_mirror_axis_index()
				}

				grid.place_block(mirror_pos, block_data, mirror_rot, mirror_transform, mat_id, mirror_info)

	return true


func try_remove_block(ray_hit: Dictionary) -> bool:
	if ray_hit.is_empty():
		return false

	var resolved := _get_hit_shape_node(ray_hit)
	if not resolved:
		return false

	if resolved.has_meta("prop_key"):
		return _try_remove_prop(resolved)

	if not resolved.has_meta("grid_id"):
		return false

	var grid := GridManager.get_grid_for_block(resolved)
	if not grid:
		return false

	var grid_pos := _resolve_grid_pos(resolved, grid, ray_hit["position"], ray_hit["normal"])

	if not grid.has_block(grid_pos):
		return false

	var data := grid.remove_block(grid_pos)
	_refund_block(data, grid.cell_size)

	if _mirror_active and mirror_axis != MirrorAxis.NONE and mirror_grid \
	   and (grid == mirror_grid or _basis_compatible(grid.get_basis_world(), mirror_grid.get_basis_world())):
		var mirror_pos := _get_mirror_pos(grid_pos, grid)
		if mirror_pos != grid_pos and grid.has_block(mirror_pos):
			data = grid.remove_block(mirror_pos)
			_refund_block(data, grid.cell_size)

	return true


## Coloca el prop seleccionado en el objetivo actual, consumiendo 1 unidad del inventario.
func try_place_prop() -> bool:
	if not _can_place or not _has_target or not _has_prop_target:
		return false
	if not _can_afford or not _target_prop_grid:
		return false

	if _inventory and _inventory.remove_item(selected_placeable, 1) < 1:
		var consumed_equipped: bool = _equipped_matches_placeable() \
			and _equipped_item_consumer.is_valid() and _equipped_item_consumer.call()
		if not consumed_equipped:
			return false

	var placed := _target_prop_grid.place_prop(_target_prop_cell, _target_prop_face, selected_placeable.id, _target_prop_local)
	if not placed and _inventory:
		_inventory.add_item(selected_placeable, 1)
	return placed


## Retira el prop apuntado y devuelve su item al inventario.
func _try_remove_prop(prop_node: Node3D) -> bool:
	var grid := GridManager.get_grid(prop_node.get_meta("grid_id"))
	if not grid:
		return false

	var info := grid.remove_prop(prop_node.get_meta("prop_key"))
	if info.is_empty():
		return false

	_refund_prop_item(info["item_id"])
	return true


func _refund_prop_item(item_id: StringName) -> void:
	if not _inventory:
		return
	var item := config_ref.get_item(item_id)
	if item:
		_inventory.add_item(item, 1)

func _refund_block(block_data: Dictionary, block_cell_size: float) -> void:
	if not _inventory:
		return

	for prop_item_id in block_data.get("detached_props", []):
		_refund_prop_item(prop_item_id)

	var mat_id: String = block_data["material_id"]
	if mat_id == "":
		return

	var build_mat := _find_build_material(mat_id)
	if not build_mat or not build_mat.item:
		return

	var cost := build_mat.get_cost_for_size(block_cell_size)
	_inventory.add_item(build_mat.item, cost)


func _find_build_material(mat_id: String) -> BuildMaterial:
	return BlockDatabase.get_material_by_id(mat_id)

func convert_aimed_grid(ray_hit: Dictionary) -> void:
	if ray_hit.is_empty():
		return
	var hit := ray_hit.get("collider") as Node3D
	if not hit:
		return

	var grid_id: String = ""
	if hit.has_meta("grid_id"):
		grid_id = hit.get_meta("grid_id")
	elif hit is DynamicGridBody and hit.has_meta("grid_id"):
		grid_id = hit.get_meta("grid_id")

	if grid_id == "":
		print("[BuildingSystem] No apuntas a un bloque")
		return

	GridManager.convert_to_dynamic(grid_id)

## Caso de prueba extremo: genera una estructura de 8000 bloques (20x20x20) frente al jugador
## y la convierte a grid dinámica, imprimiendo el tiempo de cada fase.
func debug_spawn_stress_grid() -> void:
	var planet := current_planet
	if not planet or not _player:
		return

	var block_data := BlockDatabase.get_block(BlockDatabase.BLOCK_CUBE_ID)
	if not block_data:
		return

	var basis_world := get_player_basis()
	var origin_world: Vector3 = _player.global_position - basis_world.z * 30.0 + basis_world.y * 6.0
	var grid := GridManager.create_grid(planet, origin_world, basis_world, 1.0)
	current_material_index = 1
	var mat := get_current_material()
	var mat_id := mat.material_id if mat else ""
	if mat and mat.surface_material and not grid.mesh_materials.has(mat_id):
		grid.mesh_materials[mat_id] = mat.surface_material

	var grid_basis := grid.get_basis_world()
	var base_cell := grid.world_to_grid(origin_world)

	var t0 := Time.get_ticks_msec()
	grid.begin_bulk_edit()
	for x in range(-1, 1):
		for y in range(2):
			for z in range(-2, 2):
				var grid_pos := base_cell + Vector3i(x, y, z)
				var xform := Transform3D(grid_basis, grid.grid_to_world(grid_pos))
				grid.place_block(grid_pos, block_data, Basis.IDENTITY, xform, mat_id)
	var t1 := Time.get_ticks_msec()
	grid.end_bulk_edit()
	var t2 := Time.get_ticks_msec()

	var block_count := grid.get_block_count()
	GridManager.convert_to_dynamic(grid.grid_id)
	var t3 := Time.get_ticks_msec()

	print("[StressTest] %d bloques | nodos+colocación: %d ms | mesh: %d ms | conversión a dinámica: %d ms" % [
		block_count, t1 - t0, t2 - t1, t3 - t2])


## Activa/desactiva la simetría; al activarla fija el centro en el bloque apuntado.
func toggle_symmetry(ray_hit: Dictionary) -> void:
	if _mirror_active:
		_mirror_active = false
		mirror_axis = MirrorAxis.NONE
		mirror_grid = null
		_mirror_visual.hide_plane()
		mirror_changed.emit()
		print("[Mirror] Disabled")
	else:
		if ray_hit.is_empty():
			print("[Mirror] Aim at a block to set mirror center")
			return

		var resolved := _get_hit_shape_node(ray_hit)
		if not resolved or not resolved.has_meta("grid_id"):
			print("[Mirror] Aim at a placed block")
			return

		var grid := GridManager.get_grid_for_block(resolved)
		if not grid:
			return

		var grid_pos := _resolve_grid_pos(resolved, grid, ray_hit["position"], ray_hit["normal"])
		var block_cell := grid.cell_size
		var half := Vector3.ONE * block_cell * 0.5

		var corner_world := grid.grid_to_world(grid_pos)
		var grid_basis := grid.get_basis_world()
		mirror_center_world = corner_world + grid_basis * half

		mirror_grid = grid
		mirror_axis = MirrorAxis.X
		_mirror_active = true
		_update_mirror_visual()
		mirror_changed.emit()
		print("[Mirror] Enabled at %s, axis: X" % mirror_center_world)


## Cicla el eje de simetría X → Y → Z (solo si la simetría está activa).
func switch_symmetry_plane() -> void:
	if not _mirror_active:
		return

	match mirror_axis:
		MirrorAxis.X:
			mirror_axis = MirrorAxis.Y
		MirrorAxis.Y:
			mirror_axis = MirrorAxis.Z
		MirrorAxis.Z:
			mirror_axis = MirrorAxis.X

	_update_mirror_visual()
	mirror_changed.emit()
	print("[Mirror] Axis: %s" % MirrorAxis.keys()[mirror_axis])


func _update_mirror_visual() -> void:
	if not _mirror_active or mirror_axis == MirrorAxis.NONE or not mirror_grid:
		_mirror_visual.hide_plane()
		return
	var grid_basis := mirror_grid.get_basis_world()
	_mirror_visual.show_plane(mirror_center_world, grid_basis, mirror_axis)


## Limpia el estado y el visual de simetría al salir del modo construcción.
func _on_build_mode_off() -> void:
	_mirror_active = false
	mirror_axis = MirrorAxis.NONE
	mirror_grid = null
	_mirror_visual.hide_plane()


func clear_mirror() -> void:
	mirror_axis = MirrorAxis.NONE
	_mirror_active = false
	mirror_grid = null
	mirror_changed.emit()


func _get_mirror_center_in_grid(grid: PlanetGrid) -> Vector3i:
	return grid.world_to_grid(mirror_center_world)

func _get_mirror_axis_index() -> int:
	match mirror_axis:
		MirrorAxis.X: return 0
		MirrorAxis.Y: return 1
		MirrorAxis.Z: return 2
	return -1

func _get_mirror_pos(grid_pos: Vector3i, grid: GridBase) -> Vector3i:
	var grid_basis := grid.get_basis_world()
	var s := grid.cell_size

	var corner_world := grid.grid_to_world(grid_pos)
	var center_world := corner_world + grid_basis * (Vector3.ONE * s * 0.5)

	var diff := grid_basis.inverse() * (center_world - mirror_center_world)
	match mirror_axis:
		MirrorAxis.X: diff.x = -diff.x
		MirrorAxis.Y: diff.y = -diff.y
		MirrorAxis.Z: diff.z = -diff.z

	var reflected_center := mirror_center_world + grid_basis * diff
	var reflected_corner := reflected_center - grid_basis * (Vector3.ONE * s * 0.5)
	return grid.world_to_grid(reflected_corner)

func _get_mirror_visual_basis(rot_basis: Basis) -> Basis:
	var scale := Vector3.ONE
	match mirror_axis:
		MirrorAxis.X: scale.x = -1.0
		MirrorAxis.Y: scale.y = -1.0
		MirrorAxis.Z: scale.z = -1.0
	var mirror_b := Basis.from_scale(scale)
	var result := mirror_b * rot_basis
	for i in 3:
		for j in 3:
			result[i][j] = roundf(result[i][j])
	return result

func _get_mirror_rotation(rot_basis: Basis) -> Basis:
	var scale := Vector3.ONE
	match mirror_axis:
		MirrorAxis.X: scale.x = -1.0
		MirrorAxis.Y: scale.y = -1.0
		MirrorAxis.Z: scale.z = -1.0

	var mirror_b := Basis.from_scale(scale)
	var mirrored := mirror_b * rot_basis * mirror_b

	for i in 3:
		for j in 3:
			mirrored[i][j] = roundf(mirrored[i][j])
	return mirrored

func _should_mirror() -> bool:
	if not _mirror_active or mirror_axis == MirrorAxis.NONE:
		return false
	if not mirror_grid:
		return false

	var target := _cached_grid_for_placement if _cached_grid_for_placement else _target_grid
	if target:
		if target.grid_id == mirror_grid.grid_id:
			return true
		return _basis_compatible(target.get_basis_world(), mirror_grid.get_basis_world())

	if not current_planet:
		return false
	return _basis_compatible(_target_basis, mirror_grid.get_basis_world())


static func _basis_compatible(a: Basis, b: Basis) -> bool:
	for i in 3:
		if abs(a[i].normalized().dot(b[i].normalized())) < 0.99:
			return false
	return true


func _can_afford_double(block_data: BlockData) -> bool:
	if not _inventory:
		return true

	var mat := get_current_material()
	if not mat or not mat.item:
		return true

	var grid: PlanetGrid = _cached_grid_for_placement
	if not grid:
		grid = _target_grid
	if not grid:
		grid = mirror_grid

	var count := 1
	if grid:
		var mirror_pos := _get_mirror_pos(_target_grid_pos, grid)
		if mirror_pos != _target_grid_pos:
			count = 2

	var cost := mat.get_cost_for_size(cell_size) * count
	return _inventory.get_item_count(mat.item) >= cost

## Resuelve grid_pos desde un collider: meta si el nodo es por-bloque (rampas/esquinas),
## o sondeo geométrico hacia el interior del bloque (cajas de cubos fusionadas).
func _resolve_grid_pos(hit_collider: Node3D, grid: GridBase, hit_pos: Vector3, hit_normal: Vector3) -> Vector3i:
	if hit_collider.has_meta("grid_pos"):
		return hit_collider.get_meta("grid_pos")
	var probe := hit_pos - hit_normal * (grid.cell_size * 0.1)
	return grid.world_to_cell(probe)


## Para DynamicGridBody, obtiene el CollisionShape3D impactado usando el shape index.
func _get_hit_shape_node(ray_hit: Dictionary) -> Node3D:
	var collider := ray_hit.get("collider") as Node3D
	if not collider or not collider is DynamicGridBody:
		return collider
	var shape_idx: int = ray_hit.get("shape", 0)
	var owner_id: int = collider.shape_find_owner(shape_idx)
	var shape_node : Node3D= collider.shape_owner_get_owner(owner_id)

	return shape_node


func _find_sibling(type: Variant) -> Node:
	var par := get_parent()
	if not par:
		return null
	for child in par.get_children():
		if is_instance_of(child, type):
			return child
	return null
