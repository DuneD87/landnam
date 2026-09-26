class_name ArmorFit
extends RefCounted

## Carries skinned armour made for one body onto another, by their
## BodyMeasurements, in two steps:
##
## 1. Measurements. Every vertex is placed where it was at rest on the
##    `reference` body; then, for each bone it is skinned to, it goes into
##    that bone's frame, where each coordinate is mapped from the reference's
##    slice extents to the body's: along the bone from one region to the
##    other, and across it scaled from one slice to the other. What sticks out
##    beyond the reference's extents keeps its distance, so the armour keeps
##    its thickness and its clearance over the body. The influences blend as
##    in skinning.
## 2. Clearance. Whatever still ends up inside the body (a shape the slices
##    do not tell apart) is pushed out along the skin's normal to CLEARANCE,
##    and the push spreads smoothly to whatever armour is around it.
##
## The result is written back in the armour's own bind space, so its Skin and
## weights stay as they were. The skeleton must be the one both bodies were
## measured on.
##
## fit() does the work on plain arrays and may run on any thread: read the
## armour with source() and build the mesh with build() on the main thread.

## Limits of the width and depth scale, so a thin region on either body
## does not blow the armour up or crush it.
const SCALE_RANGE := Vector2(0.55, 2.2)
## Least distance from the skin, in metres.
const CLEARANCE := 0.004
## How deep inside the body a vertex is still found, in metres.
const REACH := 0.03
## How far the clearance push spreads, in metres.
const SPREAD := 0.03
## Size of the cells the points that need a push are gathered in, in metres.
const GATHER := 0.01
const CLEARANCE_PASSES := 2

var reference: BodyMeasurements
var reference_globals: Array[Transform3D]
var body: BodyMeasurements
var body_globals: Array[Transform3D]
var surface: Grid
## Skeleton units per metre.
var units := 100.0


## Points bucketed in a grid of `cell`-sized cells, for the clearance: the
## body's skin (with its normals) and the armour points that need a push.
class Grid:
	var positions: PackedVector3Array
	var normals: PackedVector3Array
	var origin: Vector3
	var cell := 1.0
	var size: Vector3i
	## Points of cell c: items[starts[c] .. starts[c + 1]].
	var starts: PackedInt32Array
	var items: PackedInt32Array

	func _init(points: PackedVector3Array, point_normals: PackedVector3Array, cell_size: float) -> void:
		positions = points
		normals = point_normals
		cell = cell_size
		var bounds := AABB(points[0], Vector3.ZERO)
		for p in points:
			bounds = bounds.expand(p)
		origin = bounds.position - Vector3.ONE * cell
		size = Vector3i((bounds.size / cell).floor()) + Vector3i(3, 3, 3)
		var count := size.x * size.y * size.z
		var cells := PackedInt32Array()
		cells.resize(points.size())
		starts.resize(count + 1)
		for i in points.size():
			var q := Vector3i(((points[i] - origin) / cell).floor()).clamp(Vector3i.ZERO, size - Vector3i.ONE)
			var c := (q.z * size.y + q.y) * size.x + q.x
			cells[i] = c
			starts[c + 1] += 1
		for c in count:
			starts[c + 1] += starts[c]
		items.resize(points.size())
		var fill := starts.duplicate()
		for i in points.size():
			items[fill[cells[i]]] = i
			fill[cells[i]] += 1

	## The nearest point within a cell of `p` (the 2x2x2 cells around it), or -1.
	func nearest(p: Vector3) -> int:
		var g := (p - origin) / cell - Vector3(0.5, 0.5, 0.5)
		var base := Vector3i(g.floor())
		var best := -1
		var best_distance := INF
		for dz in 2:
			var z := base.z + dz
			if z < 0 or z >= size.z:
				continue
			for dy in 2:
				var y := base.y + dy
				if y < 0 or y >= size.y:
					continue
				var row := (z * size.y + y) * size.x
				for dx in 2:
					var x := base.x + dx
					if x < 0 or x >= size.x:
						continue
					var c := row + x
					for k in range(starts[c], starts[c + 1]):
						var i := items[k]
						var d := positions[i].distance_squared_to(p)
						if d < best_distance:
							best_distance = d
							best = i
		return best


## The armour mesh's surfaces as fit() and build() take them. Main thread.
static func source(mesh: ArrayMesh) -> Array[Dictionary]:
	var surfaces: Array[Dictionary] = []
	for s in mesh.get_surface_count():
		surfaces.append({
			arrays = mesh.surface_get_arrays(s),
			lods = _lods(mesh, s),
			primitive = mesh.surface_get_primitive_type(s),
			flags = mesh.surface_get_format(s) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES),
			material = mesh.surface_get_material(s),
			name = mesh.surface_get_name(s),
		})
	return surfaces


## The fitted mesh from fit()'s surfaces. Main thread.
static func build(surfaces: Array[Dictionary], name: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in surfaces.size():
		var data: Dictionary = surfaces[s]
		mesh.add_surface_from_arrays(data.primitive, data.arrays, [], data.lods, data.flags)
		mesh.surface_set_material(s, data.material)
		mesh.surface_set_name(s, data.name)
	mesh.resource_name = name
	return mesh


## The body's skin as a Grid, from its meshes ([ArrayMesh, Skin] each)
## at rest with `globals`.
static func body_surface(meshes: Array, skeleton: Skeleton3D, globals: Array[Transform3D],
		units_per_metre: float) -> Grid:
	var points := PackedVector3Array()
	var point_normals := PackedVector3Array()
	for entry in meshes:
		var mesh: ArrayMesh = entry[0]
		var binds := BodyMeasurements.bind_transforms(entry[1], skeleton, globals)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / vertices.size()
			for i in vertices.size():
				var p := Vector3.ZERO
				var n := Vector3.ZERO
				for k in range(i * per, i * per + per):
					var w := weights[k]
					if w > 0.0:
						var t: Transform3D = binds[bones[k]]
						p += t * vertices[i] * w
						n += t.basis * normals[i] * w
				points.append(p)
				point_normals.append(n.normalized())
	return Grid.new(points, point_normals, REACH * units_per_metre)


## Fits the surfaces of source() of a mesh skinned with `skin`, in place,
## and adds each one's points at rest on the body (skeleton space) as `points`.
## `bind_bones` is the skeleton bone of each bind (BodyMeasurements.bind_bones()).
func fit(surfaces: Array[Dictionary], skin_binds: Array[Transform3D], bind_bones: PackedInt32Array) -> void:
	var reference_binds: Array[Transform3D] = []
	var body_binds: Array[Transform3D] = []
	for b in skin_binds.size():
		var bone := bind_bones[b]
		reference_binds.append(reference_globals[bone] * skin_binds[b] if bone >= 0 else Transform3D.IDENTITY)
		body_binds.append(body_globals[bone] * skin_binds[b] if bone >= 0 else Transform3D.IDENTITY)
	var to_bones: Array[Transform3D] = []
	for g in reference_globals:
		to_bones.append(g.affine_inverse())
	var measured := PackedByteArray()
	measured.resize(reference_globals.size())
	for bone in measured.size():
		measured[bone] = 1 if reference.has_bone(bone) and body.has_bone(bone) else 0
	for data in surfaces:
		data.points = _fit_surface(data.arrays, reference_binds, body_binds, bind_bones, to_bones, measured)


## Fits one surface's arrays in place; returns its points at rest on the
## body, in skeleton space.
func _fit_surface(arrays: Array, reference_binds: Array[Transform3D], body_binds: Array[Transform3D],
		bind_bones: PackedInt32Array, to_bones: Array[Transform3D], measured: PackedByteArray) -> PackedVector3Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count := vertices.size()
	var per := bones.size() / count
	var has_tangents := tangents.size() == count * 4
	var slices := BodyMeasurements.SLICES
	var from_spans := reference.spans
	var to_spans := body.spans
	var from_sections := reference.sections
	var to_sections := body.sections
	var zero := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
	var targets := PackedVector3Array()
	targets.resize(count)
	var target_normals := PackedVector3Array()
	target_normals.resize(count)
	var target_tangents := PackedVector3Array()
	target_tangents.resize(count)
	var poses: Array[Transform3D] = []
	poses.resize(count)

	for i in count:
		var j := i * per
		var reference_pose := zero
		var body_pose := zero
		for k in range(j, j + per):
			var w := weights[k]
			if w > 0.0:
				var a: Transform3D = reference_binds[bones[k]]
				var b: Transform3D = body_binds[bones[k]]
				reference_pose = Transform3D(reference_pose.basis.x + a.basis.x * w, reference_pose.basis.y + a.basis.y * w,
						reference_pose.basis.z + a.basis.z * w, reference_pose.origin + a.origin * w)
				body_pose = Transform3D(body_pose.basis.x + b.basis.x * w, body_pose.basis.y + b.basis.y * w,
						body_pose.basis.z + b.basis.z * w, body_pose.origin + b.origin * w)
		poses[i] = body_pose
		var p := reference_pose * vertices[i]
		var n := (reference_pose.basis * normals[i]).normalized()
		var t := Vector3.ZERO
		if has_tangents:
			t = reference_pose.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		var target := Vector3.ZERO
		var target_normal := Vector3.ZERO
		var target_tangent := Vector3.ZERO
		for k in range(j, j + per):
			var w := weights[k]
			if w <= 0.0:
				continue
			var bone := bind_bones[bones[k]]
			if bone < 0:
				target += p * w
				target_normal += n * w
				target_tangent += t * w
				continue
			var to_bone: Transform3D = to_bones[bone]
			var l := to_bone * p
			var scale := Vector3.ONE
			if measured[bone]:
				var from: Vector2 = from_spans[bone]
				var to: Vector2 = to_spans[bone]
				var along := (l.y - from.x) / (from.y - from.x)
				# Slice extents at this point along the bone, both bodies.
				var f := clampf(along * slices - 0.5, 0.0, slices - 1.0)
				var sa := int(f)
				var blend := f - sa
				var ia := (bone * slices + sa) * 4
				var ib := (bone * slices + mini(sa + 1, slices - 1)) * 4
				var ax0 := lerpf(from_sections[ia], from_sections[ib], blend)
				var ax1 := lerpf(from_sections[ia + 1], from_sections[ib + 1], blend)
				var az0 := lerpf(from_sections[ia + 2], from_sections[ib + 2], blend)
				var az1 := lerpf(from_sections[ia + 3], from_sections[ib + 3], blend)
				var bx0 := lerpf(to_sections[ia], to_sections[ib], blend)
				var bx1 := lerpf(to_sections[ia + 1], to_sections[ib + 1], blend)
				var bz0 := lerpf(to_sections[ia + 2], to_sections[ib + 2], blend)
				var bz1 := lerpf(to_sections[ia + 3], to_sections[ib + 3], blend)
				scale.y = (to.y - to.x) / (from.y - from.x)
				l.y = to.x + (l.y - from.x) * scale.y
				# Across: scaled inside the reference's extents, kept beyond them.
				var half := (ax1 - ax0) * 0.5
				var s := clampf((bx1 - bx0) / maxf(ax1 - ax0, 1e-4), SCALE_RANGE.x, SCALE_RANGE.y)
				var u := l.x - (ax0 + ax1) * 0.5
				var c := (bx0 + bx1) * 0.5
				if u > half:
					l.x = c + half * s + u - half
				elif u < -half:
					l.x = c - half * s + u + half
				else:
					l.x = c + u * s
					scale.x = s
				half = (az1 - az0) * 0.5
				s = clampf((bz1 - bz0) / maxf(az1 - az0, 1e-4), SCALE_RANGE.x, SCALE_RANGE.y)
				u = l.z - (az0 + az1) * 0.5
				c = (bz0 + bz1) * 0.5
				if u > half:
					l.z = c + half * s + u - half
				elif u < -half:
					l.z = c - half * s + u + half
				else:
					l.z = c + u * s
					scale.z = s
			var out: Transform3D = body_globals[bone]
			target += out * l * w
			target_normal += out.basis * ((to_bone.basis * n) / scale) * w
			target_tangent += out.basis * ((to_bone.basis * t) * scale) * w
		targets[i] = target
		target_normals[i] = target_normal
		target_tangents[i] = target_tangent

	if surface != null:
		# A push can land a point on another part of the body (between the
		# thighs); a second pass sees where it ended up.
		for clearance_pass in CLEARANCE_PASSES:
			_clear_body(targets)

	# Back into the armour's bind space, through the body's skinning.
	for i in count:
		var inverse := poses[i].affine_inverse()
		vertices[i] = inverse * targets[i]
		normals[i] = (inverse.basis * target_normals[i]).normalized()
		if has_tangents:
			var tangent := (inverse.basis * target_tangents[i]).normalized()
			tangents[i * 4] = tangent.x
			tangents[i * 4 + 1] = tangent.y
			tangents[i * 4 + 2] = tangent.z
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if has_tangents:
		arrays[Mesh.ARRAY_TANGENT] = tangents
	return targets


## Pushes the points that are inside the body, or closer to it than
## CLEARANCE, out along the skin's normal. The push is a smooth field in
## space, not along the mesh: every point takes the pushes needed within
## SPREAD of it, fading with distance. Armour is often loose pieces and
## layers that touch or overlap; they all move together, so no seam opens
## and no layer goes through another.
func _clear_body(points: PackedVector3Array) -> void:
	var clearance := CLEARANCE * units
	var count := points.size()
	var needed := PackedVector3Array()
	var needed_at := PackedVector3Array()
	for i in count:
		var nearest := surface.nearest(points[i])
		if nearest < 0:
			continue
		var normal := surface.normals[nearest]
		var depth := clearance - (points[i] - surface.positions[nearest]).dot(normal)
		if depth > 0.0:
			needed.append(normal * depth)
			needed_at.append(points[i])
	if needed.is_empty():
		return
	# One source per GATHER cell, the one that needs the most. The push is
	# full up to half a cell's diagonal away, so none gets less than it needs.
	var gather := GATHER * units
	var slack := gather * sqrt(3.0) * 0.5
	var by_cell := {}
	for n in needed.size():
		var key := Vector3i((needed_at[n] / gather).floor())
		var kept: int = by_cell.get_or_add(key, n)
		if needed[n].length_squared() > needed[kept].length_squared():
			by_cell[key] = n
	var pushes := PackedVector3Array()
	var sources_at := PackedVector3Array()
	for n in by_cell.values():
		pushes.append(needed[n])
		sources_at.append(needed_at[n])
	var radius := SPREAD * units
	var sources := Grid.new(sources_at, PackedVector3Array(), radius)
	var reach := Vector3.ONE * radius
	var last := sources.size - Vector3i.ONE
	var shifted := PackedVector3Array()
	shifted.resize(count)
	for i in count:
		var p := points[i]
		var low := Vector3i(((p - sources.origin - reach) / radius).floor()).clamp(Vector3i.ZERO, last)
		var high := Vector3i(((p - sources.origin + reach) / radius).floor()).clamp(Vector3i.ZERO, last)
		var direction := Vector3.ZERO
		var amount := 0.0
		for z in range(low.z, high.z + 1):
			for y in range(low.y, high.y + 1):
				var row := (z * sources.size.y + y) * sources.size.x
				for x in range(low.x, high.x + 1):
					var c := row + x
					for k in range(sources.starts[c], sources.starts[c + 1]):
						var source := sources.items[k]
						var d := maxf(sources_at[source].distance_to(p) - slack, 0.0) / (radius - slack)
						if d >= 1.0:
							continue
						var fade := (1.0 - d * d) * (1.0 - d * d)
						direction += pushes[source] * fade
						amount = maxf(amount, pushes[source].length() * fade)
		shifted[i] = p + direction.normalized() * amount if amount > 0.0 else p
	for i in count:
		points[i] = shifted[i]


## The source surface's LODs, as add_surface_from_arrays takes them.
static func _lods(mesh: ArrayMesh, surface_index: int) -> Dictionary:
	var data := RenderingServer.mesh_get_surface(mesh.get_rid(), surface_index)
	var result := {}
	var index_count: int = data.get("index_count", 0)
	if index_count == 0:
		return result
	var width: int = data.index_data.size() / index_count
	for lod in data.get("lods", []):
		var bytes: PackedByteArray = lod.index_data
		var indices := PackedInt32Array()
		if width == 4:
			indices = bytes.to_int32_array()
		else:
			indices.resize(bytes.size() / 2)
			for k in indices.size():
				indices[k] = bytes.decode_u16(k * 2)
		result[lod.edge_length] = indices
	return result
