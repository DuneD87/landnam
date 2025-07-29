extends CharacterBody3D

@onready var voxelTool: VoxelTool

@export var mouse_sensitivity: float = 0.002
@export var roll_speed: float = 2.0
@export var move_speed: float = 2500.0
@export var vertical_speed: float = 50.0
@export var invert_y: bool = false
@export var speed_increase : float = 1.0

# Radio para la esfera que se creará con do_sphere
@export var sphere_radius: float = 50.0

var orientation: Quaternion = Quaternion.IDENTITY
var delta_yaw: float = 0.0
var delta_pitch: float = 0.0
var delta_roll: float = 0.0 


var planets:Node3D
@onready var camera: Camera3D = $Camera3D

func get_closest_planet() -> Node3D:
	var index_min = 0
	var min_distance = -1.0
	var i = 0
	for planet in planets.get_children():
		var distance =  position.distance_to(planet.position)
		if distance < min_distance || min_distance == -1:
			min_distance = distance
			index_min = i
		i += 1
		
	var node_path = "Planets/" + planets.get_child(index_min).name
	
	return get_parent().get_node(node_path)

func _ready() -> void:
	planets = get_parent().get_node("Planets")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			delta_yaw += -event.relative.x * mouse_sensitivity
			delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			toggle_mouse_capture()
	elif event is InputEventMouseButton and event.pressed:
		
		#voxelTool = get_closest_planet().get_node("VoxelLodTerrain").get_voxel_tool()
		#voxelTool.channel = VoxelBuffer.CHANNEL_SDF
			
		if event.button_index == MOUSE_BUTTON_LEFT:
			pass
			# Ejecutar do_sphere en el punto donde mira la cámara
			#perform_sphere_action()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			move_speed += speed_increase
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move_speed -= speed_increase

func _physics_process(delta: float) -> void:
	var roll_input = 0.0
	if Input.is_key_pressed(KEY_Q):
		roll_input += 1.0
	if Input.is_key_pressed(KEY_E):
		roll_input -= 1.0
	delta_roll = roll_input * roll_speed * delta

	if delta_pitch != 0.0:
		var pitch_quat = Quaternion(Vector3(-1, 0, 0), delta_pitch)
		orientation = orientation * pitch_quat
	if delta_roll != 0.0:
		var roll_quat = Quaternion(Vector3(0, 0, 1), delta_roll)
		orientation = orientation * roll_quat
	if delta_yaw != 0.0:
		var local_y_axis = camera.transform.basis.y.normalized()
		var yaw_quat = Quaternion(local_y_axis, delta_yaw)
		orientation = yaw_quat * orientation

	orientation = orientation.normalized()
	camera.transform.basis = Basis(orientation)

	delta_yaw = 0.0
	delta_pitch = 0.0
	delta_roll = 0.0

	var current_speed = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed *= 2
	handle_movement(delta, current_speed)

func handle_movement(delta: float, speed: float) -> void:
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
		var direction = camera.transform.basis * input_dir
		direction = direction.normalized()
		velocity = direction * speed
	else:
		velocity = Vector3.ZERO

	move_and_slide()

func toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func perform_sphere_action() -> void:
	var origin = camera.global_position
	var direction = -camera.global_transform.basis.z.normalized()
	var result = voxelTool.raycast(origin, direction, 2000.0)
	
	if result:
		var hit_position = result.previous_position
		var center = Vector3(hit_position.x, hit_position.y, hit_position.z)
		voxelTool.mode = VoxelTool.MODE_REMOVE 
		voxelTool.value = 0
		voxelTool.do_sphere(center, 2.5)
