extends CharacterBody3D

@export var planet: Node3D
@onready var movement: Movement = $Movement
@onready var camera_controller: CameraController = $CameraController
@onready var camera: Camera3D = $CameraPivot/PitchPivot/Camera3D
@onready var animator: AnimationPlayer = $PlayerModel/AnimationPlayer

var gravity_direction: Vector3 = Vector3.DOWN
@export var mass: float = 70.0
@export var jump_height: float = 10.0
@export var jump_time: float = 0.5
var is_jumping := false
var jump_velocity := 0.0
var was_on_floor := true
var mouse_captured := true
var sliding_threshold: float = -3.0  # Velocidad para detectar deslizamiento
var locked_forward_direction: Vector3 = Vector3.FORWARD

func _ready():
	capture_mouse(true)

func _input(event):
	camera_controller._input(event)
	
	if event.is_action_pressed("ui_cancel"):
		capture_mouse(not mouse_captured)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
		capture_mouse(true)

func _physics_process(delta: float):
	if not mouse_captured:
		return
		
	gravity_direction = planet.get_gravity_direction(global_position)
	var input_dir = movement.get_input_direction(camera, gravity_direction)
	movement.update_movement(delta, input_dir)
	
	velocity = movement.velocity
	
	# Detección mejorada de estados
	var just_left_ground = was_on_floor and not is_on_floor()
	var just_landed = not was_on_floor and is_on_floor()
	var is_sliding = is_on_floor() and velocity.y < sliding_threshold
	was_on_floor = is_on_floor()
	
	# Aplicar gravedad
	if !is_on_floor():
		var gravity_force = gravity_direction.normalized() * mass * planet.gravity_strength
		velocity += gravity_force * delta
	
	# Lógica de salto
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_sliding:
		start_jump()
	
	if is_jumping:
		velocity += -gravity_direction.normalized() * jump_velocity * delta * mass
		jump_velocity = max(0, jump_velocity - planet.gravity_strength * delta)
		
		if jump_velocity <= 0:
			is_jumping = false
	
	move_and_slide()
	
	# Manejo de animaciones mejorado
	handle_animations(input_dir, just_left_ground, just_landed, is_sliding)
	
	# Alineación y rotación
	if input_dir.length() > 0.1:
		rotate_toward_movement(input_dir, delta)
	
	align_to_gravity(gravity_direction, delta)
	camera_controller.update_camera_rotation(delta, gravity_direction)

func capture_mouse(capture: bool):
	mouse_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)

func start_jump():
	is_jumping = true
	jump_velocity = sqrt(2 * jump_height * planet.gravity_strength)
	animator.play("Jump_Start")

func handle_animations(input_dir: Vector3, just_left_ground: bool, just_landed: bool, is_sliding: bool):
	var current_anim = animator.current_animation
	
	if just_landed:
		if current_anim in ["Jump_Idle", "Jump_Start"]:
			animator.play("Jump_Land")
		else:
			play_ground_animation(input_dir)
	
	elif just_left_ground and is_jumping and not is_sliding:
		animator.play("Jump_Idle")
	
	elif is_on_floor() and not is_jumping:
		play_ground_animation(input_dir)

func play_ground_animation(input_dir: Vector3):
	if input_dir.length() < 0.1:
		if animator.current_animation != "Idle":
			animator.play("Idle")
	else:
		if animator.current_animation != "Running_A":
			animator.play("Running_A")

func rotate_toward_movement(input_dir: Vector3, delta: float):
	# Solo rotar si hay input significativo (mayor que 0.3)
	if input_dir.length() < 0.3:
		return
	
	var forward = -camera.global_transform.basis.z
	var target_dir = movement.project_on_plane(forward, gravity_direction).normalized()
	var current_dir = global_transform.basis.z
	
	# Calcular ángulo entre direcciones
	var angle = acos(clamp(current_dir.dot(target_dir), -1.0, 1.0))
	
	# Solo rotar si el ángulo es significativo (mayor a 5 grados)
	if angle > deg_to_rad(5.0):
		var rotation_axis = current_dir.cross(target_dir)
		if rotation_axis.length() > 0.001:
			# Rotación más suave con factor reducido
			var rot = Quaternion(rotation_axis.normalized(), angle * delta * 3.0)  # Reducido de 5.0 a 3.0
			global_transform.basis = Basis(rot) * global_transform.basis
			orthonormalize()

func align_to_gravity(gravity_dir: Vector3, delta: float):
	var up_dir = -gravity_dir.normalized()
	var current_up = global_transform.basis.y
	var rotation_axis = current_up.cross(up_dir)
	var angle = acos(clamp(current_up.dot(up_dir), -1.0, 1.0))

	if angle > 0.001 and rotation_axis.length() > 0.001:
		var rot = Quaternion(rotation_axis.normalized(), angle * delta * 5.0)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()
