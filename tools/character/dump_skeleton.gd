extends SceneTree

## Writes the player skeleton for the Blender tools
## (tools/character/blender/export_mpfb_human.py, fit_meshy_armor.py): every
## bone with its parent, its bind index in the player Skin and its joint
## position in the skin's space (the inverse of its bind pose). Also the
## player's own mesh (the scan) in that space, with its skin weights by
## skeleton bone and its triangles: the exporter transfers the weights to the
## MakeHuman body, since the player animations were made for them, and the
## armour fit puts garments on it. And the skirt's bones (SkirtBones), which
## the skeleton gets when a hanging skirt is worn: their joints in that space.
##
##   godot --headless --path . --script res://tools/character/dump_skeleton.gd -- <output.json>

const MODEL := "res://scenes/character/character_model.tscn"
const SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const MESH := "res://models/player/xavivar/firstage_human_male_player_mesh.tres"


func _initialize() -> void:
	var output := OS.get_cmdline_user_args()[0]
	var model: Node3D = load(MODEL).instantiate()
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var skin: Skin = load(SKIN)
	var bones := []
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		var bind_index := -1
		for b in skin.get_bind_count():
			if skin.get_bind_name(b) == name:
				bind_index = b
		var joint := skin.get_bind_pose(bind_index).affine_inverse().origin
		bones.append({name = name, parent = skeleton.get_bone_parent(i), bind_index = bind_index,
				mesh_joint = [joint.x, joint.y, joint.z]})
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({bones = bones, mesh = _mesh(skeleton, skin), skirt = _skirt(skeleton, skin)}))
	file.close()
	model.free()
	print("Skeleton with %d bones written to %s" % [bones.size(), output])
	quit()


## The skirt's bones: name, parent name and joint in the skin's space.
func _skirt(skeleton: Skeleton3D, skin: Skin) -> Array:
	var hips := skeleton.find_bone(SkirtBones.HIPS)
	var bind := -1
	for b in skin.get_bind_count():
		if skin.get_bind_name(b) == SkirtBones.HIPS:
			bind = b
	# Skin space to skeleton space: what every bind does with its bone at rest.
	var to_skin := (BodyMeasurements.rest_globals(skeleton)[hips] * skin.get_bind_pose(bind)).affine_inverse()
	var result := []
	var rests := SkirtBones.rests(skeleton)
	for name: StringName in rests:
		var joint: Vector3 = to_skin * (rests[name][1] as Transform3D).origin
		result.append({name = name, parent = rests[name][0], joint = [joint.x, joint.y, joint.z]})
	return result


## Every surface of the player mesh: positions, normals, four influences
## per vertex (skeleton bone index, weight) and its triangles.
func _mesh(skeleton: Skeleton3D, skin: Skin) -> Dictionary:
	var mesh: ArrayMesh = load(MESH)
	var result := {positions = [], normals = [], bones = [], weights = [], indices = []}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var first: int = result.positions.size() / 3
		for index in arrays[Mesh.ARRAY_INDEX]:
			result.indices.append(first + index)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / positions.size()
		for i in positions.size():
			result.positions.append_array([positions[i].x, positions[i].y, positions[i].z])
			result.normals.append_array([normals[i].x, normals[i].y, normals[i].z])
			var influences := []
			for k in per:
				var w := weights[i * per + k]
				if w > 0.0:
					influences.append([w, skeleton.find_bone(skin.get_bind_name(bones[i * per + k]))])
			influences.sort_custom(func(a, b): return a[0] > b[0])
			for k in 4:
				var influence: Array = influences[k] if k < influences.size() else [0.0, 0]
				result.bones.append(influence[1])
				result.weights.append(influence[0])
	return result
