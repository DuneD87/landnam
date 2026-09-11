class_name SimpleBirdModel extends Node3D

const NAMES := ["Gorrión", "Petirrojo", "Herrerillo", "Gaviota", "Pato"]
const PALETTES: Array[Array] = [
	[Color("806448"), Color("d5c3a1"), Color("68503a"), Color("503c2e")],
	[Color("6d7560"), Color("df7033"), Color("6e6f56"), Color("454d43")],
	[Color("559aaf"), Color("e6d461"), Color("4285b1"), Color("265075")],
]
static var _bodies: Dictionary = {}
static var _wings: Dictionary = {}
static var _material: StandardMaterial3D
var left: MeshInstance3D
var right: MeshInstance3D
var body: MeshInstance3D
var _fold: float = 1.0
var _kind: int = 0


func _ready() -> void:
	body = MeshInstance3D.new()
	left = MeshInstance3D.new()
	right = MeshInstance3D.new()
	add_child(body)
	add_child(left)
	add_child(right)
	left.position = Vector3(-0.075, 0.255, 0.0)
	right.position = Vector3(0.075, 0.255, 0.0)
	left.scale.x = -1.0
	set_species(0)
	animate(0.0, false, 1.0)


func set_species(kind: int) -> void:
	_kind = kind
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.roughness = 0.85
	if not _bodies.has(kind):
		_build(kind)
	body.mesh = _bodies[kind]
	left.mesh = _wings[kind]
	right.mesh = _wings[kind]
	for part in [body, left, right]:
		part.material_override = _material
	var wing_origin := Vector3(0.075, 0.255, 0.0)
	if kind >= 3:
		wing_origin = Vector3(0.13, 0.30, 0.04)
	right.position = wing_origin
	left.position = Vector3(-wing_origin.x, wing_origin.y, wing_origin.z)


func animate(time: float, flying: bool, delta: float) -> void:
	_fold = move_toward(_fold, 0.0 if flying else 1.0, delta * 5.0)
	var beat := 10.0 if _kind == 3 else (18.0 if _kind == 4 else 22.0)
	var angle := lerpf(sin(time * beat) * 0.7, -0.10 if _kind >= 3 else -1.16, _fold)
	right.rotation.z = angle
	left.rotation.z = -angle
	# Long water-bird wings fold backwards along the body, above the waterline.
	right.rotation.y = -1.4 * _fold if _kind >= 3 else 0.0
	left.rotation.y = -right.rotation.y
	# A little breathing while resting, without moving the feet.
	body.scale.y = 1.0 + sin(time * 3.0) * 0.008 * _fold


static func _build(kind: int) -> void:
	if kind >= 3:
		_build_water_bird(kind)
		return
	var colors: Array = PALETTES[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_oval(st, Vector3(0, 0.19, 0.015), Vector3(0.20, 0.26, 0.34), colors[0], colors[1])
	_oval(st, Vector3(0, 0.315, -0.105), Vector3(0.175, 0.17, 0.175), colors[2], colors[1])
	# Breast patch; small raised volume follows the rounded chest.
	_oval(st, Vector3(0, 0.215, -0.106), Vector3(0.155, 0.18, 0.09), colors[1], colors[1])
	for side in [-1.0, 1.0]:
		if kind == 2:
			_oval(st, Vector3(side * 0.072, 0.31, -0.108), Vector3(0.026, 0.083, 0.115), Color("e9e6cf"), Color("e9e6cf"))
		_oval(st, Vector3(side * 0.078, 0.331, -0.145), Vector3(0.023, 0.031, 0.032), Color("17232b"), Color("17232b"))
		_oval(st, Vector3(side * 0.088, 0.339, -0.153), Vector3(0.007, 0.009, 0.009), Color.WHITE, Color.WHITE)
		_rod(st, Vector3(side * 0.045, 0.085, 0.015), Vector3(side * 0.045, 0.012, -0.012), 0.008, Color("805e43"))
		for toe in [-1.0, 0.0, 1.0]:
			_rod(st, Vector3(side * 0.045, 0.009, -0.012), Vector3(side * 0.045 + toe * 0.018, 0.005, -0.060), 0.005, Color("805e43"))
		_rod(st, Vector3(side * 0.045, 0.009, -0.012), Vector3(side * 0.045, 0.005, 0.035), 0.005, Color("805e43"))
	var tip := Vector3(0, 0.300, -0.253)
	var beak := Color("665344")
	_tri(st, Vector3(-0.031, 0.31, -0.17), tip, Vector3(0, 0.332, -0.177), beak)
	_tri(st, Vector3(0, 0.332, -0.177), tip, Vector3(0.031, 0.31, -0.17), beak.lightened(0.1))
	_tri(st, Vector3(-0.031, 0.31, -0.17), Vector3(0.031, 0.31, -0.17), tip, beak.darkened(0.15))
	for feather in 5:
		var x := (feather - 2) * 0.028
		_tri(st, Vector3(x * 0.4, 0.19, 0.12), Vector3(x - 0.020, 0.18, 0.33 - absf(x) * 0.35),
			Vector3(x + 0.020, 0.18, 0.33 - absf(x) * 0.35), (colors[3] as Color).lightened(feather * 0.018))
	_bodies[kind] = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_oval(st, Vector3(0.105, 0, 0.048), Vector3(0.24, 0.037, 0.19), colors[2], colors[2])
	for feather in 6:
		var x := 0.075 + feather * 0.031
		_tri(st, Vector3(0.025, 0.008, 0.02), Vector3(x, 0.004, 0.10 + feather * 0.013),
			Vector3(x + 0.030, 0.004, 0.08 + feather * 0.013), (colors[3] as Color).lightened(0.04 * feather))
	_wings[kind] = st.commit()


static func _build_water_bird(kind: int) -> void:
	var gull := kind == 3
	var white := Color("edece1")
	var back := Color("b5bdc0") if gull else Color("837262")
	var breast := white if gull else Color("7f4d35")
	var head := white if gull else Color("276947")
	var bill := Color("e1b548") if gull else Color("dbaf42")
	var feet := Color("ca9c87") if gull else Color("d98a32")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_oval(st, Vector3(0, 0.25, 0.06), Vector3(0.29 if gull else 0.39, 0.33, 0.62), back, white if gull else Color("b9ad91"))
	_oval(st, Vector3(0, 0.30, -0.18), Vector3(0.23, 0.33, 0.28), breast, breast)
	_oval(st, Vector3(0, 0.44, -0.24), Vector3(0.22 if gull else 0.25, 0.23, 0.24), head, head)
	if not gull:
		_oval(st, Vector3(0, 0.345, -0.21), Vector3(0.22, 0.035, 0.23), white, white)
		_oval(st, Vector3(0, 0.416, -0.40), Vector3(0.14, 0.055, 0.22), bill, bill)
	else:
		_tri(st, Vector3(-0.042, 0.45, -0.32), Vector3(0, 0.42, -0.53), Vector3(0.042, 0.45, -0.32), bill)
		_tri(st, Vector3(0, 0.48, -0.32), Vector3(0, 0.42, -0.53), Vector3(-0.042, 0.45, -0.32), bill.lightened(0.12))
		_tri(st, Vector3(0.042, 0.45, -0.32), Vector3(0, 0.42, -0.53), Vector3(0, 0.48, -0.32), bill)
	for side in [-1.0, 1.0]:
		_oval(st, Vector3(side * 0.105, 0.47, -0.285), Vector3(0.025, 0.03, 0.033), Color("192128"), Color("192128"))
		_oval(st, Vector3(side * 0.115, 0.477, -0.294), Vector3(0.008, 0.009, 0.008), Color.WHITE, Color.WHITE)
		_rod(st, Vector3(side * 0.07, 0.12, 0.02), Vector3(side * 0.07, 0.02, -0.015), 0.012, feet)
		_tri(st, Vector3(side * 0.07, 0.012, 0.025), Vector3(side * 0.07 - 0.04, 0.009, -0.10), Vector3(side * 0.07 + 0.04, 0.009, -0.10), feet)
	for feather in 5:
		var x := (feather - 2) * 0.04
		_tri(st, Vector3(x * 0.5, 0.25, 0.28), Vector3(x - 0.025, 0.21, 0.48), Vector3(x + 0.025, 0.21, 0.48), white if gull else Color("343c3b"))
	_bodies[kind] = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var reach := 0.59 if gull else 0.39
	_oval(st, Vector3(reach * 0.45, 0, 0.06), Vector3(reach, 0.045, 0.28), back, back)
	for feather in 7:
		var x := 0.11 + feather * (reach - 0.11) / 6.0
		var color := Color("353b40") if gull and feather > 3 else back
		if not gull and feather >= 2 and feather <= 4:
			color = Color("355ea1")
		_tri(st, Vector3(0.05, 0.006, 0.015), Vector3(x, 0.006, 0.20 + feather * 0.015), Vector3(x + 0.05, 0.006, 0.16 + feather * 0.015), color)
	_wings[kind] = st.commit()


static func _oval(st: SurfaceTool, offset: Vector3, size: Vector3, top: Color, belly: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 7
	_append(st, sphere, Transform3D(Basis.from_scale(size), offset), top, belly)


static func _rod(st: SurfaceTool, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = from.distance_to(to)
	cylinder.radial_segments = 5
	var axis := (to - from).normalized()
	var rotation := Quaternion(Vector3.UP, axis)
	_append(st, cylinder, Transform3D(Basis(rotation), (from + to) * 0.5), color, color)


static func _append(st: SurfaceTool, mesh: PrimitiveMesh, xf: Transform3D, top: Color, belly: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var normal_xf := xf.basis.inverse().transposed()
	for i in arrays[Mesh.ARRAY_INDEX]:
		st.set_color(top.lerp(belly, clampf(0.45 - points[i].y, 0, 1)).srgb_to_linear())
		st.set_normal((normal_xf * normals[i]).normalized())
		st.add_vertex(xf * points[i])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color.srgb_to_linear())
	st.set_normal((c - a).cross(b - a).normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
