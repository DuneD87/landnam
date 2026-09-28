extends SceneTree

## Reparto de la banquisa (SeaIceLayout): polígonos válidos, sin solapes, dentro de su celda de
## Voronoi (la misma que dibuja el agua de lejos) y a qué coste se construye un bloque.
##   godot --headless --path . -s res://tests/climate/test_sea_ice_layout.gd

const SEA_RADIUS := 29950.0
const SIZE := 38.0
const PARAMS := Vector4(57.0, 63.0, 10.0, 300.0)

var _failures := 0


func _init() -> void:
	var ctx := {"map": null, "shore_on": false, "params": PARAMS, "radius": SEA_RADIUS, "bergs": []}
	for lat in [58.5, 60.0, 62.0, 66.0]:
		_check_band(lat, ctx)
	_check_bergs(ctx)
	_check_meshes(ctx)
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", what)


func _point(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * cos(lo), sin(la), cos(la) * sin(lo)) * SEA_RADIUS


func _chunks_around(at: Vector3, count: int) -> Array[Vector3i]:
	var chunk := SIZE * SeaIceLayout.CHUNK_CELLS
	var base := Vector3i((at / chunk).floor())
	var out: Array[Vector3i] = []
	for dx in range(-count, count + 1):
		for dy in range(-count, count + 1):
			for dz in range(-count, count + 1):
				var key := base + Vector3i(dx, dy, dz)
				var mid := (Vector3(key) + Vector3.ONE * 0.5) * chunk
				if absf(mid.length() - SEA_RADIUS) < chunk:
					out.append(key)
	return out


func _check_band(lat: float, ctx: Dictionary) -> void:
	var at := _point(lat, 20.0)
	var keys := _chunks_around(at, 1)
	var floes: Array[Dictionary] = []
	var t0 := Time.get_ticks_usec()
	for key in keys:
		floes.append_array(SeaIceLayout.chunk_floes(key, SIZE, ctx))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	# Superficie cubierta en un radio de 60 m alrededor del punto (lejos de los bordes del lote).
	var covered := 0
	var samples := 0
	var overlaps := 0
	var wrong_cell := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var basis := SeaIceLayout.frame(at.normalized())
	for i in 600:
		var off := Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		var p := (at + basis.x * off.x + basis.z * off.y).normalized() * SEA_RADIUS
		var hits := 0
		for floe in floes:
			var c: Vector3 = floe.center
			if c.distance_to(p) > float(floe.radius) + 1.0:
				continue
			var fb: Basis = floe.basis
			var d := p - c
			if SeaIceFloes._inside(floe.poly, Vector2(d.dot(fb.x), d.dot(fb.z)), 0.0):
				hits += 1
				var cell: Vector4i = floe.id
				if _shader_cell(p) != Vector3i(cell.x, cell.y, cell.z):
					wrong_cell += 1
		samples += 1
		covered += mini(hits, 1)
		overlaps += maxi(hits - 1, 0)
	var ice := ClimateField.sea_ice_with(at, -1.0, PARAMS)
	var convex_ok := true
	for floe in floes:
		var poly: PackedVector2Array = floe.poly
		if SeaIceLayout._area(poly) <= 0.0:
			convex_ok = false
	print("lat %.1f  ice %.2f  bloques %d  témpanos %d  cubierto %.0f%%  %.1f ms/bloque" % [
		lat, ice, keys.size(), floes.size(), 100.0 * covered / samples, ms / maxf(keys.size(), 1)])
	_expect(convex_ok, "polígonos antihorarios (área > 0) a %.1f" % lat)
	_expect(overlaps == 0, "témpanos solapados a %.1f: %d" % [lat, overlaps])
	_expect(wrong_cell == 0, "puntos fuera de su celda de Voronoi a %.1f: %d" % [lat, wrong_cell])
	if lat >= 66.0:
		_expect(covered > samples * 0.85, "banquisa cerrada casi cubierta (%d/%d)" % [covered, samples])
	if lat <= 58.5:
		_expect(covered < samples * 0.6, "borde de la banquisa abierto (%d/%d)" % [covered, samples])


## Réplica de ice_cells() del shader del agua: celda del sitio más cercano (vecindario 3x3x3).
func _shader_cell(p: Vector3) -> Vector3i:
	var q := p / SIZE
	var base := q.floor()
	var best := INF
	var best_c := Vector3i.ZERO
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var c := Vector3i(base) + Vector3i(x, y, z)
				var o := SeaIceLayout.site(c, SIZE) / SIZE
				var d := q.distance_to(o)
				if d < best:
					best = d
					best_c = c
	return best_c


func _check_bergs(ctx: Dictionary) -> void:
	var count := 0
	var cells := 0
	for x in range(-6, 7):
		for z in range(-6, 7):
			var at := _point(61.0 + x * 0.25, 20.0 + z * 0.5)
			var c := Vector3i((at / SeaIceLayout.ICEBERG_CELL).floor())
			cells += 1
			if not SeaIceLayout.cell_berg(c, ctx).is_empty():
				count += 1
	print("icebergs: %d en %d celdas" % [count, cells])
	_expect(count > 0, "hay icebergs cerca de la banquisa")
	var far := 0
	for x in range(-6, 7):
		var at := _point(30.0 + x, 20.0)
		if not SeaIceLayout.cell_berg(Vector3i((at / SeaIceLayout.ICEBERG_CELL).floor()), ctx).is_empty():
			far += 1
	_expect(far == 0, "sin icebergs en mar templado (%d)" % far)


func _check_meshes(ctx: Dictionary) -> void:
	var at := _point(60.0, 20.0)
	var key: Vector3i = _chunks_around(at, 0)[0]
	var floes := SeaIceLayout.chunk_floes(key, SIZE, ctx)
	var t0 := Time.get_ticks_usec()
	var arrays := SeaIceMeshes.floe_arrays(floes, at)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if not arrays.is_empty() else PackedVector3Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if not arrays.is_empty() else PackedInt32Array()
	print("malla: %d témpanos, %d vértices, %d triángulos, %.1f ms" % [
		floes.size(), verts.size(), indices.size() / 3, ms])
	_expect(floes.is_empty() or verts.size() > 0, "malla de témpanos")
	# Caras hacia fuera: el orden de cada triángulo concuerda con su normal.
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if not arrays.is_empty() else PackedVector3Array()
	var inward := 0
	for i in range(0, indices.size(), 3):
		var a := verts[indices[i]]
		var b := verts[indices[i + 1]]
		var c := verts[indices[i + 2]]
		# Cara frontal en Godot = horaria vista de frente: (b-a)x(c-a) va contra la normal.
		var geo := (b - a).cross(c - a)
		if geo.dot(normals[indices[i]]) > 0.0:
			inward += 1
	_expect(inward == 0, "triángulos con la cara frontal hacia dentro: %d" % inward)
	var berg := {"radius": 30.0, "height": 12.0, "draft": 26.0, "seed": 1234, "kind": 0}
	t0 = Time.get_ticks_usec()
	var mesh := SeaIceMeshes.berg_mesh(berg)
	print("iceberg: %d vértices, %.1f ms" % [mesh.surface_get_array_len(0), (Time.get_ticks_usec() - t0) / 1000.0])
	var faces := mesh.get_faces()
	var outward := 0
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if (b - a).cross(c - a).dot((a + b + c) / 3.0 - Vector3(0, (a.y + b.y + c.y) / 3.0, 0)) < 0.0:
			outward += 1
	_expect(outward > faces.size() / 3 * 0.9, "iceberg con las caras hacia fuera (%d/%d)" % [outward, faces.size() / 3])
