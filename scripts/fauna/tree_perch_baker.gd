class_name TreePerchBaker extends RefCounted

## Bake once from the rendered LOD0 wood surface, in the same coordinates as
## the instanced mesh. Foliage cards are never mistaken for a branch.
static func bake(mesh: Mesh, manual: Array[Vector3] = []) -> Dictionary:
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	if indices.is_empty():
		faces = vertices
	else:
		for index in indices:
			faces.append(vertices[index])
	var wood := TriangleMesh.new()
	if not wood.create_from_faces(faces):
		return {}
	var bounds := mesh.get_aabb()
	var leaf_faces := PackedVector3Array()
	for surface in range(1, mesh.get_surface_count()):
		var leaf_arrays := mesh.surface_get_arrays(surface)
		var leaf_vertices: PackedVector3Array = leaf_arrays[Mesh.ARRAY_VERTEX]
		var leaf_indices: PackedInt32Array = leaf_arrays[Mesh.ARRAY_INDEX]
		if leaf_indices.is_empty():
			leaf_faces.append_array(leaf_vertices)
		else:
			for index in leaf_indices:
				leaf_faces.append(leaf_vertices[index])
	var foliage: TriangleMesh
	if not leaf_faces.is_empty():
		foliage = TriangleMesh.new()
		foliage.create_from_faces(leaf_faces)
	var candidates: Array[Dictionary] = []
	var spacing := maxf(0.20, bounds.size.y * 0.035)
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var normal := (c - a).cross(b - a).normalized()
		if not normals.is_empty():
			var ni := indices[i] if not indices.is_empty() else i
			normal = normals[ni].normalized()
		if normal.y < 0.68:
			continue
		var point := (a + b + c) / 3.0
		if point.y < bounds.position.y + maxf(0.35, bounds.size.y * 0.05) or Vector2(point.x, point.z).length() < 0.35:
			continue
		# Lift only a few millimetres in tree space; feet remain on the surface.
		var hit := wood.intersect_segment(point + Vector3.UP * 0.12, point - Vector3.UP * 0.04)
		if hit.is_empty() or (hit.position as Vector3).distance_to(point) > 0.04:
			continue
		point = hit.position
		if not wood.intersect_segment(point + Vector3.UP * 0.04, point + Vector3.UP * 0.40).is_empty():
			continue
		var tangent := b - a if a.distance_squared_to(b) > a.distance_squared_to(c) else c - a
		tangent.y = 0
		if tangent.length_squared() < 0.00001:
			continue
		# Keep low branches in the bounded catalog instead of filling it with
		# the flattest faces in the canopy. All candidates already pass support checks.
		var relative_height := (point.y - bounds.position.y) / maxf(bounds.size.y, 0.01)
		candidates.append({"point": point, "normal": normal, "tangent": tangent.normalized(), "score": normal.y - relative_height * 2.0})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var perches: Array[Dictionary] = []
	for point in manual:
		perches.append({"point": point, "normal": Vector3.UP, "tangent": Vector3.RIGHT})
	for candidate in candidates:
		var separated := true
		for perch in perches:
			if (candidate.point as Vector3).distance_squared_to(perch.point) < spacing * spacing:
				separated = false
				break
		if separated:
			perches.append(candidate)
		if perches.size() >= 20:
			break
	return {"perches": perches, "wood": wood, "foliage": foliage, "bounds": bounds}
