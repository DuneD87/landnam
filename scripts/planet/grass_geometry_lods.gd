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
	var full := ArrayMesh.new()
	# Copiar los arrays elimina los LODs automáticos importados, que eliminaban hojas
	# antes de que el instancer eligiera nuestro LOD y no compensaban su anchura.
	full.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	full.surface_set_material(0, material)
	var result: Array = [full]
	for lod in range(1, 4):
		var count: int = maxi(blades.size() >> lod, 1)
		var width: float = [1.0, 1.45, 2.0, 2.8][lod]
		var output_vertices := PackedVector3Array()
		var output_normals := PackedVector3Array()
		var output_indices := PackedInt32Array()
		for blade_index in count:
			var blade: Array = ordered[blade_index]
			if lod == 1:
				_append_original_blade(blade, vertices, normals, indices, width,
					output_vertices, output_normals, output_indices)
			else:
				_append_blade(blade, vertices, normals, indices, 2 if lod == 2 else 1,
					width, output_vertices, output_normals, output_indices)
		var output: Array = []
		output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = output_vertices
		output[Mesh.ARRAY_NORMAL] = output_normals
		output[Mesh.ARRAY_INDEX] = output_indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output)
		mesh.surface_set_material(0, material)
		result.append(mesh)
	return result


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


static func _section(blade: Array, vertices: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array, height: float) -> Array:
	var points: Array = []
	for offset in range(0, indices.size(), 3):
		if not indices[offset] in blade:
			continue
		for edge in 3:
			var a: int = indices[offset + edge]
			var b: int = indices[offset + (edge + 1) % 3]
			var dy: float = vertices[b].y - vertices[a].y
			if absf(dy) < 0.00001:
				continue
			var t: float = (height - vertices[a].y) / dy
			if t >= 0.0 and t <= 1.0:
				points.append([vertices[a].lerp(vertices[b], t), normals[a].lerp(normals[b], t).normalized()])
	var pair: Array = []
	var distance: float = -1.0
	for a in points:
		for b in points:
			var d: float = a[0].distance_squared_to(b[0])
			if d > distance:
				distance = d
				pair = [a, b]
	return pair


static func _append_original_blade(blade: Array, vertices: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array, width: float,
		out_vertices: PackedVector3Array, out_normals: PackedVector3Array,
		out_indices: PackedInt32Array) -> void:
	var remap: Dictionary = {}
	for index in blade:
		var position: Vector3 = vertices[index]
		var section: Array = _section(blade, vertices, normals, indices, position.y)
		if section.size() == 2:
			var center: Vector3 = (section[0][0] + section[1][0]) * 0.5
			position = center + (position - center) * width
		remap[index] = out_vertices.size()
		out_vertices.append(position)
		out_normals.append(normals[index])
	for offset in range(0, indices.size(), 3):
		if remap.has(indices[offset]):
			for corner in 3:
				out_indices.append(remap[indices[offset + corner]])


static func _append_blade(blade: Array, vertices: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array, segments: int, width: float,
		out_vertices: PackedVector3Array, out_normals: PackedVector3Array,
		out_indices: PackedInt32Array) -> void:
	var base: int = out_vertices.size()
	var root_center: Vector3 = (vertices[blade[0]] + vertices[blade[1]]) * 0.5
	var tip: Vector3 = vertices[blade.back()]
	var direction: Vector3 = (vertices[blade[1]] - vertices[blade[0]]).normalized()
	for segment in segments:
		var pair: Array
		if segment == 0:
			pair = [[vertices[blade[0]], normals[blade[0]]], [vertices[blade[1]], normals[blade[1]]]]
		else:
			pair = _section(blade, vertices, normals, indices,
				lerpf(root_center.y, tip.y, float(segment) / float(segments)))
		# Las secciones mantienen el mismo lado para no cruzar la tira de triángulos.
		if (pair[1][0] - pair[0][0]).dot(direction) < 0.0:
			pair.reverse()
		var center: Vector3 = (pair[0][0] + pair[1][0]) * 0.5
		for point in pair:
			out_vertices.append(center + (point[0] - center) * width)
			out_normals.append(point[1])
	out_vertices.append(tip)
	out_normals.append(normals[blade.back()])
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
