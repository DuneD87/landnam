@tool
class_name HideSailVisual
extends Node3D

## Aparejo a medida: mástil, verga, cabos y paño de pieles cosidas.
## La deformación del paño corre en GPU; no se reconstruye ninguna malla al navegar.
var _rig: Node3D
var _lower_yard: MeshInstance3D
var _cloth: ShaderMaterial
var _design: Dictionary = SailDesign.LEGACY.duplicate()


func _ready() -> void:
	_build_rig()


func configure(config: Dictionary) -> void:
	var design := SailDesign.normalize(config)
	if design == _design:
		return
	_design = design
	if is_node_ready():
		for child in get_children():
			child.free()
		_build_rig()


func _build_rig() -> void:
	var width: float = _design["width"]
	var height: float = _design["height"]
	var mast: float = _design["mast_height"]
	var yard := mast - 0.6
	var radius := SailDesign.mast_radius(_design)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("60432c")
	wood.roughness = 0.95
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("b49a6d")
	rope.roughness = 1.0
	_pole(self, Vector3.ZERO, Vector3(0, mast, 0), radius, wood)
	for x in [-1.0, 1.0]:
		_pole(self, Vector3(x * clampf(width * 0.25, 0.3, 2.0), 0.08, 0.5), Vector3(0, mast - 0.2, 0), 0.016, rope)
	_rig = Node3D.new()
	add_child(_rig)
	_pole(_rig, Vector3(-width * 0.5 - 0.2, yard + 0.05, 0.08), Vector3(width * 0.5 + 0.2, yard + 0.05, 0.08), radius * 0.5, wood)
	_lower_yard = _pole(_rig, Vector3(-width * 0.5, yard - height, 0.08), Vector3(width * 0.5, yard - height, 0.08), radius * 0.32, wood)
	_cloth = ShaderMaterial.new()
	_cloth.shader = preload("res://shaders/building/hide_sail.gdshader")
	_cloth.set_shader_parameter("yard_height", yard)
	_cloth.set_shader_parameter("cloth_height", height)
	_cloth.set_shader_parameter("cloth_width", width)
	var cloth_mesh := MeshInstance3D.new()
	cloth_mesh.mesh = _make_cloth(_design)
	cloth_mesh.material_override = _cloth
	cloth_mesh.custom_aabb = SailDesign.bounds(_design).grow(minf(width, height) * 0.25)
	_rig.add_child(cloth_mesh)
	for x in [-1.0, 1.0]:
		_pole(_rig, Vector3(x * (width * 0.5 + 0.15), yard + 0.05, 0.08), Vector3(0, mast - 0.12, 0), 0.012, rope)
		_pole(self, Vector3(x * 0.32, 0.12, 0), Vector3(x * 0.32, 0.55, 0), 0.045, wood)


func restore_prop_state(state: Dictionary) -> void:
	configure(SailDesign.from_state(state))
	set_sailing_state(clampf(float(state.get("deployment", 0.0)), 0.0, 1.0), Vector3.ZERO, 0.0)


func set_sailing_state(amount: float, apparent: Vector3, fill: float) -> void:
	if _cloth == null:
		return
	var local_wind := global_basis.inverse() * apparent if is_inside_tree() else apparent
	var angle := atan2(local_wind.x, local_wind.z)
	angle = wrapf(angle, -PI * 0.5, PI * 0.5)
	_rig.rotation.y = lerp_angle(_rig.rotation.y, clampf(angle, -1.1, 1.1), 0.12)
	var rig_wind := _rig.basis.inverse() * local_wind
	_cloth.set_shader_parameter("deployment", amount)
	_cloth.set_shader_parameter("fill", fill if apparent.length_squared() > 0.1 else 0.0)
	_cloth.set_shader_parameter("belly_sign", -1.0 if rig_wind.z < 0.0 else 1.0)
	_cloth.set_shader_parameter("wind_speed", apparent.length())
	_lower_yard.position.y = float(_design["mast_height"]) - 0.6 - float(_design["height"]) * lerpf(0.045, 1.0, amount)


static func _make_cloth(design: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width: float = design["width"]
	var height: float = design["height"]
	var yard: float = design["mast_height"] - 0.6
	var columns := clampi(ceili(width * 6), 8, 64)
	var rows := clampi(ceili(height * 6), 8, 64)
	for y in rows + 1:
		for x in columns + 1:
			var uv := Vector2(float(x) / columns, float(y) / rows)
			st.set_uv(uv)
			st.add_vertex(Vector3((uv.x - 0.5) * width, yard - uv.y * height, 0.08))
	for y in rows:
		for x in columns:
			var a := y * (columns + 1) + x
			for index in [a, a + 1, a + columns + 1, a + 1, a + columns + 2, a + columns + 1]:
				st.add_index(index)
	st.generate_normals()
	return st.commit()


static func _pole(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.height = start.distance_to(end)
	cylinder.top_radius = radius * 0.8
	cylinder.bottom_radius = radius
	cylinder.radial_segments = 8
	var mesh := MeshInstance3D.new()
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = (start + end) * 0.5
	mesh.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	parent.add_child(mesh)
	return mesh
