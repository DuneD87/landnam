class_name SkirtBones
extends RefCounted

## The bones a hanging skirt is skinned to: CHAINS chains round the hips,
## each of JOINTS bones hanging straight down from a ring over the hip joints,
## which CharacterAppearanceRig swings with a SpringBoneSimulator3D while a
## piece that uses them is worn. They are added to the skeleton then
## (add_to()); their rest comes from the skeleton's own (the hips, the
## thighs), so the armour fit (tools/character/dump_skeleton.gd hands it to
## fit_meshy_armor.py) and the game put them in the same place.

const PREFIX := "skirt_"
const HIPS := &"mixamorig_Hips"
const LEFT_THIGH := &"mixamorig_LeftUpLeg"
const RIGHT_THIGH := &"mixamorig_RightUpLeg"
const SPINE := &"mixamorig_Spine"
const CHAINS := 8
const JOINTS := 4
## Sizes, as shares of the gap between the hip joints (about 20 cm): how high
## the ring is over them, how far it reaches to the sides, to the front and
## to the back, and how far apart the joints of a chain hang.
const RING_RISE := 0.1
const RING_SIDE := 1.0
const RING_FRONT := 0.75
const RING_BACK := 0.85
const DROP := 0.75


static func bone_name(chain: int, joint: int) -> StringName:
	return StringName("%s%d_%d" % [PREFIX, chain, joint])


## Whether `skin` has binds for these bones.
static func uses(skin: Skin) -> bool:
	if skin == null:
		return false
	for b in skin.get_bind_count():
		if String(skin.get_bind_name(b)).begins_with(PREFIX):
			return true
	return false


## The bones' rests in skeleton space: name -> [parent name, global rest],
## chain by chain from the ring down; empty without hips and thighs.
static func rests(skeleton: Skeleton3D) -> Dictionary:
	var hips_bone := skeleton.find_bone(HIPS)
	var left_bone := skeleton.find_bone(LEFT_THIGH)
	var right_bone := skeleton.find_bone(RIGHT_THIGH)
	var spine_bone := skeleton.find_bone(SPINE)
	if hips_bone < 0 or left_bone < 0 or right_bone < 0 or spine_bone < 0:
		return {}
	var globals := BodyMeasurements.rest_globals(skeleton)
	var left_joint := globals[left_bone].origin
	var right_joint := globals[right_bone].origin
	var gap := left_joint.distance_to(right_joint)
	var left := (left_joint - right_joint).normalized()
	var up := globals[spine_bone].origin - globals[hips_bone].origin
	up = (up - left * left.dot(up)).normalized()
	var forward := left.cross(up)
	var centre := (left_joint + right_joint) * 0.5 + up * RING_RISE * gap
	# Like every bone, +Y towards the next joint (down), which is how
	# SpringBoneSimulator3D swings a chain.
	var basis := Basis(left, -up, -forward).scaled(globals[hips_bone].basis.get_scale())
	var result := {}
	for chain in CHAINS:
		var angle := TAU * chain / CHAINS
		var depth := RING_FRONT if cos(angle) > 0.0 else RING_BACK
		var top := centre + (forward * cos(angle) * depth + left * sin(angle) * RING_SIDE) * gap
		for joint in JOINTS:
			var parent := HIPS if joint == 0 else bone_name(chain, joint - 1)
			result[bone_name(chain, joint)] = [parent, Transform3D(basis, top - up * DROP * gap * joint)]
	return result


## Adds the bones to `skeleton` unless it has them; whether it added them.
static func add_to(skeleton: Skeleton3D) -> bool:
	if skeleton.find_bone(bone_name(0, 0)) >= 0:
		return false
	var bones := rests(skeleton)
	if bones.is_empty():
		return false
	var hips_global := BodyMeasurements.rest_globals(skeleton)[skeleton.find_bone(HIPS)]
	for name: StringName in bones:
		var parent: StringName = bones[name][0]
		var parent_global: Transform3D = hips_global if parent == HIPS else bones[parent][1]
		var local: Transform3D = parent_global.affine_inverse() * bones[name][1]
		var bone := skeleton.add_bone(name)
		skeleton.set_bone_parent(bone, skeleton.find_bone(parent))
		skeleton.set_bone_rest(bone, local)
		skeleton.set_bone_pose(bone, local)
	return true
