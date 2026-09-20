extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for kind in 5:
		var bird := SimpleBirdModel.new()
		var other := SimpleBirdModel.new()
		stage.add_child(bird)
		stage.add_child(other)
		bird.set_species(kind)
		other.set_species(kind)
		var label: String = SimpleBirdModel.NAMES[kind]
		check(bird.body.mesh == other.body.mesh and bird.left.mesh == bird.right.mesh and bird.right.mesh == other.right.mesh,
			label + ": instances and mirrored wings share baked resources")
		var total := 0
		for part in [bird.body, bird.right]:
			var mesh: ArrayMesh = part.mesh
			check(mesh.get_surface_count() == 1, label + ": one surface per part")
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var valid := vertices.size() == normals.size()
			for i in vertices.size():
				valid = valid and vertices[i].is_finite() and normals[i].is_finite() and normals[i].length_squared() > .8
			for i in indices:
				valid = valid and i >= 0 and i < vertices.size()
			check(valid, label + ": finite geometry, unit normals and valid indices")
			var lods: Array = mesh.get_meta("lod_triangles", [])
			check(lods.size() >= 3 and lods[-1] < indices.size()/12, label + ": distant LOD reduces triangles by at least 4x")
			total += indices.size()/3 * (2 if part == bird.right else 1)
		check(total < 26000, label + ": full bird stays below 26k close-up triangles")
		bird.animate(0, false, 1)
		var points: PackedVector3Array = bird.right.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var resting_span := 0.0
		var lowest := INF
		for p in points:
			var transformed := bird.right.transform * p
			resting_span = maxf(resting_span, transformed.x)
			lowest = minf(lowest, transformed.y)
		check(lowest > .09, label + ": folded feathers stay above feet and the waterline")
		var widest := 0.0
		var mirrored := true
		for phase in 16:
			bird.animate(phase*.025, true, 1)
			for p in points:
				var right: Vector3 = bird.right.transform * p
				var left: Vector3 = bird.left.transform * p
				widest = maxf(widest, right.x)
				mirrored = mirrored and right.is_finite() and left.is_equal_approx(Vector3(-right.x,right.y,right.z))
		check(mirrored and widest > resting_span*1.5, label + ": symmetric flight and a distinctly narrower resting pose")
		var bounds := bird.body.mesh.get_aabb()
		check(absf(bounds.position.y) < .002 and bounds.end.y < .57, label + ": feet and body retain the existing gameplay scale")
		bird.free()
		other.free()
	stage.free()
	print("BIRD MODEL TESTS: %d failures" % failures)
	quit(1 if failures else 0)
