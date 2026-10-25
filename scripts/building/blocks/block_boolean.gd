class_name BlockBoolean
extends RefCounted

## Operaciones sobre sólidos cerrados. Permiten recortar el volumen de casco que ya existe
## de un cubo nuevo: ambos permanecen editables y la masa compartida se cuenta una sola vez.
const EPS := 0.00001

class Face:
	var points: PackedVector3Array
	var normal := Vector3.ZERO
	var distance := 0.0
	func _init(vertices: PackedVector3Array) -> void:
		points = vertices
		for i in range(1, points.size() - 1):
			normal = (points[i] - points[0]).cross(points[i + 1] - points[0])
			if normal.length_squared() > EPS * EPS:
				normal = normal.normalized()
				distance = normal.dot(points[0])
				break
	func flipped() -> Face:
		var vertices := points.duplicate()
		vertices.reverse()
		return Face.new(vertices)


class BspNode:
	var normal := Vector3.ZERO
	var distance := 0.0
	var faces: Array = []
	var front: BspNode
	var back: BspNode
	func _init(polygons: Array = []) -> void:
		build(polygons)
	func invert() -> void:
		for i in faces.size():
			faces[i] = (faces[i] as Face).flipped()
		normal = -normal
		distance = -distance
		if front:
			front.invert()
		if back:
			back.invert()
		var previous := front
		front = back
		back = previous
	func all_faces() -> Array:
		var result := faces.duplicate()
		if front:
			result.append_array(front.all_faces())
		if back:
			result.append_array(back.all_faces())
		return result
	func clipped(polygons: Array) -> Array:
		if normal.is_zero_approx():
			return polygons.duplicate()
		var ahead := []
		var behind := []
		for face: Face in polygons:
			_split(face, ahead, behind, ahead, behind)
		if front:
			ahead = front.clipped(ahead)
		if back:
			behind = back.clipped(behind)
		else:
			behind.clear()
		ahead.append_array(behind)
		return ahead
	func clip_to(other: BspNode) -> void:
		faces = other.clipped(faces)
		if front:
			front.clip_to(other)
		if back:
			back.clip_to(other)
	func build(polygons: Array) -> void:
		if polygons.is_empty():
			return
		var start := 0
		if normal.is_zero_approx():
			# La cara que define el plano se queda en este nodo: si el redondeo la clasificara
			# fuera de su propio plano, bajaría al hijo con el mismo plano sin fin.
			normal = (polygons[0] as Face).normal
			distance = (polygons[0] as Face).distance
			faces.append(polygons[0])
			start = 1
		var ahead := []
		var behind := []
		for i in range(start, polygons.size()):
			_split(polygons[i], faces, faces, ahead, behind)
		if not ahead.is_empty():
			if not front:
				front = BspNode.new()
			front.build(ahead)
		if not behind.is_empty():
			if not back:
				back = BspNode.new()
			back.build(behind)
	func _split(face: Face, coplanar_front: Array, coplanar_back: Array, ahead: Array, behind: Array) -> void:
		var kind := 0
		var sides: Array[int] = []
		for point in face.points:
			var d := normal.dot(point) - distance
			var side := 2 if d < -EPS else (1 if d > EPS else 0)
			kind |= side
			sides.append(side)
		match kind:
			0:
				(coplanar_front if normal.dot(face.normal) > 0.0 else coplanar_back).append(face)
			1:
				ahead.append(face)
			2:
				behind.append(face)
			3:
				var f := PackedVector3Array()
				var b := PackedVector3Array()
				for i in face.points.size():
					var j := (i + 1) % face.points.size()
					var a := face.points[i]
					var next := face.points[j]
					if sides[i] != 2:
						f.append(a)
					if sides[i] != 1:
						b.append(a)
					if (sides[i] | sides[j]) == 3:
						var t := (distance - normal.dot(a)) / normal.dot(next - a)
						var intersection := a.lerp(next, t)
						f.append(intersection)
						b.append(intersection)
				BlockBoolean.add_face(ahead, f)
				BlockBoolean.add_face(behind, b)


static func add_face(faces: Array, points: PackedVector3Array) -> void:
	var clean := PackedVector3Array()
	for point in points:
		if clean.is_empty() or point.distance_squared_to(clean[-1]) > EPS * EPS:
			clean.append(point)
	if clean.size() > 1 and clean[0].distance_squared_to(clean[-1]) < EPS * EPS:
		clean.remove_at(clean.size() - 1)
	if clean.size() < 3:
		return
	var face := Face.new(clean)
	if face.normal.is_zero_approx():
		return
	for point in clean:
		if absf(face.normal.dot(point) - face.distance) > EPS:
			# Las caras curvas del casco no son planas: se abanican igual que en NavalHullMesh.emit.
			for i in range(1, clean.size() - 1):
				var triangle := Face.new(PackedVector3Array([clean[0], clean[i], clean[i + 1]]))
				if not triangle.normal.is_zero_approx():
					faces.append(triangle)
			return
	faces.append(face)


static func subtract(solid: Array, cutter: Array) -> Array:
	if solid.is_empty() or cutter.is_empty():
		return solid.duplicate()
	var a := BspNode.new(solid)
	var b := BspNode.new(cutter)
	a.invert()
	a.clip_to(b)
	b.clip_to(a)
	b.invert()
	b.clip_to(a)
	b.invert()
	a.build(b.all_faces())
	a.invert()
	return a.all_faces()


static func box() -> Array:
	var vertices := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]
	var result := []
	for indices in [[3, 2, 1, 0], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		var face := PackedVector3Array()
		for i: int in indices:
			face.append(vertices[i])
		add_face(result, face)
	return result


static func from_block(info: Dictionary, scale_factor: float, offset: Vector3) -> Array:
	var source := []
	if ChunkMeshBuilder._is_solid(int(info["block_id"])):
		source = box()
	else:
		for saved: Array in info.get("naval_shape", {}).get("faces", []):
			var vertices := PackedVector3Array()
			for i in range(0, saved.size(), 3):
				vertices.append(Vector3(saved[i], saved[i + 1], saved[i + 2]))
			add_face(source, vertices)
	var rotation: Basis = info.get("rotation_basis", Basis.IDENTITY)
	var mirrored: bool = info.get("mirrored", false)
	if mirrored:
		var reflection := Vector3.ONE
		reflection[int(info["mirror_axis"])] = -1.0
		rotation *= Basis.from_scale(reflection)
	var result := []
	for face: Face in source:
		var vertices := PackedVector3Array()
		for point in face.points:
			vertices.append((rotation * (point - Vector3.ONE * 0.5) + Vector3.ONE * 0.5) * scale_factor + offset)
		if mirrored:
			vertices.reverse()
		add_face(result, vertices)
	return result


static func shape(faces: Array) -> Dictionary:
	var saved := []
	var volume := 0.0
	for face: Face in faces:
		var polygon := []
		for point in face.points:
			polygon.append_array([point.x, point.y, point.z])
		for j in range(1, face.points.size() - 1):
			volume += face.points[0].dot(face.points[j].cross(face.points[j + 1])) / 6.0
		saved.append(polygon)
	return {"faces": saved, "volume": clampf(absf(volume), 0.0, 1.0), "infill": true}
