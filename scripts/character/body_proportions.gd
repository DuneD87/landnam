class_name BodyProportions
extends SkeletonModifier3D

## Proportions that belong to the skeleton rather than the skin, laid over
## the animated pose every frame (modifier changes do not persist, so nothing
## accumulates). Place it before IK modifiers so they see the result.
##  - bone_offsets move each joint to where the current body has it (see
##    HumanRigData): the animations key the player skeleton's bone positions,
##    and each body adds its difference on top.
##  - head_scale and shoulder_width are the creator's sliders.

const HEAD := "mixamorig_Head"
const SHOULDERS := ["mixamorig_LeftShoulder", "mixamorig_RightShoulder"]
const ARMS := ["mixamorig_LeftArm", "mixamorig_RightArm"]

## Bone index -> offset added to its local position.
var bone_offsets := {}
## Uniform scale of the head.
@export var head_scale := 1.0
## Relative change of the collarbones: 0.1 moves each shoulder joint out 10%.
@export var shoulder_width := 0.0

var _head := -1
var _shoulders: Array[int] = []
var _arms: Array[int] = []


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _head < 0:
		_head = skeleton.find_bone(HEAD)
		for bone in SHOULDERS:
			_shoulders.append(skeleton.find_bone(bone))
		for bone in ARMS:
			_arms.append(skeleton.find_bone(bone))
	for bone in bone_offsets:
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone) + bone_offsets[bone])
	if _head >= 0 and not is_equal_approx(head_scale, 1.0):
		skeleton.set_bone_pose_scale(_head, skeleton.get_bone_pose_scale(_head) * head_scale)
	if is_zero_approx(shoulder_width):
		return
	# The collarbone hangs off Spine2, whose local X is sideways; the arm joint
	# sits along the collarbone, so lengthening it widens the shoulders.
	for bone in _shoulders:
		if bone >= 0:
			var position := skeleton.get_bone_pose_position(bone)
			skeleton.set_bone_pose_position(bone, Vector3(position.x * (1.0 + shoulder_width), position.y, position.z))
	for bone in _arms:
		if bone >= 0:
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone) * (1.0 + shoulder_width))
