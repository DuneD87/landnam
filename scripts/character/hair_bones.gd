class_name HairBones
extends RefCounted

## The bones loose hair hangs from: CHAINS chains round the head, each of
## JOINTS bones, children of the head, which a HairSwing swings. Unlike the
## skirt's (SkirtBones) they take each hair style's shape: chain c hangs in
## its sector of the head (c of CHAINS round it, from the front), and its
## joint j sits in the middle of the style's hair there, j steps (DROP) under
## the ring round the head at ear height (RING_RISE). Where the style has no
## hair the joint hangs straight down from the one above, so short styles
## keep a short, stiff chain they barely use.
##
## Hair above the ring stays with the head as it was skinned. Under it, a
## vertex is skinned to the two chains of its sector, at its depth under the
## ring: each joint's bone carries the hair one step around it, so it blends
## from the head into the chain and down it. Long hair is no longer skinned
## to the back and shoulders it lay on (the body's weights it was given),
## which carried it stiffly with them.
##
## Everything is at rest in the head bone's space, which the body's joint
## offsets (BodyProportions) do not change.

const PREFIX := "hair_"
const HEAD := &"mixamorig_Head"
const HEAD_TOP := &"mixamorig_HeadTop_End"
const HIPS := &"mixamorig_Hips"
const LEFT_SHOULDER := &"mixamorig_LeftShoulder"
const RIGHT_SHOULDER := &"mixamorig_RightShoulder"
const CHAINS := 10
const JOINTS := 5
## Sizes, as shares of the head's length (its bone to the top, about 26 cm):
## how high the ring is over the head bone, its reach to the sides, the front
## and the back, and how far apart the joints of a chain hang.
const RING_RISE := 0.3
const RING_SIDE := 0.3
const RING_FRONT := 0.34
const RING_BACK := 0.38
const DROP := 0.32
## Least hair (summed weights of vertices) a joint is placed by.
const MIN_HAIR := 20.0
## Least distance between two joints of a chain, in steps.
const MIN_STEP := 0.4
## Hair this far under the ring (in steps) hangs: a style with this little
## of it does not swing.
const HANGING := 0.75
const MIN_HANGING_VERTICES := 60


static func bone_name(chain: int, joint: int) -> StringName:
	return StringName("%s%d_%d" % [PREFIX, chain, joint])


## The ring in the head bone's space: {centre, up, left, forward, size}
## (size: the head's length), or empty without the bones it is placed by.
static func frame(skeleton: Skeleton3D) -> Dictionary:
	var head := skeleton.find_bone(HEAD)
	var top := skeleton.find_bone(HEAD_TOP)
	var hips := skeleton.find_bone(HIPS)
	var left_bone := skeleton.find_bone(LEFT_SHOULDER)
	var right_bone := skeleton.find_bone(RIGHT_SHOULDER)
	if head < 0 or top < 0 or hips < 0 or left_bone < 0 or right_bone < 0:
		return {}
	var globals := BodyMeasurements.rest_globals(skeleton)
	var to_head := globals[head].affine_inverse()
	var head_origin := globals[head].origin
	var top_origin := globals[top].origin
	var up := to_head.basis * (head_origin - globals[hips].origin).normalized()
	var left := to_head.basis * (globals[left_bone].origin - globals[right_bone].origin)
	up = up.normalized()
	left = (left - up * up.dot(left)).normalized()
	return {
		centre = to_head * head_origin.lerp(top_origin, RING_RISE),
		up = up, left = left, forward = left.cross(up),
		size = head_origin.distance_to(top_origin),
	}


## Where a point (head space) lies: [chain coordinate (0 to CHAINS round
## from the front), depth under the ring in steps].
static func place(point: Vector3, ring: Dictionary) -> Vector2:
	var d: Vector3 = point - ring.centre
	var angle := atan2(d.dot(ring.left), d.dot(ring.forward))
	return Vector2(fposmod(angle / TAU * CHAINS, CHAINS), -d.dot(ring.up) / (DROP * ring.size))


## The joints straight down from the ring (head space), chain by chain.
static func straight(ring: Dictionary) -> PackedVector3Array:
	var joints := PackedVector3Array()
	for chain in CHAINS:
		var angle := TAU * chain / CHAINS
		var depth := RING_FRONT if cos(angle) > 0.0 else RING_BACK
		var top: Vector3 = ring.centre + (ring.forward * cos(angle) * depth + ring.left * sin(angle) * RING_SIDE) * ring.size
		for joint in JOINTS:
			joints.append(top - ring.up * DROP * ring.size * joint)
	return joints


## The joints for a hair style whose points (head space) are `points`: each
## in the middle of the hair of its sector and depth, or straight down.
static func shaped(points: PackedVector3Array, ring: Dictionary) -> PackedVector3Array:
	var sums := PackedVector3Array()
	var weights := PackedFloat32Array()
	sums.resize(CHAINS * JOINTS)
	weights.resize(CHAINS * JOINTS)
	for p in points:
		var at := place(p, ring)
		var depth := at.y
		if depth < -1.0 or depth > JOINTS:
			continue
		var c0 := int(floor(at.x))
		var across := at.x - c0
		var j0 := int(floor(depth))
		var down := depth - j0
		for side in 2:
			var chain := (c0 + side) % CHAINS
			var wc := 1.0 - across if side == 0 else across
			for step in 2:
				var joint := j0 + step
				if joint < 0 or joint >= JOINTS:
					continue
				var w := wc * (1.0 - down if step == 0 else down)
				sums[chain * JOINTS + joint] += p * w
				weights[chain * JOINTS + joint] += w
	var joints := straight(ring)
	var step_length: float = DROP * ring.size
	for chain in CHAINS:
		for joint in JOINTS:
			var k := chain * JOINTS + joint
			if weights[k] >= MIN_HAIR:
				joints[k] = sums[k] / weights[k]
			elif joint > 0:
				joints[k] = joints[k - 1] - ring.up * step_length
			if joint > 0 and joints[k].distance_to(joints[k - 1]) < MIN_STEP * step_length:
				joints[k] = joints[k - 1] - ring.up * step_length
	return joints


## Adds the bones to `skeleton` unless it has them (straight chains);
## whether it added them.
static func add_to(skeleton: Skeleton3D) -> bool:
	if skeleton.find_bone(bone_name(0, 0)) >= 0:
		return false
	var ring := frame(skeleton)
	if ring.is_empty():
		return false
	var head := skeleton.find_bone(HEAD)
	for chain in CHAINS:
		for joint in JOINTS:
			var bone := skeleton.add_bone(bone_name(chain, joint))
			skeleton.set_bone_parent(bone, head if joint == 0 else skeleton.find_bone(bone_name(chain, joint - 1)))
	set_joints(skeleton, straight(ring), ring)
	return true


## Moves the bones' rests (and poses) onto `joints` (head space).
static func set_joints(skeleton: Skeleton3D, joints: PackedVector3Array, ring: Dictionary) -> void:
	for chain in CHAINS:
		var parent := Transform3D.IDENTITY
		for joint in JOINTS:
			var k := chain * JOINTS + joint
			# Like every bone, +Y towards the next joint, which is how
			# SpringBoneSimulator3D swings a chain; the last one carries on.
			var along: Vector3 = (joints[k + 1] - joints[k]) if joint < JOINTS - 1 else (joints[k] - joints[k - 1])
			var y := along.normalized()
			var x: Vector3 = ring.left - y * y.dot(ring.left)
			if x.length_squared() < 1e-6:
				x = ring.forward - y * y.dot(ring.forward)
			x = x.normalized()
			var global := Transform3D(Basis(x, y, x.cross(y)), joints[k])
			var local := parent.affine_inverse() * global
			var bone := skeleton.find_bone(bone_name(chain, joint))
			skeleton.set_bone_rest(bone, local)
			skeleton.set_bone_pose(bone, local)
			parent = global


## `base` with binds for the bones as they are now: at rest each moves its
## vertices exactly as the head does.
static func skin_for(base: Skin, skeleton: Skeleton3D) -> Skin:
	var skin: Skin = base.duplicate()
	var head_bind := Transform3D.IDENTITY
	for b in base.get_bind_count():
		if base.get_bind_name(b) == HEAD:
			head_bind = base.get_bind_pose(b)
	var globals := BodyMeasurements.rest_globals(skeleton)
	var to_head := globals[skeleton.find_bone(HEAD)].affine_inverse()
	for chain in CHAINS:
		for joint in JOINTS:
			var name := bone_name(chain, joint)
			var in_head := to_head * globals[skeleton.find_bone(name)]
			skin.add_named_bind(name, in_head.affine_inverse() * head_bind)
	return skin


## Skins the hanging hair to the chains: `points` are the vertices in head
## space, `bones` and `weights` their skin (4 per vertex, binds of `skin`,
## made by skin_for()), rewritten in place. Returns whether enough hangs
## for the style to swing.
static func weigh(points: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array,
		skin: Skin, ring: Dictionary) -> bool:
	var binds := {}
	for b in skin.get_bind_count():
		binds[skin.get_bind_name(b)] = b
	var head: int = binds[HEAD]
	var hanging := 0
	for v in points.size():
		var at := place(points[v], ring)
		if at.y <= 0.0:
			continue
		if at.y >= HANGING:
			hanging += 1
		var influence := {}
		var c0 := int(floor(at.x))
		var across := at.x - c0
		# Joint j's bone carries the hair from depth j to j + 2, most at j + 1.
		var depth := minf(at.y, JOINTS)
		var level := int(floor(depth))
		var down := depth - level
		for side in 2:
			var chain := (c0 + side) % CHAINS
			var wc := 1.0 - across if side == 0 else across
			for step in 2:
				var joint := level - 1 + step
				var w := wc * (1.0 - down if step == 0 else down)
				if joint >= JOINTS:
					joint = JOINTS - 1
				var bind: int = head if joint < 0 else binds[bone_name(chain, joint)]
				influence[bind] = influence.get(bind, 0.0) + w
		var k := 0
		for bind in influence:
			bones[v * 4 + k] = bind
			weights[v * 4 + k] = influence[bind]
			k += 1
		for rest in range(k, 4):
			bones[v * 4 + rest] = 0
			weights[v * 4 + rest] = 0.0
	return hanging >= MIN_HANGING_VERTICES
