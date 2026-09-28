extends SceneTree

## Converts offline sculpt data to native cached ArrayMesh resources.
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/fauna/meshes")
	for animal in ["rabbit", "fox", "mouse", "arctic_hare", "arctic_fox", "lemming"]:
		var path := "res://build/fauna/sculpted/%s.json" % animal
		# Solo se hornean las especies esculpidas: las demás conservan su .res del repositorio.
		if not FileAccess.file_exists(path) and FileAccess.file_exists("res://data/fauna/meshes/%s.res" % animal):
			continue
		if not FileAccess.file_exists(path):
			push_error("Missing sculpt: " + path)
			quit(1)
			return
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uv := PackedVector2Array()
		for v in data.vertices:
			vertices.append(Vector3(v[0], v[1], v[2]))
		for n in data.normals:
			normals.append(Vector3(n[0], n[1], n[2]))
		for c in data.colors:
			var color := Color(c[0], c[1], c[2]).srgb_to_linear()
			color.a = c[3]
			colors.append(color)
		for weight in data.uv:
			uv.append(Vector2(weight[0], weight[1]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(data.indices)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var error := ResourceSaver.save(mesh, "res://data/fauna/meshes/%s.res" % animal, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("Cannot save " + animal)
			quit(1)
			return
		print("BAKED ", animal, ": ", vertices.size(), " vertices")
	quit()
