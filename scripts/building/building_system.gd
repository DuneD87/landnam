class_name BuildingSystem
extends Node3D

## Sistema de construcción: gestiona el modo build (targeting por raycast, colocación y borrado
## de bloques, rotación, tamaño de celda, materiales/coste y simetría de espejo), delegando el
## almacenamiento en GridManager y las grids. Los bloques se ponen y se quitan con el martillo en
## la mano; un colocable elegido en la barra (antorcha) solo se pone.

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
signal recent_blocks_changed()
signal naval_piece_changed()

## Bloques recientes que recuerda el menú de bloques.
const RECENT_LIMIT := 8

## Construir gratis (consola: freebuild): ni bloques, ni colocables, ni blueprints gastan nada, y
## quitarlos tampoco devuelve nada (si no, sería una fuente de material infinita).
static var free_build := false

@export var current_planet: Node3D = null
@export var cell_size: float = 1.0
@export var max_build_distance: float = 8.0

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
## Últimos bloque+material elegidos en el menú, el más reciente primero.
var recent_blocks: Array[ItemData] = []

var naval_kind: int = -1
var naval_size := NavalPiece.DEFAULT_SIZE
var naval_profile := NavalPiece.Profile.ROUND
var _naval_source: Dictionary = {}
var _naval_rotated: Dictionary = {}
var _naval_rotation := Basis.IDENTITY
var _naval_item: ItemData
var _naval_check_left := 0.0
var _naval_space := false
var _naval_grid_bounds := {}
var _cube_merger := NavalCubeMerge.new()
var _cube_merge_plan := {}

## Cambia el material de construcción activo. Un id que no case (bloque genérico, sin material)
## solía dejar puesto el anterior, y el bloque salía del material elegido la vez anterior aunque
## el icono del hotbar dijera otra cosa; ahora cae al primero, con el que se pinta ese icono.
func set_material_by_id(mat_id: String) -> void:
	for i in BlockDatabase.build_materials.size():
		if BlockDatabase.build_materials[i].material_id == mat_id:
			current_material_index = i
			material_changed.emit(get_current_material())
			return
	if mat_id != "":
		push_warning("[BuildingSystem] Material de construcción desconocido: '%s'." % mat_id)
	current_material_index = 0
	material_changed.emit(get_current_material())

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


## El item del bloque elegido con el material activo (su icono y su nombre, para la UI).
func get_selected_block_item() -> ItemData:
	if is_naval_mode():
		return _naval_item
	var mat := get_current_material()
	var item := BlockDatabase.get_block_material_item(selected_block_id, mat.material_id if mat else "")
	return item if item else BlockDatabase.get_block_item(selected_block_id)

## Elige un bloque+material del menú: el martillo lo pone desde ahora y vuelve al modo poner.
func pick_block(item: ItemData) -> void:
	select_block(item.block_id)
	set_material_by_id(item.build_material_id)
	set_action_mode(ActionMode.BUILD)
	recent_blocks.erase(item)
	recent_blocks.push_front(item)
	if recent_blocks.size() > RECENT_LIMIT:
		recent_blocks.resize(RECENT_LIMIT)
	recent_blocks_changed.emit()


func select_block(block_id: int) -> void:
	if BlockDatabase.get_block(block_id):
		naval_kind = -1
		selected_block_id = block_id
		current_rotation_basis = Basis.IDENTITY
		if selected_placeable:
			select_placeable(null)
		selected_block_changed.emit(BlockDatabase.get_block(selected_block_id))


func is_prop_mode() -> bool:
	return selected_placeable != null


func is_naval_mode() -> bool:
	return naval_kind >= 0


func pick_naval_piece(kind: int, size: Vector3i, profile: int = NavalPiece.Profile.ROUND,
	icon: Texture2D = null) -> void:
	if kind < NavalPiece.Kind.BOW or kind > NavalPiece.Kind.STERN:
		return
	select_block(BlockDatabase.BLOCK_CUBE_ID)
	set_material_by_id("wood")
	naval_kind = kind
	naval_size = NavalPiece.clamp_size(size)
	naval_profile = profile
	_naval_source = NavalPiece.generate(kind, naval_size, profile)
	_naval_rotated = {}
	_naval_item = ItemData.new()
	_naval_item.display_name = NavalPiece.NAME_KEYS[kind]
	_naval_item.category = ItemData.Category.BLOCK
	_naval_item.block_id = BlockDatabase.BLOCK_CUBE_ID
	_naval_item.build_material_id = "wood"
	_naval_item.icon = icon
	set_action_mode(ActionMode.BUILD)
	clear_target()
	naval_piece_changed.emit()


func get_naval_blocks() -> Dictionary:
	if _naval_rotated.is_empty() or _naval_rotation != current_rotation_basis:
		_naval_rotation = current_rotation_basis
		_naval_rotated = NavalPiece.rotated(_naval_source, naval_size, current_rotation_basis)
	return _naval_rotated


## Plan completo, incluida la simetría. Las celdas repetidas sobre el plano solo se pagan una vez.
func get_naval_plan() -> Dictionary:
	var plan := {}
	for cell: Vector3i in get_naval_blocks():
		plan[_target_grid_pos + cell] = _naval_rotated[cell]
	var reference := _target_grid if _target_grid else _hit_grid_for_alignment
	if reference and is_equal_approx(reference.cell_size, cell_size) and _should_mirror():
		var mirror_origin := _get_mirror_pos(_target_grid_pos, reference)
		var axis := _get_mirror_axis_index()
		for cell: Vector3i in get_naval_blocks():
			var reflected := cell
			reflected[axis] = -reflected[axis]
			var info: Dictionary = _naval_rotated[cell].duplicate()
			info["mirrored"] = true
			info["mirror_axis"] = axis
			info["rotation_basis"] = _get_mirror_rotation(info["rotation_basis"])
			var mirrored_cell := mirror_origin + reflected
			if plan.has(mirrored_cell):
				# Dos recortes distintos dentro de una celda exigirían una unión booleana.
				# Se rechaza ese solapamiento en vez de perder una mitad de la geometría.
				if not NavalHullMesh.same_shape(plan[mirrored_cell], info):
					return {}
			else:
				plan[mirrored_cell] = info
	return plan


## Selecciona el item placeable activo (null para volver al modo bloques).
func select_placeable(item: ItemData) -> void:
	if item and is_naval_mode():
		naval_kind = -1
		naval_piece_changed.emit()
	selected_placeable = item
	_has_prop_target = false
	if item:
		set_action_mode(ActionMode.BUILD)
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
	if is_naval_mode():
		return true
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


func set_cell_size_index(index: int) -> void:
	index = clampi(index, 0, CELL_SIZES.size() - 1)
	if index != cell_size_index:
		cell_size_index = index
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
	set_action_mode(ActionMode.DESTROY if current_action_mode == ActionMode.BUILD else ActionMode.BUILD)


## Poner o quitar. Con un colocable en la mano siempre es poner: quitar es cosa del martillo.
func set_action_mode(mode: ActionMode) -> void:
	if is_prop_mode():
		mode = ActionMode.BUILD
	if mode == current_action_mode:
		return
	current_action_mode = mode
	clear_target()
	action_mode_changed.emit(current_action_mode)

func execute_primary_action(ray_hit: Dictionary) -> void:
	if current_action_mode == ActionMode.BUILD:
		try_place_block()
	else:
		try_remove_block(ray_hit)


func get_player_basis() -> Basis:
	if _player:
		return _player.global_transform.basis.orthonormalized()
	return Basis.IDENTITY


func can_afford_block(block_data: BlockData = null) -> bool:
	if not _inventory or free_build:
		return true

	if is_prop_mode():
		return _inventory.get_item_count(selected_placeable) >= 1 or _equipped_matches_placeable()

	var mat := get_current_material()
	if not mat or not mat.item:
		return true

	var cost := mat.get_cost_for_size(cell_size)
	if is_naval_mode():
		cost *= get_naval_plan().size()
	return _inventory.get_item_count(mat.item) >= cost


func _consume_block_cost(block_data: BlockData) -> bool:
	if not _inventory or free_build:
		return true

	var mat := get_current_material()
	if not mat or not mat.item:
		return true

	var cost := mat.get_cost_for_size(cell_size)
	if _inventory.get_item_count(mat.item) < cost:
		return false

	_inventory.remove_item(mat.item, cost)
	return true


## Procesa el raycast del jugador cada frame en modo build: resuelve objetivo y actualiza el preview.
func process_raycast(hit_collider: Object, hit_normal: Vector3, hit_pos: Vector3, ray_hit: Dictionary) -> void:
	_has_target = true
	_cube_merge_plan = {}

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

	if _is_normal_cube() and current_action_mode == ActionMode.BUILD:
		var reference := _target_grid if _target_grid else _hit_grid_for_alignment
		if reference:
			_cube_merge_plan = _cube_merger.resolve(reference, _target_grid_pos, cell_size, get_current_material().material_id)
			if not _cube_merge_plan.is_empty():
				_can_place = _cube_merge_plan["allowed"]
	if _player and _player.global_position.distance_to(_target_world_pos) > max_build_distance:
		_can_place = false

	_cached_grid_for_placement = _target_grid
	if is_naval_mode() and current_action_mode == ActionMode.BUILD and _can_place:
		_naval_check_left -= get_process_delta_time()
		if _naval_check_left <= 0.0:
			_naval_check_left = 0.15
			_naval_space = naval_has_space(get_naval_plan(), _target_grid)
		_can_place = _naval_space
	_can_afford = can_afford_block()

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
	_cube_merge_plan = {}
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
	if _is_normal_cube() and NavalCubeMerge.is_hull(hit_grid.get_block(hit_grid_pos)) \
		and current_action_mode == ActionMode.BUILD:
		# Una cara curva puede quedar dentro de su celda: apuntar al hueco real permite
		# rellenar esa misma celda en vez de saltarse un bloque entero.
		var local := hit_grid.get_grid_world_transform().affine_inverse() * (hit_pos + hit_normal * 0.001)
		_target_grid_pos = Vector3i((local / cell_size).floor())
		_target_basis = hit_grid.get_basis_world()
		_target_world_pos = hit_grid.get_grid_world_transform() * (Vector3(_target_grid_pos) * cell_size)
		_target_grid = GridManager.find_aligned_grid(planet, cell_size, hit_grid)
		_hit_grid_for_alignment = hit_grid
		_can_place = true
		return

	if is_equal_approx(target_cell, hit_cell):
		_target_grid_pos = hit_grid_pos + grid_face
		_target_grid = hit_grid
		_target_world_pos = _target_grid.grid_to_world(_target_grid_pos)
		_target_basis = _target_grid.get_basis_world()
		_can_place = not _target_grid.has_block(_target_grid_pos)
	else:
		_process_cross_size_placement(hit_grid, hit_grid_pos, hit_cell, target_cell, grid_face, hit_pos, planet)
	if is_naval_mode() and current_action_mode == ActionMode.BUILD:
		_align_naval_target(hit_grid, hit_grid_pos, grid_face)


## La esquina del módulo queda fuera de la cara apuntada también al construir hacia -X/-Y/-Z.
## En un extremo de casco del mismo ancho se reconoce el suelo y se alinean fondo y costados.
func _align_naval_target(hit_grid: GridBase, hit_cell: Vector3i, face: Vector3i) -> void:
	var size := NavalPiece.rotated_size(naval_size, current_rotation_basis)
	var offset := Vector3i.ZERO
	for axis in 3:
		if face[axis] < 0:
			offset[axis] = 1 - size[axis]
	var length_axis := current_rotation_basis.z.abs().max_axis_index()
	var width_axis := current_rotation_basis.x.abs().max_axis_index()
	if face[length_axis] != 0 and is_equal_approx(hit_grid.cell_size, cell_size) \
		and current_rotation_basis.y.is_equal_approx(Vector3.UP):
		var low := Vector3i(2147483647, 2147483647, 2147483647)
		var high := -low
		for cell: Vector3i in hit_grid.get_all_blocks():
			if cell[length_axis] != hit_cell[length_axis]:
				continue
			low = low.min(cell)
			high = high.max(cell)
		if high[width_axis] - low[width_axis] + 1 == size[width_axis]:
			offset[width_axis] = low[width_axis] - _target_grid_pos[width_axis]
			offset.y = low.y - _target_grid_pos.y
	_target_grid_pos += offset
	_target_world_pos += _target_basis * (Vector3(offset) * cell_size)
	_can_place = true

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
		_target_grid_pos = Vector3i.ZERO
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
	if is_naval_mode():
		return _try_place_naval()

	if not _can_place or not _has_target:
		return false
	if not _can_afford:
		return false
	if _is_normal_cube():
		var reference := _target_grid if _target_grid else _hit_grid_for_alignment
		if reference:
			var plan := _cube_merger.resolve(reference, _target_grid_pos, cell_size, get_current_material().material_id, true)
			if not plan.is_empty():
				return _try_place_merged_cube(reference, plan)

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

	# Plano: lo coloca el jugador local, y en tercera persona el punto de construccion queda a
	# distancia de camara y se apagaria solo por alejar la vista.
	AudioManager.play_material_flat(&"block_place", _sound_material_for(block_data, mat))

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


func _is_normal_cube() -> bool:
	return not is_naval_mode() and not is_prop_mode() and selected_block_id == BlockDatabase.BLOCK_CUBE_ID


func mirror_position_for_size(position: Vector3i, reference: GridBase) -> Vector3i:
	var center := reference.get_grid_world_transform().affine_inverse() * mirror_center_world
	var axis := _get_mirror_axis_index()
	var reflected := position
	reflected[axis] = roundi(2.0 * center[axis] / cell_size - 1.0 - position[axis])
	return reflected


func _try_place_merged_cube(reference: GridBase, plan: Dictionary) -> bool:
	if not plan["allowed"]:
		return false
	var position := _target_grid_pos
	var will_mirror := _should_mirror()
	var reflected := mirror_position_for_size(position, reference) if will_mirror else position
	if not _place_cube_part(reference, position, plan):
		return false
	if will_mirror and reflected != position:
		var mirror_plan := _cube_merger.resolve(reference, reflected, cell_size, get_current_material().material_id, true, true)
		if mirror_plan.get("allowed", false):
			_place_cube_part(reference, reflected, mirror_plan)
	AudioManager.play_material_flat(&"block_place", get_current_material().sound_material)
	clear_target()
	return true


func _place_cube_part(reference: GridBase, position: Vector3i, plan: Dictionary) -> bool:
	var mat := get_current_material()
	if not _consume_block_cost(get_selected_block()):
		return false
	var destination: GridBase = plan.get("grid")
	var created := destination == null
	if created:
		destination = GridManager.create_grid_aligned(current_planet, reference, cell_size)
	destination.mesh_materials[mat.material_id] = mat.surface_material
	var info: Dictionary = plan["info"]
	var block := BlockDatabase.get_block(int(info["block_id"]))
	var world := Transform3D(destination.get_basis_world(), destination.grid_to_world(position))
	if not destination.place_block(position, block, Basis.IDENTITY, world, mat.material_id, info):
		if _inventory and not free_build:
			_give(mat.item, mat.get_cost_for_size(cell_size))
		if created:
			GridManager.remove_grid(destination.grid_id)
		return false
	return true


## Comprueba todo el volumen construido, incluidas otras grids y tamaños de celda. Solo la
## madera ocupa espacio: el interior del módulo admite cubiertas, cofres y construcciones.
func naval_has_space(plan: Dictionary, grid: GridBase) -> bool:
	if plan.is_empty():
		return false
	var reference := grid if grid else _hit_grid_for_alignment
	var transform_world := reference.get_grid_world_transform() if reference else Transform3D(_target_basis, _target_world_pos)
	var minimum := Vector3.INF
	var maximum := -Vector3.INF
	for cell: Vector3i in plan:
		minimum = minimum.min(Vector3(cell) * cell_size)
		maximum = maximum.max(Vector3(cell + Vector3i.ONE) * cell_size)
	var plan_bounds := AABB(minimum, maximum - minimum)
	for other: GridBase in GridManager.get_grids_for_planet(current_planet):
		if other.get_block_count() == 0:
			continue
		if other == grid:
			for cell: Vector3i in plan:
				if grid.has_block(cell):
					return false
			continue
		var to_other := other.get_grid_world_transform().affine_inverse() * transform_world
		if not (to_other * plan_bounds).intersects(_naval_bounds(other)):
			continue
		for cell: Vector3i in plan:
			var box: AABB = to_other * AABB(Vector3(cell) * cell_size, Vector3.ONE * cell_size)
			var low := Vector3i(((box.position + Vector3.ONE * 0.001) / other.cell_size).floor())
			var high := Vector3i(((box.end - Vector3.ONE * 0.001) / other.cell_size).floor())
			for x in range(low.x, high.x + 1):
				for y in range(low.y, high.y + 1):
					for z in range(low.z, high.z + 1):
						if other.has_block(Vector3i(x, y, z)):
							return false
	return true


func _naval_bounds(grid: GridBase) -> AABB:
	var cached: Array = _naval_grid_bounds.get(grid.grid_id, [])
	if cached.is_empty() or cached[0] != grid.edit_version:
		var minimum := Vector3.INF
		var maximum := -Vector3.INF
		for cell: Vector3i in grid.get_all_blocks():
			minimum = minimum.min(Vector3(cell) * grid.cell_size)
			maximum = maximum.max(Vector3(cell + Vector3i.ONE) * grid.cell_size)
		cached = [grid.edit_version, AABB(minimum, maximum - minimum)]
		_naval_grid_bounds[grid.grid_id] = cached
	return cached[1]


func _try_place_naval() -> bool:
	if not _has_target or not _can_place or not current_planet:
		return false
	# Revalidación completa al confirmar: ni el fantasma ni la cuenta del frame anterior pagan.
	var grid := _target_grid
	var plan := get_naval_plan()
	if not naval_has_space(plan, grid):
		return false
	var mat := get_current_material()
	var cost := mat.get_cost_for_size(cell_size) * plan.size()
	if _inventory and not free_build and _inventory.get_item_count(mat.item) < cost:
		return false
	var created := grid == null
	if not grid:
		if _hit_grid_for_alignment:
			grid = GridManager.create_grid_aligned(current_planet, _hit_grid_for_alignment, cell_size)
		else:
			grid = GridManager.create_grid_exact(current_planet, _target_world_pos, _target_basis, cell_size)
			# Sin grid previa el plan está en coordenadas locales al fantasma.
			_target_grid_pos = Vector3i.ZERO
	if _inventory and not free_build:
		_inventory.remove_item(mat.item, cost)
	grid.mesh_materials[mat.material_id] = mat.surface_material
	grid.begin_bulk_edit()
	var placed: Array[Vector3i] = []
	for cell: Vector3i in plan:
		var info: Dictionary = plan[cell]
		var block := BlockDatabase.get_block(int(info["block_id"]))
		var rotation: Basis = info["rotation_basis"]
		var world := Transform3D(grid.get_basis_world() * rotation, grid.grid_to_world(cell))
		if not grid.place_block(cell, block, rotation, world, mat.material_id, info):
			for previous in placed:
				grid.remove_block(previous)
			grid.end_bulk_edit()
			if _inventory and not free_build:
				_inventory.add_item(mat.item, cost)
			if created:
				GridManager.remove_grid(grid.grid_id)
			return false
		placed.append(cell)
	grid.end_bulk_edit()
	_naval_check_left = 0.0
	AudioManager.play_material_flat(&"block_place", mat.sound_material)
	clear_target()
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
	AudioManager.play_material_flat(&"block_remove", _removed_sound_material(data))

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

	if _inventory and not free_build and _inventory.remove_item(selected_placeable, 1) < 1:
		var consumed_equipped: bool = _equipped_matches_placeable() \
			and _equipped_item_consumer.is_valid() and _equipped_item_consumer.call()
		if not consumed_equipped:
			return false

	var placed := _target_prop_grid.place_prop(_target_prop_cell, _target_prop_face, selected_placeable.id, _target_prop_local)
	if not placed and _inventory and not free_build:
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
	if not _inventory or free_build:
		return
	var item := ItemCatalog.get_item(item_id)
	if item:
		_give(item, 1)

func _refund_block(block_data: Dictionary, block_cell_size: float) -> void:
	if not _inventory or free_build:
		return

	for prop_item_id in block_data.get("detached_props", []):
		_refund_prop_item(prop_item_id)

	var mat_id: String = block_data["material_id"]
	if mat_id == "":
		return

	var build_mat := _find_build_material(mat_id)
	if not build_mat or not build_mat.item:
		return

	# Lo que se recupera va con la vida que le quedaba al bloque. Con devolución íntegra, romper y
	# recolocar era una reparación gratis e instantánea, y encima un bloque a punto de caerse
	# rendía tanto material como uno intacto. Uno sano (hp = 1) devuelve todo, como siempre.
	var cost := build_mat.get_cost_for_size(block_cell_size)
	var hp: float = block_data.get("hp", 1.0)
	var refund := mini(cost, ceili(cost * clampf(hp, 0.0, 1.0)))
	if refund > 0:
		_give(build_mat.item, refund)


## Al inventario; lo que no quepa cae al suelo delante del jugador, en vez de perderse.
func _give(item: ItemData, amount: int) -> void:
	BuildCost.give({item.id: amount}, _inventory, _player, _player_down())


func _player_down() -> Vector3:
	var down: Variant = _player.get("gravity_direction") if _player else null
	return down if down is Vector3 and (down as Vector3).length_squared() > 0.0 else Vector3.DOWN


## Desmonta la construcción entera de [grid_id] (su grupo de grids) como si se quitara bloque a
## bloque: devuelve a cada uno lo que le queda de vida y los colocables enteros (con
## construir gratis, nada). Devuelve lo devuelto.
func dismantle_group(grid_id: String) -> Dictionary:
	var group := GridManager.get_grid_group(grid_id)
	if group.is_empty():
		return {}
	var refund := {} if free_build else BuildCost.of_grids(group, true)
	if _mirror_active and mirror_grid and mirror_grid in group:
		toggle_symmetry({})
	GridManager.remove_grid_group(grid_id)
	BuildCost.give(refund, _inventory, _player, _player_down())
	return refund


## Familia de sonido de un bloque: manda la del propio BlockData (props, bloques fijos) y,
## si no la declara, la del material con el que se construye.
func _sound_material_for(block_data: BlockData, mat: BuildMaterial) -> StringName:
	if block_data and block_data.sound_material != &"":
		return block_data.sound_material
	return mat.sound_material if mat else &""


## Igual, para un bloque ya retirado: el dict de remove_block() solo conserva su material_id.
func _removed_sound_material(block_info: Dictionary) -> StringName:
	var mat := _find_build_material(block_info.get("material_id", ""))
	return mat.sound_material if mat else &""


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


## Grid a la que pertenece el collider apuntado, o null si no apuntas a una construcción.
func get_aimed_grid(ray_hit: Dictionary) -> GridBase:
	if ray_hit.is_empty():
		return null

	var hit := ray_hit.get("collider") as Node3D
	if not hit:
		return null

	if hit.has_meta("grid_id"):
		return GridManager.get_grid(hit.get_meta("grid_id"))

	var parent := hit.get_parent() as Node3D
	if parent and parent.has_meta("grid_id"):
		return GridManager.get_grid(parent.get_meta("grid_id"))

	return null


## Guarda en disco el grupo de grids al que pertenece grid_id. Devuelve el nº de bloques
## guardados, o -1 si el grupo estaba vacío o falló la escritura.
func save_grid_blueprint(grid_id: String, blueprint_name: String) -> int:
	var group := GridManager.get_grid_group(grid_id)
	if group.is_empty():
		return -1

	var data := GridBlueprint.capture(group)
	if data.is_empty():
		return -1

	if not GridBlueprint.save_to_disk(blueprint_name, data):
		return -1

	print("[BuildingSystem] Blueprint '%s' guardado (%d grids, %d bloques)" % [
		blueprint_name, (data["grids"] as Array).size(), data["block_count"]])
	return int(data["block_count"])


## Genera un casco con forma de barco frente al jugador y lo convierte a grid dinámica, con
## las dimensiones dadas en bloques (largo/ancho/alto). Ejes de grid: +Z proa, -Z popa,
## X manga, Y altura. La forma viene del afinado en punta a 45° y el rocker de quilla, con
## slopes en los escalones del costado. Con hollow, solo la cáscara (fondo, costados y
## cubierta) más mamparos transversales que dividen la bodega en `compartments` camarotes
## estancos, y entrepuentes horizontales que parten cada camarote en `decks` plantas.
func debug_spawn_ship(hollow: bool = false, compartments: int = 10,
	length: int = 120, width: int = 30, height: int = 26, decks: int = 1) -> void:

	var planet := current_planet
	if not planet or not _player:
		return

	var cube := BlockDatabase.get_block(BlockDatabase.BLOCK_CUBE_ID)
	var slope := BlockDatabase.get_block(BlockDatabase.BLOCK_SLOPE_ID)
	if not cube or not slope:
		return

	var half_len := maxi(3, length / 2)      # media eslora (a lo largo de Z)
	var half_beam := maxi(1, width / 2)      # media manga máxima, en la cuaderna maestra (X)
	var deck_y := maxi(1, height - 1)        # altura de la cubierta (casco de y=0 a deck_y)

	var basis_world := get_player_basis()
	var origin_world: Vector3 = _player.global_position \
		- basis_world.z * (half_len + 20.0) + basis_world.y * (deck_y * 0.5 + 6.0)
	var grid := GridManager.create_grid(planet, origin_world, basis_world, 1.0)
	current_material_index = 1
	var mat := get_current_material()
	var mat_id := mat.material_id if mat else ""
	if mat and mat.surface_material and not grid.mesh_materials.has(mat_id):
		grid.mesh_materials[mat_id] = mat.surface_material

	var grid_basis := grid.get_basis_world()
	var base_cell := grid.world_to_grid(origin_world)

	var bulkhead_zs: Dictionary = {}
	if hollow and compartments > 1:
		var spacing := float(2 * half_len) / float(compartments)
		for i in range(1, compartments):
			bulkhead_zs[int(round(-half_len + i * spacing))] = true

	# Alturas de los entrepuentes: reparto uniforme entre la quilla y la cubierta, sin repetir
	# ninguna de las dos. Si no cabe una planta por nivel, el set queda como quepa.
	var deck_ys: Dictionary = {}
	if hollow and decks > 1:
		var deck_spacing := float(deck_y) / float(decks)
		for i in range(1, decks):
			var level := int(round(i * deck_spacing))
			if level > 0 and level < deck_y:
				deck_ys[level] = true

	var t0 := Time.get_ticks_msec()
	grid.begin_bulk_edit()

	for z in range(-half_len, half_len + 1):
		var hw := _ship_half_width(z, half_len, half_beam)
		if hw < 0:
			continue
		var floor_y := _ship_floor(z, half_len, deck_y)

		# En hollow se salta el interior (celda con los 6 vecinos dentro del sólido), salvo en
		# las estaciones de mamparo y en las alturas de entrepuente, que se rellenan enteras
		# como pared estanca y como suelo de la planta de encima.
		for x in range(-hw, hw + 1):
			for y in range(floor_y, deck_y + 1):
				if hollow and not bulkhead_zs.has(z) and not deck_ys.has(y) \
					and _ship_is_solid(x + 1, y, z, half_len, half_beam, deck_y) \
					and _ship_is_solid(x - 1, y, z, half_len, half_beam, deck_y) \
					and _ship_is_solid(x, y + 1, z, half_len, half_beam, deck_y) \
					and _ship_is_solid(x, y - 1, z, half_len, half_beam, deck_y) \
					and _ship_is_solid(x, y, z + 1, half_len, half_beam, deck_y) \
					and _ship_is_solid(x, y, z - 1, half_len, half_beam, deck_y):
					continue
				_ship_place(grid, cube, base_cell + Vector3i(x, y, z), Basis.IDENTITY, grid_basis, mat_id)

	_ship_fill_side_steps(grid, slope, base_cell, half_len, half_beam, deck_y, grid_basis, mat_id)

	var t1 := Time.get_ticks_msec()
	grid.end_bulk_edit()
	var t2 := Time.get_ticks_msec()

	var block_count := grid.get_block_count()
	GridManager.convert_to_dynamic(grid.grid_id)
	var t3 := Time.get_ticks_msec()

	print("[ShipTest] %d bloques | nodos+colocación: %d ms | mesh: %d ms | conversión a dinámica: %d ms" % [
		block_count, t1 - t0, t2 - t1, t3 - t2])


## Coloca un bloque del barco componiendo la rotación en el world_transform igual que
## try_place_block (basis = grid_basis * rot), para que colisión y mallado coincidan.
func _ship_place(grid: GridBase, block_data: BlockData, gp: Vector3i, rot: Basis, grid_basis: Basis, mat_id: String) -> void:
	var xform := Transform3D(grid_basis * rot, grid.grid_to_world(gp))
	grid.place_block(gp, block_data, rot, xform, mat_id)


## Media manga del casco en la estación z: manga máxima en el cuerpo central y afinado a 45°
## (1 celda por estación) hacia los extremos, de modo que los slopes del costado encajen
## borde con borde en una pared diagonal continua: en punta hacia proa (+Z) y hasta un
## espejo estrecho en popa (-Z).
## true si la celda (coordenadas de grid relativas a base_cell) cae dentro del sólido del casco.
func _ship_is_solid(x: int, y: int, z: int, half_len: int, half_beam: int, deck_y: int) -> bool:
	if absi(z) > half_len:
		return false
	var hw := _ship_half_width(z, half_len, half_beam)
	if hw < 0 or absi(x) > hw:
		return false
	return y >= _ship_floor(z, half_len, deck_y) and y <= deck_y


func _ship_half_width(z: int, half_len: int, half_beam: int) -> int:
	var bow_hw := half_len - z         # 0 en la punta de proa, +1 por estación hacia popa
	var stern_hw := z + half_len + 2   # espejo de 2 celdas en popa, +1 por estación hacia proa
	return mini(half_beam, mini(bow_hw, stern_hw))


## Altura del fondo del casco (rocker de quilla): sube hacia proa y popa. La subida se limita
## a la altura disponible para que en cascos bajos siga quedando bodega en los extremos.
func _ship_floor(z: int, half_len: int, deck_y: int) -> int:
	var mid := int(round(half_len * 0.55))
	var az := absi(z)
	if az <= mid or half_len <= mid:
		return 0
	var rise := float(clampi(deck_y - 1, 0, 3))
	var frac := float(az - mid) / float(half_len - mid)
	return int(round(lerpf(0.0, rise, frac)))


## Suaviza la V en planta: donde la manga se estrecha entre estaciones contiguas, completa el
## escalón del costado con slopes tumbados sobre su lado (la hipotenusa queda como pared
## vertical diagonal a 45°), apilados de fondo a cubierta en la estación estrecha del par.
func _ship_fill_side_steps(grid: GridBase, slope: BlockData, base_cell: Vector3i, half_len: int,
	half_beam: int, deck_y: int, grid_basis: Basis, mat_id: String) -> void:

	# Slope girado 90° sobre Z (roll): las caras triangulares quedan horizontales y el macizo
	# ocupa media celda en diagonal. El sufijo indica hacia dónde miran sus dos caras completas,
	# que deben quedar pegadas al casco (hacia crujía y hacia la estación ancha del par).
	var roll := Basis(Vector3.BACK, deg_to_rad(90.0))
	var yaw_180 := Basis(Vector3.UP, deg_to_rad(180.0))
	var solid_px_pz := roll
	var solid_nx_pz := roll.inverse()
	var solid_nx_nz := yaw_180 * solid_px_pz
	var solid_px_nz := yaw_180 * solid_nx_pz

	for z in range(-half_len, half_len):
		var hw_near := _ship_half_width(z, half_len, half_beam)
		var hw_far := _ship_half_width(z + 1, half_len, half_beam)
		if hw_near == hw_far:
			continue

		# El relleno va en la estación estrecha del par, en la columna x que la ancha ocupa de
		# más, con la diagonal del slope mirando hacia fuera del casco.
		var narrows_forward := hw_far < hw_near   # proa: la estación ancha queda hacia -Z
		var narrow_z := z + 1 if narrows_forward else z
		var wide := maxi(hw_near, hw_far)
		var floor_y := _ship_floor(narrow_z, half_len, deck_y)

		var starboard_rot := solid_nx_nz if narrows_forward else solid_nx_pz
		var port_rot := solid_px_nz if narrows_forward else solid_px_pz
		for y in range(floor_y, deck_y + 1):
			_ship_place(grid, slope, base_cell + Vector3i(wide, y, narrow_z), starboard_rot, grid_basis, mat_id)
			_ship_place(grid, slope, base_cell + Vector3i(-wide, y, narrow_z), port_rot, grid_basis, mat_id)


func is_symmetry_active() -> bool:
	return _mirror_active and mirror_axis != MirrorAxis.NONE


## La simetría de la rueda del martillo: sin ella la pone en el bloque apuntado (eje X) y, puesta,
## pasa al siguiente eje; después del Z se quita. false si para ponerla no se apunta a un bloque.
func cycle_symmetry(ray_hit: Dictionary) -> bool:
	if not is_symmetry_active():
		toggle_symmetry(ray_hit)
		return is_symmetry_active()
	if mirror_axis == MirrorAxis.Z:
		toggle_symmetry(ray_hit)
	else:
		switch_symmetry_plane()
	return true


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
