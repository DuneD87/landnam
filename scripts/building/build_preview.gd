class_name BuildPreview
extends Node3D

## Ghost visual del modo construcción (sin input ni lógica de colocación). BuildingSystem llama
## a update_preview() / hide_preview() cada frame.

@export var ghost_color_valid: Color = Color(0.3, 0.8, 1.0, 0.35)
@export var ghost_color_invalid: Color = Color(1.0, 0.2, 0.2, 0.35)

var _building_system: BuildingSystem = null
var _ghost_node: Node3D = null
var _ghost_mesh_instance: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null

var _mirror_ghost_node: Node3D = null
var _mirror_ghost_mesh: MeshInstance3D = null

var _prop_ghost: Node3D = null
var _prop_ghost_material: StandardMaterial3D = null

var _highlight_node: Node3D = null
var _highlight_mesh: MeshInstance3D = null

var _mirror_highlight_node: Node3D = null
var _mirror_highlight_mesh: MeshInstance3D = null
var _naval_hint: Label

func setup(building_system: BuildingSystem) -> void:
	_building_system = building_system
	_setup_ghost()
	_setup_mirror_ghost()
	_setup_highlight()

	_building_system.selected_block_changed.connect(_on_block_changed)
	_building_system.placeable_changed.connect(_on_placeable_changed)
	_building_system.build_mode_changed.connect(_on_build_mode_changed)
	_building_system.rotation_changed.connect(_on_ghost_mesh_dirty)
	_building_system.cell_size_changed.connect(_on_cell_size_changed)
	_building_system.material_changed.connect(_on_material_changed)
	_building_system.mirror_changed.connect(_on_mirror_changed)
	_building_system.naval_piece_changed.connect(_refresh_ghost_mesh)
	var hud := CanvasLayer.new()
	add_child(hud)
	_naval_hint = Label.new()
	_naval_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_naval_hint.offset_left = -650
	_naval_hint.offset_right = 650
	_naval_hint.offset_top = -200
	_naval_hint.offset_bottom = -120
	_naval_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_naval_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_naval_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_naval_hint.add_theme_constant_override("shadow_outline_size", 4)
	_naval_hint.visible = false
	hud.add_child(_naval_hint)

	_ghost_node.visible = false


func _setup_mirror_ghost() -> void:
	_mirror_ghost_node = Node3D.new()
	_mirror_ghost_node.name = "MirrorGhost"

	_mirror_ghost_mesh = MeshInstance3D.new()
	_mirror_ghost_mesh.name = "MirrorGhostMesh"

	var mirror_mat := StandardMaterial3D.new()
	mirror_mat.render_priority = 5
	mirror_mat.albedo_color = Color(0.8, 0.6, 1.0, 0.3)
	mirror_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mirror_mat.no_depth_test = false
	mirror_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mirror_ghost_mesh.material_override = mirror_mat

	_mirror_ghost_node.add_child(_mirror_ghost_mesh)
	add_child(_mirror_ghost_node)
	_mirror_ghost_node.visible = false


func update_preview(world_pos: Vector3, basis: Basis, can_place: bool, _ray_hit: Dictionary) -> void:
	if not _ghost_node or not _building_system or not _building_system.build_mode:
		return

	_ghost_node.visible = true
	_ghost_node.global_transform = Transform3D(basis, world_pos)
	if _building_system.is_naval_mode():
		_ghost_mesh_instance.transform = Transform3D(Basis.from_scale(Vector3.ONE * _building_system.cell_size), Vector3.ZERO)
		_ghost_material.albedo_color = ghost_color_valid if can_place else ghost_color_invalid
		_update_naval_hint()
		_update_mirror_preview()
		return

	var rot_basis := _building_system.get_rotation_basis()
	var s := _building_system.cell_size
	var cell_center := Vector3(0.5, 0.5, 0.5) * s
	var mesh_offset := Vector3(0.5, 0, 0.5) * s
	var rotated_offset := rot_basis * (mesh_offset - cell_center) + cell_center

	_ghost_mesh_instance.transform = Transform3D(rot_basis, rotated_offset)
	_ghost_mesh_instance.scale = Vector3(s, s, s)
	_ghost_material.albedo_color = ghost_color_valid if can_place else ghost_color_invalid

	_update_mirror_preview()


func _update_mirror_preview() -> void:
	if not _building_system._should_mirror():
		_mirror_ghost_node.visible = false
		return

	var grid: GridBase = _building_system._cached_grid_for_placement
	if not grid:
		grid = _building_system._target_grid
	if not grid:
		grid = _building_system.mirror_grid
	if not grid:
		_mirror_ghost_node.visible = false
		return
	if _building_system.is_naval_mode() and not is_equal_approx(grid.cell_size, _building_system.cell_size):
		_mirror_ghost_node.visible = false
		return

	var mirror_pos := _building_system._get_mirror_pos(_building_system._target_grid_pos, grid)
	var cube_merge := not _building_system._cube_merge_plan.is_empty()
	if cube_merge:
		mirror_pos = _building_system.mirror_position_for_size(_building_system._target_grid_pos, grid)

	if mirror_pos == _building_system._target_grid_pos and not _building_system.is_naval_mode():
		_mirror_ghost_node.visible = false
		return

	var mirror_world := grid.grid_to_world(mirror_pos)
	if cube_merge:
		mirror_world = grid.get_grid_world_transform() * (Vector3(mirror_pos) * _building_system.cell_size)
	if _building_system.is_naval_mode():
		var scale_vec := Vector3.ONE * _building_system.cell_size
		var offset := Vector3.ZERO
		var axis := _building_system._get_mirror_axis_index()
		scale_vec[axis] *= -1.0
		offset[axis] = _building_system.cell_size
		_mirror_ghost_node.global_transform = Transform3D(grid.get_basis_world(), mirror_world)
		_mirror_ghost_mesh.transform = Transform3D(Basis.from_scale(scale_vec), offset)
		_mirror_ghost_mesh.mesh = _ghost_mesh_instance.mesh
		_mirror_ghost_node.visible = true
		return
	var mirror_rot := _building_system._get_mirror_rotation(_building_system.current_rotation_basis)

	var s := _building_system.cell_size
	var cell_center := Vector3(0.5, 0.5, 0.5) * s
	var mesh_offset := Vector3(0.5, 0, 0.5) * s
	var rotated_offset := mirror_rot * (mesh_offset - cell_center) + cell_center

	var grid_basis := grid.get_basis_world()
	_mirror_ghost_node.global_transform = Transform3D(grid_basis, mirror_world)
	_mirror_ghost_mesh.transform = Transform3D(mirror_rot, rotated_offset)

	var scale_vec := Vector3(s, s, s)
	var axis_idx := _building_system._get_mirror_axis_index()
	if axis_idx >= 0:
		scale_vec[axis_idx] = -s
	_mirror_ghost_mesh.scale = scale_vec

	_mirror_ghost_mesh.mesh = _ghost_mesh_instance.mesh

	var can_mirror := not grid.has_block(mirror_pos)
	if cube_merge:
		var plan := _building_system._cube_merger.resolve(grid, mirror_pos, _building_system.cell_size,
			_building_system.get_current_material().material_id, false, true)
		can_mirror = plan.get("allowed", false)
	var mat := _mirror_ghost_mesh.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.3) if can_mirror \
					   else Color(1.0, 0.2, 0.2, 0.3)

	_mirror_ghost_node.visible = true

func hide_preview() -> void:
	if _naval_hint:
		_naval_hint.visible = false
	if _ghost_node:
		_ghost_node.visible = false
	if _mirror_ghost_node:
		_mirror_ghost_node.visible = false


## Reconstruye el ghost del prop instanciando su escena con material fantasma.
func _on_placeable_changed(item: ItemData) -> void:
	if _prop_ghost:
		_prop_ghost.queue_free()
		_prop_ghost = null

	if not item or item.scene_path == "":
		return

	_prop_ghost = (load(item.scene_path) as PackedScene).instantiate() as Node3D
	if _prop_ghost is HideSailVisual:
		_prop_ghost.configure(_building_system.sail_design)
	_prop_ghost_material = StandardMaterial3D.new()
	_prop_ghost_material.render_priority = 5
	_prop_ghost_material.albedo_color = ghost_color_valid
	_prop_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_prop_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_prop_ghost)
	_apply_prop_ghost_material(_prop_ghost)
	_prop_ghost.visible = false


func _apply_prop_ghost_material(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _prop_ghost_material
	elif node is Light3D or node is GPUParticles3D:
		(node as Node3D).visible = false
	for child in node.get_children():
		_apply_prop_ghost_material(child)


func update_prop_preview(world_transform: Transform3D, valid: bool) -> void:
	if not _prop_ghost:
		return
	_prop_ghost.visible = true
	_prop_ghost.global_transform = world_transform
	_prop_ghost_material.albedo_color = ghost_color_valid if valid else ghost_color_invalid
	if _building_system.is_sail_mode():
		var design := _building_system.sail_design
		var cost := SailDesign.cost(design)
		_naval_hint.text = "%s · %s × %s m · %s m²\n%s · %s m\n%s" % [
			tr("ITEM_HIDE_SAIL"), ItemTrait.number(design["width"]), ItemTrait.number(design["height"]),
			ItemTrait.number(SailDesign.area(design)), tr("SAIL_MAST_HEIGHT"), ItemTrait.number(design["mast_height"]),
			tr("BUILD_MENU_FREE") if BuildingSystem.free_build else BuildCost.describe(cost)]
		_naval_hint.visible = true


func hide_prop_preview() -> void:
	if _prop_ghost:
		_prop_ghost.visible = false
	if _naval_hint:
		_naval_hint.visible = false

func _setup_highlight() -> void:
	_highlight_node = Node3D.new()
	_highlight_node.name = "BlockHighlight"

	_highlight_mesh = MeshInstance3D.new()
	_highlight_mesh.mesh = BoxMesh.new()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.1, 0.1, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 5
	_highlight_mesh.material_override = mat

	_highlight_node.add_child(_highlight_mesh)
	add_child(_highlight_node)
	_highlight_node.visible = false
	_mirror_highlight_node = Node3D.new()
	_mirror_highlight_node.name = "MirrorBlockHighlight"
	_mirror_highlight_mesh = MeshInstance3D.new()
	_mirror_highlight_mesh.mesh = BoxMesh.new()

	var mirror_mat := StandardMaterial3D.new()
	mirror_mat.albedo_color = Color(0.5, 0.1, 0.1, 0.5)
	mirror_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mirror_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mirror_highlight_mesh.material_override = mirror_mat

	_mirror_highlight_node.add_child(_mirror_highlight_mesh)
	add_child(_mirror_highlight_node)
	_mirror_highlight_node.visible = false

func show_highlight(cell_world_pos: Vector3, grid_basis: Basis, cell_size: float) -> void:
	if not _highlight_node: return
	_highlight_node.global_transform = Transform3D(grid_basis, cell_world_pos)
	_highlight_mesh.position = Vector3(0.5, 0.5, 0.5) * cell_size
	_highlight_mesh.scale = Vector3.ONE * cell_size * 1.02
	_highlight_node.visible = true

func show_mirror_highlight(cell_world_pos: Vector3, grid_basis: Basis, cell_size: float) -> void:
	if not _mirror_highlight_node: return
	_mirror_highlight_node.global_transform = Transform3D(grid_basis, cell_world_pos)
	_mirror_highlight_mesh.position = Vector3(0.5, 0.5, 0.5) * cell_size
	_mirror_highlight_mesh.scale = Vector3.ONE * cell_size * 1.02
	_mirror_highlight_node.visible = true

func hide_highlight() -> void:
	if _highlight_node: _highlight_node.visible = false
	if _mirror_highlight_node: _mirror_highlight_node.visible = false

func hide_mirror_highlight() -> void:
	if _mirror_highlight_node: _mirror_highlight_node.visible = false

func _on_mirror_changed() -> void:
	if not _building_system._mirror_active:
		_mirror_ghost_node.visible = false

func _on_material_changed(_material: BuildMaterial) -> void:
	_refresh_ghost_mesh()

func _on_cell_size_changed(_new_size: float) -> void:
	_refresh_ghost_mesh()

func _on_block_changed(_block_data: BlockData) -> void:
	_refresh_ghost_mesh()

func _on_ghost_mesh_dirty() -> void:
	_refresh_ghost_mesh()

func _on_build_mode_changed(active: bool) -> void:
	if _ghost_node:
		_ghost_node.visible = active and not _building_system.is_prop_mode()
	if _mirror_ghost_node and not active:
		_mirror_ghost_node.visible = false
	if not active:
		hide_prop_preview()
	if active:
		_refresh_ghost_mesh()


func _setup_ghost() -> void:
	_ghost_node = Node3D.new()
	_ghost_node.name = "GhostBlock"

	_ghost_mesh_instance = MeshInstance3D.new()
	_ghost_mesh_instance.name = "GhostMesh"

	_ghost_material = StandardMaterial3D.new()
	_ghost_material.render_priority = 5
	_ghost_material.albedo_color = ghost_color_valid
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.no_depth_test = false
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mesh_instance.material_override = _ghost_material

	_ghost_node.add_child(_ghost_mesh_instance)
	add_child(_ghost_node)
	_refresh_ghost_mesh()


func _refresh_ghost_mesh() -> void:
	if not _building_system:
		return
	if _naval_hint:
		_naval_hint.visible = false
	if _building_system.is_naval_mode():
		_ghost_mesh_instance.mesh = ChunkMeshBuilder.build_mesh(_building_system.get_naval_blocks(), 1.0, Transform3D.IDENTITY)
		return
	var block_data := _building_system.get_selected_block()
	var mat := _building_system.get_current_material()
	if block_data:
		_ghost_mesh_instance.mesh = block_data.for_material(mat.material_id if mat else "").mesh
		var s := _building_system.cell_size
		_ghost_mesh_instance.scale = Vector3(s, s, s)

	if mat and mat.preview_color != Color.WHITE:
		_ghost_material.albedo_color.r = mat.preview_color.r
		_ghost_material.albedo_color.g = mat.preview_color.g
		_ghost_material.albedo_color.b = mat.preview_color.b


func _update_naval_hint() -> void:
	var size := Vector3(_building_system.naval_size) * _building_system.cell_size
	var mat := _building_system.get_current_material()
	var count := _building_system.get_naval_plan().size()
	var cost := count * mat.get_cost_for_size(_building_system.cell_size)
	var price := tr("BUILD_MENU_FREE") if BuildingSystem.free_build else "%d %s" % [cost, mat.item.get_display_name().to_lower()]
	_naval_hint.text = "%s · %s × %s × %s m\n%s · %s\n%s" % [
		tr(NavalPiece.NAME_KEYS[_building_system.naval_kind]), ItemTrait.number(size.x),
		ItemTrait.number(size.y), ItemTrait.number(size.z),
		tr("NAVAL_THICKNESS_VALUE") % ItemTrait.number(_building_system.cell_size), price, tr("NAVAL_PLACE_HINT")]
	_naval_hint.visible = true
