class_name RockFracture
extends RefCounted

## Parte la malla de una roca en trozos de Voronoi que juntos son la roca entera: cada trozo es la
## roca recortada por los planos que la separan de las demás semillas, con la cara del corte
## cerrada (la envolvente de los puntos del corte en ese plano: las rocas son casi convexas).
## Las semillas se reparten por dentro de la roca, lo más separadas posible, para que los trozos
## salgan de tamaños parecidos. Cada trozo sale centrado en su centroide, con los puntos para su
## colisión convexa, su volumen (en unidades de la malla) y sus vecinos (los trozos con los que
## comparte cara): la roca a medio picar sabe qué sostiene a qué.
##
## Se calcula una vez por malla y número de trozos (las rocas de un tipo comparten malla y se
## escalan por instancia). Recortar es lo caro (decenas de ms con muchos trozos): prepare lo lanza
## en hilos al cargar la vegetación y collect monta las mallas en el hilo principal. Lo que no se
## ha preparado se calcula al pedirlo.
##
## Los trozos conservan el COLOR de la roca (ProceduralRock: oclusión de las cavidades y cara
## curtida) y las caras de los cortes salen con CUT_COLOR, limpias. Cada malla de trozo guarda en el
## meta "rock_offset" dónde queda dentro de la roca entera (su centroide, en las coordenadas de la
## roca): mesh_instance lo pasa al shader de roca, que texturiza en los ejes de la roca, y así el
## trozo no cambia de dibujo al soltarse.

## clave (malla y trozos) -> [{mesh, offset, points, volume, neighbors}]
static var _cache: Dictionary = {}
## clave -> [tarea, resultado (lo llena el hilo), material, rock_offset]
static var _pending: Dictionary = {}

## Cara del corte: sin oclusión (r) y sin curtir (g), sin la tierra ni el musgo de fuera.
const CUT_COLOR := Color(1.0, 0.0, 0.0, 1.0)


## Un MeshInstance3D con [mesh] (la roca o uno de sus trozos) y su sitio dentro de la roca entera.
static func mesh_instance(mesh: Mesh) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.set_instance_shader_parameter(&"rock_offset", mesh.get_meta(&"rock_offset", Vector3.ZERO))
	return visual


## Los [count] trozos de [mesh] (su primera superficie).
static func pieces_of(mesh: Mesh, count: int) -> Array:
	var key := _key(mesh, count)
	if not _cache.has(key):
		if _pending.has(key):
			_finish(key)
		else:
			_cache[key] = _assemble(compute(mesh.surface_get_arrays(0), count, hash(key)),
				mesh.surface_get_material(0), mesh.get_meta(&"rock_offset", Vector3.ZERO))
	return _cache[key]


## Calcula en un hilo los [count] trozos de [mesh], si no están ya.
static func prepare(mesh: Mesh, count: int) -> void:
	var key := _key(mesh, count)
	if _cache.has(key) or _pending.has(key):
		return
	var result: Array = []
	# La malla se lee aquí: pedirle los arrays desde un hilo espera al servidor de render.
	var task := WorkerThreadPool.add_task(Callable(RockFracture, &"_compute_into").bind(result,
		mesh.surface_get_arrays(0), count, hash(key)), false, "RockFracture")
	_pending[key] = [task, result, mesh.surface_get_material(0), mesh.get_meta(&"rock_offset", Vector3.ZERO)]


## Monta las mallas de una roca que ya han acabado los hilos (una por llamada). Devuelve true si
## queda algo pendiente.
static func collect() -> bool:
	for key in _pending:
		if WorkerThreadPool.is_task_completed(_pending[key][0]):
			_finish(key)
			break
	return not _pending.is_empty()


static func _key(mesh: Mesh, count: int) -> String:
	return "%d:%d" % [mesh.get_instance_id(), count]


static func _finish(key: String) -> void:
	var job: Array = _pending[key]
	_pending.erase(key)
	WorkerThreadPool.wait_for_task_completion(job[0])
	var result: Array = job[1]
	_cache[key] = _assemble(result[0] if not result.is_empty() else [], job[2], job[3])


static func _compute_into(result: Array, arrays: Array, count: int, seed: int) -> void:
	result.append(compute(arrays, count, seed))


## Los [count] trozos de la superficie [arrays], con las semillas sacadas de [seed]. Solo datos, sin
## mallas (vale desde un hilo): [{arrays, offset, points, volume, neighbors}].
static func compute(arrays: Array, count: int, seed: int) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if verts.is_empty():
		return []
	if indices.is_empty():
		for i in verts.size():
			indices.append(i)
	var triangles: Array = []
	for t in range(0, indices.size() - 2, 3):
		var polygon: Array = []
		for k in 3:
			var i := indices[t + k]
			polygon.append([verts[i], normals[i] if i < normals.size() else Vector3.UP,
				uvs[i] if i < uvs.size() else Vector2.ZERO, colors[i] if i < colors.size() else Color.WHITE])
		triangles.append(polygon)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var seeds := _seeds(verts, count, rng)
	var pieces: Array = []
	# Semilla -> trozo (-1 si se ha quedado en nada).
	var piece_of := PackedInt32Array()
	piece_of.resize(seeds.size())
	piece_of.fill(-1)
	for i in seeds.size():
		# Los planos de las semillas más cercanas primero: son los que más recortan y los demás ya
		# van sobre poco.
		var others: Array = []
		for j in seeds.size():
			if j != i:
				others.append(j)
		var from := seeds[i]
		others.sort_custom(func(a: int, b: int) -> bool:
			return from.distance_squared_to(seeds[a]) < from.distance_squared_to(seeds[b]))
		var polygons := triangles
		var planes: Array = []
		for j: int in others:
			var normal := (seeds[j] - from).normalized()
			var distance := normal.dot((from + seeds[j]) * 0.5)
			polygons = _clip(polygons, normal, distance)
			planes.append([j, normal, distance])
			if polygons.is_empty():
				break
		if polygons.is_empty():
			continue
		var piece := _build(polygons)
		if piece.is_empty():
			continue
		# Vecinos: las semillas de cuyo plano queda cara en el trozo.
		var faces := PackedInt32Array()
		for plane in planes:
			var normal: Vector3 = plane[1]
			for polygon in polygons:
				var vertex: Array = polygon[0]
				if (vertex[1] as Vector3).dot(normal) > 0.999 \
						and absf(normal.dot(vertex[0]) - float(plane[2])) < 1e-4:
					faces.append(plane[0])
					break
		piece.faces = faces
		piece_of[i] = pieces.size()
		pieces.append(piece)
	for piece in pieces:
		var neighbors := PackedInt32Array()
		for j in piece.faces:
			if piece_of[j] >= 0:
				neighbors.append(piece_of[j])
		piece.neighbors = neighbors
		piece.erase("faces")
	return pieces


## [count] semillas por dentro de la roca de [verts], lo más separadas posible: de muchas
## candidatas entre el centro y la superficie (las rocas son estrelladas desde su centro), cada
## vez la más lejana de las ya elegidas.
static func _seeds(verts: PackedVector3Array, count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var center := Vector3.ZERO
	for v in verts:
		center += v
	center /= float(verts.size())
	var candidates := PackedVector3Array()
	for k in count * 8:
		candidates.append(center.lerp(verts[rng.randi() % verts.size()], 0.8 * pow(rng.randf(), 1.0 / 3.0)))
	var seeds := PackedVector3Array([candidates[0]])
	var nearest := PackedFloat32Array()
	nearest.resize(candidates.size())
	nearest.fill(INF)
	while seeds.size() < count:
		var last := seeds[seeds.size() - 1]
		var best := 0
		for c in candidates.size():
			nearest[c] = minf(nearest[c], candidates[c].distance_squared_to(last))
			if nearest[c] > nearest[best]:
				best = c
		if nearest[best] < 1e-8:
			break
		seeds.append(candidates[best])
	return seeds


## Se queda con lo de [polygons] en el lado normal·x <= distance y cierra el corte.
static func _clip(polygons: Array, normal: Vector3, distance: float) -> Array:
	var out: Array = []
	var cut := PackedVector3Array()
	var sides := PackedFloat32Array()
	for polygon in polygons:
		var size: int = polygon.size()
		sides.resize(size)
		var inside := 0
		for k in size:
			sides[k] = normal.dot(polygon[k][0]) - distance
			if sides[k] <= 0.0:
				inside += 1
		# Casi todo queda entero a un lado: se pasa tal cual.
		if inside == size:
			out.append(polygon)
			continue
		if inside == 0:
			continue
		var kept: Array = []
		for k in size:
			var a: Array = polygon[k]
			var b: Array = polygon[(k + 1) % size]
			var da := sides[k]
			var db := sides[(k + 1) % size]
			if da <= 0.0:
				kept.append(a)
			if (da <= 0.0) != (db <= 0.0):
				var t := da / (da - db)
				var v := [(a[0] as Vector3).lerp(b[0], t), (a[1] as Vector3).lerp(b[1], t).normalized(),
					(a[2] as Vector2).lerp(b[2], t), (a[3] as Color).lerp(b[3], t)]
				kept.append(v)
				cut.append(v[0])
		if kept.size() >= 3:
			out.append(kept)
	if cut.size() >= 3:
		var cap := _cap(cut, normal, distance)
		if cap.size() >= 3:
			out.append(cap)
	return out


## La cara del corte: la envolvente de [points] en el plano, mirando hacia +[normal] (fuera del
## trozo), con UV planares.
static func _cap(points: PackedVector3Array, normal: Vector3, distance: float) -> Array:
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := normal.cross(u)
	var flat := PackedVector2Array()
	for p in points:
		flat.append(Vector2(p.dot(u), p.dot(v)))
	var hull := Geometry2D.convex_hull(flat)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	var polygon: Array = []
	# La envolvente va en sentido antihorario visto desde +normal; Godot dibuja de frente las caras
	# en sentido horario: al revés.
	for i in range(hull.size() - 1, -1, -1):
		var q := hull[i]
		polygon.append([u * q.x + v * q.y + normal * distance, normal, q * 0.5, CUT_COLOR])
	return polygon


static func _build(polygons: Array) -> Dictionary:
	var centroid := Vector3.ZERO
	var n := 0
	for polygon in polygons:
		for vertex in polygon:
			centroid += vertex[0]
			n += 1
	if n < 4:
		return {}
	centroid /= float(n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := PackedVector3Array()
	var volume := 0.0
	for polygon in polygons:
		var a: Vector3 = (polygon[0][0] as Vector3) - centroid
		for k in range(1, polygon.size() - 1):
			var b: Vector3 = (polygon[k][0] as Vector3) - centroid
			var c: Vector3 = (polygon[k + 1][0] as Vector3) - centroid
			volume += a.dot(b.cross(c))
			for vertex in [polygon[0], polygon[k], polygon[k + 1]]:
				st.set_normal(vertex[1])
				st.set_uv(vertex[2])
				st.set_color(vertex[3])
				st.add_vertex((vertex[0] as Vector3) - centroid)
		for vertex in polygon:
			points.append((vertex[0] as Vector3) - centroid)
	st.generate_tangents()
	return {"arrays": st.commit_to_arrays(), "offset": centroid, "points": points,
		"volume": absf(volume) / 6.0}


## [offset]: el de la malla que se parte dentro de la roca entera.
static func _assemble(data: Array, material: Material, offset: Vector3) -> Array:
	var pieces: Array = []
	for piece in data:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piece.arrays)
		if material != null:
			mesh.surface_set_material(0, material)
		mesh.set_meta(&"rock_offset", offset + (piece.offset as Vector3))
		pieces.append({"mesh": mesh, "offset": piece.offset, "points": piece.points,
			"volume": piece.volume, "neighbors": piece.neighbors})
	return pieces
