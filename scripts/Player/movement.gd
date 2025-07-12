extends Node

class_name Movement

@export var speed: float = 5.0
@export var acceleration: float = 10.0

var velocity: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO

func get_input_direction(camera: Camera3D, gravity_dir: Vector3) -> Vector3:
	# Usar la dirección hacia adelante de la CÁMARA en lugar del personaje
	var forward = -camera.global_transform.basis.z
	var right = camera.global_transform.basis.x
	var up = camera.global_transform.basis.y
	# Proyectar sobre el plano tangente a la gravedad
	forward = project_on_plane(forward, gravity_dir).normalized()
	right = project_on_plane(right, gravity_dir).normalized()
	up = project_on_plane(up, gravity_dir).normalized()
	
	var player: CharacterBody3D = get_parent()
	print(player.is_on_floor())

	var dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += forward
	if Input.is_action_pressed("move_back"):
		dir -= forward
	if Input.is_action_pressed("move_left"):
		dir -= right
	if Input.is_action_pressed("move_right"):
		dir += right

	return dir.normalized()

func project_on_plane(vector: Vector3, normal: Vector3) -> Vector3:
	return vector - normal * vector.dot(normal)

func update_movement(delta: float, direction_input: Vector3):
	direction = direction.lerp(direction_input, delta * acceleration)
	velocity = direction * speed
