extends Node

class_name Movement
const Config = preload("res://scripts/config.gd")

@export var speed: float = 5.0
@export var acceleration: float = 10.0
@export var fall_speed_threshold: float = 5.0
@export var jump_height: float = 3.0
@export var mass: float = 70.0

var current_animation = Config.IDLE

var is_jumping = false
var is_falling = false
var is_running = false
var is_sprinting = false

var jump_velocity = 0.0
var gravity_velocity = 0.0

var velocity: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO

func handle_jump_movement(delta: float, gravity_strength: float, gravity_direction: Vector3 , is_on_floor: bool):
	if Input.is_action_just_pressed("jump") and !is_jumping && !is_falling:
		is_jumping = true
		jump_velocity = sqrt(2 * jump_height * gravity_strength)
		current_animation = Config.JUMP_START
		
	if is_jumping:
		velocity += -gravity_direction.normalized() * jump_velocity * delta * mass
		jump_velocity = max(0, jump_velocity - gravity_strength * delta)

		if jump_velocity > 0.0:
			current_animation = Config.JUMP_IDLE
		elif !is_on_floor:
			current_animation = Config.FALLING
		else:
			is_jumping = false
			current_animation = Config.JUMP_LAND

func handle_idle_movement(delta: float, gravity_direction: Vector3, camera: Camera3D, is_on_floor: bool, gravity_strength: float, is_attacking: bool, current_velocity: Vector3) -> Vector3:
	
	var input_dir = get_input_direction(camera, gravity_direction)
	update_movement(delta, input_dir)
	
	var downward_velocity = current_velocity.dot(gravity_direction.normalized())
	is_falling = !is_on_floor and !is_jumping and downward_velocity > fall_speed_threshold
	
	if is_falling:
		current_animation = Config.FALLING
		
	if Input.is_action_pressed("Sprint"):
		is_sprinting = true
		velocity = velocity * 1.8
		if !is_jumping && !is_falling:
			current_animation = Config.SPRINT
	else:
		is_sprinting = false
		velocity = velocity

	if !is_on_floor:
		var gravity_accel = gravity_strength * mass
		var gravity_dir = gravity_direction.normalized()
		
		gravity_velocity = lerp(gravity_velocity, gravity_accel, delta)

		velocity += gravity_dir * gravity_velocity * delta
	else:
		gravity_velocity = 0.0
		
	if !is_attacking && !is_jumping && !is_sprinting && !is_falling:
		is_running = input_dir.length() > 0.1
		
		if !is_running:
			current_animation = Config.IDLE
		else:
			current_animation = Config.RUN	
			
	return input_dir

func get_input_direction(camera: Camera3D, gravity_dir: Vector3) -> Vector3:
	# Usar la dirección hacia adelante de la CÁMARA en lugar del personaje
	var forward = -camera.global_transform.basis.z
	var right = camera.global_transform.basis.x
	var up = camera.global_transform.basis.y
	# Proyectar sobre el plano tangente a la gravedad
	forward = project_on_plane(forward, gravity_dir).normalized()
	right = project_on_plane(right, gravity_dir).normalized()
	up = project_on_plane(up, gravity_dir).normalized()
	
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
