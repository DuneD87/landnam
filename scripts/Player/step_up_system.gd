class_name StepUpSystem
extends Node

@export var max_step_height: float = 0.55
@export var step_margin: float = 0.02
@export var step_speed: float = 12.0

var _body: CharacterBody3D
var _collision_shape: CollisionShape3D

var _stepping: bool = false
var _step_target: Vector3 = Vector3.ZERO
var _step_up_dir: Vector3 = Vector3.UP
var _step_timer: float = 0.0

const STEP_TIMEOUT := 0.2


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	for child in _body.get_children():
		if child is CollisionShape3D:
			_collision_shape = child
			break


func try_step_up(delta: float, gravity_dir: Vector3, intended_velocity: Vector3) -> bool:
	_step_up_dir = -gravity_dir.normalized()

	if _stepping:
		_step_timer += delta
		if _step_timer > STEP_TIMEOUT:
			_stepping = false
			_step_timer = 0.0
			return false
		_apply_step_lerp(delta)
		return true

	if not _body.is_on_floor():
		return false

	var up := _step_up_dir
	var intended_h := intended_velocity - up * intended_velocity.dot(up)
	var real_h := _body.get_real_velocity() - up * _body.get_real_velocity().dot(up)

	if intended_h.length() < 0.1:
		return false

	var speed_ratio := real_h.length() / intended_h.length()
	if speed_ratio > 0.7:
		return false

	var move_dir := intended_h.normalized()
	var space_state := _body.get_world_3d().direct_space_state
	var shape: Shape3D = _collision_shape.shape
	var body_transform := _body.global_transform

	# 1. Obstacle davant?
	var foot_check := _cast_shape(space_state, shape, body_transform, move_dir, 0.3)
	if foot_check.is_empty():
		return false

	# 2. Pujar — comprovar sostre
	var raised_transform := body_transform
	var ceiling_check := _cast_shape(space_state, shape, body_transform, up, max_step_height)
	if not ceiling_check.is_empty():
		var ceiling_dist: float = ceiling_check.get("travel", Vector3.ZERO).length()
		if ceiling_dist < step_margin:
			return false
		raised_transform.origin = body_transform.origin + up * (ceiling_dist - step_margin)
	else:
		raised_transform.origin = body_transform.origin + up * max_step_height

	# 3. Avançar des de posició elevada
	var forward_raised := _cast_shape(space_state, shape, raised_transform, move_dir, 0.3)
	if not forward_raised.is_empty():
		var travel_dist: float = forward_raised.get("travel", Vector3.ZERO).length()
		if travel_dist < step_margin:
			return false

	# 4. Baixar per trobar terra
	var forward_pos := raised_transform
	forward_pos.origin += move_dir * 0.15
	var down_check := _cast_shape(space_state, shape, forward_pos, -up, max_step_height + 0.1)

	if down_check.is_empty():
		return false

	var land_pos: Vector3 = forward_pos.origin + down_check.get("travel", Vector3.ZERO)

	# 5. Verificar que hem PUJAT
	var height_gained := (land_pos - body_transform.origin).dot(up)
	if height_gained < step_margin or height_gained > max_step_height:
		return false

	# 6. Iniciar step-up suau
	_step_target = land_pos + up * step_margin
	_stepping = true
	_step_timer = 0.0
	_apply_step_lerp(delta)

	return true


func _apply_step_lerp(delta: float) -> void:
	var up := _step_up_dir
	var current := _body.global_position
	var target := _step_target

	var current_height := current.dot(up)
	var target_height := target.dot(up)
	var diff := target_height - current_height

	if diff < step_margin:
		_stepping = false
		_step_timer = 0.0
		return

	var step_amount := step_speed * delta
	var new_height := current_height + minf(step_amount, diff)
	_body.global_position = current + up * (new_height - current_height)

	if (target_height - new_height) < step_margin:
		_stepping = false
		_step_timer = 0.0


func _cast_shape(space_state: PhysicsDirectSpaceState3D, shape: Shape3D,
				 from: Transform3D, direction: Vector3, distance: float) -> Dictionary:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = from
	params.motion = direction * distance
	params.collision_mask = _body.collision_mask
	params.exclude = [_body.get_rid()]
	params.margin = 0.01

	var result := space_state.cast_motion(params)

	if result[0] >= 1.0:
		return {}

	var travel := direction * distance * result[0]
	return { "travel": travel, "safe": result[0], "unsafe": result[1] }
