class_name PreviewPosture
extends SkeletonModifier3D

## Straightens the creation preview's idle: the game's idle is a crouched,
## guarded stance (upper spine bent about 20 degrees, neck about 36 degrees
## forward, shoulders raised and forward), which from the front sinks the head
## between the shoulders, the more so once PreviewHeadAim lifts the face to the
## camera. Each listed bone keeps only part of the animation's rotation away
## from its rest, so the breathing still shows. Arms, legs and hips keep the
## animation. Add it before PreviewHeadAim.

## Bone -> share of the animation's rotation it keeps (0 rest, 1 animation).
const KEEP := {
	"mixamorig_Spine": 0.5,
	"mixamorig_Spine1": 0.3,
	"mixamorig_Spine2": 0.3,
	"mixamorig_Neck": 0.3,
	"mixamorig_Head": 0.3,
	"mixamorig_LeftShoulder": 0.3,
	"mixamorig_RightShoulder": 0.3,
}

var _bones := {}


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _bones.is_empty():
		for name in KEEP:
			var bone := skeleton.find_bone(name)
			if bone >= 0:
				_bones[bone] = KEEP[name]
	for bone in _bones:
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var pose := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, rest.slerp(pose, _bones[bone]))
