class_name HairTuck
extends RefCounted

## Tucks hair (and beards) under what covers the head: hoods, helmets. Seen
## from the centre of the head, the pieces that cover it are a map of how far
## away, in every direction, their inner surface is (an octahedral map, with
## no poles). In the directions they cover, the hair is squeezed towards the
## head until it fits under them, keeping its layers: from its innermost
## point there to its outermost, everything is scaled into the room the
## piece leaves. Where they do not cover (the face opening, below the rim),
## the hair stays as it is, so a fringe or hair falling from under a hood
## still shows; the map fades at the edges so the hair eases out of them.
##
## Everything is at rest in skeleton space, like ArmorFit, and the result is
## written back in the hair's bind space. tuck() may run on any thread.

## Cells per side of the direction maps.
const MAP_SIZE := 48
## How far under the piece's inner surface the hair stays, in metres.
const MARGIN := 0.004
## Least thickness the hair keeps when squeezed, in metres.
const THIN := 0.003
## Cells the covered area grows by (closes the piece's small holes) and
## rounds the coverage fades over at its edges.
const GROW := 1
const FADE := 2

var body_globals: Array[Transform3D]
## Skeleton units per metre.
var units := 100.0
var _centre: Vector3
var _to_head: Basis
var _from_head: Basis
## Per cell: distance to the covering pieces' inner surface, and how much the
## direction is covered (0-1).
var _limit: PackedFloat32Array
var _coverage: PackedFloat32Array


## `cover` are the covering pieces' points at rest in skeleton space;
## `head_centre` and `head_basis` place the head in it.
func _init(cover: PackedVector3Array, head_centre: Vector3, head_basis: Basis, globals: Array[Transform3D],
		units_per_metre: float) -> void:
	body_globals = globals
	units = units_per_metre
	_centre = head_centre
	_from_head = head_basis.orthonormalized()
	_to_head = _from_head.inverse()
	var cells := MAP_SIZE * MAP_SIZE
	_limit.resize(cells)
	_limit.fill(INF)
	for p in cover:
		var d := _to_head * (p - _centre)
		var r := d.length()
		if r < 1e-6:
			continue
		var c := _cell(d / r)
		_limit[c] = minf(_limit[c], r)
	var covered := PackedByteArray()
	covered.resize(cells)
	for c in cells:
		covered[c] = 1 if _limit[c] < INF else 0
	for round in GROW:
		_grow(_limit, covered, true)
	_coverage.resize(cells)
	for c in cells:
		_coverage[c] = float(covered[c])
	for round in FADE:
		_coverage = _blur(_coverage)
	_spread(_limit, covered)


## Squeezes the hair mesh arrays (a proxy skinned with the body's Skin, whose
## bind poses are `skin_binds` and bones `bind_bones`) under the covering
## pieces, in place.
func tuck(arrays: Array, skin_binds: Array[Transform3D], bind_bones: PackedInt32Array) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count := vertices.size()
	var per := bones.size() / count
	var binds: Array[Transform3D] = []
	for b in skin_binds.size():
		binds.append(body_globals[bind_bones[b]] * skin_binds[b] if bind_bones[b] >= 0 else Transform3D.IDENTITY)
	var zero := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
	var poses: Array[Transform3D] = []
	poses.resize(count)
	var directions := PackedVector3Array()
	directions.resize(count)
	var radii := PackedFloat32Array()
	radii.resize(count)
	# Where the hair is, and its innermost and outermost point per direction.
	var cells := MAP_SIZE * MAP_SIZE
	var inner := PackedFloat32Array()
	inner.resize(cells)
	inner.fill(INF)
	var outer := PackedFloat32Array()
	outer.resize(cells)
	outer.fill(-INF)
	for i in count:
		var pose := zero
		for k in range(i * per, i * per + per):
			var w := weights[k]
			if w > 0.0:
				var t: Transform3D = binds[bones[k]]
				pose = Transform3D(pose.basis.x + t.basis.x * w, pose.basis.y + t.basis.y * w,
						pose.basis.z + t.basis.z * w, pose.origin + t.origin * w)
		poses[i] = pose
		var d := _to_head * (pose * vertices[i] - _centre)
		var r := d.length()
		radii[i] = r
		if r < 1e-6:
			continue
		directions[i] = d / r
		var c := _cell(d / r)
		inner[c] = minf(inner[c], r)
		outer[c] = maxf(outer[c], r)
	var has_hair := PackedByteArray()
	has_hair.resize(cells)
	for c in cells:
		has_hair[c] = 1 if inner[c] < INF else 0
	var has_outer := has_hair.duplicate()
	_spread(inner, has_hair)
	_spread(outer, has_outer)

	var margin := MARGIN * units
	var thin := THIN * units
	for i in count:
		var r := radii[i]
		if r < 1e-6:
			continue
		var uv := _uv(directions[i])
		var cover := _sample(_coverage, uv)
		if cover <= 1e-3:
			continue
		var limit := _sample(_limit, uv) - margin
		var r_in := _sample(inner, uv)
		var r_out := maxf(_sample(outer, uv), r)
		if r_out <= limit:
			continue
		var squeezed := r
		if limit - r_in > thin:
			if r > r_in:
				squeezed = r_in + (r - r_in) * (limit - r_in) / (r_out - r_in)
		else:
			# No room between the head and the piece: all of it under the piece.
			squeezed = minf(r, maxf(limit, thin))
		squeezed = minf(squeezed, r)
		var tucked := lerpf(r, squeezed, cover)
		var p := _centre + _from_head * (directions[i] * tucked)
		vertices[i] = poses[i].affine_inverse() * p
	arrays[Mesh.ARRAY_VERTEX] = vertices


## How much the pieces cover the direction of `p` (skeleton space), 0-1.
func coverage_at(p: Vector3) -> float:
	var d := _to_head * (p - _centre)
	return _sample(_coverage, _uv(d.normalized())) if d.length() > 1e-6 else 0.0


## How far beyond the pieces' inner surface `p` is, in skeleton units
## (negative under it).
func beyond(p: Vector3) -> float:
	var d := _to_head * (p - _centre)
	if d.length() < 1e-6:
		return -INF
	return d.length() - _sample(_limit, _uv(d.normalized()))


## Octahedral map of a unit direction in the head's frame (Y up), in cells.
static func _uv(d: Vector3) -> Vector2:
	# The upper hemisphere (the skull, what pieces cover most) is the
	# continuous centre of the map.
	var n := Vector3(d.x, d.z, d.y) / (absf(d.x) + absf(d.y) + absf(d.z))
	var o := Vector2(n.x, n.y)
	if n.z < 0.0:
		o = Vector2((1.0 - absf(n.y)) * signf(n.x), (1.0 - absf(n.x)) * signf(n.y))
	return (o * 0.5 + Vector2(0.5, 0.5)) * MAP_SIZE


static func _cell(d: Vector3) -> int:
	var uv := _uv(d)
	var x := clampi(int(uv.x), 0, MAP_SIZE - 1)
	var y := clampi(int(uv.y), 0, MAP_SIZE - 1)
	return y * MAP_SIZE + x


## Bilinear, between cell centres, clamped at the edges.
static func _sample(map: PackedFloat32Array, uv: Vector2) -> float:
	var f := (uv - Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2(MAP_SIZE - 1, MAP_SIZE - 1))
	var x := int(f.x)
	var y := int(f.y)
	var x1 := mini(x + 1, MAP_SIZE - 1)
	var y1 := mini(y + 1, MAP_SIZE - 1)
	var fx := f.x - x
	var fy := f.y - y
	var top := lerpf(map[y * MAP_SIZE + x], map[y * MAP_SIZE + x1], fx)
	var bottom := lerpf(map[y1 * MAP_SIZE + x], map[y1 * MAP_SIZE + x1], fx)
	return lerpf(top, bottom, fy)


## Grows the cells that have a value by one, taking the least (`least`) or
## the greatest of their neighbours.
static func _grow(map: PackedFloat32Array, known: PackedByteArray, least: bool) -> void:
	var next := map.duplicate()
	var next_known := known.duplicate()
	for y in MAP_SIZE:
		for x in MAP_SIZE:
			var c := y * MAP_SIZE + x
			if known[c]:
				continue
			var found := false
			var value := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= MAP_SIZE or ny >= MAP_SIZE or not known[ny * MAP_SIZE + nx]:
						continue
					var v := map[ny * MAP_SIZE + nx]
					if not found or (v < value if least else v > value):
						value = v
					found = true
			if found:
				next[c] = value
				next_known[c] = 1
	for c in map.size():
		map[c] = next[c]
		known[c] = next_known[c]


## Fills the cells without a value from their neighbours, outwards, so the
## map can be sampled anywhere.
static func _spread(map: PackedFloat32Array, known: PackedByteArray) -> void:
	var any := false
	for k in known:
		if k:
			any = true
			break
	if not any:
		map.fill(0.0)
		return
	var complete := false
	while not complete:
		var next := map.duplicate()
		var next_known := known.duplicate()
		complete = true
		for y in MAP_SIZE:
			for x in MAP_SIZE:
				var c := y * MAP_SIZE + x
				if known[c]:
					continue
				var sum := 0.0
				var n := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and ny >= 0 and nx < MAP_SIZE and ny < MAP_SIZE and known[ny * MAP_SIZE + nx]:
							sum += map[ny * MAP_SIZE + nx]
							n += 1
				if n > 0:
					next[c] = sum / n
					next_known[c] = 1
				else:
					complete = false
		for c in map.size():
			map[c] = next[c]
			known[c] = next_known[c]


static func _blur(map: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(map.size())
	for y in MAP_SIZE:
		for x in MAP_SIZE:
			var sum := 0.0
			var n := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < MAP_SIZE and ny < MAP_SIZE:
						sum += map[ny * MAP_SIZE + nx]
						n += 1
			result[y * MAP_SIZE + x] = sum / n
	return result
