extends Node

class_name CameraController

@export var mouse_sensitivity := 0.002
@export var invert_y := false
@export var max_pitch := 1.5  # ~85 grados
@export var min_pitch := -1.5
@export var camera_distance: float = 5.0  # Distancia de la cámara al personaje
@export var camera_height: float = 2.0  # Altura de la cámara sobre el personaje

@onready var camera_pivot: Node3D = $"../CameraPivot"
@onready var pitch_pivot: Node3D = $"../CameraPivot/PitchPivot"
@onready var camera: Camera3D = $"../CameraPivot/PitchPivot/Camera3D"

var pitch := 0.0
var yaw := 0.0
var delta_yaw := 0.0
var delta_pitch := 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	update_camera_position()

func _input(event: InputEvent):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		delta_yaw += -event.relative.x * mouse_sensitivity
		delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle_mouse_capture()

func update_camera_rotation(delta: float, gravity_dir: Vector3):
	var player = get_parent()

	# Yaw: rotar el CameraPivot alrededor del eje "up" del personaje
	if delta_yaw != 0.0:
		var up_axis = -gravity_dir.normalized()
		var yaw_rot = Quaternion(up_axis, delta_yaw)
		var player_pos = player.global_position
		var relative_pos = camera_pivot.global_position - player_pos
		relative_pos = yaw_rot * relative_pos
		camera_pivot.global_position = player_pos + relative_pos
		camera_pivot.global_transform.basis = Basis(yaw_rot) * camera_pivot.global_transform.basis
		camera_pivot.orthonormalize()
		yaw += delta_yaw

	# Pitch: rotar el PitchPivot en su eje local X
	pitch = clamp(pitch + delta_pitch, min_pitch, max_pitch)
	pitch_pivot.rotation.x = pitch

	# Actualizar la posición de la cámara
	update_camera_position()

	# Reiniciar deltas
	delta_yaw = 0.0
	delta_pitch = 0.0

func update_camera_position():
	var player = get_parent()
	var player_pos = player.global_position
	var gravity_dir = player.gravity_direction
	var up_axis = -gravity_dir.normalized()

	# Dirección "hacia atrás" del CameraPivot
	var pivot_direction = -camera_pivot.global_transform.basis.z
	var planar_direction = (pivot_direction - up_axis * pivot_direction.dot(up_axis)).normalized()
	
	# Posicionar el CameraPivot detrás del personaje y a la altura deseada
	var pivot_offset = planar_direction * camera_distance + up_axis * camera_height
	camera_pivot.global_position = player_pos + pivot_offset
	
	# Posicionar la Camera3D relativa al PitchPivot
	camera.position = Vector3(0, 0, camera_distance)

func toggle_mouse_capture():
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		else Input.MOUSE_MODE_CAPTURED
	)
