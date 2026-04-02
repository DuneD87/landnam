# mirror_plane_visual.gd
class_name MirrorPlaneVisual
extends Node3D

const PLANE_SIZE := 10.0
const AXIS_COLORS := {
	BuildingSystem.MirrorAxis.X: Color(1.0, 0.2, 0.2, 0.18),
	BuildingSystem.MirrorAxis.Y: Color(0.2, 1.0, 0.2, 0.18),
	BuildingSystem.MirrorAxis.Z: Color(0.2, 0.4, 1.0, 0.18),
}
const AXIS_LINE_COLORS := {
	BuildingSystem.MirrorAxis.X: Color(1.0, 0.3, 0.3, 0.3),
	BuildingSystem.MirrorAxis.Y: Color(0.3, 1.0, 0.3, 0.3),
	BuildingSystem.MirrorAxis.Z: Color(0.3, 0.5, 1.0, 0.3),
}

var _plane_mesh: MeshInstance3D
var _border_mesh: MeshInstance3D
var _plane_material: StandardMaterial3D
var _border_material: StandardMaterial3D
var _current_axis: BuildingSystem.MirrorAxis = BuildingSystem.MirrorAxis.NONE


func _ready() -> void:
	_create_plane()
	_create_border()
	visible = false


func _create_plane() -> void:
	_plane_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(PLANE_SIZE, PLANE_SIZE)
	_plane_mesh.mesh = quad
	_plane_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_plane_material = StandardMaterial3D.new()
	_plane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plane_material.no_depth_test = true
	_plane_material.render_priority = 5
	_plane_material.albedo_color = Color(1, 1, 1, 0.15)
	_plane_mesh.material_override = _plane_material

	add_child(_plane_mesh)


func _create_border() -> void:
	_border_mesh = MeshInstance3D.new()
	_border_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_border_material = StandardMaterial3D.new()
	_border_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_material.no_depth_test = true
	_border_material.render_priority = 5
	_border_material.albedo_color = Color(1, 1, 1, 0.6)

	_border_mesh.material_override = _border_material
	add_child(_border_mesh)
	_update_border_mesh()


func _update_border_mesh() -> void:
	var im := ImmediateMesh.new()
	var half := PLANE_SIZE * 0.5

	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_add_vertex(Vector3(-half, -half, 0))
	im.surface_add_vertex(Vector3(half, -half, 0))
	im.surface_add_vertex(Vector3(half, half, 0))
	im.surface_add_vertex(Vector3(-half, half, 0))
	im.surface_add_vertex(Vector3(-half, -half, 0))
	im.surface_end()

	# Línia central horitzontal
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3(-half, 0, 0))
	im.surface_add_vertex(Vector3(half, 0, 0))
	im.surface_end()

	# Línia central vertical
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3(0, -half, 0))
	im.surface_add_vertex(Vector3(0, half, 0))
	im.surface_end()

	_border_mesh.mesh = im


func show_plane(center: Vector3, grid_basis: Basis, axis: BuildingSystem.MirrorAxis) -> void:
	if axis == BuildingSystem.MirrorAxis.NONE:
		visible = false
		return

	_current_axis = axis
	global_position = center

	# Orientar el pla segons l'eix dins la basis de la grid
	var plane_basis: Basis
	match axis:
		BuildingSystem.MirrorAxis.X:
			# Pla YZ — normal apunta a X local
			plane_basis = grid_basis * Basis(
				Vector3(0, 0, 1),
				Vector3(0, 1, 0),
				Vector3(1, 0, 0)
			)
		BuildingSystem.MirrorAxis.Y:
			# Pla XZ — normal apunta a Y local
			plane_basis = grid_basis * Basis(
				Vector3(1, 0, 0),
				Vector3(0, 0, 1),
				Vector3(0, 1, 0)
			)
		BuildingSystem.MirrorAxis.Z:
			# Pla XY — normal apunta a Z local (per defecte del QuadMesh)
			plane_basis = grid_basis

	global_transform.basis = plane_basis

	# Colors per eix
	_plane_material.albedo_color = AXIS_COLORS.get(axis, Color(1, 1, 1, 0.15))
	_border_material.albedo_color = AXIS_LINE_COLORS.get(axis, Color(1, 1, 1, 0.6))

	visible = true


func hide_plane() -> void:
	visible = false
