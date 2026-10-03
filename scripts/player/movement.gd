extends Node

class_name Movement

## Movimiento compartido por jugador y NPCs: correr, saltar, nadar y gravedad, con animación y daño
## por caída. La dirección viene del input o, en modo IA (use_ai_input), de ai_direction.

const Config = preload("res://scripts/config.gd")
const SWIM_TRANSITION_DELAY = 0.3

@export var speed: float = 5.0
## Velocidad al andar (el jugador la ajusta al ritmo de su animación de andar).
@export var walk_speed: float = 0.6
## Velocidad al esprintar (el jugador la fija en _setup_gaits; los NPCs no esprintan).
@export var sprint_speed: float = 9.0
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

## Lo que el combate recorta: velocidad al apuntar, y sin correr ni saltar mientras golpea,
## esquiva o se tambalea (o sin aguante para correr).
var speed_scale: float = 1.0
var sprint_blocked: bool = false
var jump_blocked: bool = false

## Andar en vez de correr (el jugador lo alterna con walk_toggle). Esprintar sigue a su velocidad.
var walking: bool = false

## Si true, get_input_direction() devuelve ai_direction en vez de leer Input (modo IA de los NPCs).
var use_ai_input: bool = false
var ai_direction: Vector3 = Vector3.ZERO

## Emitido al aterrizar tras un vuelo. [impact_speed] = velocidad descendente máxima (m/s).
signal landed(impact_speed: float)
## Emitido en el frame en que arranca un salto.
signal jumped()
## Emitido al cruzar la lamina de agua con los pies. [speed] es la velocidad vertical del cruce
## (positiva hacia abajo) y [entering] distingue zambullirse de salir.
signal water_crossed(speed: float, entering: bool)
var _was_on_floor: bool = true
var _peak_airborne_speed: float = 0.0

func handle_jump_movement(delta: float, gravity_strength: float, gravity_direction: Vector3 , is_on_floor: bool):
	if is_swimming:
		return
	if Input.is_action_just_pressed("jump") and !is_jumping && !is_falling and not jump_blocked:
		is_jumping = true
		jump_velocity = sqrt(2 * jump_height * gravity_strength)
		current_animation = Config.ANIMATION.JUMP_START
		jumped.emit()
		
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

func handle_run_movement(delta: float, is_attacking: bool, gravity_direction: Vector3, camera: Camera3D, idle_animation: Config.ANIMATION, run_animation: Config.ANIMATION) -> Vector3:
	var input_dir = get_input_direction(camera, gravity_direction)
	var wants_sprint: bool = Input.is_action_pressed("Sprint") and input_dir.length() > 0.1 \
		and not sprint_blocked and not use_ai_input
	update_movement(delta, input_dir, walking and not wants_sprint)
	
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
		
	# Correr exige input de movimiento: con Shift pulsado y quieto se quedaba la animación de
	# sprint en el sitio (y bloqueaba can_perform_action).
	if Input.is_action_pressed("Sprint") && input_dir.length() > 0.1 and not sprint_blocked and not use_ai_input:
		if !is_jumping && !is_falling && !use_swim_animations:
			is_sprinting = true
			velocity = direction * sprint_speed * speed_scale
			current_animation = Config.ANIMATION.SPRINT
	else:
		is_sprinting = false
		
	if !is_attacking && !is_jumping && !is_sprinting && !is_falling:
		is_running = input_dir.length() > 0.1
		
		if !is_running:
			current_animation = Config.ANIMATION.SWIM_IDLE if use_swim_animations else idle_animation
		elif use_swim_animations:
			current_animation = Config.ANIMATION.SWIM
		else:
			current_animation = Config.ANIMATION.WALK if walking else run_animation
			
	return input_dir

func handle_idle_movement(delta: float, gravity_direction: Vector3, is_on_floor: bool, gravity_strength: float, current_velocity: Vector3):
	var downward_velocity = current_velocity.dot(gravity_direction.normalized())
	is_falling = !is_on_floor && !is_jumping && downward_velocity > fall_speed_threshold && !is_swimming

	if is_falling:
		current_animation = Config.ANIMATION.FALLING

	if not is_on_floor and not is_swimming:
		_peak_airborne_speed = max(_peak_airborne_speed, downward_velocity)

	if not _was_on_floor and is_on_floor and not is_swimming:
		if _peak_airborne_speed > 0.0:
			landed.emit(_peak_airborne_speed)
		_peak_airborne_speed = 0.0
	_was_on_floor = is_on_floor

	if on_platform:
		gravity_velocity = 0.0
		return

	if !is_on_floor && !is_swimming:
		var gravity_accel =  gravity_strength * mass
		var gravity_dir = gravity_direction.normalized()
		gravity_velocity = downward_velocity + lerp(gravity_velocity, gravity_accel, delta)
		velocity += gravity_dir * gravity_velocity * delta
	else:
		gravity_velocity = 0.0
	
## [even_falling] lee el input también cayendo (agarrarse a una pared en el aire).
func get_input_direction(camera: Camera3D, gravity_dir: Vector3, even_falling: bool = false) -> Vector3:
	if is_falling and not even_falling:
		return Vector3.ZERO

	if use_ai_input:
		return ai_direction

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

func update_movement(delta: float, direction_input: Vector3, walk: bool = false):
	direction = direction.lerp(direction_input, delta * acceleration)
	if !is_swimming:
		velocity = direction * (walk_speed if walk else speed) * speed_scale
	else:
		velocity = direction * swim_speed
