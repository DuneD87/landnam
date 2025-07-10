# res://scripts/player/player_controller.gd
extends CharacterBody3D

@export var planet: Node3D
@onready var movement: Movement = $Movement
@onready var camera: Camera3D = $Camera3D
@onready var model: Node3D = $PlayerModel
@onready var animator: AnimationPlayer = $PlayerModel/AnimationPlayer
@onready var camera_controller: CameraController = $CameraController

var gravity_direction: Vector3 = Vector3.DOWN

func _ready() -> void:
	set_process_input(true) 

func _input(event):
	camera_controller._input(event)

func align_to_gravity(gravity_dir: Vector3, delta: float):
	var up_dir = -gravity_dir.normalized()
	var current_up = global_transform.basis.y
	var rotation_axis = current_up.cross(up_dir)
	var angle = acos(clamp(current_up.dot(up_dir), -1.0, 1.0))

	if angle > 0.001 and rotation_axis.length() > 0.001:
		var rot = Quaternion(rotation_axis.normalized(), angle * delta * 5.0)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()
	
func _physics_process(delta: float) -> void:
	var input_dir = movement.get_input_direction(camera)
	movement.update_movement(delta, input_dir, gravity_direction)
	
	velocity = movement.velocity
	gravity_direction = planet.get_gravity_direction(position)
	velocity += planet.apply_gravity(velocity, gravity_direction, delta)
		
	move_and_slide()
	align_to_gravity(planet.get_gravity_direction(global_position), delta)

	camera_controller.update_camera_rotation(delta)
	
	update_animation(input_dir)


func update_animation(direction_input: Vector3):
	if direction_input.length() < 0.1:
		animator.play("Idle")
	else:
		animator.play("Running_A")
