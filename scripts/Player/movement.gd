extends Node

class_name Movement
const Config = preload("res://scripts/config.gd")
const SWIM_TRANSITION_DELAY = 0.3

@export var speed: float = 5.0
@export var swim_speed: float = 2.5
@export var acceleration: float = 10.0
@export var fall_speed_threshold: float = 5.0
@export var jump_height: float = 3.0
@export var mass: float = 70.0

var current_animation = Config.ANIMATION.IDLE
var on_platform: bool = false

var is_jumping = false
var is_falling = false
var is_running = false
var is_sprinting = false
var is_swimming = false
var was_swimming = false
var swim_transition_timer = 0.0

var jump_velocity = 0.0
var gravity_velocity = 0.0

var velocity: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO

func handle_jump_movement(delta: float, gravity_strength: float, gravity_direction: Vector3 , is_on_floor: bool):
	if is_swimming:
		return
	if Input.is_action_just_pressed("jump") and !is_jumping && !is_falling:
		is_jumping = true
		jump_velocity = sqrt(2 * jump_height * gravity_strength)
		current_animation = Config.ANIMATION.JUMP_START
		
	if is_jumping:
		velocity += -gravity_direction.normalized() * jump_velocity * delta * mass
		jump_velocity = max(0, jump_velocity - gravity_strength * delta)

		if jump_velocity > 0.0:
			current_animation = Config.ANIMATION.JUMP_IDLE
		elif !is_on_floor:
			current_animation = Config.ANIMATION.FALLING
		else:
			is_jumping = false
			current_animation = Config.ANIMATION.JUMP_LAND

func handle_run_movement(delta: float, is_attacking: bool, gravity_direction: Vector3, camera: Camera3D) -> Vector3:
	var input_dir = get_input_direction(camera, gravity_direction)
	update_movement(delta, input_dir)
	
	if is_swimming != was_swimming:
		swim_transition_timer = SWIM_TRANSITION_DELAY
		was_swimming = is_swimming
	
	swim_transition_timer = max(0, swim_transition_timer - delta)
	var use_swim_animations = is_swimming || swim_transition_timer > 0
	
	if is_swimming:
		is_jumping = false
		is_falling = false
		jump_velocity = 0.0
		gravity_velocity = 0.0
		
	if Input.is_action_pressed("Sprint"):
		if !is_jumping && !is_falling && !use_swim_animations:
			is_sprinting = true
			velocity = velocity * 1.8
			current_animation = Config.ANIMATION.SPRINT
	else:
		is_sprinting = false
		
	if !is_attacking && !is_jumping && !is_sprinting && !is_falling:
		is_running = input_dir.length() > 0.1
		
		if !is_running:
			current_animation = Config.ANIMATION.SWIM_IDLE if use_swim_animations else Config.ANIMATION.IDLE
		else:
			current_animation = Config.ANIMATION.SWIM if use_swim_animations else Config.ANIMATION.RUN
			
	return input_dir

func handle_idle_movement(delta: float, gravity_direction: Vector3, is_on_floor: bool, gravity_strength: float, current_velocity: Vector3):
	var downward_velocity = current_velocity.dot(gravity_direction.normalized())
	is_falling = !is_on_floor && !is_jumping && downward_velocity > fall_speed_threshold && !is_swimming
	
	if is_falling:
		current_animation = Config.ANIMATION.FALLING
	
	if on_platform:
		gravity_velocity = 0.0
		return
		
	if !is_on_floor && !is_swimming:
		var gravity_accel = gravity_strength * mass
		var gravity_dir = gravity_direction.normalized()
		gravity_velocity = lerp(gravity_velocity, gravity_accel, delta)
		velocity += gravity_dir * gravity_velocity * delta
	else:
		gravity_velocity = 0.0
	
func get_input_direction(camera: Camera3D, gravity_dir: Vector3) -> Vector3:
	if is_falling:
		return Vector3.ZERO
		
	var forward = -camera.global_transform.basis.z
	var right = camera.global_transform.basis.x
	var up = camera.global_transform.basis.y
	
	if !is_swimming:
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
	if !is_swimming:
		velocity = direction * speed
	else:
		velocity = direction * swim_speed
