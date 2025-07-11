extends CharacterBody3D

@export var planet: Node3D
@onready var movement: Movement = $Movement
@onready var camera_controller: CameraController = $CameraController
@onready var camera: Camera3D = $CameraPivot/PitchPivot/Camera3D
@onready var animator: AnimationPlayer = $PlayerModel/AnimationPlayer

var gravity_direction: Vector3 = Vector3.DOWN

func _input(event):
	camera_controller._input(event)

func _physics_process(delta: float):
	gravity_direction = planet.get_gravity_direction(global_position)
	var input_dir = movement.get_input_direction(camera, gravity_direction)
	movement.update_movement(delta, input_dir)
	
	velocity = movement.velocity
	velocity += planet.apply_gravity(velocity, gravity_direction, delta)

	move_and_slide()
	
	# Align the character to face the movement direction
	if input_dir.length() > 0.1:
		var forward = -camera.global_transform.basis.z
		var target_dir = movement.project_on_plane(forward, gravity_direction).normalized()
		var current_dir = global_transform.basis.z
		var rotation_axis = current_dir.cross(target_dir)
		var angle = acos(clamp(current_dir.dot(target_dir), -1.0, 1.0))
		if angle > 0.001 and rotation_axis.length() > 0.001:
			var rot = Quaternion(rotation_axis.normalized(), angle * delta * 5.0)
			global_transform.basis = Basis(rot) * global_transform.basis
			orthonormalize()
	
	align_to_gravity(gravity_direction, delta)

	camera_controller.update_camera_rotation(delta, gravity_direction)

	update_animation(input_dir)

func align_to_gravity(gravity_dir: Vector3, delta: float):
	var up_dir = -gravity_dir.normalized()
	var current_up = global_transform.basis.y
	var rotation_axis = current_up.cross(up_dir)
	var angle = acos(clamp(current_up.dot(up_dir), -1.0, 1.0))

	if angle > 0.001 and rotation_axis.length() > 0.001:
		var rot = Quaternion(rotation_axis.normalized(), angle * delta * 5.0)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()

func update_animation(direction_input: Vector3):
	if direction_input.length() < 0.1:
		animator.play("Idle")
	else:
		animator.play("Running_A")
