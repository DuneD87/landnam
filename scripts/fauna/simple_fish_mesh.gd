class_name SimpleFishMesh extends RefCounted

## Stylized marine species. Geometry is baked by tools/fauna/bake_fish_meshes.gd;
## spawning a new species never runs the SurfaceTool builder during play.
enum Kind { SARDINE, BREAM, CLOWNFISH, BUTTERFLY, BLUE_TANG, WRASSE }
const MAX_SCALE: float = 1.1
const ANIMATION_MARGIN: float = 0.09
const TYPES: Array[Dictionary] = [
	{"name": "Sardina", "length": 0.94, "height": 0.24, "width": 0.17, "tail": 0.24, "span": 0.19, "fork": true,
	 "dorsal": 0.12, "body": Color("7aa9b7"), "back": Color("244c68"), "belly": Color("e0e8de"), "fin": Color("708f9c"), "speed": 1.25},
	{"name": "Dorada", "length": 0.76, "height": 0.44, "width": 0.24, "tail": 0.23, "span": 0.23, "fork": true,
	 "dorsal": 0.15, "body": Color("b7b392"), "back": Color("67716c"), "belly": Color("eee6c8"), "fin": Color("a99b62"), "speed": 0.95},
	{"name": "Pez payaso", "length": 0.65, "height": 0.35, "width": 0.23, "tail": 0.19, "span": 0.17, "fork": false,
	 "dorsal": 0.12, "body": Color("f68326"), "back": Color("c94812"), "belly": Color("ffb64e"), "fin": Color("ee7624"), "speed": 0.8},
	{"name": "Pez mariposa", "length": 0.57, "height": 0.61, "width": 0.17, "tail": 0.17, "span": 0.17, "fork": false,
	 "dorsal": 0.18, "body": Color("f3d848"), "back": Color("c6a629"), "belly": Color("fff0a8"), "fin": Color("e3b431"), "speed": 0.7},
	{"name": "Cirujano azul", "length": 0.75, "height": 0.43, "width": 0.17, "tail": 0.23, "span": 0.21, "fork": true,
	 "dorsal": 0.10, "body": Color("2375d9"), "back": Color("163478"), "belly": Color("65b0e5"), "fin": Color("1a4c9f"), "speed": 1.0},
	{"name": "Lábrido", "length": 0.98, "height": 0.28, "width": 0.20, "tail": 0.18, "span": 0.14, "fork": false,
	 "dorsal": 0.09, "body": Color("32b8a0"), "back": Color("176974"), "belly": Color("b8dfb6"), "fin": Color("d4719b"), "speed": 1.1},
]
static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
const BAKED_MESHES: Array[ArrayMesh] = [preload("res://data/fauna/meshes/fish/0.res"), preload("res://data/fauna/meshes/fish/1.res"), preload("res://data/fauna/meshes/fish/2.res"), preload("res://data/fauna/meshes/fish/3.res"), preload("res://data/fauna/meshes/fish/4.res"), preload("res://data/fauna/meshes/fish/5.res")]


static func mesh(kind: int = Kind.SARDINE) -> ArrayMesh:
	return BAKED_MESHES[clampi(kind, 0, TYPES.size() - 1)]


## Offline builder kept to regenerate assets without changing their geometry.
static func build_mesh(kind: int = Kind.SARDINE) -> ArrayMesh:
	kind = clampi(kind, 0, TYPES.size() - 1)
	if _meshes.has(kind):
		return _meshes[kind]
	var spec := TYPES[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build_body(st, spec)
	_build_fins(st, spec, kind)
	_build_face(st, spec)
	var result := st.commit()
	_meshes[kind] = result
	return result


static func collision_bounds(kind: int) -> AABB:
	var bounds := mesh(kind).get_aabb()
	bounds.position.x -= ANIMATION_MARGIN
	bounds.size.x += ANIMATION_MARGIN * 2.0
	return bounds.grow(0.015)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/fauna/simple_fish.gdshader")
	return _material


static func _girth(u: float) -> float:
	# Tapered snout, shoulder, belly and narrow caudal peduncle.
	var positions := [0.0, 0.08, 0.22, 0.40, 0.55, 0.73, 0.90, 1.0]
	var radii := [0.09, 0.42, 0.82, 1.0, 0.95, 0.65, 0.27, 0.11]
	for i in range(1, positions.size()):
		if u <= positions[i]:
			return lerpf(radii[i - 1], radii[i], inverse_lerp(positions[i - 1], positions[i], u))
	return 0.11


static func _surface(spec: Dictionary, u: float, angle: float) -> Vector3:
	var radius := _girth(u)
	return Vector3(cos(angle) * float(spec.width) * 0.5 * radius,
		sin(angle) * float(spec.height) * 0.5 * radius, (u - 0.5) * float(spec.length))


static func _body_color(spec: Dictionary, point: Vector3) -> Color:
	var t := point.y / (float(spec.height) * 0.5)
	if t >= 0.0:
		return (spec.body as Color).lerp(spec.back, pow(t, 1.5) * 0.8)
	return (spec.body as Color).lerp(spec.belly, -t * 0.85)


static func _build_body(st: SurfaceTool, spec: Dictionary) -> void:
	const RINGS := 22
	const SIDES := 16
	for ring in RINGS:
		for side in SIDES:
			var a := _surface(spec, float(ring) / RINGS, TAU * side / SIDES)
			var b := _surface(spec, float(ring + 1) / RINGS, TAU * side / SIDES)
			var c := _surface(spec, float(ring + 1) / RINGS, TAU * (side + 1) / SIDES)
			var d := _surface(spec, float(ring) / RINGS, TAU * (side + 1) / SIDES)
			_body_triangle(st, spec, a, b, c)
			_body_triangle(st, spec, a, c, d)
	# Closed nose and tail root.
	for end in [0.0, 1.0]:
		var center := Vector3(0, 0, (end - 0.5) * float(spec.length))
		for side in SIDES:
			_body_triangle(st, spec, center, _surface(spec, end, TAU * side / SIDES),
				_surface(spec, end, TAU * (side + 1) / SIDES))


static func _body_triangle(st: SurfaceTool, spec: Dictionary, a: Vector3, b: Vector3, c: Vector3) -> void:
	for point in [a, b, c]:
		# Elliptical normals keep a little faceting while rounding the body.
		var u := clampf(point.z / float(spec.length) + 0.5, 0.0, 1.0)
		var slope := (_girth(minf(u + 0.015, 1.0)) - _girth(maxf(u - 0.015, 0.0))) / 0.03
		var normal := Vector3(point.x / pow(float(spec.width) * 0.5, 2),
			point.y / pow(float(spec.height) * 0.5, 2), -slope / float(spec.length)).normalized()
		_vertex(st, spec, point, _body_color(spec, point), normal, 0.0)


static func _build_fins(st: SurfaceTool, spec: Dictionary, kind: int) -> void:
	var length: float = spec.length
	var height: float = spec.height
	var root := length * 0.5
	var tail: float = spec.tail
	var span: float = spec.span
	var fin: Color = spec.fin
	var tail_color := Color("f6d335") if kind == Kind.BLUE_TANG else fin
	var outline: Array[Vector3] = [Vector3(0, height * 0.06, root)]
	if spec.fork:
		outline.append_array([Vector3(0, span, root + tail), Vector3(0, 0, root + tail * 0.52),
			Vector3(0, -span, root + tail), Vector3(0, -height * 0.06, root)])
	else:
		outline.append_array([Vector3(0, span * 0.85, root + tail * 0.50),
			Vector3(0, span, root + tail * 0.85), Vector3(0, span * 0.6, root + tail),
			Vector3(0, -span * 0.6, root + tail), Vector3(0, -span, root + tail * 0.85),
			Vector3(0, -span * 0.85, root + tail * 0.50), Vector3(0, -height * 0.06, root)])
	_fan(st, spec, Vector3(0, 0, root), outline, tail_color, kind == Kind.CLOWNFISH)
	# Different dorsal silhouettes: single sail, spiny crest, or long soft ribbon.
	var crest: Array[Vector3] = []
	var first := 0.23 if kind != Kind.SARDINE else 0.42
	var last := 0.91 if kind != Kind.SARDINE else 0.67
	for i in 13:
		var u := lerpf(first, last, float(i) / 12.0)
		var point := _surface(spec, u, PI * 0.5)
		var raised := sin(PI * float(i) / 12.0) * float(spec.dorsal)
		if kind == Kind.BREAM and i % 2 == 1:
			raised += 0.055
		point.y += raised
		crest.append(point)
	_fan(st, spec, _surface(spec, 0.59, PI * 0.5) * Vector3(1, 0.85, 1), crest, fin, kind == Kind.CLOWNFISH)
	var bottom := float(spec.dorsal) * (0.95 if kind == Kind.BUTTERFLY else 0.55)
	_fan(st, spec, Vector3(0, -height * 0.25, length * 0.20), [
		Vector3(0, -height * 0.40, -length * 0.08), Vector3(0, -height * 0.48 - bottom, length * 0.10),
		Vector3(0, -height * 0.20 - bottom * 0.5, length * 0.35), Vector3(0, -height * 0.10, length * 0.43)], fin)
	# Paired pectoral fins have actual width and sweep backward in three dimensions.
	for side in [-1.0, 1.0]:
		var base := Vector3(side * float(spec.width) * 0.43, -height * 0.08, -length * 0.11)
		_fan(st, spec, base, [base + Vector3(0, height * 0.10, -0.025),
			base + Vector3(side * 0.14, -height * 0.16, length * 0.22),
			base + Vector3(side * 0.08, -height * 0.25, length * 0.14),
			base + Vector3(0, -height * 0.08, 0.025)], fin.lightened(0.12))


static func _fan(st: SurfaceTool, spec: Dictionary, center: Vector3, edge: Array[Vector3], color: Color, dark_edge: bool = false) -> void:
	for i in range(edge.size() - 1):
		var a := edge[i]
		var b := edge[i + 1]
		var normal := (a - center).cross(b - center).normalized()
		if normal.is_zero_approx():
			continue
		var inner_a := center.lerp(a, 0.88)
		var inner_b := center.lerp(b, 0.88)
		var rim := Color("253341") if dark_edge else color.darkened(0.20)
		for point in [center, inner_a, inner_b]:
			_vertex(st, spec, point, color.lightened(0.07) if point == center else color, normal, 1.0)
		for point in [inner_a, a, b, inner_a, b, inner_b]:
			_vertex(st, spec, point, rim, normal, 1.0)


static func _build_face(st: SurfaceTool, spec: Dictionary) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 5
	for side in [-1.0, 1.0]:
		var eye := _surface(spec, 0.19, 0.25 if side > 0 else PI - 0.25)
		eye.x += side * 0.005
		_ellipsoid(st, spec, sphere, eye, Vector3(0.024, 0.067, 0.067), Color("d8c58a"))
		_ellipsoid(st, spec, sphere, eye + Vector3(side * 0.013, 0, -0.004), Vector3(0.014, 0.043, 0.045), Color("101e29"))
		_ellipsoid(st, spec, sphere, eye + Vector3(side * 0.020, 0.010, -0.012), Vector3(0.006, 0.013, 0.013), Color("effbf4"))
		# Fine curved gill seam sitting just above the skin.
		for i in 8:
			var theta := lerpf(-0.75, 0.8, float(i) / 8.0)
			var next := lerpf(-0.75, 0.8, float(i + 1) / 8.0)
			if side < 0:
				theta = PI - theta
				next = PI - next
			var a := _surface(spec, 0.30, theta) + Vector3(side * 0.002, 0, 0)
			var b := _surface(spec, 0.30, next) + Vector3(side * 0.002, 0, 0)
			var c := b + Vector3(0, 0, 0.006)
			for point in [a, b, c, a, c, a + Vector3(0, 0, 0.006)]:
				_vertex(st, spec, point, (spec.back as Color).darkened(0.20), Vector3(side, 0, 0), 2.0)
	_ellipsoid(st, spec, sphere, Vector3(0, -0.009, -float(spec.length) * 0.492),
		Vector3(float(spec.width) * 0.12, 0.008, 0.023), Color("344047"))


static func _ellipsoid(st: SurfaceTool, spec: Dictionary, primitive: PrimitiveMesh, offset: Vector3, size: Vector3, color: Color) -> void:
	var arrays := primitive.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		_vertex(st, spec, offset + vertices[index] * size, color, (normals[index] / size).normalized(), 2.0)


static func _vertex(st: SurfaceTool, spec: Dictionary, point: Vector3, color: Color, normal: Vector3, part: float) -> void:
	# Vertex colors are raw shader data; palettes above are authored in sRGB.
	st.set_color(color.srgb_to_linear())
	st.set_normal(normal)
	st.set_uv(Vector2(point.z / float(spec.length) + 0.5, point.y / float(spec.height) + 0.5))
	st.set_uv2(Vector2(part, smoothstep(0.02, float(spec.length) * 0.5 + float(spec.tail), point.z)))
	st.add_vertex(point)
