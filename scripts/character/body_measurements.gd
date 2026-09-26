class_name BodyMeasurements
extends Resource

## A body's measurements, taken in the skeleton's rest pose (with the body's
## joint offsets, see BodyProportions). ArmorFit uses them to carry armour
## made for one body (the player scan, `REFERENCE`) onto another.
##
## Per bone they are a tape measure along the bone: the vertices the bone
## moves most, in the bone's own frame (Y along the bone), cut into SLICES
## slices from one end of that region to the other, each with its width (X)
## and depth (Z) as the extents of the slice. `summary` names a few of them
## the way a tailor would (height, chest, waist...), in metres.

const REFERENCE := "res://data/character/armor_fit/reference_body.tres"
const SLICES := 6
## Fewer vertices than this in a slice use the whole region's extents.
const MIN_SLICE_VERTICES := 12
## Share of vertices left out at each end of an extent, so a stray vertex
## does not set it.
const TRIM := 0.01
## Where each summary girth is taken: the bones, the slices of each and
## whether it is the widest or the narrowest of them. The girth is the
## ellipse through the slice's width and depth.
const GIRTHS := {
	&"chest": [[&"mixamorig_Spine1", &"mixamorig_Spine2"], [0, 1, 2, 3, 4, 5], &"widest"],
	&"waist": [[&"mixamorig_Spine"], [0, 1, 2, 3, 4, 5], &"narrowest"],
	&"hips": [[&"mixamorig_Hips"], [1, 2, 3, 4, 5], &"widest"],
	&"head": [[&"mixamorig_Head"], [0, 1, 2, 3, 4, 5], &"widest"],
	&"upper_arm": [[&"mixamorig_LeftArm"], [3], &"widest"],
	&"forearm": [[&"mixamorig_LeftForeArm"], [1], &"widest"],
	&"thigh": [[&"mixamorig_LeftUpLeg"], [1], &"widest"],
	&"calf": [[&"mixamorig_LeftLeg"], [0, 1, 2], &"widest"],
}
## Summary lengths, as the distance between two joints.
const SPANS := {
	&"shoulders": [&"mixamorig_LeftArm", &"mixamorig_RightArm"],
	&"arm": [&"mixamorig_LeftArm", &"mixamorig_LeftHand"],
	&"leg": [&"mixamorig_LeftUpLeg", &"mixamorig_LeftFoot"],
	&"torso": [&"mixamorig_Hips", &"mixamorig_Neck"],
}

## Skeleton bone names, in bone order.
@export var bone_names: PackedStringArray
## Per bone, where its region starts and ends along the bone (Y). A bone with
## no region has an empty span (x == y).
@export var spans: PackedVector2Array
## Per bone and slice: min X, max X, min Z, max Z.
@export var sections: PackedFloat32Array
## Name -> metres: height, the girths of GIRTHS, the widths and depths of
## the chest, waist and hips ("chest_width"...) and the lengths of SPANS.
## Taken from the tape measure above, they are close to a tailor's but not
## the same (a region ends where its bone stops moving the skin most).
@export var summary := {}


## Measures the meshes, each [ArrayMesh, Skin], skinned to `skeleton` with
## `globals` (every bone's global transform in skeleton space). `to_model`
## takes skeleton space to the model's, whose Y is up, in metres.
static func measure(meshes: Array, skeleton: Skeleton3D, globals: Array[Transform3D],
		to_model: Transform3D) -> BodyMeasurements:
	var bone_count := skeleton.get_bone_count()
	var locals: Array[PackedVector3Array] = []
	locals.resize(bone_count)
	var inverses: Array[Transform3D] = []
	for g in globals:
		inverses.append(g.affine_inverse())
	var lowest := INF
	var highest := -INF
	for entry in meshes:
		var mesh: ArrayMesh = entry[0]
		var binds := bind_transforms(entry[1], skeleton, globals)
		var skeleton_bones := bind_bones(entry[1], skeleton)
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / vertices.size()
			for i in vertices.size():
				var j := i * per
				var p := Vector3.ZERO
				var top := j
				for k in range(j, j + per):
					var w := weights[k]
					if w > 0.0:
						p += binds[bones[k]] * vertices[i] * w
						if w > weights[top]:
							top = k
				var bone := skeleton_bones[bones[top]]
				if bone >= 0:
					locals[bone].append(inverses[bone] * p)
				var up := (to_model * p).y
				lowest = minf(lowest, up)
				highest = maxf(highest, up)

	var result := BodyMeasurements.new()
	result.spans.resize(bone_count)
	result.sections.resize(bone_count * SLICES * 4)
	for bone in bone_count:
		result.bone_names.append(skeleton.get_bone_name(bone))
		result._measure_bone(bone, locals[bone])
	result._summarise(skeleton, globals, to_model, highest - lowest)
	return result


## Global transform of each bone in skeleton space at rest, each joint moved
## by `offsets` (bone -> local position offset, see BodyProportions).
static func rest_globals(skeleton: Skeleton3D, offsets := {}) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(skeleton.get_bone_count())
	var done := PackedByteArray()
	done.resize(globals.size())
	for bone in globals.size():
		_rest_global(skeleton, offsets, bone, globals, done)
	return globals


static func _rest_global(skeleton: Skeleton3D, offsets: Dictionary, bone: int,
		globals: Array[Transform3D], done: PackedByteArray) -> Transform3D:
	if done[bone]:
		return globals[bone]
	var local := skeleton.get_bone_rest(bone)
	local.origin += offsets.get(bone, Vector3.ZERO)
	var parent := skeleton.get_bone_parent(bone)
	globals[bone] = local if parent < 0 else _rest_global(skeleton, offsets, parent, globals, done) * local
	done[bone] = 1
	return globals[bone]


## Skeleton bone of each bind of `skin`.
static func bind_bones(skin: Skin, skeleton: Skeleton3D) -> PackedInt32Array:
	var result := PackedInt32Array()
	for b in skin.get_bind_count():
		var name := skin.get_bind_name(b)
		result.append(skeleton.find_bone(name) if name != &"" else skin.get_bind_bone(b))
	return result


## Per bind of `skin`, the transform that takes a vertex to skeleton space
## with the bones at `globals`.
static func bind_transforms(skin: Skin, skeleton: Skeleton3D, globals: Array[Transform3D]) -> Array[Transform3D]:
	var bones := bind_bones(skin, skeleton)
	var result: Array[Transform3D] = []
	for b in bones.size():
		result.append(globals[bones[b]] * skin.get_bind_pose(b) if bones[b] >= 0 else Transform3D.IDENTITY)
	return result


func has_bone(bone: int) -> bool:
	return bone < spans.size() and spans[bone].y > spans[bone].x


## The bone's slice extents at `t` (0 at the start of its region, 1 at the
## end), interpolated between slice centres: min X, max X, min Z, max Z.
func section_at(bone: int, t: float) -> PackedFloat32Array:
	var f := clampf(t * SLICES - 0.5, 0.0, SLICES - 1.0)
	var a := int(f)
	var b := mini(a + 1, SLICES - 1)
	var blend := f - a
	var result := PackedFloat32Array()
	result.resize(4)
	for k in 4:
		result[k] = lerpf(sections[(bone * SLICES + a) * 4 + k], sections[(bone * SLICES + b) * 4 + k], blend)
	return result


func _measure_bone(bone: int, points: PackedVector3Array) -> void:
	if points.size() < MIN_SLICE_VERTICES:
		spans[bone] = Vector2.ZERO
		return
	var ys := PackedFloat32Array()
	for p in points:
		ys.append(p.y)
	ys.sort()
	var y_min := _trimmed(ys, TRIM)
	var y_max := _trimmed(ys, 1.0 - TRIM)
	if y_max - y_min < 1e-4:
		spans[bone] = Vector2.ZERO
		return
	spans[bone] = Vector2(y_min, y_max)
	var xs: Array[PackedFloat32Array] = []
	var zs: Array[PackedFloat32Array] = []
	xs.resize(SLICES)
	zs.resize(SLICES)
	var all_x := PackedFloat32Array()
	var all_z := PackedFloat32Array()
	for p in points:
		var s := clampi(int((p.y - y_min) / (y_max - y_min) * SLICES), 0, SLICES - 1)
		xs[s].append(p.x)
		zs[s].append(p.z)
		all_x.append(p.x)
		all_z.append(p.z)
	all_x.sort()
	all_z.sort()
	for s in SLICES:
		var x := xs[s] if xs[s].size() >= MIN_SLICE_VERTICES else all_x
		var z := zs[s] if zs[s].size() >= MIN_SLICE_VERTICES else all_z
		x.sort()
		z.sort()
		var at := (bone * SLICES + s) * 4
		sections[at] = _trimmed(x, TRIM)
		sections[at + 1] = _trimmed(x, 1.0 - TRIM)
		sections[at + 2] = _trimmed(z, TRIM)
		sections[at + 3] = _trimmed(z, 1.0 - TRIM)


static func _trimmed(sorted: PackedFloat32Array, share: float) -> float:
	return sorted[clampi(roundi(share * (sorted.size() - 1)), 0, sorted.size() - 1)]


func _summarise(skeleton: Skeleton3D, globals: Array[Transform3D], to_model: Transform3D, height: float) -> void:
	var metres := to_model.basis.get_scale().x
	summary = {&"height": height}
	for name in GIRTHS:
		var spec: Array = GIRTHS[name]
		var widest: bool = spec[2] == &"widest"
		var best := -1.0
		for bone_name in spec[0]:
			var bone := skeleton.find_bone(bone_name)
			if not has_bone(bone):
				continue
			for slice: int in spec[1]:
				var at := (bone * SLICES + slice) * 4
				var width := (sections[at + 1] - sections[at]) * metres
				var depth := (sections[at + 3] - sections[at + 2]) * metres
				var girth := _ellipse_perimeter(width * 0.5, depth * 0.5)
				if best < 0.0 or (girth > best if widest else girth < best):
					best = girth
					summary[name] = girth
					if name in [&"chest", &"waist", &"hips"]:
						summary[StringName(String(name) + "_width")] = width
						summary[StringName(String(name) + "_depth")] = depth
	for name in SPANS:
		var a := skeleton.find_bone(SPANS[name][0])
		var b := skeleton.find_bone(SPANS[name][1])
		if a >= 0 and b >= 0:
			summary[name] = globals[a].origin.distance_to(globals[b].origin) * metres


## Ramanujan's approximation.
static func _ellipse_perimeter(a: float, b: float) -> float:
	return PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))
