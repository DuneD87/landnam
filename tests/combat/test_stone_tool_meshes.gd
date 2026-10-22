extends SceneTree

## Orientación exterior de modelos generados y horneados: índices, normales y materiales.
## godot --headless --path . --script res://tests/combat/test_stone_tool_meshes.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for entry in [["stone_axe_01", WeaponMeshes.stone_axe],
			["stone_pickaxe_01", WeaponMeshes.stone_pickaxe]]:
		_check_mesh((entry[1] as Callable).call(), entry[0] + " generado")
		_check_mesh(load("res://data/items/meshes/weapons/%s.res" % entry[0]), entry[0] + " horneado")
	print("STONE TOOL MESH TESTS: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check_mesh(mesh: Mesh, label: String) -> void:
	for s in mesh.get_surface_count():
		var material := mesh.surface_get_material(s) as StandardMaterial3D
		var part := label + "/" + material.resource_name
		_check(material.cull_mode == BaseMaterial3D.CULL_BACK, part + ": descarta las caras traseras")
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var volume := 0.0
		var reversed_normals := 0
		var inward_sides := 0
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			var face := (c - a).cross(b - a)
			if face.length_squared() < 1e-16:
				continue
			var normal := (normals[indices[i]] + normals[indices[i + 1]] + normals[indices[i + 2]]).normalized()
			volume += a.dot(b.cross(c)) / 6.0
			if face.dot(normal) <= 0.0:
				reversed_normals += 1
			var center := (a + b + c) / 3.0
			if material.resource_name in ["wood", "leather"] and absf(normal.y) < 0.5:
				if normal.dot(Vector3(center.x, 0.0, center.z)) <= 0.0:
					inward_sides += 1
			elif material.resource_name == "stone" and absf(normal.x) > 0.5:
				if normal.x * center.x <= 0.0:
					inward_sides += 1
		# En Godot el frontal es horario: una envolvente exterior tiene volumen firmado negativo.
		_check(volume < -1e-8, part + ": envolvente hacia fuera")
		_check(reversed_normals == 0, part + ": normales coherentes con los triángulos")
		_check(inward_sides == 0, part + ": laterales hacia el exterior")


func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
