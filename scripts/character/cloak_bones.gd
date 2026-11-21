class_name CloakBones
extends RefCounted

## The bones a cloak hangs from: CHAINS chains in an open ring at the height
## of the shoulders, from beside the chest on one side round the back to the
## other (a cloak is open in front), each of JOINTS bones hanging plumb from
## there, children of the upper spine, which CharacterAppearanceRig swings
## with a CloakSwing while a piece that uses them is worn. Like the skirt's
## (SkirtBones) they are added to the skeleton then (add_to()) and their rest
## comes from the skeleton's own (the neck, the shoulders), so the armour fit
## (tools/character/dump_skeleton.gd hands it to fit_meshy_armor.py) and the
## game put them in the same place.

const PREFIX := "cloak_"
const SPINE := &"mixamorig_Spine2"
const NECK := &"mixamorig_Neck"
const LEFT_ARM := &"mixamorig_LeftArm"
const RIGHT_ARM := &"mixamorig_RightArm"
const CHAINS := 7
const JOINTS := 8
## Where each chain starts round the ring, degrees from straight behind
## (positive: the character's left); the ends are beside the chest, in
## front of the shoulders.
const ANGLES: Array[float] = [-100.0, -66.0, -33.0, 0.0, 33.0, 66.0, 100.0]
## Sizes, as shares of the gap between the shoulder joints (about 38 cm):
## how far below the neck joint the ring is, how far it reaches to the
## sides, behind and in front, and how far apart the joints of a chain hang.
const RING_DROP := 0.12
const RING_SIDE := 0.74
const RING_BACK := 0.42
const RING_FRONT := 0.2
const DROP := 0.354
## A cloak is made for the arms hanging this many degrees out from straight
## down (as they do standing), not spread as at rest: its Skin binds the
## upper arms there (arm_hang()), so standing it is as made, and what of it
## follows an arm moves from there with it.
const ARM_HANG := 14.0
const ARMS: Array[StringName] = [&"mixamorig_LeftArm", &"mixamorig_RightArm"]
const FOREARMS: Array[StringName] = [&"mixamorig_LeftForeArm", &"mixamorig_RightForeArm"]


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
## chain by chain from the ring down; empty without the spine, the neck and
## the shoulders.
static func rests(skeleton: Skeleton3D) -> Dictionary:
	var spine_bone := skeleton.find_bone(SPINE)
	var neck_bone := skeleton.find_bone(NECK)
	var left_bone := skeleton.find_bone(LEFT_ARM)
	var right_bone := skeleton.find_bone(RIGHT_ARM)
	if spine_bone < 0 or neck_bone < 0 or left_bone < 0 or right_bone < 0:
		return {}
	var globals := BodyMeasurements.rest_globals(skeleton)
	var left_joint := globals[left_bone].origin
	var right_joint := globals[right_bone].origin
	var gap := left_joint.distance_to(right_joint)
	var left := (left_joint - right_joint).normalized()
	var up := globals[neck_bone].origin - globals[spine_bone].origin
	up = (up - left * left.dot(up)).normalized()
	var forward := left.cross(up)
	var centre := globals[neck_bone].origin - up * RING_DROP * gap
	# Like every bone, +Y towards the next joint (down), which is how
	# SpringBoneSimulator3D swings a chain.
	var basis := Basis(left, -up, -forward).scaled(globals[spine_bone].basis.get_scale())
	var result := {}
	for chain in CHAINS:
		var angle := deg_to_rad(ANGLES[chain])
		var depth := RING_BACK if cos(angle) > 0.0 else RING_FRONT
		var top := centre + (-forward * cos(angle) * depth + left * sin(angle) * RING_SIDE) * gap
		for joint in JOINTS:
			var parent := SPINE if joint == 0 else bone_name(chain, joint - 1)
			result[bone_name(chain, joint)] = [parent, Transform3D(basis, top - up * DROP * gap * joint)]
	return result


## Adds the bones to `skeleton` unless it has them; whether it added them.
static func add_to(skeleton: Skeleton3D) -> bool:
	if skeleton.find_bone(bone_name(0, 0)) >= 0:
		return false
	var bones := rests(skeleton)
	if bones.is_empty():
		return false
	var spine_global := BodyMeasurements.rest_globals(skeleton)[skeleton.find_bone(SPINE)]
	for name: StringName in bones:
		var parent: StringName = bones[name][0]
		var parent_global: Transform3D = spine_global if parent == SPINE else bones[parent][1]
		var local: Transform3D = parent_global.affine_inverse() * bones[name][1]
		var bone := skeleton.add_bone(name)
		skeleton.set_bone_parent(bone, skeleton.find_bone(parent))
		skeleton.set_bone_rest(bone, local)
		skeleton.set_bone_pose(bone, local)
	return true


## What takes a point made with the upper arm `arm` (ARMS) hanging (ARM_HANG)
## to where it is with the arm at rest, in the space of `skin` (the player's:
## Y up, +X to the character's left): about the shoulder joint, the shortest
## turn from hanging to the rest direction. A cloak's Skin binds that arm as
## its own bind after this.
static func arm_hang(skin: Skin, arm: int) -> Transform3D:
	var joint := Vector3.ZERO
	var elbow := Vector3.ZERO
	for b in skin.get_bind_count():
		if skin.get_bind_name(b) == ARMS[arm]:
			joint = skin.get_bind_pose(b).affine_inverse().origin
		elif skin.get_bind_name(b) == FOREARMS[arm]:
			elbow = skin.get_bind_pose(b).affine_inverse().origin
	var side := 1.0 if arm == 0 else -1.0
	var hang := Vector3(side * sin(deg_to_rad(ARM_HANG)), -cos(deg_to_rad(ARM_HANG)), 0.0)
	var to_rest := Basis(Quaternion(hang, (elbow - joint).normalized()))
	return Transform3D(to_rest, joint - to_rest * joint)
