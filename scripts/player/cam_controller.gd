extends Node
class_name CameraController

@export var mouse_sensitivity := 0.001
@export var invert_y := false
@export var max_pitch := 1.2
@export var min_pitch := -1.2

@export var camera_distance: float = 8.0
@export var min_distance: float = 0.5
@export var max_distance: float = 15.0
@export var zoom_speed: float = 0.4
@export var target_height_offset: float = 1.5
@export var collision_mask: int = 1
@export var collision_padding: float = 0.5

@export var fp_threshold: float = 0.5
@export var fp_eye_height: float = 1.7
@onready var camera_pivot: Node3D = $"../CameraPivot"
@onready var pitch_pivot: Node3D = $"../CameraPivot/PitchPivot"
@onready var camera: Camera3D = $"../CameraPivot/PitchPivot/Camera3D"
@onready var player_model: Node3D = $"../PlayerModel"

## Se apaga mientras otro modo usa la rueda (colocar un blueprint); el giro de ratón sigue vivo.
var zoom_enabled := true

## Objetivo fijado (punto en mundo) o null. Mientras hay uno, la cámara lo encuadra sola y el
## ratón en horizontal sirve para cambiar de objetivo (consume_lock_swipe).
var lock_point: Variant = null
## 0..1: cámara de apuntar (sobre el hombro derecho y más cerca). La fija el combate.
var aim_target: float = 0.0
## 0..1: cierre extra del encuadre mientras se tensa.
var aim_zoom: float = 0.0
## Ajustes del encuadre de apuntar.
@export var aim_shoulder: float = 0.62
@export var aim_distance: float = 2.1
@export var aim_fov_drop: float = 16.0
var _aim: float = 0.0
var _lock_swipe: float = 0.0
var _shake: float = 0.0
var _base_fov: float = -1.0

var pitch := 0.0
var yaw := 0.0
var delta_yaw := 0.0
var delta_pitch := 0.0
var target_distance: float
var first_person := false
var _current_up_axis: Vector3 = Vector3.UP
var _prev_platform_basis: Basis = Basis.IDENTITY
var _tracking_platform: DynamicGridBody = null

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_pivot.top_level = true
	target_distance = camera_distance
		
func reset_camera_rotation():
	camera_pivot.rotation = Vector3.ZERO
	pitch_pivot.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.position = Vector3.ZERO
	update_camera_transform()

## Sensibilidad de la escena por el multiplicador de las opciones.
func _look_sensitivity() -> float:
	return mouse_sensitivity * SettingsManager.mouse_scale


func _input(event: InputEvent):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			and lock_point != null:
		_lock_swipe += -event.relative.x * _look_sensitivity()
	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		delta_yaw += -event.relative.x * _look_sensitivity()
		delta_pitch += -event.relative.y * _look_sensitivity() * (-1 if invert_y != SettingsManager.invert_y else 1)
	elif event is InputEventMouseButton and event.pressed:
		if not zoom_enabled:
			return
		if Input.is_action_pressed("left_ctrl") || Input.is_action_pressed("left_shift"):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = max(target_distance - zoom_speed, min_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = min(target_distance + zoom_speed, max_distance)

## Ratón horizontal acumulado con un objetivo fijado (radianes); se vacía al leerlo.
func consume_lock_swipe() -> float:
	var value := _lock_swipe
	_lock_swipe = 0.0
	return value


## Sacudida de cámara (golpes). Se suma y se apaga sola.
func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 0.6)


## Con objetivo fijado, gira yaw y pitch hacia él (control proporcional: en una esfera el yaw no
## es un ángulo absoluto, así que se corrige por la diferencia que se ve cada frame).
func _track_lock_point() -> void:
	var player = get_parent()
	var up: Vector3 = _current_up_axis
	var eye: Vector3 = player.global_position + up * target_height_offset
	var to: Vector3 = (lock_point as Vector3) - eye
	var to_h := to - up * to.dot(up)
	# El PitchPivot de la escena va girado 180°: la cámara mira hacia -Z del pivote de yaw.
	var cur := -camera_pivot.global_basis.z
	cur = cur - up * cur.dot(up)
	if to_h.length_squared() > 0.01 and cur.length_squared() > 1e-6:
		to_h = to_h.normalized()
		cur = cur.normalized()
		var angle := atan2(up.dot(cur.cross(to_h)), cur.dot(to_h))
		yaw += angle * 0.18
		camera_pivot.rotation.y = yaw
	var dist := to.length()
	# Algo por encima del objetivo, más cuanto más cerca (encuadra la cabeza del oso sin
	# tapar al personaje).
	# Hasta el límite normal de la cámara: un ave fijada puede ir muy por encima.
	var desired := clampf(asin(clampf(to.normalized().dot(up), -1.0, 1.0)) - lerpf(0.32, 0.14, clampf(dist / 20.0, 0.0, 1.0)), min_pitch, max_pitch)
	pitch = lerpf(pitch, desired, 0.12)


func update_camera_rotation():
	if lock_point != null:
		_track_lock_point()
		delta_yaw = 0.0
		delta_pitch = 0.0
	if delta_yaw != 0.0:
		yaw += delta_yaw
		camera_pivot.rotation.y = yaw
	if delta_pitch != 0.0:
		pitch = clamp(pitch + delta_pitch, min_pitch, max_pitch)
		pitch_pivot.rotation.x = pitch

	camera_distance = lerp(camera_distance, target_distance, 0.15)

	if not first_person and camera_distance <= fp_threshold:
		first_person = true
		player_model.visible = false
	elif first_person and camera_distance > fp_threshold + 0.5:
		first_person = false
		player_model.visible = true

	update_camera_transform()
	delta_yaw = 0.0
	delta_pitch = 0.0

func update_camera_transform():
	var player = get_parent()
	var player_pos = player.global_position
	var target_up: Vector3
	if player._platform_body and is_instance_valid(player._platform_body):
		target_up = player._platform_body.global_transform.basis.y.normalized()
		var current_platform_basis: Basis = player._platform_body.global_transform.basis
		if _tracking_platform == player._platform_body:
			var prev_forward := _prev_platform_basis.z
			var curr_forward := current_platform_basis.z
			prev_forward = (prev_forward - target_up * prev_forward.dot(target_up)).normalized()
			curr_forward = (curr_forward - target_up * curr_forward.dot(target_up)).normalized()
			var cross := prev_forward.cross(curr_forward)
			var dot := prev_forward.dot(curr_forward)
			var yaw_delta := atan2(cross.dot(target_up), dot)
			yaw += yaw_delta
		_tracking_platform = player._platform_body
		_prev_platform_basis = current_platform_basis
	else:
		target_up = -player.gravity_direction.normalized()

	_current_up_axis = _current_up_axis.slerp(target_up, 0.01)
	var up_axis = _current_up_axis
		
	camera_pivot.global_position = player_pos
	camera_pivot.global_transform.basis = Basis(up_axis, yaw)

	var current_up = camera_pivot.global_transform.basis.y
	if current_up.dot(up_axis) < 0.999:
		var align_axis = current_up.cross(up_axis)
		if align_axis.length() > 0.001:
			var align_angle = acos(clamp(current_up.dot(up_axis), -1.0, 1.0))
			camera_pivot.global_transform.basis = Basis(align_axis.normalized(), align_angle) * camera_pivot.global_transform.basis

	pitch_pivot.rotation.x = -pitch

	_aim = move_toward(_aim, aim_target, 0.08)
	var aim_ease := _aim * _aim * (3.0 - 2.0 * _aim)
	if _base_fov < 0.0:
		_base_fov = camera.fov
	camera.fov = _base_fov - aim_fov_drop * aim_ease * (0.55 + 0.45 * aim_zoom)
	_shake = maxf(0.0, _shake - 0.02)

	if first_person:
		camera.global_position = player_pos + up_axis * fp_eye_height
		var fp_forward = pitch_pivot.global_transform.basis * Vector3.BACK
		camera.look_at(camera.global_position + fp_forward, up_axis)
	else:
		var orbit_dir = -pitch_pivot.global_transform.basis.z
		var target_pos = player_pos + up_axis * target_height_offset
		# Apuntando: el encuadre se corre al hombro derecho y se acerca.
		if aim_ease > 0.0:
			var right: Vector3 = camera.global_transform.basis.x
			target_pos += right * aim_shoulder * aim_ease + up_axis * 0.1 * aim_ease
		var distance := lerpf(camera_distance, minf(camera_distance, aim_distance), aim_ease)
		var ideal_pos = target_pos + orbit_dir * distance
		var final_pos = adjust_for_collisions(target_pos, ideal_pos)
		if _shake > 0.0:
			var t := Time.get_ticks_msec() * 0.001
			final_pos += (camera_pivot.global_transform.basis.x * sin(t * 71.0) + up_axis * sin(t * 83.0 + 1.3)) * _shake * 0.12
		camera.global_position = final_pos
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
