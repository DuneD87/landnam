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


func setup(building_system: BuildingSystem) -> void:
	_building_system = building_system
	_setup_ghost()

	_building_system.selected_block_changed.connect(_on_block_changed)
	_building_system.build_mode_changed.connect(_on_build_mode_changed)
	_building_system.rotation_changed.connect(_on_ghost_mesh_dirty)
	_building_system.cell_size_changed.connect(_on_cell_size_changed)

	_ghost_node.visible = false


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


func hide_preview() -> void:
	if _ghost_node:
		_ghost_node.visible = false


# ==========================================================================
#  Signal callbacks
# ==========================================================================

func _on_cell_size_changed(_new_size: float) -> void:
	_refresh_ghost_mesh()

func _on_block_changed(_block_data: BlockData) -> void:
	_refresh_ghost_mesh()

func _on_ghost_mesh_dirty() -> void:
	_refresh_ghost_mesh()

func _on_build_mode_changed(active: bool) -> void:
	if _ghost_node:
		_ghost_node.visible = active
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
