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
var sliding_threshold: float = -3.0
var locked_forward_direction: Vector3 = Vector3.FORWARD

var free_flight_enabled := false

# Free flight variables
var orientation: Quaternion = Quaternion.IDENTITY
var delta_yaw: float = 0.0
var delta_pitch: float = 0.0
var delta_roll: float = 0.0
@export var mouse_sensitivity: float = 0.002
@export var roll_speed: float = 2.0
@export var invert_y: bool = false
@export var free_flight_speed: float = 20.0

func _ready():
	capture_mouse(true)

func _input(event):
	if free_flight_enabled:
		if event is InputEventMouseMotion and mouse_captured:
			delta_yaw += -event.relative.x * mouse_sensitivity
			delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	else:
		camera_controller._input(event)

	if event.is_action_pressed("ui_cancel"):
		capture_mouse(not mouse_captured)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
		capture_mouse(true)

	if event.is_action_pressed("toggle_free_flight"):
		free_flight_enabled = !free_flight_enabled
		if free_flight_enabled:
			print("Free flight activado")
			# Al activar free flight, sincronizamos la orientación actual
			orientation = Quaternion(camera.global_transform.basis)
		else:
			print("Free flight desactivado")

func _physics_process(delta: float):
	if not mouse_captured:
		return

	if free_flight_enabled:
		update_free_flight(delta)
	else:
		update_normal_movement(delta)

func update_free_flight(delta: float) -> void:
	# Handle rotation
	if delta_pitch != 0.0:
		var pitch_quat = Quaternion(Vector3(-1, 0, 0), delta_pitch)
		orientation = orientation * pitch_quat
	if delta_yaw != 0.0:
		var local_y_axis = camera.global_transform.basis.y.normalized()
		var yaw_quat = Quaternion(local_y_axis, delta_yaw)
		orientation = yaw_quat * orientation

	# Handle roll
	var roll_input = 0.0
	if Input.is_key_pressed(KEY_Q):
		roll_input += 1.0
	if Input.is_key_pressed(KEY_E):
		roll_input -= 1.0
	delta_roll = roll_input * roll_speed * delta
	
	if delta_roll != 0.0:
		var roll_quat = Quaternion(Vector3(0, 0, 1), delta_roll)
		orientation = orientation * roll_quat

	orientation = orientation.normalized()
	camera.global_transform.basis = Basis(orientation)

	# Reset rotation deltas
	delta_yaw = 0.0
	delta_pitch = 0.0
	delta_roll = 0.0

	# Handle movement
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_SPACE):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0

	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		var direction = camera.global_transform.basis * input_dir
		velocity = direction * free_flight_speed
	else:
		velocity = Vector3.ZERO

	move_and_slide()

func update_normal_movement(delta: float) -> void:
	if Input.is_action_just_released("camera_zoom_in"):
		camera_controller.camera_distance += 1
	if Input.is_action_just_released("camera_zoom_out"):
		camera_controller.camera_distance -= 1

	gravity_direction = planet.get_gravity_direction(global_position)
	up_direction = -gravity_direction
	var input_dir = movement.get_input_direction(camera, gravity_direction)
	movement.update_movement(delta, input_dir)
	velocity = movement.velocity

	var just_left_ground = was_on_floor and not is_on_floor()
	var just_landed = not was_on_floor and is_on_floor()
	var is_sliding = is_on_floor() and velocity.y < sliding_threshold
	was_on_floor = is_on_floor()

	if !is_on_floor():
		var gravity_force = gravity_direction.normalized() * mass * planet.gravity_strength
		velocity += gravity_force * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_sliding:
		start_jump()

	if is_jumping:
		velocity += -gravity_direction.normalized() * jump_velocity * delta * mass
		jump_velocity = max(0, jump_velocity - planet.gravity_strength * delta)
		if jump_velocity <= 0:
			is_jumping = false

	move_and_slide()

	handle_animations(input_dir, just_left_ground, just_landed, is_sliding)

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
	if free_flight_enabled:
		return

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
	if input_dir.length() < 0.3:
		return

	var forward = -camera.global_transform.basis.z
	var target_dir = movement.project_on_plane(forward, gravity_direction).normalized()
	var current_dir = global_transform.basis.z

	var angle = acos(clamp(current_dir.dot(target_dir), -1.0, 1.0))

	if angle > deg_to_rad(5.0):
		var rotation_axis = current_dir.cross(target_dir)
		if rotation_axis.length() > 0.001:
			var rot = Quaternion(rotation_axis.normalized(), angle * delta * 3.0)
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
