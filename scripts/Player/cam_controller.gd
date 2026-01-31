extends Node

class_name CameraController

@export var mouse_sensitivity := 0.001
@export var invert_y := false
@export var max_pitch := 1.2  # ~70 grados
@export var min_pitch := -1.2
@export var camera_distance: float = 8.0
@export var camera_height: float = 4.0
@export var target_height_offset: float = 1.5
@export var collision_mask: int = 1
@export var collision_padding: float = 0.5

@onready var camera_pivot: Node3D = $"../CameraPivot"
@onready var pitch_pivot: Node3D = $"../CameraPivot/PitchPivot"
@onready var camera: Camera3D = $"../CameraPivot/PitchPivot/Camera3D"

var pitch := 0.0
var yaw := 0.0
var delta_yaw := 0.0
var delta_pitch := 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_pivot.top_level = true
	reset_camera_rotation()

func reset_camera_rotation():
	camera_pivot.rotation = Vector3.ZERO
	pitch_pivot.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.position = Vector3.ZERO
	update_camera_transform()

func _input(event: InputEvent):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		delta_yaw += -event.relative.x * mouse_sensitivity
		delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle_mouse_capture()

func update_camera_rotation():	
	if delta_yaw != 0.0:
		yaw += delta_yaw
		camera_pivot.rotation.y = yaw
	
	if delta_pitch != 0.0:
		pitch = clamp(pitch + delta_pitch, min_pitch, max_pitch)
		pitch_pivot.rotation.x = pitch
	
	update_camera_transform()
	delta_yaw = 0.0
	delta_pitch = 0.0

func update_camera_transform():
	var player = get_parent()
	var player_pos = player.global_position
	var up_axis = -player.gravity_direction.normalized()
	
	camera_pivot.global_position = player_pos
	
	# Aplicar yaw alrededor del up del jugador
	camera_pivot.global_transform.basis = Basis(up_axis, yaw)
	
	# Alinear el up del pivot con el up del jugador
	var current_up = camera_pivot.global_transform.basis.y
	if current_up.dot(up_axis) < 0.999:
		var align_axis = current_up.cross(up_axis)
		if align_axis.length() > 0.001:
			var align_angle = acos(clamp(current_up.dot(up_axis), -1.0, 1.0))
			camera_pivot.global_transform.basis = Basis(align_axis.normalized(), align_angle) * camera_pivot.global_transform.basis
	
	pitch_pivot.rotation.x = pitch
	
	var camera_forward = -pitch_pivot.global_transform.basis.z
	var target_pos = player_pos + up_axis * target_height_offset
	var horizontal_offset = -camera_forward * camera_distance
	var vertical_offset = up_axis * camera_height
	var ideal_camera_pos = target_pos + horizontal_offset + vertical_offset
	var final_camera_pos = adjust_for_collisions(target_pos, ideal_camera_pos)
	
	camera.global_position = final_camera_pos
	camera.look_at(target_pos, up_axis)

func adjust_for_collisions(target_pos: Vector3, ideal_pos: Vector3) -> Vector3:
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		target_pos,
		ideal_pos,
		collision_mask
	)
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position + (target_pos - result.position).normalized() * collision_padding
	return ideal_pos

func toggle_mouse_capture():
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		else Input.MOUSE_MODE_CAPTURED
	)
