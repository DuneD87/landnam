class_name SeaIceMeshes extends RefCounted

## Mallas de la banquisa: las losas de los témpanos (un ArrayMesh por bloque) y los icebergs.
## Estático y sin estado: lo llaman los hilos de SeaIceFloes.

## Bisel del canto de arriba: cuánto se mete la cara de arriba y cuánto baja el canto.
const TOP_BEVEL := 0.35
const TOP_DROP := 0.12
const BOTTOM_BEVEL := 0.5
const SEGMENTS := 44


## Arrays de un bloque de témpanos, con los vértices relativos a `origin` (planeta).
## CUSTOM0 = centro del témpano (mismo espacio) + radio; CUSTOM1 = semilla, francobordo, calado.
## El shader mueve cada témpano entero con la ola alrededor de su centro.
static func floe_arrays(floes: Array[Dictionary], origin: Vector3) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var indices := PackedInt32Array()
	for floe in floes:
		_add_floe(floe, origin, verts, normals, custom0, custom1, indices)
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


const FLOE_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)


static func _add_floe(floe: Dictionary, origin: Vector3, verts: PackedVector3Array,
		normals: PackedVector3Array, custom0: PackedFloat32Array, custom1: PackedFloat32Array,
		indices: PackedInt32Array) -> void:
	var poly: PackedVector2Array = floe.poly
	var basis: Basis = floe.basis
	var center: Vector3 = floe.center - origin
	var top: float = floe.top
	var bottom: float = floe.bottom
	var seed: float = floe.seed
	var count := poly.size()
	var c0 := [center.x, center.y, center.z, float(floe.radius)]
	var c1 := [seed, top, bottom, 0.0]
	var up := basis.y

	var add := func(p: Vector2, h: float, n: Vector3) -> int:
		verts.append(center + basis.x * p.x + basis.y * h + basis.z * p.y)
		normals.append(n.normalized())
		custom0.append_array(c0)
		custom1.append_array(c1)
		return verts.size() - 1

	# Normal hacia fuera de cada esquina (media de sus dos aristas): con los chaflanes el canto se ve
	# redondeado aunque los anillos compartan vértices.
	var out := PackedVector3Array()
	for i in count:
		out.append((_edge_normal(poly, i, basis) + _edge_normal(poly, (i - 1 + count) % count, basis)).normalized())
	var low := bottom + BOTTOM_BEVEL * 0.6
	var drop := top - TOP_DROP
	# Anillos (cada uno con la normal de la parte que cierra): cara de arriba, bisel, lado y fondo.
	var apex: int = add.call(Vector2.ZERO, top + lerpf(0.04, 0.2, fmod(seed * 7.13, 1.0)), up)
	var roof := PackedInt32Array()
	var bevel_in := PackedInt32Array()
	var bevel_out := PackedInt32Array()
	var side_top := PackedInt32Array()
	var side_low := PackedInt32Array()
	var base_ring := PackedInt32Array()
	for i in count:
		var p := poly[i]
		var inward := -p.normalized()
		var p_in := p + inward * minf(TOP_BEVEL, p.length() * 0.4)
		var p_bottom := p + inward * minf(BOTTOM_BEVEL, p.length() * 0.5)
		roof.append(add.call(p_in, top, up))
		bevel_in.append(add.call(p_in, top, up * 1.4 + out[i]))
		bevel_out.append(add.call(p, drop, up * 0.6 + out[i]))
		side_top.append(add.call(p, drop, out[i]))
		side_low.append(add.call(p, low, out[i]))
		base_ring.append(add.call(p_bottom, bottom, out[i] * 0.5 - up))
	var keel: int = add.call(Vector2.ZERO, bottom, -up)
	for i in count:
		var j := (i + 1) % count
		var edge := _edge_normal(poly, i, basis)
		_index_tri(apex, roof[i], roof[j], up, verts, indices)
		_index_quad(bevel_in[i], bevel_in[j], bevel_out[j], bevel_out[i], edge + up, verts, indices)
		_index_quad(side_top[i], side_top[j], side_low[j], side_low[i], edge, verts, indices)
		_index_quad(side_low[i], side_low[j], base_ring[j], base_ring[i], edge - up, verts, indices)
		_index_tri(keel, base_ring[j], base_ring[i], -up, verts, indices)


## Normal hacia fuera de la arista i -> i+1 (el polígono es antihorario en u/w).
static func _edge_normal(poly: PackedVector2Array, i: int, basis: Basis) -> Vector3:
	var e := poly[(i + 1) % poly.size()] - poly[i]
	var n := Vector2(e.y, -e.x).normalized()
	return (basis.x * n.x + basis.z * n.y).normalized()


## Triángulo indexado. Godot toma como cara frontal la que se ve en sentido horario: si el orden
## dado mira al revés de `facing`, se da la vuelta.
static func _index_tri(a: int, b: int, c: int, facing: Vector3, verts: PackedVector3Array,
		indices: PackedInt32Array) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(facing) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])


static func _index_quad(a: int, b: int, c: int, d: int, facing: Vector3, verts: PackedVector3Array,
		indices: PackedInt32Array) -> void:
	_index_tri(a, b, c, facing, verts, indices)
	_index_tri(a, c, d, facing, verts, indices)


## Iceberg en su marco local (y = arriba, 0 = nivel del mar). Tabular (kind 0): paredes casi
## verticales con estratos y techo plano; cúpula (kind 1): masa redondeada con picos. Bajo el agua
## sigue más del doble de lo que asoma, que se ve buceando.
static func berg_mesh(berg: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(berg.seed)
	var radius: float = berg.radius
	var height: float = berg.height
	var draft: float = berg.draft
	var kind: int = berg.kind
	var noise := FastNoiseLite.new()
	noise.seed = int(berg.seed) & 0x7fffffff
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.6 / radius
	noise.fractal_octaves = 4
	var harmonics: Array[Vector2] = []
	for k in range(2, 7):
		harmonics.append(Vector2(rng.randf_range(0.04, 0.16) / pow(k, 0.7), rng.randf() * TAU))

	# Perfil: (altura, escala del contorno). De la quilla al techo.
	var profile: Array[Vector2] = []
	var under := [[-1.0, 0.35], [-0.85, 0.7], [-0.6, 0.95], [-0.35, 1.08], [-0.12, 1.04], [-0.03, 1.0]]
	for p in under:
		profile.append(Vector2(p[0] * draft, p[1]))
	if kind == 0:
		var strata := 7
		for j in strata:
			var t := float(j + 1) / float(strata)
			profile.append(Vector2(t * height * 0.94, 1.0 - t * 0.04 + rng.randf_range(-0.035, 0.035)))
		profile.append(Vector2(height, 0.9))
	else:
		for j in 8:
			var t := float(j + 1) / 8.0
			profile.append(Vector2(t * height, pow(maxf(1.0 - pow(t, 1.7), 0.0), 0.55) * 0.97 + 0.03))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for p in profile:
		var ring := PackedVector3Array()
		for s in SEGMENTS:
			var angle := TAU * float(s) / SEGMENTS
			var dir := Vector3(cos(angle), 0.0, sin(angle))
			var r := radius * p.y * _outline(harmonics, angle)
			var point := dir * r + Vector3(0.0, p.x, 0.0)
			# Rugosidad 3D, más fuerte en las paredes que en la línea de agua (la ola la pule).
			var rough := noise.get_noise_3dv(point) * radius * 0.12
			point += dir * rough
			if kind == 1:
				point.y += maxf(noise.get_noise_2d(point.x * 0.7, point.z * 0.7), 0.0) * height * 0.5 * p.y * float(p.x > 0.0)
			ring.append(point)
		rings.append(ring)
	for j in rings.size() - 1:
		for s in SEGMENTS:
			var s1 := (s + 1) % SEGMENTS
			_berg_quad(st, rings[j][s], rings[j][s1], rings[j + 1][s1], rings[j + 1][s])
	# Techo: anillos concéntricos con algo de relieve, y el centro.
	var top_ring := rings[rings.size() - 1]
	var roof_rings := 3
	var prev := top_ring
	var top_y := profile[profile.size() - 1].x
	for k in roof_rings:
		var f := 1.0 - float(k + 1) / float(roof_rings + 1)
		var ring := PackedVector3Array()
		for s in SEGMENTS:
			var p := top_ring[s]
			var q := Vector3(p.x * f, 0.0, p.z * f)
			var bump := noise.get_noise_2d(q.x, q.z) * height * (0.06 if kind == 0 else 0.25)
			q.y = lerpf(top_y, p.y, f * f) + maxf(bump, -0.3) + (1.0 - f) * height * (0.02 if kind == 0 else 0.3)
			ring.append(q)
		for s in SEGMENTS:
			var s1 := (s + 1) % SEGMENTS
			_berg_quad(st, prev[s], prev[s1], ring[s1], ring[s])
		prev = ring
	var apex := Vector3(0.0, prev[0].y, 0.0)
	var sum := 0.0
	for p in prev:
		sum += p.y
	apex.y = sum / SEGMENTS + (0.1 if kind == 0 else height * 0.12)
	for s in SEGMENTS:
		_berg_tri(st, prev[s], prev[(s + 1) % SEGMENTS], apex)
	# Quilla.
	var keel := Vector3(0.0, -draft * 1.02, 0.0)
	for s in SEGMENTS:
		_berg_tri(st, rings[0][(s + 1) % SEGMENTS], rings[0][s], keel)
	st.index()
	st.generate_normals()
	return st.commit()


static func _outline(harmonics: Array[Vector2], angle: float) -> float:
	var r := 1.0
	for k in harmonics.size():
		r += harmonics[k].x * sin(float(k + 2) * angle + harmonics[k].y)
	return r


## Cara hacia fuera: con los anillos subiendo y el ángulo creciendo de +x a +z, a-b-c se ve en
## sentido horario desde fuera, que es la cara frontal en Godot.
static func _berg_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_berg_tri(st, a, b, c)
	_berg_tri(st, a, c, d)


static func _berg_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
