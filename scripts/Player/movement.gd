# res://scripts/player/movement.gd
extends Node

class_name Movement

@export var speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 5.0

var velocity: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO

func get_input_direction(camera: Camera3D) -> Vector3:
	var dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir -= camera.global_transform.basis.z
	if Input.is_action_pressed("move_back"):
		dir += camera.global_transform.basis.z
	if Input.is_action_pressed("move_left"):
		dir -= camera.global_transform.basis.x
	if Input.is_action_pressed("move_right"):
		dir += camera.global_transform.basis.x
	return dir.normalized()

func project_on_plane(vector: Vector3, normal: Vector3) -> Vector3:
	return vector - normal * vector.dot(normal)
	
func update_movement(delta: float, direction_input: Vector3, gravity_direction: Vector3):
	var target_dir = project_on_plane(direction_input, gravity_direction)
	direction = direction.lerp(target_dir, delta * acceleration)
	velocity = direction * speed
