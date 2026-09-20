extends RefCounted

## LODs de la mata original: conserva hojas completas y su silueta, sin tarjetas.
## La selección es anidada (las 8 hojas lejanas también existen en los LODs mayores).
## Solo se construye al cargar la vegetación; no se simplifica durante cada frame.

static func build(source: Mesh) -> Array:
	if source == null or source.get_surface_count() != 1:
		push_error("Grass LOD: se necesita una mata de una superficie.")
		return []
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var blades: Array = _find_blades(vertices, indices)
	if blades.size() < 8:
		push_error("Grass LOD: no se han encontrado suficientes hojas separadas.")
		return []
	var ordered: Array = _order_blades(blades, vertices)
	var material: Material = source.surface_get_material(0)
	# La curva se calcula una vez por hoja y se muestrea igual en todos los LODs.
	# UV: transversal / semilla. UV2: raíz->punta / marca de geometría refinada.
	var result: Array = []
	for lod in 4:
		var count: int = maxi(blades.size() >> lod, 1)
		var width: float = [1.0, 1.45, 2.0, 2.8][lod]
		var segments: int = [5, 3, 2, 1][lod]
		var output_vertices := PackedVector3Array()
		var output_normals := PackedVector3Array()
		var output_uvs := PackedVector2Array()
		var output_uv2s := PackedVector2Array()
		var output_indices := PackedInt32Array()
		for blade_index in count:
			_append_curved_blade(ordered[blade_index], vertices, normals, segments,
				width, _blade_seed(blade_index), output_vertices, output_normals,
				output_uvs, output_uv2s, output_indices)
		var output: Array = []
		output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = output_vertices
		output[Mesh.ARRAY_NORMAL] = output_normals
		output[Mesh.ARRAY_TEX_UV] = output_uvs
		output[Mesh.ARRAY_TEX_UV2] = output_uv2s
		output[Mesh.ARRAY_INDEX] = output_indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output)
		mesh.surface_set_material(0, material)
		result.append(mesh)
	return result


static func _blade_seed(index: int) -> float:
	var h: int = ((index + 1) * 2654435761) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


static func _find_blades(vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var parents := PackedInt32Array()
	for index in vertices.size():
		parents.append(index)
	for index in range(0, indices.size(), 3):
		var root: int = _root(parents, indices[index])
		parents[_root(parents, indices[index + 1])] = root
		parents[_root(parents, indices[index + 2])] = root
	var groups: Dictionary = {}
	for index in vertices.size():
		var root: int = _root(parents, index)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(index)
	var blades: Array = groups.values()
	for blade in blades:
		blade.sort_custom(func(a: int, b: int) -> bool: return vertices[a].y < vertices[b].y)
	return blades


static func _root(parents: PackedInt32Array, index: int) -> int:
	while parents[index] != index:
		index = parents[index]
	return index


static func _order_blades(blades: Array, vertices: PackedVector3Array) -> Array:
	var remaining: Array = blades.duplicate()
	remaining.sort_custom(func(a: Array, b: Array) -> bool:
		return vertices[a.back()].y > vertices[b.back()].y)
	var chosen: Array = [remaining.pop_front()]
	# Muestreo por máxima separación de puntas: conserva altura y hojas exteriores,
	# evitando quedarse solo con un lado del modelo o elegir hojas al azar por LOD.
	while not remaining.is_empty():
		var best: int = 0
		var best_distance: float = -1.0
		for index in remaining.size():
			var tip: Vector3 = vertices[remaining[index].back()]
			var nearest: float = INF
			for blade in chosen:
				nearest = minf(nearest, tip.distance_squared_to(vertices[blade.back()]))
			if nearest > best_distance:
				best_distance = nearest
				best = index
		chosen.append(remaining[best])
		remaining.remove_at(best)
	return chosen


## Conserva raíces, puntas y reparto del asset, pero reconstruye una cinta curva.
## La sección se ensancha en el tercio inferior y acaba en una punta fina; las
## normales siguen la tangente real de la curva en vez de heredar caras planas.
static func _append_curved_blade(blade: Array, vertices: PackedVector3Array,
		normals: PackedVector3Array, segments: int, width: float, seed: float,
		out_vertices: PackedVector3Array, out_normals: PackedVector3Array,
		out_uvs: PackedVector2Array, out_uv2s: PackedVector2Array,
		out_indices: PackedInt32Array) -> void:
	var base: int = out_vertices.size()
	var root: Vector3 = (vertices[blade[0]] + vertices[blade[1]]) * 0.5
	var tip: Vector3 = vertices[blade.back()]
	var height: float = tip.y - root.y
	var side: Vector3 = vertices[blade[1]] - vertices[blade[0]]
	side.y = 0.0
	var root_width: float = side.length()
	side = side.normalized()
	var lean := Vector3(tip.x - root.x, 0.0, tip.z - root.z)
	# Arranque vertical, arco abierto arriba. Mantiene la altura de la mata.
	var control_a: Vector3 = root + Vector3.UP * height * 0.60 + lean * 0.06
	var control_b: Vector3 = tip - lean * 0.40 - Vector3.UP * height * (0.015 + seed * 0.085)
	var blade_width: float = maxf(root_width * 1.20, height * 0.065)
	var reference_normal: Vector3 = normals[blade[0]]
	# La orientación se decide en la raíz y se mantiene en toda la cinta.
	# Reevaluarla contra la normal importada en cada sección puede invertir la
	# normal cuando la punta se curva más de 90 grados respecto a esa referencia.
	var facing: float = -1.0 if (control_a - root).cross(side).dot(reference_normal) < 0.0 else 1.0
	for segment in segments + 1:
		var t: float = float(segment) / float(segments)
		var center: Vector3 = root.bezier_interpolate(control_a, control_b, tip, t)
		var tangent: Vector3 = root.bezier_derivative(control_a, control_b, tip, t).normalized()
		# Una torsión pequeña evita que todas las caras de una hoja brillen a la vez.
		var section_side: Vector3 = side.rotated(Vector3.UP, (seed - 0.5) * 0.42 * t)
		var normal: Vector3 = tangent.cross(section_side).normalized() * facing
		if segment == segments:
			out_vertices.append(tip)
			out_normals.append(normal)
			out_uvs.append(Vector2(0.5, seed))
			out_uv2s.append(Vector2(1.0, 1.0))
			continue
		# Ancho uniforme al arrancar, hombro suave y estrechamiento hasta la punta.
		var profile: float = (1.0 - pow(t, 1.65)) * (0.56 + 0.75 * sin(PI * t))
		# Un único triángulo conserva área aproximada de la cinta completa.
		if segments == 1:
			profile = 1.02
		for edge in 2:
			out_vertices.append(center + section_side * (float(edge) - 0.5) * blade_width * width * profile)
			out_normals.append(normal)
			out_uvs.append(Vector2(float(edge), seed))
			out_uv2s.append(Vector2(t, 1.0))
	for segment in segments:
		var a: int = base + segment * 2
		_append_triangle(a, a + 1, a + 2, out_vertices, out_normals, out_indices)
		if segment < segments - 1:
			_append_triangle(a + 1, a + 3, a + 2, out_vertices, out_normals, out_indices)


static func _append_triangle(a: int, b: int, c: int, vertices: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	# Godot usa caras frontales en sentido horario.
	var cross_normal: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if cross_normal.dot(normals[a] + normals[b] + normals[c]) > 0.0:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))
