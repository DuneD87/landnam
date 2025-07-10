# res://scripts/player/camera_controller.gd
extends Node

class_name CameraController

@export var mouse_sensitivity: float = 0.002
@export var roll_speed: float = 2.0
@export var invert_y: bool = false

@onready var camera: Camera3D = $"../Camera3D"

var orientation: Quaternion = Quaternion.IDENTITY
var delta_yaw: float = 0.0
var delta_pitch: float = 0.0
var delta_roll: float = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		delta_yaw += -event.relative.x * mouse_sensitivity
		delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle_mouse_capture()

func update_camera_rotation(delta: float):
	var player = get_parent()
	var player_up = player.global_transform.basis.y
	var player_forward = -player.global_transform.basis.z
	var player_right = player.global_transform.basis.x

	# Aplicar yaw en torno al eje Y local del personaje (normal al terreno)
	if delta_yaw != 0.0:
		var yaw_quat = Quaternion(player_up, delta_yaw)
		player.rotate_object_local(player_up, delta_yaw)

	# Calculamos la rotación de pitch SOLO para la cámara (para que no afecte al modelo)
	if delta_pitch != 0.0:
		# Aplica pitch alrededor del eje X local de la cámara
		var pitch_quat = Quaternion(player_right, delta_pitch * (-1 if invert_y else 1))
		camera.transform.basis = Basis(pitch_quat) * camera.transform.basis

	# Re-orthonormalizar para evitar acumulación de errores
	camera.transform.basis = camera.transform.basis.orthonormalized()

	delta_yaw = 0.0
	delta_pitch = 0.0


func toggle_mouse_capture():
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		else Input.MOUSE_MODE_CAPTURED
	)
