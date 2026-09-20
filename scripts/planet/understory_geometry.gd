@tool
extends RefCounted

## Diseño determinista: tallos, frondes, hojas y pétalos son geometría opaca.
## Los LODs conservan las hojas terminales y subconjuntos de las demás.
const SPECIES := ["wood_fern", "royal_fern", "round_shrub", "willow_shrub",
	"flowering_shrub", "wild_asparagus", "broadleaf", "wildflowers"]
const GRASS_SHADER = preload("res://shaders/grass_wind.gdshader")
static var _cache: Dictionary = {}

var _leaves: Array = []
var _stems: Array = []
var _rng := RandomNumberGenerator.new()
var _height: float = 1.0
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


static func build(species: String) -> Array:
	if _cache.has(species):
		return _cache[species]
	if not species in SPECIES:
		push_error("Especie de sotobosque desconocida: " + species)
		return []
	var builder = new()
	builder._rng.seed = 7183 + SPECIES.find(species) * 7919
	match species:
		"wood_fern", "royal_fern":
			builder._fern(species == "royal_fern")
		"round_shrub", "willow_shrub", "flowering_shrub":
			builder._shrub(species)
		"wild_asparagus":
			builder._asparagus()
		"broadleaf":
			builder._broadleaf()
		"wildflowers":
			builder._wildflowers()
	var material: ShaderMaterial = builder._material(species)
	var result: Array = []
	for lod in 4:
		result.append(builder._mesh(lod, material))
	_cache[species] = result
	return result


func _material(species: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = species
	material.shader = GRASS_SHADER
	material.set_shader_parameter("use_vertex_color", true)
	material.set_shader_parameter("base_color", Color.WHITE)
	material.set_shader_parameter("tip_color", Color.WHITE)
	material.set_shader_parameter("ground_tint_amount", 0.0)
	material.set_shader_parameter("dry_amount", 0.0)
	material.set_shader_parameter("variation_value", 0.07)
	material.set_shader_parameter("blade_variation", 0.045)
	# Las hojas ya tienen pliegue y normales geométricas: no aplicarles la
	# curvatura ni la inclinación hacia el cielo de las cintas de hierba.
	material.set_shader_parameter("blade_curvature", 0.0)
	material.set_shader_parameter("near_normal_strength", 0.0)
	material.set_shader_parameter("distant_normal_strength", 0.06)
	material.set_shader_parameter("diffuse_wrap", 0.22)
	material.set_shader_parameter("transmission_strength", 0.35)
	material.set_shader_parameter("grass_height", _height)
	material.set_shader_parameter("bend_curve", 2.0)
	material.set_shader_parameter("wind_amplitude", 0.55 if "fern" in species else 0.35)
	material.set_shader_parameter("wind_speed", 0.18)
	material.set_shader_parameter("flutter_amount", 0.07)
	material.set_shader_parameter("ambient_intensity", 0.08)
	material.set_shader_parameter("ambient_color_top", Color(0.77, 0.85, 0.94))
	material.set_shader_parameter("ambient_color_bottom", Color(0.36, 0.40, 0.26))
	material.set_shader_parameter("planet_position", Vector3(0, -30000, 0))
	material.set_shader_parameter("light_direction", Vector3(0.4, 0.8, 0.3).normalized())
	material.set_shader_parameter("fade_start", 148.0)
	material.set_shader_parameter("fade_end", 176.0)
	return material


func _leaf(a: Vector3, b: Vector3, c: Vector3, width: float, color: Color,
		terminal: bool = false, facing: Vector3 = Vector3.UP) -> void:
	var seed: float = _rng.randf()
	var tier: int = 3 if terminal else 0
	if not terminal:
		var selection: int = _rng.randi()
		while tier < 3 and (selection & (1 << tier)) == 0:
			tier += 1
	_leaves.append({"a": a, "b": b, "c": c, "width": width,
		"color": color, "seed": seed, "tier": tier, "facing": facing})
	_height = maxf(_height, maxf(b.y, c.y))


func _stem(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	if a.distance_squared_to(b) < 0.000001:
		return
	_stems.append({"a": a, "b": b, "width": width, "color": color})
	_height = maxf(_height, maxf(a.y, b.y))


func _fern(tall: bool) -> void:
	var count: int = 9 if tall else 11
	var leaf_color := Color(0.44, 0.62, 0.36) if tall else Color(0.38, 0.56, 0.32)
	for frond in count:
		var angle: float = frond * TAU / count + _rng.randf_range(-0.12, 0.12)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-radial.z, 0, radial.x)
		var reach: float = _rng.randf_range(0.52, 0.82) * (0.8 if tall else 1.0)
		var top: float = _rng.randf_range(0.52, 0.82) * (1.65 if tall else 1.0)
		var root := radial * 0.05
		var control: Vector3 = radial * reach * 0.16 + Vector3.UP * top * 1.28
		var tip: Vector3 = radial * reach + Vector3.UP * top * 0.60
		var previous: Vector3 = root
		for step in range(1, 6):
			var point := _curve(root, control, tip, step / 5.0)
			_stem(previous, point, 0.011, leaf_color.darkened(0.18))
			previous = point
		var pairs: int = 9 if tall else 11
		for pair in pairs:
			var t: float = 0.15 + float(pair) / float(pairs) * 0.78
			var center := _curve(root, control, tip, t)
			var span: float = reach * 0.40 * pow(1.0 - t, 0.55)
			for sign_side in [-1.0, 1.0]:
				var direction: Vector3 = side * sign_side + radial * 0.42
				var end: Vector3 = center + direction * span + Vector3.UP * 0.035
				var mid: Vector3 = center.lerp(end, 0.55) + Vector3.UP * span * 0.20
				_leaf(center, mid, end, span * (0.34 if tall else 0.27),
					leaf_color.lightened(_rng.randf_range(0, 0.08)), pair == 1)
		var start := _curve(root, control, tip, 0.82)
		_leaf(start, start.lerp(tip, 0.5) + Vector3.UP * 0.025, tip,
			0.045, leaf_color.lightened(0.10), true)


func _shrub(species: String) -> void:
	var willow: bool = species == "willow_shrub"
	var flowers: bool = species == "flowering_shrub"
	var color := Color(0.46, 0.61, 0.40)
	if willow:
		color = Color(0.53, 0.65, 0.45)
	elif flowers:
		color = Color(0.42, 0.55, 0.35)
	var wood := Color(0.36, 0.31, 0.21)
	var branches: int = 11 if willow else 13
	for branch in branches:
		var angle: float = branch * 2.399963 + _rng.randf_range(-0.25, 0.25)
		var direction := Vector3(cos(angle), 0, sin(angle))
		var height: float = _rng.randf_range(0.68, 1.12) * 1.3 if willow else _rng.randf_range(0.42, 1.06)
		var reach: float = _rng.randf_range(0.32, 0.68) if willow else 0.80 - height * 0.35
		var root: Vector3 = direction * 0.055
		var knee: Vector3 = direction * reach * 0.28 + Vector3.UP * height * (0.42 if willow else 0.22)
		var end: Vector3 = direction * reach + Vector3.UP * height
		_stem(root, knee, 0.028, wood)
		_stem(knee, end, 0.019, wood.lightened(0.08))
		for node in 6:
			var t: float = 0.05 + node * 0.18
			var origin: Vector3 = knee.lerp(end, t)
			for sign_side in [-1.0, 1.0]:
				var lateral: Vector3 = direction.rotated(Vector3.UP, sign_side * 0.95)
				var shoot: Vector3 = origin + lateral * 0.17 + Vector3.UP * 0.06
				_stem(origin, shoot, 0.006, wood.lightened(0.16))
				var length_leaf: float = _rng.randf_range(0.20, 0.28) * (1.45 if willow else 1.15)
				var tip: Vector3 = shoot + lateral * length_leaf + Vector3.UP * (0.035 if willow else 0.085)
				_leaf(shoot, shoot.lerp(tip, 0.5) + Vector3.UP * 0.09, tip,
					length_leaf * (0.24 if willow else 0.68),
					color.lightened(_rng.randf_range(-0.04, 0.08)), node == 5)
		_leaf(end - Vector3.UP * 0.04, end + Vector3.UP * 0.14,
			end + direction * 0.10 + Vector3.UP * 0.18, 0.10, color.lightened(0.12), true)
		if flowers and branch % 2 == 0:
			_flower(end + Vector3.UP * 0.035, 0.095, Color(0.77, 0.62, 0.73))


func _asparagus() -> void:
	var color := Color(0.51, 0.64, 0.39)
	for cane in 6:
		var angle: float = cane * 2.399963
		var radial := Vector3(cos(angle), 0, sin(angle))
		var height: float = _rng.randf_range(0.95, 1.48)
		var root: Vector3 = radial * 0.075
		var top: Vector3 = radial * 0.30 + Vector3.UP * height
		_stem(root, top, 0.014, color.darkened(0.2))
		for level in 5:
			var t: float = 0.28 + level * 0.14
			var center: Vector3 = root.lerp(top, t)
			for side in 3:
				var arm: Vector3 = radial.rotated(Vector3.UP, side * TAU / 3.0 + level * 0.7)
				var branch_tip: Vector3 = center + arm * (1.0 - t) * 0.52 + Vector3.UP * 0.12
				_stem(center, branch_tip, 0.004, color)
				for tuft in 3:
					var bud: Vector3 = center.lerp(branch_tip, 0.35 + tuft * 0.30)
					for needle in 3:
						var needle_dir: Vector3 = arm.rotated(Vector3.UP, (needle - 1.0) * 0.60)
						var tip: Vector3 = bud + needle_dir * 0.14 + Vector3.UP * (0.05 + needle * 0.014)
						_leaf(bud, bud.lerp(tip, 0.55) + Vector3.UP * 0.045, tip,
							0.014, color.lightened(_rng.randf_range(0, 0.10)), tuft == 2 and needle == 1)


func _broadleaf() -> void:
	var color := Color(0.42, 0.59, 0.40)
	for leaf in 13:
		var angle: float = leaf * 2.399963
		var radial := Vector3(cos(angle), 0, sin(angle))
		var height: float = _rng.randf_range(0.30, 0.66)
		var root: Vector3 = radial * 0.045
		var neck: Vector3 = radial * 0.15 + Vector3.UP * height * 0.32
		_stem(root, neck, 0.014, color.darkened(0.16))
		var tip: Vector3 = radial * _rng.randf_range(0.40, 0.64) + Vector3.UP * height * 0.70
		_leaf(neck, radial * 0.29 + Vector3.UP * height * 1.40, tip,
			_rng.randf_range(0.20, 0.29), color.lightened(_rng.randf_range(0, 0.10)), leaf % 3 == 0)


func _wildflowers() -> void:
	var green := Color(0.48, 0.61, 0.36)
	for stalk in 9:
		var angle: float = stalk * 2.399963
		var direction := Vector3(cos(angle), 0, sin(angle))
		var root: Vector3 = direction * _rng.randf_range(0.06, 0.24)
		var head: Vector3 = root + direction * 0.12 + Vector3.UP * _rng.randf_range(0.40, 0.76)
		_stem(root, head, 0.009, green.darkened(0.18))
		for side in [-1.0, 1.0]:
			var base: Vector3 = root.lerp(head, 0.26 if side < 0.0 else 0.50)
			var end: Vector3 = base + direction.rotated(Vector3.UP, side * 1.1) * 0.18 + Vector3.UP * 0.06
			_leaf(base, base.lerp(end, 0.5) + Vector3.UP * 0.06, end, 0.055, green, true)
		_flower(head, 0.070, Color(0.90, 0.85, 0.68) if stalk % 3 else Color(0.68, 0.62, 0.79))


func _flower(center: Vector3, radius: float, color: Color) -> void:
	for petal in 5:
		var angle: float = petal * TAU / 5.0
		var outward := Vector3(cos(angle), 0, sin(angle))
		_leaf(center, center + outward * radius * 0.5 + Vector3.UP * 0.025,
			center + outward * radius, radius * 0.65, color, true)
	# Centro cálido sin material ni draw call adicional.
	_leaf(center - Vector3.RIGHT * radius * 0.20 + Vector3.UP * 0.005,
		center + Vector3.UP * 0.032, center + Vector3.RIGHT * radius * 0.20 + Vector3.UP * 0.005,
		radius * 0.42, Color(0.79, 0.62, 0.28), true)


func _mesh(lod: int, material: Material) -> ArrayMesh:
	_v.clear()
	_n.clear()
	_uv.clear()
	_uv2.clear()
	_colors.clear()
	_indices.clear()
	for stem in _stems:
		# Ramitas muy finas no necesitan cilindros en los LODs distantes.
		if lod >= 2 and stem.width < 0.008:
			continue
		_append_stem(stem, lod)
	for leaf in _leaves:
		if leaf.tier >= lod:
			_append_leaf(leaf, lod)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _append_leaf(leaf: Dictionary, lod: int) -> void:
	var segments: int = [3, 2, 2, 1][lod]
	var columns: int = 3 if lod < 2 else 2
	if leaf.width < 0.025:
		segments = 2 if lod == 0 else 1
		columns = 2
	var width_gain: float = [1.0, 1.20, 1.48, 1.85][lod]
	var base: int = _v.size()
	var first_index: int = _indices.size()
	var length_axis: Vector3 = (leaf.c - leaf.a).normalized()
	var side: Vector3 = length_axis.cross(leaf.facing)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var normal: Vector3 = side.cross(length_axis).normalized()
	for row in segments:
		var t: float = float(row) / segments
		var center := _curve(leaf.a, leaf.b, leaf.c, t)
		var tangent: Vector3 = ((leaf.b - leaf.a) * (1.0 - t) + (leaf.c - leaf.b) * t).normalized()
		var row_normal: Vector3 = side.cross(tangent).normalized()
		var profile: float = 0.13 + sin(PI * pow(t, 0.80)) * 0.87
		if lod == 3:
			profile = 0.80
		for column in columns:
			var u: float = float(column) / (columns - 1)
			var width: float = leaf.width * width_gain * profile
			var position: Vector3 = center + side * (u - 0.5) * width
			position += row_normal * (1.0 - absf(u * 2.0 - 1.0)) * width * 0.13
			var n: Vector3 = (row_normal + side * (u - 0.5) * 0.35).normalized()
			_vertex(position, n, Vector2(u, leaf.seed), leaf.color * lerpf(0.83, 1.08, t))
	_vertex(leaf.c, normal, Vector2(0.5, leaf.seed), leaf.color * 1.08)
	for row in segments - 1:
		for column in columns - 1:
			var a: int = base + row * columns + column
			_triangle(a, a + columns, a + 1)
			_triangle(a + 1, a + columns, a + columns + 1)
	var last: int = base + (segments - 1) * columns
	for column in columns - 1:
		_triangle(last + column, base + segments * columns, last + column + 1)
	_leaf_normals(base, first_index)


func _leaf_normals(first_vertex: int, first_index: int) -> void:
	# Derivar la normal del pliegue y la curva realmente triangulados. La punta
	# antes heredaba la normal de la cuerda raíz->punta, orientada hacia arriba
	# incluso en hojas que caen. Cada hoja conserva sus vértices independientes.
	for vertex in range(first_vertex, _v.size()):
		_n[vertex] = Vector3.ZERO
	for offset in range(first_index, _indices.size(), 3):
		var a: int = _indices[offset]
		var b: int = _indices[offset + 1]
		var c: int = _indices[offset + 2]
		# Caras horarias: el producto vectorial convencional apunta hacia dentro.
		var face: Vector3 = (_v[c] - _v[a]).cross(_v[b] - _v[a])
		_n[a] += face
		_n[b] += face
		_n[c] += face
	for vertex in range(first_vertex, _v.size()):
		_n[vertex] = _n[vertex].normalized()


func _append_stem(stem: Dictionary, lod: int) -> void:
	var direction: Vector3 = (stem.b - stem.a).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var normal: Vector3 = side.cross(direction).normalized()
	var base: int = _v.size()
	if lod == 3:
		# En pantalla ocupa menos de un píxel: una cinta conserva el tallo.
		_vertex(stem.a - side * stem.width * 0.7, normal, Vector2(0, 0.5), stem.color)
		_vertex(stem.a + side * stem.width * 0.7, normal, Vector2(1, 0.5), stem.color)
		_vertex(stem.b - side * stem.width * 0.4, normal, Vector2(0, 0.5), stem.color)
		_vertex(stem.b + side * stem.width * 0.4, normal, Vector2(1, 0.5), stem.color)
		_triangle(base, base + 1, base + 2)
		_triangle(base + 1, base + 3, base + 2)
		return
	var sides: int = 4 if lod == 0 else 3
	for ring in 2:
		var center: Vector3 = stem.a if ring == 0 else stem.b
		var radius: float = stem.width * (0.5 if ring == 0 else 0.30)
		for face in sides:
			var angle: float = TAU * face / sides
			var n: Vector3 = side * cos(angle) + normal * sin(angle)
			_vertex(center + n * radius, n, Vector2(float(face) / sides, 0.5), stem.color)
	for face in sides:
		var next: int = (face + 1) % sides
		_triangle(base + face, base + next, base + sides + face)
		_triangle(base + next, base + sides + next, base + sides + face)


func _vertex(position: Vector3, normal: Vector3, uv: Vector2, color: Color) -> void:
	_v.append(position)
	_n.append(normal)
	_uv.append(uv)
	_uv2.append(Vector2(clampf(position.y / _height, 0, 1), 1.0))
	# COLOR no lleva la conversión source_color de los uniforms.
	var linear: Color = color.srgb_to_linear()
	linear.a = 1.0
	_colors.append(linear)


func _triangle(a: int, b: int, c: int) -> void:
	var face: Vector3 = (_v[b] - _v[a]).cross(_v[c] - _v[a])
	if face.dot(_n[a] + _n[b] + _n[c]) > 0:
		_indices.append_array(PackedInt32Array([a, c, b]))
	else:
		_indices.append_array(PackedInt32Array([a, b, c]))


static func _curve(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)
