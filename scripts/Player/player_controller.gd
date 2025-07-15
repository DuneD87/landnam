extends CharacterBody3D
const Config = preload("res://scripts/config.gd")

@onready var movement: Movement = $Movement
@onready var camera_controller: CameraController = $CameraController
@onready var camera: Camera3D = $CameraPivot/PitchPivot/Camera3D
@onready var animation_controller: AnimationController = $AnimationController
@onready var free_flight_controller: FreeFlightController = $FreeFlightController

@export var planet: Node3D
@export var animator_tree: AnimationTree
@export var mouse_sensitivity: float = 0.002
@export var invert_y: bool = false
@export var timer : Timer

var gravity_direction: Vector3 = Vector3.DOWN
var locked_forward_direction: Vector3 = Vector3.FORWARD

var is_attacking = false
var mouse_captured = true
var free_flight_enabled = false

var current_animation = Config.IDLE

func capture_mouse(capture: bool):
	mouse_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)
	
func on_animation_finish(_name: String):
	if current_animation == Config.IDLE:
		return
	print("Animation finished: ", _name, " current_animation: ", current_animation)
	
				
func on_animation_start(_name: String):
	if current_animation == Config.IDLE:
		return
	print("Animation started: ", _name, " current_animation: ", current_animation)

func on_timeout():
	if current_animation == Config.ATTACK_1:
		is_attacking = false
		
func _ready():
	timer = Timer.new()
	timer.connect("timeout", on_timeout)
	add_child(timer)
	
	capture_mouse(true) 

	
func _input(event):
	if free_flight_enabled:
		if event is InputEventMouseMotion and mouse_captured:
			free_flight_controller.delta_yaw += -event.relative.x * mouse_sensitivity
			free_flight_controller.delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
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
			free_flight_controller.orientation = Quaternion(camera.global_transform.basis)
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
	free_flight_controller.update_free_flight(delta, camera)
	velocity = free_flight_controller.velocity
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
		
func handle_attack(delta: float):
	if Input.is_action_just_pressed("attack_1") && !is_attacking && !movement.is_falling:
		current_animation = Config.ATTACK_1
		timer.start(0.7)
		dig_hole(2.0, 100.0)
		is_attacking = true
		

func update_normal_movement(delta: float) -> void:
	gravity_direction = planet.get_gravity_direction(global_position)
	up_direction = -gravity_direction
	
	var input_dir = movement.handle_idle_movement(delta, gravity_direction, camera, is_on_floor(), planet.gravity_strength, is_attacking, velocity)
	movement.handle_jump_movement(delta, planet.gravity_strength, gravity_direction, is_on_floor())
	current_animation = movement.current_animation
	
	handle_attack(delta)
	animation_controller.handle_animations(delta, current_animation, free_flight_enabled)
	velocity = movement.velocity
	
	if movement.is_running || movement.is_sprinting:
		rotate_toward_movement(input_dir, delta)

	align_to_gravity(gravity_direction, delta)
	camera_controller.update_camera_rotation()
	
	move_and_slide()
