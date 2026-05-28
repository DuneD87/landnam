extends AIState
class_name IdleState

## El NPC se queda quieto un tiempo aleatorio y luego deambula.
## Si detecta una amenaza (controller.target dentro del radio) huye.

## Duración mínima del estado idle (segundos).
@export var min_idle_time: float = 2.0
## Duración máxima del estado idle (segundos).
@export var max_idle_time: float = 6.0
## Radio de detección de amenaza. 0 = sin detección.
@export var flee_trigger_radius: float = 10.0

var _timer: float = 0.0


func enter() -> void:
	_timer = randf_range(min_idle_time, max_idle_time)
	controller.desired_direction = Vector3.ZERO
	controller.movement.direction = Vector3.ZERO


func update(delta: float) -> StringName:
	# Amenaza detectada → huir
	if flee_trigger_radius > 0.0 and controller.is_target_within(flee_trigger_radius):
		return &"FleeState"

	_timer -= delta
	if _timer <= 0.0:
		return &"WanderState"

	return &""


func exit() -> void:
	pass
