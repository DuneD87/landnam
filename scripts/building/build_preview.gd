class_name BuildPreview
extends Node3D

## Pure visual ghost preview. No input, no placement logic.
## BuildingSystem calls update_preview() / hide_preview() each frame.

@export var ghost_color_valid: Color = Color(0.3, 0.8, 1.0, 0.35)
@export var ghost_color_invalid: Color = Color(1.0, 0.2, 0.2, 0.35)

var _building_system: BuildingSystem = null
var _ghost_node: Node3D = null
var _ghost_mesh_instance: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null

var _mirror_ghost_node: Node3D = null
var _mirror_ghost_mesh: MeshInstance3D = null


func setup(building_system: BuildingSystem) -> void:
	_building_system = building_system
	_setup_ghost()
	_setup_mirror_ghost()
	_building_system.selected_block_changed.connect(_on_block_changed)
	_building_system.build_mode_changed.connect(_on_build_mode_changed)
	_building_system.rotation_changed.connect(_on_ghost_mesh_dirty)
	_building_system.cell_size_changed.connect(_on_cell_size_changed)
	_building_system.material_changed.connect(_on_material_changed)
	_building_system.mirror_changed.connect(_on_mirror_changed)

	_ghost_node.visible = false


func _setup_mirror_ghost() -> void:
	# Nodo raíz independiente del ghost principal
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
	# Hijo de self (BuildPreview), NO de _ghost_node
	add_child(_mirror_ghost_node)
	_mirror_ghost_node.visible = false
# ==========================================================================
#  Public API  (called by BuildingSystem)
# ==========================================================================

func update_preview(world_pos: Vector3, basis: Basis, can_place: bool, _ray_hit: Dictionary) -> void:
	if not _ghost_node or not _building_system or not _building_system.build_mode:
		return

	_ghost_node.visible = true
	_ghost_node.global_transform = Transform3D(basis, world_pos)

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

	var grid: PlanetGrid = _building_system._cached_grid_for_placement
	if not grid:
		grid = _building_system._target_grid
	if not grid:
		grid = _building_system.mirror_grid
	if not grid:
		_mirror_ghost_node.visible = false
		return

	var mirror_pos := _building_system._get_mirror_pos(_building_system._target_grid_pos, grid)

	if mirror_pos == _building_system._target_grid_pos:
		_mirror_ghost_node.visible = false
		return

	var mirror_world := grid.grid_to_world(mirror_pos)
	var mirror_rot := _building_system._get_mirror_rotation(
		_building_system.current_rotation_basis
	)

	var s := _building_system.cell_size
	var cell_center := Vector3(0.5, 0.5, 0.5) * s
	var mesh_offset := Vector3(0.5, 0, 0.5) * s
	var rotated_offset := mirror_rot * (mesh_offset - cell_center) + cell_center

	var grid_basis := grid.get_basis_world()
	_mirror_ghost_node.global_transform = Transform3D(grid_basis, mirror_world)
	_mirror_ghost_mesh.transform = Transform3D(mirror_rot, rotated_offset)

	# ← Escala negativa en el eje mirror para reflejar la mesh visualmente
	var scale_vec := Vector3(s, s, s)
	var axis_idx := _building_system._get_mirror_axis_index()
	if axis_idx >= 0:
		scale_vec[axis_idx] = -s
	_mirror_ghost_mesh.scale = scale_vec

	_mirror_ghost_mesh.mesh = _ghost_mesh_instance.mesh

	var can_mirror := not grid.has_block(mirror_pos)
	var mat := _mirror_ghost_mesh.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.3) if can_mirror \
					   else Color(1.0, 0.2, 0.2, 0.3)

	_mirror_ghost_node.visible = true

func hide_preview() -> void:
	if _ghost_node:
		_ghost_node.visible = false
	if _mirror_ghost_node:
		_mirror_ghost_node.visible = false


# ==========================================================================
#  Signal callbacks
# ==========================================================================
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
		_ghost_node.visible = active
	if _mirror_ghost_node and not active:
		_mirror_ghost_node.visible = false
	if active:
		_refresh_ghost_mesh()


# ==========================================================================
#  Internal
# ==========================================================================

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
	var block_data := _building_system.get_selected_block()
	if block_data:
		_ghost_mesh_instance.mesh = block_data.mesh
		var s := _building_system.cell_size
		_ghost_mesh_instance.scale = Vector3(s, s, s)

	var mat := _building_system.get_current_material()
	if mat and mat.preview_color != Color.WHITE:
		_ghost_material.albedo_color.r = mat.preview_color.r
		_ghost_material.albedo_color.g = mat.preview_color.g
		_ghost_material.albedo_color.b = mat.preview_color.b
