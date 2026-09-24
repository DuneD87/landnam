class_name HumanShape
extends RefCounted

## The human for one set of morph weights: joint displacements, raw anchors,
## body and proxy geometry (see HumanBodyData and HumanProxyData).
##
## set_weights() is incremental: the anchors only change by the morphs whose
## weight changed, so dragging a slider refits the proxies cheaply. Geometry is
## in the "residual" space the meshes are skinned in: the skeleton, offset by
## joint_offsets, adds the joints' rigid part.

## Blend shape of the baked body and of the proxies that shut with the
## eyelids (see blink_mix()).
const BLINK := &"blink"
## Morphs that shape the eye opening. The blink relaxes them as the lids shut:
## a wide-open eye would not close otherwise, and a hooded lid would fold
## into itself.
const BLINK_RELAXES: Array[StringName] = [&"eye_opening", &"eye_opening-", &"eyelid", &"eyelid-"]

var data: HumanBodyData
var sex := &"male"
## Morph weights applied to the anchors.
var weights := {}
## Current raw anchors.
var anchors: PackedVector3Array
## Per bone, how far the joints are from the male base's.
var joint_offsets: PackedVector3Array
## Height of the raw soles.
var ground := 0.0

var _anchor_morphs := {}
## Per proxy, the eyelid rings' base centres and spreads.
var _lid_rest := {}
## [proxy, anchor morph] -> whether the morph moves the proxy's anchors.
var _reach := {}

static var _morphable_bodies := {}


func _init(body: HumanBodyData) -> void:
	data = body
	anchors = data.anchors.duplicate()
	joint_offsets.resize(data.bone_names.size())
	for i in data.anchor_names.size():
		_anchor_morphs[StringName(data.anchor_names[i])] = i
	ground = data.ground.get(&"male", 0.0)


func set_weights(new_weights: Dictionary, new_sex: StringName) -> void:
	sex = new_sex
	var names := {}
	for name in weights:
		names[name] = true
	for name in new_weights:
		names[name] = true
	var offsets := data.anchor_offsets
	var indices := data.anchor_indices
	var deltas := data.anchor_deltas
	for name in names:
		var change: float = new_weights.get(name, 0.0) - weights.get(name, 0.0)
		if absf(change) < 1e-6:
			continue
		var m: int = _anchor_morphs.get(name, -1)
		if m < 0:
			continue
		for k in range(offsets[m], offsets[m + 1]):
			anchors[indices[k]] += deltas[k] * change
	weights = new_weights.duplicate()

	joint_offsets.fill(Vector3.ZERO)
	ground = data.ground.get(&"male", 0.0)
	for name in weights:
		var w: float = weights[name]
		if is_zero_approx(w):
			continue
		var jd: PackedVector3Array = data.joint_deltas.get(name, PackedVector3Array())
		for b in jd.size():
			joint_offsets[b] += jd[b] * w
		ground += data.ground_deltas.get(name, 0.0) * w


## Joint positions (skin space) for the current weights.
func joint_positions() -> PackedVector3Array:
	var result := data.joints.duplicate()
	for b in result.size():
		result[b] += joint_offsets[b]
	return result


## Body mesh with every morph as a blend shape, for live editing. Built once
## per body data and shared.
func body_morphable() -> ArrayMesh:
	if _morphable_bodies.has(data):
		return _morphable_bodies[data]
	var base := data.mesh.surface_get_arrays(0)
	var result := ArrayMesh.new()
	# NORMALIZED with absolute targets blends as base + sum(w * (target - base)).
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var shapes: Array[Array] = []
	for m in data.names.size():
		result.add_blend_shape(data.names[m])
		var vertices: PackedVector3Array = base[Mesh.ARRAY_VERTEX].duplicate()
		var normals: PackedVector3Array = base[Mesh.ARRAY_NORMAL].duplicate()
		for k in range(data.offsets[m], data.offsets[m + 1]):
			var i := data.indices[k]
			vertices[i] += data.position_deltas[k]
			normals[i] = (normals[i] + data.normal_deltas[k]).normalized()
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = vertices
		shape[Mesh.ARRAY_NORMAL] = normals
		shape[Mesh.ARRAY_TANGENT] = base[Mesh.ARRAY_TANGENT]
		shapes.append(shape)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base, shapes)
	_morphable_bodies[data] = result
	return result


## Body mesh with the current weights baked into its vertices. `shapes` stay
## blend shapes on top, each a mix of morphs (name -> {morph: weight}).
func body_baked(shapes := {}) -> ArrayMesh:
	var arrays := data.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var touched := PackedByteArray()
	touched.resize(vertices.size())
	for name in weights:
		var w: float = weights[name]
		var m := data.morph(name)
		if m < 0 or is_zero_approx(w):
			continue
		for k in range(data.offsets[m], data.offsets[m + 1]):
			var i := data.indices[k]
			vertices[i] += data.position_deltas[k] * w
			normals[i] += data.normal_deltas[k] * w
			touched[i] = 1
	for i in vertices.size():
		if touched[i]:
			normals[i] = normals[i].normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var result := ArrayMesh.new()
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var targets: Array[Array] = []
	for shape_name in shapes:
		result.add_blend_shape(shape_name)
		var mix: Dictionary = shapes[shape_name]
		var shape_vertices := vertices.duplicate()
		var shape_normals := normals.duplicate()
		for name in mix:
			var m := data.morph(name)
			var w: float = mix[name]
			if m < 0:
				continue
			for k in range(data.offsets[m], data.offsets[m + 1]):
				var i := data.indices[k]
				shape_vertices[i] += data.position_deltas[k] * w
				shape_normals[i] += data.normal_deltas[k] * w
		for i in shape_normals.size():
			shape_normals[i] = shape_normals[i].normalized()
		var target := []
		target.resize(Mesh.ARRAY_MAX)
		target[Mesh.ARRAY_VERTEX] = shape_vertices
		target[Mesh.ARRAY_NORMAL] = shape_normals
		target[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		targets.append(target)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, targets)
	return result


## The blink morph of the current sex (see HumanBlink).
func blink_morph() -> StringName:
	return StringName("blink@" + sex)


## The blink as changes to the current morph weights: the lids shut and the
## morphs that shape the eye opening relax.
func blink_mix() -> Dictionary:
	var mix := {blink_morph(): 1.0}
	for name in BLINK_RELAXES:
		var w: float = weights.get(name, 0.0)
		if not is_zero_approx(w):
			mix[name] = -w
	return mix


## Proxy mesh refitted to the current body. A proxy fitted to the eyelids
## (the eyelashes) gets a BLINK blend shape that follows them shut.
func proxy_mesh(proxy: HumanProxyData, reuse: ArrayMesh = null) -> ArrayMesh:
	var arrays := proxy.arrays().duplicate()
	var positions := proxy_positions(proxy)
	arrays[Mesh.ARRAY_VERTEX] = positions
	var shapes: Array[Array] = []
	var blink := proxy_blink(proxy)
	if not blink.is_empty():
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = blink
		shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		shape[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		shapes.append(shape)
	var result := reuse if reuse != null else ArrayMesh.new()
	result.clear_surfaces()
	result.clear_blend_shapes()
	if not shapes.is_empty():
		result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		result.add_blend_shape(BLINK)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	return result


## Proxy vertices (output order) with the eyelids shut (blink_mix()), or
## nothing when the blink does not reach the proxy. Eyeballs never follow it.
func proxy_blink(proxy: HumanProxyData) -> PackedVector3Array:
	var m: int = _anchor_morphs.get(blink_morph(), -1)
	if m < 0 or not proxy.lid_rings.is_empty() or not _reaches(proxy, m):
		return PackedVector3Array()
	var open := anchors
	anchors = anchors.duplicate()
	var mix := blink_mix()
	for name in mix:
		var n: int = _anchor_morphs.get(name, -1)
		if n < 0:
			continue
		var w: float = mix[name]
		for k in range(data.anchor_offsets[n], data.anchor_offsets[n + 1]):
			anchors[data.anchor_indices[k]] += data.anchor_deltas[k] * w
	var closed := proxy_positions(proxy)
	anchors = open
	return closed


## Whether anchor morph `m` moves any anchor the proxy is fitted to.
func _reaches(proxy: HumanProxyData, m: int) -> bool:
	var key := [proxy, m]
	if not _reach.has(key):
		var moved := {}
		for k in range(data.anchor_offsets[m], data.anchor_offsets[m + 1]):
			moved[data.anchor_indices[k]] = true
		var found := false
		for ref in proxy.fit_refs:
			if moved.has(ref):
				found = true
				break
		_reach[key] = found
	return _reach[key]


## Proxy vertices (output order) refitted to the current body.
func proxy_positions(proxy: HumanProxyData) -> PackedVector3Array:
	var count := proxy.pose_weights.size() / 4
	var raw := PackedVector3Array()
	raw.resize(count)
	if not proxy.lid_rings.is_empty():
		_fit_eyes(proxy, raw)
	else:
		_fit(proxy, raw)

	# Pose: raw -> skin space per bone (MakeHuman's weights), less the ground.
	# The weights of a vertex add up to one.
	var pose: Array = data.pose.get(sex, data.pose[&"male"])
	var adjusted: Array[Transform3D] = []
	adjusted.resize(pose.size())
	var down := Vector3(0.0, ground, 0.0)
	for b in pose.size():
		var t: Transform3D = pose[b]
		adjusted[b] = Transform3D(t.basis, t.origin - down)
	var bones := proxy.pose_bones
	var bone_weights := proxy.pose_weights
	var posed := PackedVector3Array()
	posed.resize(count)
	for i in count:
		var p := raw[i]
		var j := i * 4
		var result := adjusted[bones[j]] * p * bone_weights[j]
		for k in range(1, 4):
			var w := bone_weights[j + k]
			if w > 0.0:
				result += adjusted[bones[j + k]] * p * w
		posed[i] = result

	# Less the joints' rigid part, which the skeleton adds back through the
	# skin weights (the player's, not the pose's).
	var arrays := proxy.arrays()
	var skin_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var skin_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var source := proxy.source
	var output := PackedVector3Array()
	output.resize(source.size())
	for i in source.size():
		var j := i * 4
		output[i] = posed[source[i]] - joint_offsets[skin_bones[j]] * skin_weights[j] \
				- joint_offsets[skin_bones[j + 1]] * skin_weights[j + 1] \
				- joint_offsets[skin_bones[j + 2]] * skin_weights[j + 2] \
				- joint_offsets[skin_bones[j + 3]] * skin_weights[j + 3]
	return output


func _fit(proxy: HumanProxyData, raw: PackedVector3Array) -> void:
	var scale := Vector3(0.1, 0.1, 0.1)
	var s := proxy.fit_scales
	if s.size() == 9:
		# MakeHuman: width from X, height from Z (up) and depth from Y.
		var width := absf(anchors[int(s[0])].x - anchors[int(s[1])].x) / s[2]
		var height := absf(anchors[int(s[3])].z - anchors[int(s[4])].z) / s[5]
		var depth := absf(anchors[int(s[6])].y - anchors[int(s[7])].y) / s[8]
		scale = Vector3(width, depth, height)
	var refs := proxy.fit_refs
	var fit_weights := proxy.fit_weights
	var offsets := proxy.fit_offsets
	for i in raw.size():
		var j := i * 3
		raw[i] = anchors[refs[j]] * fit_weights[j] + anchors[refs[j + 1]] * fit_weights[j + 1] \
				+ anchors[refs[j + 2]] * fit_weights[j + 2] + offsets[i] * scale


func _fit_eyes(proxy: HumanProxyData, raw: PackedVector3Array) -> void:
	if not _lid_rest.has(proxy):
		var rest := []
		for ring in proxy.lid_rings:
			rest.append(_centre_and_spread(ring, data.anchors))
		_lid_rest[proxy] = rest
	var rest: Array = _lid_rest[proxy]
	var now := []
	for ring in proxy.lid_rings:
		now.append(_centre_and_spread(ring, anchors))
	for i in raw.size():
		var side := proxy.lid_side[i]
		var scale: float = now[side][1] / rest[side][1]
		raw[i] = now[side][0] + (proxy.lid_raw[i] - rest[side][0]) * scale


static func _centre_and_spread(ring: PackedInt32Array, points: PackedVector3Array) -> Array:
	var centre := Vector3.ZERO
	for i in ring:
		centre += points[i]
	centre /= ring.size()
	var spread := 0.0
	for i in ring:
		spread += (points[i] - centre).length_squared()
	return [centre, sqrt(spread)]
