class_name PreviewHeadAim
extends SkeletonModifier3D

## Turns the head of the creation preview towards the camera, within a limit,
## so close-ups show the face instead of the idle animation's lowered gaze.
## The face direction is taken from the rest pose, where the model faces its
## own +Z.

const HEAD := "mixamorig_Head"

@export var target: Node3D
@export_range(0.0, 1.0) var weight := 1.0
@export var max_angle := deg_to_rad(45.0)

## Head joint in world space as the modifier chain left it (joint offsets
## included), for the preview camera to frame; nothing outside the chain sees
## the modified pose.
var head_position := Vector3.ZERO

var _head := -1
## Face direction in the head bone's frame.
var _face_local := Vector3.ZERO


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or target == null:
		return
	if _head < 0:
		_head = skeleton.find_bone(HEAD)
		if _head < 0:
			return
		var rest := skeleton.get_bone_global_rest(_head).basis
		var model := skeleton.owner as Node3D
		var model_forward := skeleton.global_basis.inverse() * model.global_basis.z
		_face_local = (rest.inverse() * model_forward).normalized()
	var pose := skeleton.get_bone_global_pose(_head)
	var head_world := skeleton.global_transform * pose.origin
	head_position = head_world
	var face := (skeleton.global_basis * (pose.basis * _face_local)).normalized()
	var wanted := (target.global_position - head_world).normalized()
	var angle := minf(face.angle_to(wanted), max_angle) * weight
	var axis := face.cross(wanted)
	if axis.length_squared() < 1e-8 or angle < 1e-4:
		return
	# Turn in skeleton space.
	var axis_local := (skeleton.global_basis.inverse() * axis).normalized()
	pose.basis = Basis(axis_local, angle) * pose.basis
	skeleton.set_bone_global_pose(_head, pose)
