class_name BodyProportions
extends SkeletonModifier3D

## Moves each joint where the current body has it, over the animated pose,
## every frame (modifier changes do not persist, so nothing accumulates). The
## animations key the player skeleton's bone positions; each body adds its
## difference on top (see CharacterAppearanceRig and HumanShape). Place it
## before IK modifiers so they see the result.

## Bone index -> offset added to its local position.
var bone_offsets := {}


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in bone_offsets:
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone) + bone_offsets[bone])
