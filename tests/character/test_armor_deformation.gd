extends SceneTree

## Regression for texture shearing caused by abrupt skinning weights.
## Measures the actual fitted meshes in idle and running, with modifiers
## applied. Physics is disabled to isolate the skinning from skirt swing.
##   godot --headless --path . --script res://tests/character/test_armor_deformation.gd

const PIECES := ["fur_mantle", "fur_loincloth", "fur_mittens", "fur_moccasins",
		"hide_tunic", "hide_trousers", "hide_mittens", "hide_boots"]
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
	var model: Node3D = load("res://scenes/character/character_model.tscn").instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	rig.apply(CharacterAppearance.new())
	var pieces := {}
	for id in PIECES:
		var item: MeshInstance3D = load("res://scenes/items/armor/stone_age/%s_equipable.tscn" % id).instantiate()
		skeleton.add_child(item)
		rig.dress(item)
		pieces[id] = item
	var start := Time.get_ticks_msec()
	while rig.is_dressing() and Time.get_ticks_msec() - start < 120000:
		await process_frame
	check(not rig.is_dressing(), "all garments finish fitting")
	if rig.is_dressing():
		model.free()
		quit(1)
		return
	for child in skeleton.get_children():
		if child is SkirtSwing:
			child.active = false
	var poses: Array[Transform3D] = []
	skeleton.skeleton_updated.connect(func() -> void:
		poses.clear()
		for b in skeleton.get_bone_count():
			poses.append(skeleton.get_bone_global_pose(b)))
	player.stop()
	player.active = false
	skeleton.reset_bone_poses()
	for frame in 3:
		await process_frame
	var rest := {}
	var edges := {}
	for id in pieces:
		var item: MeshInstance3D = pieces[id]
		var arrays := item.mesh.surface_get_arrays(0)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		var per := weights.size() / count
		check(weights.size() == count * 8 and item.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS,
				"%s keeps eight influences after fitting" % id)
		var valid := true
		for i in count:
			var total := 0.0
			for k in range(i * per, i * per + per):
				valid = valid and is_finite(weights[k]) and weights[k] >= 0.0
				total += weights[k]
			valid = valid and absf(total - 1.0) < 0.001
		check(valid, "%s has finite, normalised weights" % id)
		rest[id] = _points(arrays, item.skin, skeleton, poses)
		edges[id] = _edges(arrays[Mesh.ARRAY_INDEX], rest[id], 0.002 / skeleton.global_basis.get_scale().x)
	player.active = true
	for sample in [["idle", 0.0], ["running", 0.25], ["running", 0.75]]:
		check(player.has_animation(sample[0]), "animation %s exists" % sample[0])
		player.play(sample[0])
		player.seek(sample[1], true)
		player.speed_scale = 0.0
		for frame in 3:
			await process_frame
		for id in pieces:
			var item: MeshInstance3D = pieces[id]
			var posed := _points(item.mesh.surface_get_arrays(0), item.skin, skeleton, poses)
			var ratios := PackedFloat32Array()
			for edge: Vector2i in edges[id]:
				ratios.append(posed[edge.x].distance_to(posed[edge.y]) / rest[id][edge.x].distance_to(rest[id][edge.y]))
			ratios.sort()
			var p99 := ratios[int((ratios.size() - 1) * 0.99)]
			var largest := ratios[-1]
			check(p99 < 2.0 and largest < 4.5,
					"%s in %s %.2f: edge stretch p99 %.2fx, max %.2fx" % [id, sample[0], sample[1], p99, largest])
	model.free()
	print("ARMOR DEFORMATION TESTS: %d failures" % failures)
	quit(1 if failures else 0)


func _points(arrays: Array, skin: Skin, skeleton: Skeleton3D, poses: Array[Transform3D]) -> PackedVector3Array:
	var binds := BodyMeasurements.bind_transforms(skin, skeleton, poses)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	var result := PackedVector3Array()
	for i in vertices.size():
		var p := Vector3.ZERO
		for k in range(i * per, i * per + per):
			p += binds[bones[k]] * vertices[i] * weights[k]
		result.append(p)
	return result


func _edges(indices: PackedInt32Array, points: PackedVector3Array, minimum_length: float) -> Array[Vector2i]:
	var unique := {}
	for t in range(0, indices.size(), 3):
		for corner in 3:
			var a := indices[t + corner]
			var b := indices[t + (corner + 1) % 3]
			if points[a].distance_to(points[b]) >= minimum_length:
				unique[Vector2i(mini(a, b), maxi(a, b))] = true
	var result: Array[Vector2i] = []
	result.assign(unique.keys())
	return result
