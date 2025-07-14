extends CharacterBody3D

enum {IDLE, RUN, JUMP_START, JUMP_IDLE, JUMP_LAND, ATTACK_1, SPRINT, FALLING}

@onready var movement: Movement = $Movement
@onready var camera_controller: CameraController = $CameraController
@onready var camera: Camera3D = $CameraPivot/PitchPivot/Camera3D
@onready var animator: AnimationPlayer = $PlayerModel/AnimationPlayer
@onready var animation_tree: AnimationTree = $PlayerModel/AnimationTree
@export var planet: Node3D
@export var animator_tree: AnimationTree
@export var mass: float = 70.0
@export var jump_height: float = 15.0
@export var mouse_sensitivity: float = 0.002
@export var roll_speed: float = 2.0
@export var invert_y: bool = false
@export var free_flight_speed: float = 20.0
@export var blend_speed: float = 15.0
@export var timer : Timer

var locked_forward_direction: Vector3 = Vector3.FORWARD
var gravity_direction: Vector3 = Vector3.DOWN
var jump_velocity = 0.0
var sliding_threshold = -3.0
var run_val = 0
var sprint_val = 0
var jump_start_val = 0
var jump_idle_val = 0
var jump_end_val = 0

var is_jumping = false
var is_falling = false
var is_running = false
var is_sprinting = false
var is_attacking = false
var mouse_captured = true
var free_flight_enabled = false

var current_animation = IDLE

# Free flight variables
var orientation: Quaternion = Quaternion.IDENTITY
var delta_yaw: float = 0.0
var delta_pitch: float = 0.0
var delta_roll: float = 0.0


func capture_mouse(capture: bool):
	mouse_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)
	
func on_animation_finish(_name: String):
	if current_animation == IDLE:
		return
	
	#print("Animation finished: ", _name, " current_animation: ", current_animation)
	
	match current_animation:
		ATTACK_1:
			is_attacking = false
		JUMP_START:
			current_animation = JUMP_IDLE
				
func on_animation_start(_name: String):
	if current_animation == IDLE:
		return
	#print("Animation started: ", _name, " current_animation: ", current_animation)

func on_timeout():
	if current_animation == ATTACK_1:
		is_attacking = false
func _ready():
	timer = Timer.new()
	timer.connect("timeout", on_timeout)
	add_child(timer)
	
	capture_mouse(true) 
	animator.connect("animation_finished", on_animation_finish)
	animator.connect("animation_started", on_animation_start)
	
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
		
	if Input.is_action_just_released("camera_zoom_in"):
		camera_controller.camera_distance -= 1
		camera_controller.update_camera_transform()
	if Input.is_action_just_released("camera_zoom_out"):
		camera_controller.camera_distance += 1
		camera_controller.update_camera_transform()


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

func rotate_toward_movement(input_dir: Vector3, delta: float):
	if input_dir.length() < 0.3:
		return

	var forward = -camera.global_transform.basis.z
	var target_dir = movement.project_on_plane(forward, gravity_direction).normalized()
	var current_dir = global_transform.basis.z

	var angle = acos(clamp(current_dir.dot(target_dir), -1.0, 1.0))

	if angle > deg_to_rad(10.0):
		var rotation_axis = current_dir.cross(target_dir)
		if rotation_axis.length() > 0.1:
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

func dig_hole(radius: float, distance: float):
	var voxel_tool: VoxelTool = planet.voxel_terrain.get_voxel_tool()
	var origin = camera.global_position
	var direction = -camera.global_transform.basis.z.normalized()
	var result = voxel_tool.raycast(origin, direction, distance)
	
	if result:
		var hit_position = result.previous_position
		var center = Vector3(hit_position.x, hit_position.y, hit_position.z)
		voxel_tool.mode = VoxelTool.MODE_REMOVE 
		voxel_tool.value = 0
		voxel_tool.do_sphere(center, radius)
func update_tree():
	animation_tree["parameters/bRun/blend_amount"] = run_val
	animation_tree["parameters/bSprint/blend_amount"] = sprint_val
	animation_tree["parameters/bJumpStart/blend_amount"] = jump_start_val
	animation_tree["parameters/bJumpIdle/blend_amount"] = jump_idle_val
	animation_tree["parameters/bJumpLand/blend_amount"] = jump_end_val

func handle_animations(delta: float):
	if free_flight_enabled:
		return

	match current_animation:
		IDLE:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)	
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		RUN:
			run_val = lerpf(run_val, 1, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)	
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		SPRINT:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 1, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		JUMP_START:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 1, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		JUMP_IDLE:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 1, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		JUMP_LAND:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 1, blend_speed*delta)
		ATTACK_1:
			animation_tree.set("parameters/oAttack_1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			
	update_tree()

func handle_idle_movement(delta: float) -> Vector3:
	gravity_direction = planet.get_gravity_direction(global_position)
	up_direction = -gravity_direction
	var input_dir = movement.get_input_direction(camera, gravity_direction)
	movement.update_movement(delta, input_dir)
	
	if is_sprinting:
		velocity = movement.velocity * 1.8
	else:
		velocity = movement.velocity
	
	if !is_on_floor():
		var gravity_force = gravity_direction.normalized() * mass * planet.gravity_strength
		velocity += gravity_force * delta
		
	if !is_attacking && !is_jumping && !is_sprinting && !is_falling:
		is_running = input_dir.length() > 0.1
		
		if !is_running:
			current_animation = IDLE
		else:
			current_animation = RUN	
			
	return input_dir

func update_normal_movement(delta: float) -> void:
	var input_dir = handle_idle_movement(delta)
	
	if Input.is_action_pressed("Sprint"):
		is_sprinting = true
		if !is_jumping && !is_falling:
			current_animation = SPRINT
	else:
		is_sprinting = false
		
	if Input.is_action_just_pressed("jump") and is_on_floor():
		is_jumping = true
		jump_velocity = sqrt(2 * jump_height * planet.gravity_strength)
		current_animation = JUMP_START
		
	if Input.is_action_just_pressed("attack_1") && !is_attacking:
		current_animation = ATTACK_1
		timer.start(0.7)
		dig_hole(2.0, 100.0)
		is_attacking = true

	if is_jumping:
		velocity += -gravity_direction.normalized() * jump_velocity * delta * mass
		jump_velocity = max(0, jump_velocity - planet.gravity_strength * delta)
				
		if jump_velocity <= 2.0:
			is_jumping = false
			current_animation = JUMP_LAND

	move_and_slide()

	handle_animations(delta)

	if is_running:
		rotate_toward_movement(input_dir, delta)

	align_to_gravity(gravity_direction, delta)
	camera_controller.update_camera_rotation()
