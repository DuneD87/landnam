class_name PeltBones
extends RefCounted

## The bones a pelt's forelegs hang from (the wolf's pelt worn with its
## head, tools/character/blender/build_fur_armor.py): a chain of JOINTS
## bones on each side, from the wolf's shoulder on the pelt over the
## character's, down the pelt to the chest and plumb from there (AT),
## children of the upper spine, which CharacterAppearanceRig swings with a PeltSwing while a piece
## that uses them is worn. Like the skirt's (SkirtBones) they are added to
## the skeleton then (add_to()) and their rest comes from the skeleton's own
## (the neck, the shoulders), so the armour fit
## (tools/character/dump_skeleton.gd hands it to build_fur_armor.py) and the
## game put them in the same place.

const PREFIX := "pelt_"
const SPINE := &"mixamorig_Spine2"
const NECK := &"mixamorig_Neck"
const LEFT_ARM := &"mixamorig_LeftArm"
const RIGHT_ARM := &"mixamorig_RightArm"
## A chain on each side: the character's left, then its right.
const CHAINS := 2
## Where the joints of the left chain are (the right's mirror them), from
## the neck joint, as shares of the gap between the shoulder joints (about
## 38 cm): to the side, to the front and up. On the pelt as it falls from
## the head on the scan (build_fur_armor.py's drape()), where it puts the
## wolf's shoulder, a foreleg's thickness over it, down to the chest; then
## plumb.
const AT: Array[Vector3] = [Vector3(0.433, 0.342, 0.199), Vector3(0.451, 0.397, -0.04),
		Vector3(0.457, 0.45, -0.279), Vector3(0.457, 0.475, -0.517), Vector3(0.457, 0.475, -0.755)]
const JOINTS := 5


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
## chain by chain from the top down; empty without the spine, the neck and
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
	var scale := globals[spine_bone].basis.get_scale()
	var result := {}
	for chain in CHAINS:
		var side := 1.0 if chain == 0 else -1.0
		var joints: Array[Vector3] = []
		for at in AT:
			joints.append(globals[neck_bone].origin + (left * side * at.x + forward * at.y + up * at.z) * gap)
		for joint in JOINTS:
			var parent := SPINE if joint == 0 else bone_name(chain, joint - 1)
			# Like every bone, +Y towards the next joint, which is how
			# SpringBoneSimulator3D swings a chain (the last, as the one before).
			var next := joint + 1 if joint < JOINTS - 1 else joint
			var along := (joints[next] - joints[next - 1]).normalized()
			var across := left.cross(along).normalized()
			var basis := Basis(along.cross(across), along, across).orthonormalized().scaled(scale)
			result[bone_name(chain, joint)] = [parent, Transform3D(basis, joints[joint])]
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
