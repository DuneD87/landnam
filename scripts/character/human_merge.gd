class_name HumanMerge

## The light versions of a dressed human, for when it stands a little way off and when it is far:
##
## - the merged mesh: everything it wears in one mesh, one surface per material and one skin, on
##   its own skeleton (the body, the hair and each garment are a mesh of their own with several
##   surfaces, some thirty draws per pass; merged it is six or seven). The vertices are the same and
##   the skin is all the skins' binds in a row, so it poses exactly as the pieces did;
## - the crowd body (CrowdBody): a coarser merge posed by a texture of bone matrices, without a
##   skeleton. Its vertices are moved to the human's own rest pose (the skeleton's rest plus its
##   BodyProportions) and its matrices baked from CrowdClips with those proportions.
##
## gather() runs on the main thread once the human is dressed and fitted; build() in a thread
## (with the arrays its meshes were built from, MeshArrays: reading a mesh back from the renderer
## stalls it, so when it must it pauses between surfaces); finish() on the main thread again.

## Never merged: nobody sees them from where the light versions show.
const SKIP: Array[StringName] = [&"HumanEyes", &"HumanTeeth", &"HumanTongue", &"HumanEyebrows", &"HumanEyelashes"]
## The coarsest level of detail each version takes, as the error of the mesh's LODs, metres.
const NEAR_ERROR := 0.008
const FAR_ERROR := 0.06
## The crowd body's second, lighter mesh, for the figures further than CrowdBody.DISTANT_REACH.
const DISTANT_ERROR := 0.3
const READ_PAUSE_MS := 3


## Waiting to be built: [who asked (an id), gather()'s job]; and built: id -> build()'s result.
static var _queue: Array = []
static var _results := {}
static var _dropped := {}
static var _lock := Mutex.new()
static var _task := -1


## Queues `job` (gather()) to be built in the background, one at a time; take() gives it to `id`.
static func request(id: int, job: Dictionary) -> void:
	_lock.lock()
	_dropped.erase(id)
	_queue.append([id, job])
	_lock.unlock()
	pump()


## The result for `id` once built ({} if nothing came out), or null while it waits.
static func take(id: int) -> Variant:
	_lock.lock()
	var result: Variant = _results.get(id)
	_results.erase(id)
	_lock.unlock()
	return result


## `id` no longer wants what it asked for.
static func cancel(id: int) -> void:
	_lock.lock()
	_queue = _queue.filter(func(entry: Array) -> bool: return entry[0] != id)
	_results.erase(id)
	_dropped[id] = true
	_lock.unlock()


## On the main thread, now and then: keeps the builder going while there is something to build.
static func pump() -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _task < 0:
		_lock.lock()
		var waiting := not _queue.is_empty()
		_lock.unlock()
		if waiting:
			_task = WorkerThreadPool.add_task(_work, false, "HumanMerge")


## Waits for the builder and forgets everything (leaving the game).
static func shutdown() -> void:
	_lock.lock()
	_queue.clear()
	_lock.unlock()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_results.clear()
	_dropped.clear()


static func _work() -> void:
	while true:
		_lock.lock()
		var entry: Array = _queue.pop_front() if not _queue.is_empty() else []
		_lock.unlock()
		if entry.is_empty():
			return
		var result := build(entry[1])
		_lock.lock()
		if not _dropped.has(entry[0]):
			_results[entry[0]] = result
		_lock.unlock()


## One material's worth of triangles.
class Group:
	var material: Material
	var vertex := PackedVector3Array()
	var normal := PackedVector3Array()
	var tangent := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var color := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var custom_bones := PackedByteArray()
	var custom_weights := PackedByteArray()
	var index := PackedInt32Array()
	var has_uv2 := false
	var has_color := false


## What build() needs of `model` (Villager.build_model, in the tree and dressed), or {} if it
## cannot be merged. `nodes` are the meshes the merged one stands for.
static func gather(model: Node3D) -> Dictionary:
	var skeleton := model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	var armature := model.get_node_or_null("Armature") as Node3D
	if skeleton == null or armature == null:
		return {}
	var sources := []
	var nodes: Array[MeshInstance3D] = []
	for instance: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null or instance.skin == null or not instance.mesh is ArrayMesh:
			continue
		var at := Transform3D.IDENTITY
		var shown := instance.layers != 0 and instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var node: Node = instance
		while node != skeleton and node != null:
			if node is Node3D:
				shown = shown and (node as Node3D).visible
				at = (node as Node3D).transform * at
			node = node.get_parent()
		if not shown:
			continue
		nodes.append(instance)
		if SKIP.has(instance.name):
			continue
		# A skinned mesh is posed in its skeleton's space: off it, it would not land where it does.
		if not at.is_equal_approx(Transform3D.IDENTITY):
			return {}
		var materials := []
		for s in instance.mesh.get_surface_count():
			materials.append(instance.get_active_material(s))
		sources.append({mesh = instance.mesh, skin = instance.skin, materials = materials})
	if sources.is_empty():
		return {}
	var bones := PackedStringArray()
	var parents := PackedInt32Array()
	var rests: Array[Transform3D] = []
	for b in skeleton.get_bone_count():
		bones.append(skeleton.get_bone_name(b))
		parents.append(skeleton.get_bone_parent(b))
		rests.append(skeleton.get_bone_rest(b))
	var proportions := skeleton.get_node_or_null("BodyProportions") as BodyProportions
	return {sources = sources, nodes = nodes, bones = bones, parents = parents, rests = rests,
		offsets = proportions.bone_offsets.duplicate() if proportions != null else {},
		to_model = armature.transform * skeleton.transform}


## In a thread: {near: ArrayMesh, skin: Skin, far: ArrayMesh, far_materials: the source material of
## each of its surfaces, image: the bone matrices}. {} if nothing came out.
static func build(job: Dictionary) -> Dictionary:
	CrowdClips.ensure()
	var bones: PackedStringArray = job.bones
	var parents: PackedInt32Array = job.parents
	var rests: Array = job.rests
	var offsets: Dictionary = job.offsets
	var to_model: Transform3D = job.to_model
	var count := bones.size()
	var crowd_bones := CrowdClips.bones()
	# The human's own rest pose, and the crowd's bone each of its bones follows (itself, or the
	# nearest one above it that the clips move).
	var ref: Array[Transform3D] = []
	var follows := PackedInt32Array()
	for b in count:
		var local: Transform3D = rests[b]
		if offsets.has(b):
			local.origin += offsets[b]
		ref.append(ref[parents[b]] * local if parents[b] >= 0 else local)
		var own := crowd_bones.find(bones[b])
		follows.append(own if own >= 0 else (follows[parents[b]] if parents[b] >= 0 else 0))
	# Just the crowd body (a village's stand-ins, which never show the merged mesh).
	var far_only: bool = job.get("far_only", false)
	var near := {}
	var far := {}
	var distant := {}
	var binds := {}
	var bind_names: Array[StringName] = []
	var bind_poses: Array[Transform3D] = []
	for source: Dictionary in job.sources:
		var mesh: ArrayMesh = source.mesh
		var skin: Skin = source.skin
		var unified := PackedInt32Array()
		var crowd := PackedInt32Array()
		var at_rest: Array[Transform3D] = []
		for i in skin.get_bind_count():
			var name := skin.get_bind_name(i)
			var bone := bones.find(name) if name != &"" else skin.get_bind_bone(i)
			if bone < 0 or bone >= count:
				bone = 0
			var pose := skin.get_bind_pose(i)
			var key := [bone, pose]
			if not binds.has(key):
				binds[key] = bind_names.size()
				bind_names.append(StringName(bones[bone]))
				bind_poses.append(pose)
			unified.append(binds[key])
			crowd.append(follows[bone])
			at_rest.append(ref[bone] * pose)
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			# Kept on the CPU when it was built (MeshArrays); read back from the renderer, paced, if not.
			var kept := MeshArrays.is_kept(mesh)
			var arrays := MeshArrays.read(mesh, s)
			if not kept:
				OS.delay_msec(READ_PAUSE_MS)
			var carried := MeshArrays.lods(mesh, s)
			if not kept:
				OS.delay_msec(READ_PAUSE_MS)
			if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_NORMAL] == null:
				continue
			var material: Material = source.materials[s]
			var lods := _lods(arrays, carried)
			if not far_only:
				_append(_group(near, material), arrays, _indices(arrays, lods, NEAR_ERROR), unified, [], Transform3D.IDENTITY)
			_append(_group(far, material), arrays, _indices(arrays, lods, FAR_ERROR), crowd, at_rest, to_model)
			_append(_group(distant, material), arrays, _indices(arrays, lods, DISTANT_ERROR), crowd, at_rest, to_model)
	if far.is_empty():
		return {}
	var skin := Skin.new()
	for i in bind_names.size():
		skin.add_named_bind(bind_names[i], bind_poses[i])
	var far_materials := _materials(far.values())
	var distant_materials := _materials(distant.values())
	# The crowd's shaders, here: compiling one on the main thread (crowd()) was a 300 ms frame.
	CrowdShader.warm(far_materials + distant_materials)
	return {near = _mesh(near.values(), false) if not far_only else null, skin = skin,
		far = _mesh(far.values(), true), far_materials = far_materials,
		distant = _mesh(distant.values(), true), distant_materials = distant_materials,
		image = _bake(job, ref)}


## The source material of each surface _mesh() makes of `groups`.
static func _materials(groups: Array) -> Array[Material]:
	var materials: Array[Material] = []
	for group: Group in groups:
		if not group.index.is_empty():
			materials.append(group.material)
	return materials


## On the main thread: the merged mesh of build()'s `result`, to go under the human's skeleton.
static func merged(result: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "Merged"
	instance.mesh = result.near
	instance.skin = result.skin
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	return instance


## On the main thread: the crowd body of build()'s `result`.
static func crowd(result: Dictionary) -> CrowdBody:
	var body := CrowdBody.new()
	body.mesh = result.far
	body.distant = result.distant
	body.bones = ImageTexture.create_from_image(result.image)
	# One material per source material, shared by the two meshes.
	var made := {}
	for pair: Array in [[body.mesh, result.far_materials], [body.distant, result.distant_materials]]:
		var mesh: ArrayMesh = pair[0]
		var materials: Array = pair[1]
		for s in mesh.get_surface_count():
			if not made.has(materials[s]):
				made[materials[s]] = CrowdShader.material(materials[s], body.bones)
			if made[materials[s]] == null:
				return null
			mesh.surface_set_material(s, made[materials[s]])
	return body


static func _group(groups: Dictionary, material: Material) -> Group:
	if not groups.has(material):
		var group := Group.new()
		group.material = material
		groups[material] = group
	return groups[material]


## The LODs of a surface, [error, its triangles] from fine to coarse: the ones it carries (`carried`,
## MeshArrays.lods) or, if it has none (the hair), the ones MeshLods can make of it.
static func _lods(arrays: Array, carried: Dictionary) -> Array:
	var out := []
	for error: float in carried:
		out.append([error, carried[error]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if out.is_empty() and not arrays.is_empty() and arrays[Mesh.ARRAY_INDEX] != null:
		var made := MeshLods.generate(arrays)
		for error: float in made:
			out.append([error, made[error]])
		out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


## The triangles of the coarsest of a surface's `lods` within `max_error`, or all of them.
static func _indices(arrays: Array, lods: Array, max_error: float) -> PackedInt32Array:
	var chosen := PackedInt32Array()
	for lod: Array in lods:
		if float(lod[0]) <= max_error:
			chosen = lod[1]
	if not chosen.is_empty():
		return chosen
	if arrays[Mesh.ARRAY_INDEX] != null:
		return arrays[Mesh.ARRAY_INDEX]
	return PackedInt32Array(range((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))


## Adds the vertices `indices` use to `group`, with their bones through `bind_map` (the bind of
## their skin -> the bone they get) and at most four of them. With `at_rest` (each bind's matrix
## in the human's rest pose), the far version: the vertex goes to that pose and on to the model's
## space (`to_model`), and its bones and weights go as bytes.
static func _append(group: Group, arrays: Array, indices: PackedInt32Array, bind_map: PackedInt32Array,
		at_rest: Array, to_model: Transform3D) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(vertices.size(), 1)
	var far := not at_rest.is_empty()
	var has_tangent := tangents.size() == vertices.size() * 4
	var has_uv := uvs.size() == vertices.size()
	var has_uv2 := uv2s.size() == vertices.size()
	var has_color := colors.size() == vertices.size()
	group.has_uv2 = group.has_uv2 or has_uv2
	group.has_color = group.has_color or has_color
	var remap := PackedInt32Array()
	remap.resize(vertices.size())
	remap.fill(-1)
	var pick_bone := PackedInt32Array([0, 0, 0, 0])
	var pick_weight := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in indices:
		var n := remap[i]
		if n >= 0:
			group.index.append(n)
			continue
		n = group.vertex.size()
		remap[i] = n
		group.index.append(n)
		var vertex := vertices[i]
		var normal := normals[i]
		var tangent := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2]) if has_tangent else Vector3.RIGHT
		# Its four heaviest bones, as the bones they get; the same one twice adds up.
		pick_weight.fill(0.0)
		var total := 0.0
		var moved := Vector3.ZERO
		var turned := Vector3.ZERO
		var swung := Vector3.ZERO
		var base := i * per
		for k in per:
			var w := weights[base + k]
			if w <= 0.0:
				continue
			var bind := bones[base + k]
			if bind >= bind_map.size():
				continue
			if far:
				var m: Transform3D = at_rest[bind]
				moved += (m * vertex) * w
				turned += (m.basis * normal) * w
				swung += (m.basis * tangent) * w
				total += w
			var bone := bind_map[bind]
			var slot := -1
			var lightest := 0
			for j in 4:
				if pick_weight[j] > 0.0 and pick_bone[j] == bone:
					slot = j
					break
				if pick_weight[j] < pick_weight[lightest]:
					lightest = j
			if slot >= 0:
				pick_weight[slot] += w
			elif w > pick_weight[lightest]:
				pick_bone[lightest] = bone
				pick_weight[lightest] = w
		var sum := pick_weight[0] + pick_weight[1] + pick_weight[2] + pick_weight[3]
		if sum <= 0.0:
			pick_bone[0] = 0
			pick_weight[0] = 1.0
			sum = 1.0
		if far and total > 0.0:
			vertex = to_model * (moved / total)
			normal = (to_model.basis * turned).normalized()
			tangent = (to_model.basis * swung).normalized()
		elif far:
			vertex = to_model * vertex
		group.vertex.append(vertex)
		group.normal.append(normal)
		group.tangent.append(tangent.x)
		group.tangent.append(tangent.y)
		group.tangent.append(tangent.z)
		group.tangent.append(tangents[i * 4 + 3] if has_tangent else 1.0)
		group.uv.append(uvs[i] if has_uv else Vector2.ZERO)
		group.uv2.append(uv2s[i] if has_uv2 else Vector2.ZERO)
		group.color.append(colors[i] if has_color else Color.WHITE)
		if far:
			var left := 255
			var heaviest := 0
			for j in 4:
				var byte := int(round(pick_weight[j] / sum * 255.0))
				group.custom_bones.append(pick_bone[j] if pick_weight[j] > 0.0 else 0)
				group.custom_weights.append(byte)
				left -= byte
				if pick_weight[j] > pick_weight[heaviest]:
					heaviest = j
			# The bytes add up to one whole.
			var last := group.custom_weights.size() - 4 + heaviest
			group.custom_weights[last] = clampi(group.custom_weights[last] + left, 0, 255)
		else:
			for j in 4:
				group.bones.append(pick_bone[j] if pick_weight[j] > 0.0 else 0)
				group.weights.append(pick_weight[j] / sum)


static func _mesh(groups: Array, far: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for group: Group in groups:
		if group.index.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.vertex
		arrays[Mesh.ARRAY_NORMAL] = group.normal
		arrays[Mesh.ARRAY_TANGENT] = group.tangent
		arrays[Mesh.ARRAY_TEX_UV] = group.uv
		if group.has_uv2:
			arrays[Mesh.ARRAY_TEX_UV2] = group.uv2
		if group.has_color:
			arrays[Mesh.ARRAY_COLOR] = group.color
		arrays[Mesh.ARRAY_INDEX] = group.index
		var flags := 0
		if far:
			arrays[Mesh.ARRAY_CUSTOM0] = group.custom_bones
			arrays[Mesh.ARRAY_CUSTOM1] = group.custom_weights
			flags = (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		else:
			arrays[Mesh.ARRAY_BONES] = group.bones
			arrays[Mesh.ARRAY_WEIGHTS] = group.weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		if not far:
			mesh.surface_set_material(mesh.get_surface_count() - 1, group.material)
	return mesh


## The matrix of each of the crowd's bones at each of its rows, in the model's space and from the
## human's rest pose (`ref`): three RGBA texels per bone, a row of the image per row of the clips.
static func _bake(job: Dictionary, ref: Array[Transform3D]) -> Image:
	var bones: PackedStringArray = job.bones
	var offsets: Dictionary = job.offsets
	var to_model: Transform3D = job.to_model
	var names := CrowdClips.bones()
	var parents := CrowdClips.parents()
	var rows := CrowdClips.rows()
	var count := names.size()
	var back: Array[Transform3D] = []
	var offset := PackedVector3Array()
	var from_model := to_model.affine_inverse()
	for c in count:
		var bone := bones.find(names[c])
		back.append((ref[bone].affine_inverse() if bone >= 0 else Transform3D.IDENTITY) * from_model)
		offset.append(offsets.get(bone, Vector3.ZERO))
	var width := count * 3
	var data := PackedFloat32Array()
	data.resize(width * rows.size() * 4)
	var global: Array[Transform3D] = []
	global.resize(count)
	var at := 0
	for r in rows.size():
		var row: Array = rows[r]
		for c in count:
			var local: Transform3D = row[c]
			local.origin += offset[c]
			var g: Transform3D = global[parents[c]] * local if parents[c] >= 0 else local
			global[c] = g
			var m := to_model * g * back[c]
			var b := m.basis
			var o := m.origin
			data[at] = b.x.x
			data[at + 1] = b.y.x
			data[at + 2] = b.z.x
			data[at + 3] = o.x
			data[at + 4] = b.x.y
			data[at + 5] = b.y.y
			data[at + 6] = b.z.y
			data[at + 7] = o.y
			data[at + 8] = b.x.z
			data[at + 9] = b.y.z
			data[at + 10] = b.z.z
			data[at + 11] = o.z
			at += 12
	var image := Image.create_from_data(width, rows.size(), false, Image.FORMAT_RGBAF, data.to_byte_array())
	image.convert(Image.FORMAT_RGBAH)
	return image
