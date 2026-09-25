extends RefCounted

## LODs de la mata original: conserva hojas completas y su silueta, sin tarjetas.
## La selección es anidada (las hojas lejanas también existen en los LODs mayores).
## Solo se construye al cargar la vegetación; no se simplifica durante cada frame.

## Ensanchado de las hojas por LOD. grass_wind.gdshader usa el mismo factor para
## el morph continuo entre niveles (lod_width_growth).
const WIDTH_GROWTH := 1.55
## Anchura respecto a la del asset. Las hojas del modelo miden ~1/9 de su largo y
## se leían como palas; más estrechas y más numerosas se leen como hierba.
const WIDTH_SCALE := 0.62
## Hojas añadidas a LOD0: más bajas, rellenan la mata de cerca y no llegan a LOD1.
const EXTRA_BLADES := 32

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
	var shapes: Array = []
	for blade in _order_blades(blades, vertices):
		shapes.append(_blade_shape(blade, vertices, normals))
	# Las añadidas van al final del orden anidado: solo existen en LOD0.
	shapes.append_array(_extra_blades(shapes))
	var center := Vector3.ZERO
	for shape in shapes:
		center += shape.root
	center /= float(shapes.size())
	for index in shapes.size():
		var shape: Dictionary = shapes[index]
		var outward := Vector3(shape.root.x - center.x, 0.0, shape.root.z - center.z)
		if outward.length_squared() < 0.0004:
			outward = Vector3(shape.tip.x - shape.root.x, 0.0, shape.tip.z - shape.root.z)
		if outward.length_squared() < 0.0004:
			outward = Vector3.RIGHT.rotated(Vector3.UP, _blade_seed(index) * TAU)
		shape.outward = outward.normalized()
		# Las hojas de silueta (las que llegan a LOD3) conservan su punta: marcan la
		# altura y el contorno de la mata. Las demás pueden doblarse y caer.
		var seed: float = _blade_seed(index)
		shape.bend = 0.0 if survival_level(index, shapes.size()) == 3 \
			else smoothstep(0.25, 1.0, fposmod(seed * 7.13, 1.0)) * 0.8
	var material: Material = source.surface_get_material(0)
	# La curva se calcula una vez por hoja y se muestrea igual en todos los LODs.
	# UV: transversal / semilla. UV2: raíz->punta / marca de geometría refinada.
	var result: Array = []
	for lod in 4:
		var count: int = maxi(shapes.size() >> lod, 1)
		var width: float = pow(WIDTH_GROWTH, lod)
		var segments: int = [4, 3, 2, 1][lod]
		var output_vertices := PackedVector3Array()
		var output_normals := PackedVector3Array()
		var output_uvs := PackedVector2Array()
		var output_uv2s := PackedVector2Array()
		var output_custom := PackedFloat32Array()
		var output_indices := PackedInt32Array()
		for blade_index in count:
			# CUSTOM0.w: LOD de esta malla y último LOD en el que sigue la hoja.
			var packed: float = float(lod * 4 + survival_level(blade_index, shapes.size()))
			_append_curved_blade(shapes[blade_index], segments, width,
				_blade_seed(blade_index), packed, output_vertices, output_normals,
				output_uvs, output_uv2s, output_custom, output_indices)
		var output: Array = []
		output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = output_vertices
		output[Mesh.ARRAY_NORMAL] = output_normals
		output[Mesh.ARRAY_TEX_UV] = output_uvs
		output[Mesh.ARRAY_TEX_UV2] = output_uv2s
		output[Mesh.ARRAY_CUSTOM0] = output_custom
		output[Mesh.ARRAY_INDEX] = output_indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, material)
		result.append(mesh)
	return result


## Raíz, punta, lado y normal de una hoja del asset.
static func _blade_shape(blade: Array, vertices: PackedVector3Array,
		normals: PackedVector3Array) -> Dictionary:
	var side: Vector3 = vertices[blade[1]] - vertices[blade[0]]
	side.y = 0.0
	return {"root": (vertices[blade[0]] + vertices[blade[1]]) * 0.5,
		"tip": vertices[blade.back()], "side": side, "normal": normals[blade[0]],
		"original": true}


## Copias giradas y más bajas de hojas del asset, repartidas alrededor del centro
## de la mata. Rellenan la parte baja: una mata real es más densa abajo que arriba.
static func _extra_blades(shapes: Array) -> Array:
	var center := Vector3.ZERO
	for shape in shapes:
		center += shape.root
	center /= float(shapes.size())
	center.y = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 90127
	var extra: Array = []
	for k in EXTRA_BLADES:
		var source: Dictionary = shapes[rng.randi() % shapes.size()]
		var angle: float = rng.randf_range(-PI, PI)
		var root: Vector3 = center + (source.root - center).rotated(Vector3.UP, angle) * rng.randf_range(0.5, 0.95)
		var tip: Vector3 = root + (source.tip - source.root).rotated(Vector3.UP, angle) * rng.randf_range(0.5, 0.82)
		extra.append({"root": root, "tip": tip, "side": source.side.rotated(Vector3.UP, angle),
			"normal": source.normal.rotated(Vector3.UP, angle), "original": false})
	return extra


## Último LOD en el que existe la hoja de la posición dada del orden anidado.
static func survival_level(index: int, total: int) -> int:
	var level: int = 0
	while level < 3 and index < maxi(total >> (level + 1), 1):
		level += 1
	return level


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
## Las hojas con bend se abren hacia fuera de la mata y caen por la punta: sube,
## se arquea y baja. Sin él, casi todas las hojas del asset eran rectas y verticales.
static func _append_curved_blade(blade: Dictionary, segments: int, width: float,
		seed: float, packed: float,
		out_vertices: PackedVector3Array, out_normals: PackedVector3Array,
		out_uvs: PackedVector2Array, out_uv2s: PackedVector2Array,
		out_custom: PackedFloat32Array, out_indices: PackedInt32Array) -> void:
	var base: int = out_vertices.size()
	var root: Vector3 = blade.root
	var tip: Vector3 = blade.tip
	var height: float = tip.y - root.y
	var side: Vector3 = blade.side
	var root_width: float = side.length()
	side = side.normalized()
	var bend: float = blade.get("bend", 0.0)
	var outward: Vector3 = blade.get("outward", Vector3.ZERO)
	tip += outward * height * bend * 0.45 - Vector3.UP * height * bend * 0.34
	var lean := Vector3(tip.x - root.x, 0.0, tip.z - root.z)
	if bend > 0.0 and lean.length_squared() > 0.000001:
		# Una hoja se dobla por su cara, no de canto: su anchura queda perpendicular a
		# la dirección en la que cae (inclinación del asset más la apertura). Casi
		# paralela, la normal de la punta (tangente × anchura) degenera y se invierte.
		var across: Vector3 = Vector3.UP.cross(lean.normalized()).normalized()
		side = across if across.dot(side) >= 0.0 else -across
		outward = lean.normalized()
	# Arranque vertical, arco abierto arriba. Mantiene la altura de la mata.
	var control_a: Vector3 = root + Vector3.UP * height * 0.60 + lean * 0.06 + outward * height * bend * 0.04
	# Recta: la punta llega casi en vertical. Doblada: llega hacia fuera, cayendo ~30°.
	var straight: Vector3 = tip - lean * 0.40 - Vector3.UP * height * (0.015 + seed * 0.085)
	var drooping: Vector3 = tip - outward * height * 0.22 + Vector3.UP * height * 0.12
	var control_b: Vector3 = straight.lerp(drooping, bend)
	var blade_width: float = maxf(root_width * 1.20, height * 0.065) * WIDTH_SCALE
	var reference_normal: Vector3 = blade.normal
	# La orientación se decide en la raíz y se mantiene en toda la cinta.
	# Reevaluarla contra la normal importada en cada sección puede invertir la
	# normal cuando la punta se curva más de 90 grados respecto a esa referencia.
	var facing: float = -1.0 if (control_a - root).cross(side).dot(reference_normal) < 0.0 else 1.0
	for segment in segments + 1:
		var t: float = float(segment) / float(segments)
		var center: Vector3 = root.bezier_interpolate(control_a, control_b, tip, t)
		# La punta usa la tangente de su último tramo: en una hoja muy doblada con pocos
		# tramos, la tangente exacta en t = 1 queda a más de 90° de la fila anterior.
		var tangent_t: float = t if segment < segments else (float(segments) - 0.5) / float(segments)
		var tangent: Vector3 = root.bezier_derivative(control_a, control_b, tip, tangent_t).normalized()
		# Una torsión pequeña evita que todas las caras de una hoja brillen a la vez.
		var section_side: Vector3 = side.rotated(Vector3.UP, (seed - 0.5) * 0.42 * t)
		var normal: Vector3 = tangent.cross(section_side).normalized() * facing
		if segment == segments:
			out_vertices.append(tip)
			out_normals.append(normal)
			out_uvs.append(Vector2(0.5, seed))
			out_uv2s.append(Vector2(1.0, 1.0))
			# La punta está en el eje: el morph no la mueve.
			out_custom.append_array(PackedFloat32Array([0.0, 0.0, 0.0, packed]))
			continue
		# Ancho uniforme al arrancar, hombro suave y estrechamiento hasta la punta.
		var profile: float = (1.0 - pow(t, 1.65)) * (0.56 + 0.75 * sin(PI * t))
		# Un único triángulo conserva área aproximada de la cinta completa.
		if segments == 1:
			profile = 1.02
		for edge in 2:
			var offset: Vector3 = section_side * (float(edge) - 0.5) * blade_width * width * profile
			out_vertices.append(center + offset)
			out_normals.append(normal)
			out_uvs.append(Vector2(float(edge), seed))
			out_uv2s.append(Vector2(t, 1.0))
			out_custom.append_array(PackedFloat32Array([offset.x, offset.y, offset.z, packed]))
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
