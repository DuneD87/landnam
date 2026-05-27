extends AIState
class_name FleeState

## El NPC huye de controller.target en dirección opuesta proyectada en la superficie.
## Deja de huir cuando el target supera [member safe_distance] o se agota [member max_flee_time].

## Distancia al target a partir de la cual el NPC se considera a salvo.
@export var safe_distance: float = 20.0
## Tiempo máximo de huida continua (evita loops infinitos si el NPC queda atrapado).
@export var max_flee_time: float = 8.0
## Multiplicador de velocidad durante la huida. Se restaura en exit().
@export var speed_multiplier: float = 1.6

var _timer: float = 0.0
var _original_speed: float = 0.0


func enter() -> void:
	_timer = max_flee_time
	# Guardar velocidad base y aplicar boost de huida
	_original_speed = controller.movement.speed
	controller.movement.speed = _original_speed * speed_multiplier


func update(delta: float) -> StringName:
	_timer -= delta

	# Condiciones de parada: a salvo, timeout o target inválido
	if _timer <= 0.0 or not controller.is_target_within(safe_distance):
		return &"IdleState"

	# Dirección de huida: opuesta al target, proyectada en el plano de gravedad
	if is_instance_valid(controller.target):
		var away := controller.npc.global_position - controller.target.global_position
		controller.desired_direction = controller.project_on_gravity_plane(away)

	return &""


func exit() -> void:
	# Restaurar velocidad original
	controller.movement.speed = _original_speed
	controller.desired_direction = Vector3.ZERO
