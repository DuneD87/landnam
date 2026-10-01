@tool
class_name WeaponMeshes
extends RefCounted

## Mallas de las armas de combate, generadas por código y horneadas a recursos por
## tools/combat/bake_weapons.gd (el alta de un arma nunca ejecuta el SurfaceTool).
##
## Convención de todas: metros, el origen es el punto de agarre de la mano, +Y recorre el arma
## hacia la punta (o hacia arriba, en el arco), +Z es hacia donde mira el filo (o hacia el
## blanco, en el arco y el tirachinas) y X es el plano de la hoja.

const WOOD := &"wood"
const DARK_WOOD := &"dark_wood"
const STEEL := &"steel"
const IRON := &"iron"
const LEATHER := &"leather"
const FLINT := &"flint"
const FEATHER := &"feather"
const CORD := &"cord"
const STONE := &"stone"
const BARK := &"bark"


## Materiales compartidos, uno por tipo. El grano va en la textura de ruido y las UV lo estiran
## a lo largo de la pieza, así que la madera parece veta y no manchas.
static func make_material(kind: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = String(kind)
	match kind:
		WOOD:
			mat.albedo_texture = _noise_texture(Color(0.22, 0.13, 0.07), Color(0.42, 0.28, 0.16), 0.9, 7)
			mat.roughness = 0.72
		DARK_WOOD:
			mat.albedo_texture = _noise_texture(Color(0.16, 0.09, 0.05), Color(0.36, 0.22, 0.12), 0.9, 11)
			mat.roughness = 0.55
		STEEL:
			mat.albedo_texture = _noise_texture(Color(0.50, 0.52, 0.55), Color(0.72, 0.74, 0.77), 3.0, 3)
			mat.metallic = 0.92
			mat.roughness = 0.32
			mat.roughness_texture = _noise_texture(Color(0.55, 0.55, 0.55), Color(0.95, 0.95, 0.95), 6.0, 5)
		IRON:
			mat.albedo_texture = _noise_texture(Color(0.22, 0.22, 0.23), Color(0.40, 0.39, 0.38), 2.5, 13)
			mat.metallic = 0.85
			mat.roughness = 0.5
		LEATHER:
			mat.albedo_texture = _noise_texture(Color(0.18, 0.10, 0.06), Color(0.32, 0.19, 0.11), 4.0, 17)
			mat.roughness = 0.85
		FLINT:
			mat.albedo_texture = _noise_texture(Color(0.16, 0.16, 0.17), Color(0.42, 0.40, 0.38), 5.0, 19)
			mat.roughness = 0.38
			mat.metallic = 0.1
		FEATHER:
			mat.albedo_color = Color(0.86, 0.84, 0.78)
			mat.roughness = 0.9
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		CORD:
			mat.albedo_color = Color(0.62, 0.55, 0.42)
			mat.roughness = 0.95
		STONE:
			mat.albedo_texture = _noise_texture(Color(0.22, 0.20, 0.18), Color(0.42, 0.39, 0.35), 6.0, 23)
			mat.roughness = 0.9
		BARK:
			# Corteza gris parda, con el grano a lo largo como la madera.
			mat.albedo_texture = _noise_texture(Color(0.10, 0.08, 0.06), Color(0.30, 0.26, 0.21), 1.6, 29)
			mat.roughness = 0.92
	return mat


static func _noise_texture(dark: Color, light: Color, frequency: float, seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.01 * frequency
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, light)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	tex.generate_mipmaps = true
	return tex


## Constructor de mallas multimaterial: una superficie por material.
class Builder:
	var tools: Dictionary = {}
	var materials: Dictionary = {}

	func st(kind: StringName) -> SurfaceTool:
		if not tools.has(kind):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[kind] = tool
		return tools[kind]

	func commit(material_for: Callable) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for kind in tools:
			var tool: SurfaceTool = tools[kind]
			tool.generate_normals()
			tool.generate_tangents()
			tool.set_material(material_for.call(kind))
			tool.commit(mesh)
		return mesh


## Superficie de revolución alrededor de Y. [profile] = [(radio, y)] de abajo arriba. [twist]
## retuerce las UV (vendas en espiral).
static func lathe(st: SurfaceTool, profile: Array, segments: int = 12, center: Vector3 = Vector3.ZERO,
		u_scale: float = 1.0, v_scale: float = 4.0) -> void:
	var rings := profile.size()
	var base := _vertex_count(st)
	for i in rings:
		var r: float = profile[i].x
		var y: float = profile[i].y
		for j in segments + 1:
			var a := TAU * float(j) / float(segments)
			_emit(st, Vector2(float(j) / segments * u_scale, y * v_scale), center + Vector3(cos(a) * r, y, sin(a) * r))
	for i in rings - 1:
		for j in segments:
			var a0 := base + i * (segments + 1) + j
			var b0 := a0 + segments + 1
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	# Tapas: un abanico en cada extremo con radio > 0.
	for end in [0, rings - 1]:
		var r: float = profile[end].x
		if r <= 0.0005:
			continue
		var y: float = profile[end].y
		var c := _vertex_count(st)
		_emit(st, Vector2(0.5, 0.5), center + Vector3(0, y, 0))
		for j in segments + 1:
			var a := TAU * float(j) / float(segments)
			_emit(st, Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5), center + Vector3(cos(a) * r, y, sin(a) * r))
		for j in segments:
			if end == 0:
				st.add_index(c)
				st.add_index(c + 1 + j)
				st.add_index(c + 2 + j)
			else:
				st.add_index(c)
				st.add_index(c + 2 + j)
				st.add_index(c + 1 + j)


## Tubo a lo largo de una polilínea, de sección elíptica (rx en X local, rz en el binormal).
## [up_hint] fija hacia dónde apunta el eje "rx" de la sección.
static func tube(st: SurfaceTool, points: PackedVector3Array, radii: PackedVector2Array,
		segments: int = 8, side_hint: Vector3 = Vector3.RIGHT, cap: bool = true) -> void:
	var n := points.size()
	var base := _vertex_count(st)
	var length := 0.0
	for i in n:
		if i > 0:
			length += points[i].distance_to(points[i - 1])
		var tangent: Vector3
		if i == 0:
			tangent = points[1] - points[0]
		elif i == n - 1:
			tangent = points[i] - points[i - 1]
		else:
			tangent = points[i + 1] - points[i - 1]
		tangent = tangent.normalized()
		var side := (side_hint - tangent * side_hint.dot(tangent)).normalized()
		var other := tangent.cross(side).normalized()
		for j in segments + 1:
			var a := TAU * float(j) / float(segments)
			var offset := side * cos(a) * radii[i].x + other * sin(a) * radii[i].y
			_emit(st, Vector2(float(j) / segments, length * 4.0), points[i] + offset)
	for i in n - 1:
		for j in segments:
			var a0 := base + i * (segments + 1) + j
			var b0 := a0 + segments + 1
			st.add_index(a0)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(b0 + 1)
			st.add_index(b0)
	if not cap:
		return
	for end in [0, n - 1]:
		var c := _vertex_count(st)
		_emit(st, Vector2(0.5, 0.5), points[end])
		var ring_start: int = base + end * (segments + 1)
		for j in segments:
			if end == 0:
				st.add_index(c)
				st.add_index(ring_start + j)
				st.add_index(ring_start + j + 1)
			else:
				st.add_index(c)
				st.add_index(ring_start + j + 1)
				st.add_index(ring_start + j)


## Triángulo suelto (caras planas: no comparte vértices, así la normal sale por cara).
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_scale: float = 4.0) -> void:
	var base := _vertex_count(st)
	for p in [a, b, c]:
		_emit(st, Vector2(p.x + p.z, p.y) * uv_scale, p)
	st.add_index(base)
	st.add_index(base + 1)
	st.add_index(base + 2)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_scale: float = 4.0) -> void:
	tri(st, a, b, c, uv_scale)
	tri(st, a, c, d, uv_scale)


## Prisma de caras planas entre dos secciones poligonales (mismo número de vértices, en orden).
static func loft(st: SurfaceTool, rings: Array, cap_start: bool = true, cap_end: bool = true) -> void:
	for r in rings.size() - 1:
		var lo: PackedVector3Array = rings[r]
		var hi: PackedVector3Array = rings[r + 1]
		var m := lo.size()
		for j in m:
			var k := (j + 1) % m
			quad(st, lo[j], lo[k], hi[k], hi[j])
	if cap_start:
		_fan(st, rings[0], true)
	if cap_end:
		_fan(st, rings[rings.size() - 1], false)


static func _fan(st: SurfaceTool, ring: PackedVector3Array, flip: bool) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for j in ring.size():
		var k := (j + 1) % ring.size()
		if flip:
			tri(st, c, ring[k], ring[j])
		else:
			tri(st, c, ring[j], ring[k])


static func box(st: SurfaceTool, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		lo.append(center + basis * Vector3(c.x * h.x, -h.y, c.y * h.z))
		hi.append(center + basis * Vector3(c.x * h.x, h.y, c.y * h.z))
	loft(st, [lo, hi])


## SurfaceTool no expone cuántos vértices lleva, y los índices los necesitan: se cuenta aquí.
static func _vertex_count(st: SurfaceTool) -> int:
	return st.get_meta(&"vcount", 0)


## Caras planas: los vértices que siguen no se suavizan con sus vecinos (aristas de metal
## marcadas). Por defecto SurfaceTool suaviza todo lo que coincide en posición.
static func set_flat(st: SurfaceTool, flat: bool) -> void:
	st.set_meta(&"flat", flat)


static func _emit(st: SurfaceTool, uv: Vector2, p: Vector3) -> void:
	st.set_smooth_group(0xFFFFFFFF if st.get_meta(&"flat", false) else 0)
	st.set_uv(uv)
	st.add_vertex(p)
	st.set_meta(&"vcount", _vertex_count(st) + 1)


# ---------------------------------------------------------------------------------------------
# Piezas


## Empuñadura con vendas: radio que sube y baja en espiral para que se vea el cuero enrollado.
static func wrapped_grip(st: SurfaceTool, y0: float, y1: float, radius: float, turns: int = 9) -> void:
	var profile := []
	var steps := turns * 4
	for i in steps + 1:
		var t := float(i) / steps
		var bump := 0.12 * radius * absf(sin(t * turns * PI))
		profile.append(Vector2(radius + bump, lerpf(y0, y1, t)))
	lathe(st, profile, 10, Vector3.ZERO, 1.0, 12.0)


## Hoja de sección romboidal (aristas en ±Z, lomo en ±X) de [y0] a la punta. [width] es la
## anchura total en Z en el arranque; el perfil hace una ligera hoja de laurel.
static func blade(st: SurfaceTool, y0: float, length: float, width: float, thickness: float,
		tip: float, fuller: bool = true) -> void:
	var rings := []
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		var y := y0 + length * t
		# Anchura: se ensancha un poco al 60 % (laurel) y se estrecha hacia la punta.
		var w := width * 0.5 * (1.0 + 0.10 * sin(t * PI * 0.95)) * (1.0 - 0.25 * t)
		var th := thickness * 0.5 * (1.0 - 0.45 * t)
		var ring := PackedVector3Array()
		ring.append(Vector3(0, y, w))
		if fuller:
			ring.append(Vector3(th * 0.8, y, w * 0.35))
		ring.append(Vector3(th, y, 0))
		if fuller:
			ring.append(Vector3(th * 0.8, y, -w * 0.35))
		ring.append(Vector3(0, y, -w))
		if fuller:
			ring.append(Vector3(-th * 0.8, y, -w * 0.35))
		ring.append(Vector3(-th, y, 0))
		if fuller:
			ring.append(Vector3(-th * 0.8, y, w * 0.35))
		rings.append(ring)
	# Punta: todos los vértices convergen.
	var last: PackedVector3Array = rings[rings.size() - 1]
	var point := Vector3(0, y0 + length + tip, 0)
	for j in last.size():
		var k := (j + 1) % last.size()
		tri(st, last[j], last[k], point)
	loft(st, rings, true, false)


# ---------------------------------------------------------------------------------------------
# Armas


static func sword() -> ArrayMesh:
	var b := Builder.new()
	var steel := b.st(STEEL)
	set_flat(steel, true)
	blade(steel, 0.115, 0.70, 0.054, 0.011, 0.11)
	var iron := b.st(IRON)
	set_flat(iron, true)
	# Guarda: barra que se afina hacia las puntas, un poco curvada hacia la hoja.
	var guard_rings := []
	for i in 9:
		var t := float(i) / 8.0 * 2.0 - 1.0
		var z := t * 0.105
		var y := 0.100 + 0.012 * t * t
		var h := 0.013 * (1.0 - 0.45 * absf(t))
		var th := 0.015 * (1.0 - 0.35 * absf(t))
		guard_rings.append(PackedVector3Array([
			Vector3(-th, y - h, z), Vector3(th, y - h, z), Vector3(th, y + h, z), Vector3(-th, y + h, z)]))
	for i in guard_rings.size():
		var ring: PackedVector3Array = guard_rings[i]
		# Reordena: el loft va a lo largo de Z, así que cada anillo es una sección en XY.
		guard_rings[i] = ring
	loft(iron, guard_rings)
	# Pomo facetado.
	set_flat(iron, false)
	lathe(iron, [Vector2(0.0, -0.165), Vector2(0.022, -0.158), Vector2(0.030, -0.140),
		Vector2(0.026, -0.122), Vector2(0.014, -0.112)], 8)
	lathe(iron, [Vector2(0.019, 0.078), Vector2(0.022, 0.086), Vector2(0.016, 0.092)], 8)
	wrapped_grip(b.st(LEATHER), -0.115, 0.080, 0.0165, 10)
	return b.commit(make_material)


static func battle_axe() -> ArrayMesh:
	var b := Builder.new()
	# Astil de madera, un poco más grueso al pie para que no se escurra.
	lathe(b.st(WOOD), [Vector2(0.0, -0.22), Vector2(0.021, -0.22), Vector2(0.023, -0.19),
		Vector2(0.019, -0.10), Vector2(0.018, 0.30), Vector2(0.019, 0.56), Vector2(0.0, 0.575)], 10, Vector3.ZERO, 1.0, 1.5)
	wrapped_grip(b.st(LEATHER), -0.12, 0.10, 0.0205, 8)
	var iron := b.st(IRON)
	set_flat(iron, true)
	# Cabeza barbada: perfil en el plano YZ, extruido en X con grosor que baja hacia el filo.
	var cols := 12
	var rings := []
	for i in cols + 1:
		var t := float(i) / cols
		var z := lerpf(-0.035, 0.155, t)
		# Arriba casi recto; abajo la barba cae hacia el filo.
		var top := 0.545 + 0.02 * t * t
		var bottom := 0.470 - 0.11 * pow(t, 2.2)
		# Grueso junto al ojo y casi cuchilla en el filo.
		var th := lerpf(0.012, 0.0014, smoothstep(0.2, 1.0, t))
		var ring := PackedVector3Array([
			Vector3(-th, bottom, z), Vector3(th, bottom, z), Vector3(th, top, z), Vector3(-th, top, z)])
		rings.append(ring)
	# El loft va a lo largo de Z: cada anillo es la sección XY de esa columna.
	loft(iron, rings)
	# Ojo del hacha alrededor del astil y un pequeño martillo trasero.
	box(iron, Vector3(0, 0.51, -0.005), Vector3(0.05, 0.085, 0.06))
	box(iron, Vector3(0, 0.51, -0.05), Vector3(0.036, 0.05, 0.03))
	return b.commit(make_material)


static func mace() -> ArrayMesh:
	var b := Builder.new()
	lathe(b.st(DARK_WOOD), [Vector2(0.0, -0.17), Vector2(0.020, -0.17), Vector2(0.022, -0.15),
		Vector2(0.018, -0.08), Vector2(0.017, 0.40), Vector2(0.0, 0.41)], 10, Vector3.ZERO, 1.0, 1.5)
	wrapped_grip(b.st(LEATHER), -0.13, 0.09, 0.0195, 9)
	var iron := b.st(IRON)
	# Collar y núcleo de la cabeza.
	lathe(iron, [Vector2(0.024, 0.34), Vector2(0.028, 0.36), Vector2(0.034, 0.39), Vector2(0.040, 0.43),
		Vector2(0.042, 0.47), Vector2(0.036, 0.51), Vector2(0.020, 0.535), Vector2(0.0, 0.54)], 12)
	set_flat(iron, true)
	# Seis pestañas: trapecios gruesos radiales, con el borde exterior en punta roma.
	for k in 6:
		var a := TAU * k / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var th := 0.006
		var inner_lo := Vector3(0, 0.375, 0) + dir * 0.030
		var inner_hi := Vector3(0, 0.515, 0) + dir * 0.030
		var outer_lo := Vector3(0, 0.392, 0) + dir * 0.078
		var outer_hi := Vector3(0, 0.500, 0) + dir * 0.082
		var ring_a := PackedVector3Array([inner_lo - side * th, outer_lo - side * th * 0.4,
			outer_hi - side * th * 0.4, inner_hi - side * th])
		var ring_b := PackedVector3Array([inner_lo + side * th, outer_lo + side * th * 0.4,
			outer_hi + side * th * 0.4, inner_hi + side * th])
		loft(iron, [ring_a, ring_b])
	set_flat(iron, false)
	# Remate.
	lathe(iron, [Vector2(0.0, 0.53), Vector2(0.014, 0.535), Vector2(0.010, 0.56), Vector2(0.0, 0.575)], 8)
	lathe(iron, [Vector2(0.0, -0.19), Vector2(0.021, -0.185), Vector2(0.024, -0.170), Vector2(0.019, -0.160)], 8)
	return b.commit(make_material)


## Espadón a dos manos: hoja larga y ancha, guarda recta, puño largo para las dos manos
## (la izquierda va 0,13 m por debajo de la derecha) y pomo de disco.
static func greatsword() -> ArrayMesh:
	var b := Builder.new()
	var steel := b.st(STEEL)
	set_flat(steel, true)
	blade(steel, 0.135, 1.05, 0.064, 0.013, 0.13)
	var iron := b.st(IRON)
	box(iron, Vector3(0, 0.112, 0), Vector3(0.032, 0.026, 0.30))
	# Remates de la guarda.
	for z in [-0.155, 0.155]:
		box(iron, Vector3(0, 0.112, z), Vector3(0.036, 0.036, 0.02))
	set_flat(iron, false)
	lathe(iron, [Vector2(0.021, 0.086), Vector2(0.024, 0.094), Vector2(0.018, 0.100)], 8)
	# Pomo de disco.
	lathe(iron, [Vector2(0.0, -0.335), Vector2(0.018, -0.332), Vector2(0.034, -0.318),
		Vector2(0.034, -0.300), Vector2(0.018, -0.288), Vector2(0.014, -0.280)], 12)
	wrapped_grip(b.st(LEATHER), -0.282, 0.088, 0.018, 16)
	return b.commit(make_material)


## Astil largo de las armas grandes a dos manos, de [y0] a [y1], con vendas donde van las manos.
static func _long_haft(b: Builder, y0: float, y1: float, radius: float) -> void:
	lathe(b.st(WOOD), [Vector2(0.0, y0), Vector2(radius * 1.05, y0), Vector2(radius * 1.12, y0 + 0.03),
		Vector2(radius, y0 + 0.12), Vector2(radius * 0.95, y1 - 0.05), Vector2(0.0, y1)], 10, Vector3.ZERO, 1.0, 1.0)
	wrapped_grip(b.st(LEATHER), -0.34, 0.08, radius * 1.1, 14)
	# Regatón de hierro al pie.
	lathe(b.st(IRON), [Vector2(0.0, y0 - 0.03), Vector2(radius * 1.2, y0 - 0.02), Vector2(radius * 1.2, y0 + 0.02),
		Vector2(radius * 1.05, y0 + 0.03)], 8)


## Hacha grande a dos manos: la cabeza del hacha de guerra, mayor, al final de un astil largo.
static func great_axe() -> ArrayMesh:
	var b := Builder.new()
	_long_haft(b, -0.40, 0.99, 0.021)
	var iron := b.st(IRON)
	set_flat(iron, true)
	var cols := 14
	var rings := []
	for i in cols + 1:
		var t := float(i) / cols
		var z := lerpf(-0.045, 0.235, t)
		var top := 0.955 + 0.05 * t * t
		var bottom := 0.835 - 0.19 * pow(t, 2.0)
		var th := lerpf(0.016, 0.0016, smoothstep(0.2, 1.0, t))
		rings.append(PackedVector3Array([
			Vector3(-th, bottom, z), Vector3(th, bottom, z), Vector3(th, top, z), Vector3(-th, top, z)]))
	loft(iron, rings)
	box(iron, Vector3(0, 0.90, -0.005), Vector3(0.058, 0.12, 0.07))
	# Pico trasero.
	loft(iron, [
		PackedVector3Array([Vector3(-0.014, 0.87, -0.04), Vector3(0.014, 0.87, -0.04), Vector3(0.014, 0.93, -0.04), Vector3(-0.014, 0.93, -0.04)]),
		PackedVector3Array([Vector3(-0.003, 0.885, -0.13), Vector3(0.003, 0.885, -0.13), Vector3(0.003, 0.895, -0.13), Vector3(-0.003, 0.895, -0.13)]),
	])
	return b.commit(make_material)


## Martillo de guerra a dos manos: mazo de hierro con la cara hacia el filo (+Z) y un pico
## detrás, sobre un astil largo con barras de hierro bajo la cabeza.
static func war_hammer() -> ArrayMesh:
	var b := Builder.new()
	_long_haft(b, -0.40, 0.98, 0.022)
	var iron := b.st(IRON)
	set_flat(iron, true)
	# Mazo: prisma de sección octogonal a lo largo de Z.
	var faces := []
	for z in [-0.02, 0.10, 0.125]:
		var r := 0.058 if z < 0.12 else 0.050
		var ring := PackedVector3Array()
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			ring.append(Vector3(cos(a) * r, 0.90 + sin(a) * r, z))
		faces.append(ring)
	loft(iron, faces)
	# Pico trasero, curvado hacia abajo.
	loft(iron, [
		PackedVector3Array([Vector3(-0.022, 0.87, -0.02), Vector3(0.022, 0.87, -0.02), Vector3(0.022, 0.93, -0.02), Vector3(-0.022, 0.93, -0.02)]),
		PackedVector3Array([Vector3(-0.012, 0.875, -0.10), Vector3(0.012, 0.875, -0.10), Vector3(0.012, 0.905, -0.10), Vector3(-0.012, 0.905, -0.10)]),
		PackedVector3Array([Vector3(-0.002, 0.855, -0.17), Vector3(0.002, 0.855, -0.17), Vector3(0.002, 0.862, -0.17), Vector3(-0.002, 0.862, -0.17)]),
	])
	# Barras de refuerzo bajo la cabeza y remate.
	for side in [-1.0, 1.0]:
		box(iron, Vector3(side * 0.024, 0.78, 0), Vector3(0.006, 0.18, 0.02))
	set_flat(iron, false)
	lathe(iron, [Vector2(0.0, 0.955), Vector2(0.016, 0.96), Vector2(0.010, 0.99), Vector2(0.0, 1.01)], 8)
	return b.commit(make_material)


static func spear() -> ArrayMesh:
	var b := Builder.new()
	lathe(b.st(WOOD), [Vector2(0.0, -0.92), Vector2(0.014, -0.92), Vector2(0.016, -0.88),
		Vector2(0.017, 0.0), Vector2(0.0155, 0.90), Vector2(0.0, 0.905)], 8, Vector3.ZERO, 1.0, 0.8)
	wrapped_grip(b.st(LEATHER), -0.10, 0.12, 0.0185, 8)
	# Ataduras de cuerda bajo la moharra.
	wrapped_grip(b.st(CORD), 0.83, 0.90, 0.0175, 6)
	var steel := b.st(STEEL)
	lathe(steel, [Vector2(0.017, 0.88), Vector2(0.020, 0.93), Vector2(0.013, 0.965)], 8)
	set_flat(steel, true)
	blade(steel, 0.955, 0.21, 0.066, 0.014, 0.08)
	# Regatón.
	lathe(b.st(IRON), [Vector2(0.0, -0.965), Vector2(0.010, -0.94), Vector2(0.0155, -0.905)], 8)
	return b.commit(make_material)


## Curva de las palas del arco: z (hacia el blanco) según y. Las puntas vuelven hacia delante
## (recurvo). [draw] 0..1 dobla más las palas al tensar.
static func bow_limb_z(y: float, half: float, draw: float = 0.0) -> float:
	var t := absf(y) / half
	var bend := -(0.15 + 0.15 * draw) * t * t
	var recurve := 0.055 * pow(maxf(t - 0.78, 0.0) / 0.22, 2.0)
	return bend + recurve


const BOW_HALF := 0.68


## Punta de la pala (donde engancha la cuerda). [draw] 0..1: al tensar, las puntas vienen
## hacia el arquero y se acercan entre sí (las palas giran, no se estiran).
static func bow_tip(top: bool, draw: float = 0.0) -> Vector3:
	var y := BOW_HALF if top else -BOW_HALF
	var z := bow_limb_z(y, BOW_HALF, draw)
	var rest_z := bow_limb_z(y, BOW_HALF)
	return Vector3(0, y * (1.0 - 0.5 * (z - rest_z) * (z - rest_z) / (BOW_HALF * BOW_HALF)), z)


## Arco con una forma de mezcla "drawn" (palas dobladas a tope): el visual la mueve con la
## tensión. Misma topología en las dos formas.
static func bow_flexing() -> ArrayMesh:
	var rest := bow(0.0)
	var drawn := bow(1.0)
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	mesh.add_blend_shape(&"drawn")
	for i in rest.get_surface_count():
		var arrays := rest.surface_get_arrays(i)
		var target := drawn.surface_get_arrays(i)
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = target[Mesh.ARRAY_VERTEX]
		shape[Mesh.ARRAY_NORMAL] = target[Mesh.ARRAY_NORMAL]
		shape[Mesh.ARRAY_TANGENT] = target[Mesh.ARRAY_TANGENT]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
		mesh.surface_set_material(i, rest.surface_get_material(i))
	return mesh


static func bow(draw: float = 0.0) -> ArrayMesh:
	var b := Builder.new()
	var wood := b.st(DARK_WOOD)
	for sign in [1.0, -1.0]:
		var points := PackedVector3Array()
		var radii := PackedVector2Array()
		var steps := 16
		for i in steps + 1:
			var t := float(i) / steps
			var y: float = sign * lerpf(0.05, BOW_HALF, t)
			var z := bow_limb_z(y, BOW_HALF, draw)
			var rest_z := bow_limb_z(y, BOW_HALF)
			points.append(Vector3(0, y * (1.0 - 0.5 * (z - rest_z) * (z - rest_z) / (BOW_HALF * BOW_HALF)), z))
			# Pala ancha en X y fina en Z; se afina hacia la punta.
			radii.append(Vector2(lerpf(0.020, 0.007, t), lerpf(0.011, 0.005, t)))
		tube(wood, points, radii, 8, Vector3.RIGHT)
	# Puño y ventana de flecha.
	lathe(b.st(LEATHER), [Vector2(0.0, -0.075), Vector2(0.019, -0.07), Vector2(0.021, -0.05),
		Vector2(0.021, 0.05), Vector2(0.019, 0.07), Vector2(0.0, 0.075)], 10, Vector3(0, 0, 0.004), 1.0, 12.0)
	for sign in [1.0, -1.0]:
		var tip := bow_tip(sign > 0.0, draw)
		lathe(b.st(CORD), [Vector2(0.0, -0.012), Vector2(0.009, -0.008), Vector2(0.009, 0.008),
			Vector2(0.0, 0.012)], 6, tip)
	return b.commit(make_material)


## Aljaba de cuero: boca en el origen, el fondo hacia -Y (ArcheryPose.QUIVER_LENGTH).
static func quiver() -> ArrayMesh:
	var b := Builder.new()
	var h := ArcheryPose.QUIVER_LENGTH
	# Tubo algo más ancho arriba, con el borde vuelto hacia dentro para que se vea el hueco.
	lathe(b.st(LEATHER), [Vector2(0.0, -h), Vector2(0.036, -h + 0.004), Vector2(0.042, -h + 0.03),
		Vector2(0.046, -0.3), Vector2(0.052, -0.03), Vector2(0.056, -0.012), Vector2(0.056, 0.0),
		Vector2(0.049, 0.004), Vector2(0.046, -0.02), Vector2(0.044, -0.08), Vector2(0.0, -0.08)], 14, Vector3.ZERO, 1.0, 3.0)
	# Refuerzos y la correa que cruza el pecho sale de las dos argollas.
	for y in [-0.05, -h * 0.55, -h + 0.05]:
		lathe(b.st(CORD), [Vector2(0.0, y - 0.018), Vector2(0.050 if y > -0.3 else 0.047, y - 0.016),
			Vector2(0.051 if y > -0.3 else 0.048, y + 0.016), Vector2(0.0, y + 0.018)], 14)
	return b.commit(make_material)


## Puntas de las horquillas del tirachinas (donde se ata la goma).
const SLING_PRONG_TIPS := [Vector3(-0.045, 0.125, 0.0), Vector3(0.045, 0.125, 0.0)]


static func slingshot() -> ArrayMesh:
	var b := Builder.new()
	var wood := b.st(WOOD)
	lathe(wood, [Vector2(0.0, -0.105), Vector2(0.015, -0.10), Vector2(0.016, -0.06),
		Vector2(0.015, 0.0), Vector2(0.017, 0.03), Vector2(0.0, 0.05)], 10, Vector3.ZERO, 1.0, 2.0)
	for tip in SLING_PRONG_TIPS:
		var points := PackedVector3Array([Vector3(tip.x * 0.08, 0.01, 0), Vector3(tip.x * 0.5, 0.068, 0),
			Vector3(tip.x * 0.9, 0.105, 0), tip])
		var radii := PackedVector2Array([Vector2(0.012, 0.012), Vector2(0.0105, 0.0105),
			Vector2(0.0095, 0.0095), Vector2(0.009, 0.009)])
		tube(wood, points, radii, 8, Vector3.FORWARD, false)
		lathe(wood, [Vector2(0.009, -0.004), Vector2(0.0085, 0.0), Vector2(0.0, 0.004)], 8, tip)
	wrapped_grip(b.st(LEATHER), -0.09, -0.01, 0.0165, 6)
	for tip in SLING_PRONG_TIPS:
		lathe(b.st(CORD), [Vector2(0.0, -0.012), Vector2(0.0105, -0.01), Vector2(0.0105, 0.004),
			Vector2(0.0, 0.006)], 6, tip - Vector3(0, 0.012, 0))
	return b.commit(make_material)


## Largo de la flecha: el origen es el centro, la punta en +Y.
const ARROW_LENGTH := 0.74


static func arrow() -> ArrayMesh:
	var b := Builder.new()
	var h := ARROW_LENGTH * 0.5
	lathe(b.st(WOOD), [Vector2(0.0, -h), Vector2(0.0045, -h + 0.004), Vector2(0.0045, h - 0.045),
		Vector2(0.0, h - 0.04)], 6, Vector3.ZERO, 1.0, 1.0)
	# Punta de sílex de cuatro caras.
	var flint := b.st(FLINT)
	var tip := Vector3(0, h + 0.012, 0)
	var y0 := h - 0.05
	var ring := [Vector3(0.014, y0 + 0.012, 0), Vector3(0, y0 + 0.004, 0.004), Vector3(-0.014, y0 + 0.012, 0),
		Vector3(0, y0 + 0.004, -0.004)]
	var neck := Vector3(0, y0 - 0.004, 0)
	for j in 4:
		var k := (j + 1) % 4
		tri(flint, ring[j], ring[k], tip)
		tri(flint, ring[k], ring[j], neck)
	# Atadura de la punta.
	lathe(b.st(CORD), [Vector2(0.005, y0 - 0.012), Vector2(0.0055, y0 - 0.006), Vector2(0.005, y0)], 6)
	# Tres plumas.
	var feather := b.st(FEATHER)
	for k in 3:
		var a := TAU * k / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		var f0 := Vector3(0, -h + 0.03, 0) + d * 0.004
		var f1 := Vector3(0, -h + 0.16, 0) + d * 0.004
		var f2 := Vector3(0, -h + 0.07, 0) + d * 0.026
		var f3 := Vector3(0, -h + 0.035, 0) + d * 0.022
		quad(feather, f0, f3, f2, f1)
	# Culatín.
	lathe(b.st(CORD), [Vector2(0.0, -h - 0.012), Vector2(0.0055, -h - 0.01), Vector2(0.0055, -h + 0.01),
		Vector2(0.0045, -h + 0.012)], 6)
	return b.commit(_arrow_material)


static func _arrow_material(kind: StringName) -> Material:
	var mat := make_material(kind)
	if kind == FEATHER:
		mat.albedo_color = Color(0.78, 0.22, 0.14)
	return mat


static func pebble() -> ArrayMesh:
	var b := Builder.new()
	var st := b.st(STONE)
	var sphere := SphereMesh.new()
	sphere.radius = 0.028
	sphere.height = 0.05
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 60.0
	for i in verts.size():
		var v := verts[i]
		var bump := 1.0 + 0.18 * noise.get_noise_3dv(v)
		_emit(st, uvs[i], Vector3(v.x * 1.15, v.y, v.z * 0.9) * bump)
	for i in indices:
		st.add_index(i)
	return b.commit(make_material)


## Rama caída: un palo torcido de corteza con un par de ramitas, para recoger del suelo. Se empuña
## por el origen, cerca del extremo grueso, y +Y va hacia la punta. [variant] cambia la forma y el
## largo (la 0 es la que se lleva en la mano).
static func branch(variant: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + variant * 104729
	var length := 1.3 if variant == 0 else rng.randf_range(0.95, 1.5)
	var b := Builder.new()
	var bark := b.st(BARK)
	var points := PackedVector3Array()
	var radii := PackedVector2Array()
	var steps := 9
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	for i in steps + 1:
		var t := float(i) / steps
		# Curva suave de un lado y nudos que tuercen un poco el palo.
		var wobble := bend * sin(t * PI) * 0.045 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.008
		points.append(Vector3(0, -0.18 + length * t, 0) + wobble)
		var r := lerpf(0.026, 0.012, t) * rng.randf_range(0.92, 1.08)
		radii.append(Vector2(r, r * rng.randf_range(0.85, 1.0)))
	tube(bark, points, radii, 8, Vector3.RIGHT, true)
	# Ramitas: salen hacia la punta, finas y cortas, alguna partida.
	for k in rng.randi_range(2, 3):
		var at := rng.randf_range(0.35, 0.85)
		var i := int(at * steps)
		var base := points[i]
		var around := rng.randf() * TAU
		var dir := (Vector3(cos(around), 0, sin(around)) * rng.randf_range(0.6, 1.0) + Vector3.UP * rng.randf_range(0.6, 1.1)).normalized()
		var twig_length := rng.randf_range(0.08, 0.26)
		var twig := PackedVector3Array([base, base + dir * twig_length * 0.5 + Vector3(0, 0.01, 0), base + dir * twig_length])
		var r0 := radii[i].x * 0.45
		tube(bark, twig, PackedVector2Array([Vector2(r0, r0), Vector2(r0 * 0.7, r0 * 0.7), Vector2(r0 * 0.4, r0 * 0.4)]), 5, Vector3.RIGHT, true)
	return b.commit(make_material)



## La rama tirada en el suelo (objeto del planeta): tumbada, con el palo a lo largo de -Z, centrada
## en el origen y con lo más bajo un centímetro por debajo de y = 0.
static func lying_branch(variant: int) -> ArrayMesh:
	var source := branch(variant)
	var length := source.get_aabb().size.y
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, length * 0.5 - 0.18))
	xf.origin.y = -(xf * source.get_aabb()).position.y - 0.01
	var mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, xf)
		st.set_material(source.surface_get_material(surface))
		st.commit(mesh)
	return mesh
