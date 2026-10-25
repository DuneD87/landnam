class_name NavalHullMesh
extends RefCounted

## Casco de superficies curvas. Se corta la cáscara en celdas para conservar edición y daño;
## cada celda guarda sus caras reales, volumen y una envolvente convexa para la física.
const PARTIAL_ID := 9
const FULL_ID := 10
const WOOD := preload("res://data/building/naval_wood.tres")
const EPS := 0.00001
const ARC_STEPS := 12


static func generate(kind: int, size: Vector3i, rounded: bool) -> Dictionary:
	var pieces := {}
	var width := float(size.x) * 0.5
	var height := float(size.y)
	var length := float(size.z)
	var steps := maxi(16, size.z * 3) if kind == 0 else 1
	var start := 1.0 if kind == 2 else 0.0
	for z in steps:
		var a := _station(kind, width, height, length, start, float(z) / steps, rounded)
		var b := _station(kind, width, height, length, start, float(z + 1) / steps, rounded)
		var outer_a: Array = a[0]
		var inner_a: Array = a[1]
		var outer_b: Array = b[0]
		var inner_b: Array = b[1]
		for u in outer_a.size() - 1:
			var points := [outer_a[u], outer_a[u + 1], inner_a[u + 1], inner_a[u],
				outer_b[u], outer_b[u + 1], inner_b[u + 1], inner_b[u]]
			_add_part(pieces, points)
	if kind == 2:
		var outline := _profile(width, height, minf(width * 0.8, height * 0.6), 0.0)
		var polygon := PackedVector2Array()
		for point: Vector2 in outline:
			polygon.append(point)
		var indices := Geometry2D.triangulate_polygon(polygon)
		for i in range(0, indices.size(), 3):
			var points := []
			for z: float in [0.0, 1.0]:
				for j in 3:
					var point := polygon[indices[i + j]]
					points.append(Vector3(point.x + width, point.y, z))
			_add_part(pieces, points, true)
	var result := {}
	for cell: Vector3i in pieces:
		var faces: Dictionary = pieces[cell]
		var saved := []
		var volume := 0.0
		for face: Array in faces.values():
			if face.size() < 3:
				continue
			var polygon := []
			for point: Vector3 in face:
				var local := point - Vector3(cell)
				polygon.append_array([local.x, local.y, local.z])
			for j in range(1, face.size() - 1):
				volume += (face[0] as Vector3).dot((face[j] as Vector3).cross(face[j + 1])) / 6.0
			saved.append(polygon)
		volume = absf(volume)
		if volume < EPS:
			continue
		if absf(volume - 1.0) < 0.0001:
			result[cell] = {"block_id": FULL_ID, "material_id": "wood", "rotation_basis": Basis.IDENTITY}
		else:
			result[cell] = {"block_id": PARTIAL_ID, "material_id": "wood", "rotation_basis": Basis.IDENTITY,
				"naval_shape": {"faces": saved, "volume": minf(volume, 1.0)}}
	return result


static func _station(kind: int, width: float, height: float, length: float, start: float,
	t: float, rounded: bool) -> Array:
	var half := width
	var z := lerpf(start, length, t)
	var inner_z := z
	var inner_half := width - 1.0
	if kind == 0:
		# El perfil elíptico enlaza tangencialmente con el tramo recto y cierra con nariz redonda.
		var angle := t * PI * 0.5
		if rounded:
			half = width * cos(angle)
			z = length * sin(angle)
			var normal := Vector2(cos(angle) / width, sin(angle) / length).normalized()
			inner_half = maxf(0.0, half - normal.x)
			inner_z = maxf(0.0, z - normal.y)
		else:
			half = width * (1.0 - t)
			var normal := Vector2(length, width).normalized()
			inner_half = maxf(0.0, half - normal.x)
			inner_z = maxf(0.0, z - normal.y)
	var radius := minf(half * 0.8, height * 0.6)
	var outer_profile := _profile(half, height, radius, 0.0)
	var inner_profile := _profile(inner_half, height, maxf(0.0, radius - 1.0), 1.0)
	var outer := []
	var inner := []
	for i in outer_profile.size():
		outer.append(Vector3(outer_profile[i].x + width, outer_profile[i].y, z))
		inner.append(Vector3(inner_profile[i].x + width, inner_profile[i].y, inner_z))
	return [outer, inner]


static func _profile(half: float, height: float, radius: float, floor_y: float) -> Array[Vector2]:
	radius = minf(radius, half)
	var result: Array[Vector2] = [Vector2(-half, height)]
	for i in ARC_STEPS + 1:
		var angle := float(i) / ARC_STEPS * PI * 0.5
		result.append(Vector2(-half + radius - radius * cos(angle), floor_y + radius - radius * sin(angle)))
	for i in ARC_STEPS + 1:
		var angle := float(i) / ARC_STEPS * PI * 0.5
		result.append(Vector2(half - radius + radius * sin(angle), floor_y + radius - radius * cos(angle)))
	result.append(Vector2(half, height))
	return result


static func _add_part(cells: Dictionary, points: Array, prism: bool = false) -> void:
	var topology := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	if prism:
		topology = [[0, 2, 1], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]]
	var center := Vector3.ZERO
	var minimum := Vector3.INF
	var maximum := -Vector3.INF
	for point: Vector3 in points:
		center += point / points.size()
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	if (maximum - minimum).x * (maximum - minimum).y * (maximum - minimum).z < EPS:
		return
	var faces := []
	for indices: Array in topology:
		var face := []
		for index: int in indices:
			face.append(points[index])
		face = _clean(face)
		if face.size() < 3:
			continue
		var normal: Vector3 = (face[1] - face[0]).cross(face[2] - face[0])
		if normal.dot(face[0] - center) < 0:
			face.reverse()
		faces.append(face)
	var low := Vector3i((minimum + Vector3.ONE * EPS).floor())
	var high := Vector3i((maximum - Vector3.ONE * EPS).floor())
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				var clipped := faces
				for axis in 3:
					clipped = _clip(clipped, axis, float(cell[axis]), false)
					clipped = _clip(clipped, axis, float(cell[axis] + 1), true)
					if clipped.is_empty():
						break
				if clipped.is_empty():
					continue
				if not cells.has(cell):
					cells[cell] = {}
				var stored: Dictionary = cells[cell]
				for face: Array in clipped:
					var keys := PackedStringArray()
					for point: Vector3 in face:
						keys.append("%d,%d,%d" % [roundi(point.x * 100000), roundi(point.y * 100000), roundi(point.z * 100000)])
					keys.sort()
					var key := "|".join(keys)
					if stored.has(key):
						stored.erase(key)
					else:
						stored[key] = face


static func _clip(faces: Array, axis: int, limit: float, less: bool) -> Array:
	var inside := false
	var outside := false
	for face: Array in faces:
		for point: Vector3 in face:
			var distance := (point[axis] - limit) * (1.0 if less else -1.0)
			inside = inside or distance < -EPS
			outside = outside or distance > EPS
	if not outside:
		return faces
	if not inside:
		return []
	var result := []
	var cuts := []
	for face: Array in faces:
		var polygon := []
		for i in face.size():
			var a: Vector3 = face[i]
			var b: Vector3 = face[(i + 1) % face.size()]
			var da := (a[axis] - limit) * (1.0 if less else -1.0)
			var db := (b[axis] - limit) * (1.0 if less else -1.0)
			if da <= EPS:
				polygon.append(a)
			if (da < -EPS and db > EPS) or (da > EPS and db < -EPS):
				var point := a.lerp(b, da / (da - db))
				point[axis] = limit
				polygon.append(point)
		polygon = _clean(polygon)
		for point: Vector3 in polygon:
			if absf(point[axis] - limit) < EPS:
				var unique := true
				for other: Vector3 in cuts:
					if other.distance_squared_to(point) < EPS * EPS:
						unique = false
						break
				if unique:
					cuts.append(point)
		if polygon.size() >= 3:
			result.append(polygon)
	if cuts.size() >= 3:
		var center := Vector3.ZERO
		for point: Vector3 in cuts:
			center += point / cuts.size()
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		cuts.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			return atan2(a[v] - center[v], a[u] - center[u]) < atan2(b[v] - center[v], b[u] - center[u]))
		if not less:
			cuts.reverse()
		result.append(cuts)
	return result


static func _clean(points: Array) -> Array:
	var result := []
	for point: Vector3 in points:
		if result.is_empty() or point.distance_squared_to(result[-1]) > EPS * EPS:
			result.append(point)
	if result.size() > 1 and (result[0] as Vector3).distance_squared_to(result[-1]) < EPS * EPS:
		result.pop_back()
	return result


static func block_data(base: BlockData, shape: Dictionary) -> BlockData:
	if shape.is_empty() or shape.get("faces", []).is_empty():
		return base
	var result := base.duplicate() as BlockData
	var points := PackedVector3Array()
	for face: Array in shape["faces"]:
		for i in range(0, face.size(), 3):
			points.append(Vector3(face[i], face[i + 1], face[i + 2]) - Vector3.ONE * 0.5)
	var collision := ConvexPolygonShape3D.new()
	collision.points = points
	collision.set_meta("naval_volume", float(shape["volume"]))
	result.collision_shape = collision
	return result


static func same_shape(a: Dictionary, b: Dictionary) -> bool:
	if int(a["block_id"]) == FULL_ID and int(b["block_id"]) == FULL_ID:
		return true
	return _shape_points(a) == _shape_points(b)


static func _shape_points(info: Dictionary) -> PackedStringArray:
	var rotation: Basis = info.get("rotation_basis", Basis.IDENTITY)
	if info.get("mirrored", false):
		var scale := Vector3.ONE
		scale[int(info["mirror_axis"])] = -1.0
		rotation *= Basis.from_scale(scale)
	var points := {}
	for face: Array in info.get("naval_shape", {}).get("faces", []):
		for i in range(0, face.size(), 3):
			var point := rotation * (Vector3(face[i], face[i + 1], face[i + 2]) - Vector3.ONE * 0.5)
			points["%d,%d,%d" % [roundi(point.x * 10000), roundi(point.y * 10000), roundi(point.z * 10000)]] = true
	var result := PackedStringArray(points.keys())
	result.sort()
	return result


static func emit(st: SurfaceTool, shape: Dictionary, offset: Vector3, rotation: Basis, size: float, flip: bool) -> void:
	var center := Vector3.ONE * 0.5
	for face: Array in shape.get("faces", []):
		var polygon := PackedVector3Array()
		for i in range(0, face.size(), 3):
			polygon.append(Vector3(face[i], face[i + 1], face[i + 2]))
		for j in range(1, polygon.size() - 1):
			var a := polygon[0]
			var b := polygon[j]
			var c := polygon[j + 1]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < EPS * EPS:
				continue
			normal = (rotation * normal.normalized()).normalized()
			var tangent := ChunkMeshBuilder.uv_tangent(normal)
			for point: Vector3 in [a, b, c] if flip else [a, c, b]:
				var position := (rotation * (point - center) + center) * size + offset
				st.set_normal(normal)
				st.set_uv(ChunkMeshBuilder.planar_uv(position, tangent, normal))
				st.add_vertex(position)
