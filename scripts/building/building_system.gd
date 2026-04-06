class_name BuildingSystem
extends Node3D

const config_ref = preload("res://scripts/config.gd")

const CELL_SIZES: Array[float] = [0.25, 0.5, 1.0, 2.0]
enum MirrorAxis { NONE, X, Y, Z }
enum ActionMode { BUILD, DESTROY }

signal build_mode_changed(active: bool)
signal selected_block_changed(block_data: BlockData)
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
var mirror_grid: PlanetGrid = null
var _mirror_active: bool = false

var build_materials: Array[BuildMaterial] = []
var _block_material_items: Array[ItemData] = []
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
var _target_grid: GridBase = null
var _target_grid_pos: Vector3i = Vector3i.ZERO
var _can_place: bool = false
var _can_afford: bool = false
var _is_aiming_at_block: bool = false
var _has_target: bool = false
var _cached_grid_for_placement: GridBase = null
var _hit_grid_for_alignment: GridBase = null
var current_action_mode: ActionMode = ActionMode.BUILD

func _generate_block_material_items() -> void:
	_block_material_items.clear()

	for mat in build_materials:
		for block_id in BlockDatabase.get_all_ids():
			var block := BlockDatabase.get_block(block_id)
			var item := ItemData.new()
			item.id = StringName("block_%s_%s" % [block.block_name, mat.material_id])
			item.display_name = "%s %s" % [mat.display_name, block.block_name.capitalize()]
			item.description = block.block_description
			item.category = ItemData.Category.BLOCK
			item.block_id = block.block_id
			item.build_material_id = mat.material_id
			item.surface_material = mat.surface_material
			item.stackable = false
			item.max_stack = 1

			# Generar icona dinàmica
			var icon := await _icon_generator.generate_icon(block.mesh, mat.surface_material)
			if icon:
				item.icon = icon
				# També actualitzar BlockData si no té icona encara
				if not block.preview_icon:
					block.preview_icon = icon

			_block_material_items.append(item)

	print("[BuildingSystem] Generated %d block+material items with icons." % _block_material_items.size())


## Retorna diccionari agrupat: { material_id: { "display_name": String, "items": Array[ItemData] } }
func get_block_items_by_material() -> Dictionary:
	var result := {}
	for mat in build_materials:
		result[mat.material_id] = {
			"display_name": mat.display_name,
			"items": [] as Array[ItemData]
		}
	for item in _block_material_items:
		if result.has(item.build_material_id):
			result[item.build_material_id]["items"].append(item)
	return result


func set_material_by_id(mat_id: String) -> void:
	for i in BlockDatabase.build_materials.size():
		if BlockDatabase.build_materials[i].material_id == mat_id:
			current_material_index = i
			material_changed.emit(get_current_material())
			return

func _register_default_materials() -> void:
	var stone := BuildMaterial.new()
	stone.material_id = "stone"
	stone.display_name = "Stone"
	stone.item = config_ref.get_item(&"stone_01")
	stone.base_cost = 1
	stone.surface_material = stone.item.surface_material
	build_materials.append(stone)

	var wood := BuildMaterial.new()
	wood.material_id = "wood"
	wood.display_name = "Wood"
	wood.item = config_ref.get_item(&"wood_01")
	wood.base_cost = 1
	wood.surface_material = wood.item.surface_material
	build_materials.append(wood)

	print("[BuildingSystem] Registered %d materials." % build_materials.size())
	
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

	_generate_block_material_items()


func get_current_material() -> BuildMaterial:
	return BlockDatabase.get_material_at(current_material_index)

func cycle_material() -> void:
	if BlockDatabase.get_material_count() <= 1:
		return
	current_material_index = (current_material_index + 1) % BlockDatabase.get_material_count()
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
	
	# Limpiamos los efectos visuales inmediatamente al cambiar de modo
	clear_target()
	action_mode_changed.emit(current_action_mode)
	print("[BuildingSystem] Modo: ", "CONSTRUIR" if current_action_mode == ActionMode.BUILD else "ELIMINAR")

func execute_primary_action(ray_hit: Dictionary) -> void:
	if current_action_mode == ActionMode.BUILD:
		try_place_block()
	else:
		try_remove_block(ray_hit)

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
	_is_aiming_at_block = hit_collider.has_meta("grid_id") or (hit_collider is DynamicGridBody and hit_collider.has_meta("grid_id"))
	if _is_aiming_at_block:
		_process_aim_at_block(hit_collider, hit_normal, hit_pos)
		
		var hit_grid := GridManager.get_grid_for_block(hit_collider as Node3D)
		if not hit_grid and hit_collider is DynamicGridBody:
			hit_grid = GridManager.get_grid_for_block(hit_collider)
		
		if hit_grid and _build_preview:
			if current_action_mode == ActionMode.DESTROY:
				var grid_pos := _resolve_grid_pos(hit_collider, hit_grid, hit_pos, hit_normal)
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
		_process_aim_at_terrain(hit_normal, hit_pos)
		if _build_preview:
			_build_preview.hide_highlight()

	if _player and _player.global_position.distance_to(_target_world_pos) > max_build_distance:
		_can_place = false

	_can_afford = can_afford_block()
	_cached_grid_for_placement = _target_grid

	if _build_preview:
		# Mostrar Ghost Block SOLO en modo construcción
		if current_action_mode == ActionMode.BUILD:
			var is_valid := _can_place and _can_afford
			_build_preview.update_preview(_target_world_pos, _target_basis, is_valid, ray_hit)
		else:
			_build_preview.hide_preview()


func clear_target() -> void:
	_has_target = false
	_can_place = false
	_can_afford = false
	if _build_preview:
		_build_preview.hide_preview()
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

	var block_transform := (hit_collider as Node3D).global_transform
	var block_basis := block_transform.basis
	var hit_grid_pos := _resolve_grid_pos(hit_collider as Node3D, hit_grid, hit_pos, hit_normal)
	var hit_cell := hit_grid.cell_size
	var target_cell := cell_size

	var hit_rot_basis: Basis
	if hit_collider.has_meta("rotation_basis"):
		hit_rot_basis = hit_collider.get_meta("rotation_basis")
	else:
		var block_info := hit_grid.get_block(hit_grid_pos)
		hit_rot_basis = block_info.get("rotation_basis", Basis.IDENTITY)

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

func _process_cross_size_placement(hit_grid: PlanetGrid, hit_grid_pos: Vector3i, hit_cell: float, target_cell: float,
	grid_face: Vector3i, hit_pos: Vector3, planet: Node3D) -> void:
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

	# Posición mundo (calculada en espacio de hit_grid, que es correcto)
	var snapped_local := hit_grid.origin_local + hit_grid.basis_local * target_continuous
	_target_world_pos = planet.global_transform * snapped_local
	_target_basis = hit_grid.get_basis_world()

	# Buscar grid alineada al MISMO origin que hit_grid
	_target_grid = GridManager.find_aligned_grid(planet, target_cell, hit_grid)

	# Guardar referencia para que try_place_block cree grid alineada si no existe
	_hit_grid_for_alignment = hit_grid

	if _target_grid:
		# Re-snap es seguro porque comparten origin → no hay offset
		_target_grid_pos = _target_grid.world_to_grid(_target_world_pos)
		_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
	else:
		# Grid se creará al colocar; calcular grid_pos en espacio de hit_grid
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
		# Buscar grid que esté cerca Y alineada con el player
		_target_grid = GridManager.find_nearest_grid(planet, adjusted_pos, cell_size,player_basis, true)

	if _target_grid:
		_target_grid_pos = _target_grid.world_to_grid(adjusted_pos)
		_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
		_target_basis = _target_grid.get_basis_world()
		_can_place = not _target_grid.has_block(_target_grid_pos)
	else:
		# No hay grid compatible → se creará una nueva al colocar
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
	var block := grid.place_block(_target_grid_pos, block_data, current_rotation_basis, place_transform, mat_id, m_data)

	if not block:
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

	var hit_collider := ray_hit.get("collider") as Node3D
	if not hit_collider:
		return false

	var grid := GridManager.get_grid_for_block(hit_collider)
	if not grid:
		return false

	var grid_pos := _resolve_grid_pos(hit_collider, grid, ray_hit["position"], ray_hit["normal"])

	if not grid.has_block(grid_pos):
		return false

	var data := grid.remove_block(grid_pos)
	_refund_block(data, grid.cell_size)

	# Mirror remove
	if _mirror_active and mirror_axis != MirrorAxis.NONE and mirror_grid \
	   and (grid == mirror_grid or _basis_compatible(grid.get_basis_world(), mirror_grid.get_basis_world())):
		var mirror_pos := _get_mirror_pos(grid_pos, grid)
		if mirror_pos != grid_pos and grid.has_block(mirror_pos):
			data = grid.remove_block(mirror_pos)
			_refund_block(data, grid.cell_size)

	return true

func _refund_block(block_data: Dictionary, block_cell_size: float) -> void:
	if not _inventory:
		return

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

## Toggle simetria on/off. Si s'activa, fixa el centre al bloc apuntat.
func toggle_symmetry(ray_hit: Dictionary) -> void:
	if _mirror_active:
		# Desactivar
		_mirror_active = false
		mirror_axis = MirrorAxis.NONE
		mirror_grid = null
		_mirror_visual.hide_plane()
		mirror_changed.emit()
		print("[Mirror] Disabled")
	else:
		# Activar: necessitem un bloc com a centre
		if ray_hit.is_empty():
			print("[Mirror] Aim at a block to set mirror center")
			return

		var hit_collider := ray_hit.get("collider") as Node3D
		if not hit_collider or not hit_collider.has_meta("grid_pos"):
			print("[Mirror] Aim at a placed block")
			return

		var grid := GridManager.get_grid_for_block(hit_collider)
		if not grid:
			return

		# Fixar centre
		var grid_pos: Vector3i = hit_collider.get_meta("grid_pos")
		var block_cell := grid.cell_size
		var half := Vector3.ONE * block_cell * 0.5
		var grid_space_center := Vector3(grid_pos) * block_cell + half
		var local_pos: Vector3 = grid.origin_local + grid.basis_local * grid_space_center
		mirror_center_world = grid.planet_node.global_transform * local_pos

		mirror_grid = grid
		mirror_axis = MirrorAxis.X  # per defecte comença amb X
		_mirror_active = true
		_update_mirror_visual()
		mirror_changed.emit()
		print("[Mirror] Enabled at %s, axis: X" % mirror_center_world)


## Cicla entre eixos X → Y → Z (només si simetria activa)
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


## Cridar des de toggle_build_mode i set_build_mode per netejar visual
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

	# Centro del bloque en mundo
	var corner_world := grid.grid_to_world(grid_pos)
	var center_world := corner_world + grid_basis * (Vector3.ONE * s * 0.5)

	# Reflejar centro alrededor de mirror_center_world en ejes locales de la grid
	var diff := grid_basis.inverse() * (center_world - mirror_center_world)
	match mirror_axis:
		MirrorAxis.X: diff.x = -diff.x
		MirrorAxis.Y: diff.y = -diff.y
		MirrorAxis.Z: diff.z = -diff.z

	# Reconstruir posición mundo del centro reflejado → esquina → grid pos
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
	var result := mirror_b * rot_basis   # M·R, det = -1
	for i in 3:
		for j in 3:
			result[i][j] = roundf(result[i][j])
	return result
	
func _get_mirror_rotation(rot_basis: Basis) -> Basis:
	# Espejamos invirtiendo el eje correspondiente
	var scale := Vector3.ONE
	match mirror_axis:
		MirrorAxis.X: scale.x = -1.0
		MirrorAxis.Y: scale.y = -1.0
		MirrorAxis.Z: scale.z = -1.0

	var mirror_b := Basis.from_scale(scale)
	var mirrored := mirror_b * rot_basis * mirror_b

	# Re-snap a valores enteros para evitar drift
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
		# Cross-size: permitir si comparten basis (están alineadas)
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
	
## Resuelve grid_pos desde un collider. Para estático lee meta, para dinámico calcula desde hit.
func _resolve_grid_pos(hit_collider: Node3D, grid: GridBase, hit_pos: Vector3, hit_normal: Vector3) -> Vector3i:
	if hit_collider.has_meta("grid_pos"):
		return hit_collider.get_meta("grid_pos")
	# Dinámico: probe hacia dentro del bloque
	var probe := hit_pos - hit_normal * (grid.cell_size * 0.1)
	return grid.world_to_grid(probe)
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
