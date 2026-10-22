@tool
class_name ProcMesh
extends RefCounted

## Primitivas para generar mallas por código con SurfaceTool: superficies de revolución, tubos,
## triángulos, prismas y cajas, más el constructor multimaterial y las texturas de ruido de sus
## materiales. Las usan las armas (WeaponMeshes), los objetos de supervivencia (SurvivalMeshes) y
## las vísceras (GutPile).


static func noise_texture(dark: Color, light: Color, frequency: float, seed_value: int) -> NoiseTexture2D:
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

	## [flip_faces] invierte los triángulos y genera sus normales y tangentes hacia el exterior
	## cuando las piezas se han construido con el orden contrario al frontal horario de Godot.
	func commit(material_for: Callable, flip_faces: bool = false) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for kind in tools:
			var tool: SurfaceTool = tools[kind]
			tool.generate_normals(flip_faces)
			tool.generate_tangents()
			var material: Material = material_for.call(kind)
			if flip_faces:
				var arrays := tool.commit_to_arrays()
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for i in range(0, indices.size(), 3):
					var second := indices[i + 1]
					indices[i + 1] = indices[i + 2]
					indices[i + 2] = second
				arrays[Mesh.ARRAY_INDEX] = indices
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				mesh.surface_set_material(mesh.get_surface_count() - 1, material)
			else:
				tool.set_material(material)
				tool.commit(mesh)
		return mesh


## Superficie de revolución alrededor de Y. [profile] = [(radio, y)] de abajo arriba. [twist]
## retuerce las UV (vendas en espiral).
static func lathe(st: SurfaceTool, profile: Array, segments: int = 12, center: Vector3 = Vector3.ZERO,
		u_scale: float = 1.0, v_scale: float = 4.0) -> void:
	var rings := profile.size()
	var base := vertex_count(st)
	for i in rings:
		var r: float = profile[i].x
		var y: float = profile[i].y
		for j in segments + 1:
			var a := TAU * float(j) / float(segments)
			emit(st, Vector2(float(j) / segments * u_scale, y * v_scale), center + Vector3(cos(a) * r, y, sin(a) * r))
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
		var c := vertex_count(st)
		emit(st, Vector2(0.5, 0.5), center + Vector3(0, y, 0))
		for j in segments + 1:
			var a := TAU * float(j) / float(segments)
			emit(st, Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5), center + Vector3(cos(a) * r, y, sin(a) * r))
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
	var base := vertex_count(st)
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
			emit(st, Vector2(float(j) / segments, length * 4.0), points[i] + offset)
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
		var c := vertex_count(st)
		emit(st, Vector2(0.5, 0.5), points[end])
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
	var base := vertex_count(st)
	for p in [a, b, c]:
		emit(st, Vector2(p.x + p.z, p.y) * uv_scale, p)
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
		fan(st, rings[0], true)
	if cap_end:
		fan(st, rings[rings.size() - 1], false)


## Tapa un anillo con un abanico de triángulos desde su centro.
static func fan(st: SurfaceTool, ring: PackedVector3Array, flip: bool) -> void:
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
static func vertex_count(st: SurfaceTool) -> int:
	return st.get_meta(&"vcount", 0)


## Caras planas: los vértices que siguen no se suavizan con sus vecinos (aristas de metal
## marcadas). Por defecto SurfaceTool suaviza todo lo que coincide en posición.
static func set_flat(st: SurfaceTool, flat: bool) -> void:
	st.set_meta(&"flat", flat)


## Añade un vértice con su UV, en el grupo de suavizado que diga set_flat, y lo cuenta.
static func emit(st: SurfaceTool, uv: Vector2, p: Vector3) -> void:
	st.set_smooth_group(0xFFFFFFFF if st.get_meta(&"flat", false) else 0)
	st.set_uv(uv)
	st.add_vertex(p)
	st.set_meta(&"vcount", vertex_count(st) + 1)
