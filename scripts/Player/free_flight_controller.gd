extends Node
class_name FreeFlightController

@export var roll_speed: float = 2.0
@export var free_flight_speed: float = 20.0
@export var velocity: Vector3

var orientation: Quaternion = Quaternion.IDENTITY
var delta_yaw: float = 0.0
var delta_pitch: float = 0.0
var delta_roll: float = 0.0

func update_free_flight(delta: float, camera: Camera3D, ) -> void:
	if delta_pitch != 0.0:
		var pitch_quat = Quaternion(Vector3(-1, 0, 0), delta_pitch)
		orientation = orientation * pitch_quat
	if delta_yaw != 0.0:
		var local_y_axis = camera.global_transform.basis.y.normalized()
		var yaw_quat = Quaternion(local_y_axis, delta_yaw)
		orientation = yaw_quat * orientation

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

	delta_yaw = 0.0
	delta_pitch = 0.0
	delta_roll = 0.0

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
