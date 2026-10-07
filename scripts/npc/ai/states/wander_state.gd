extends AIState
class_name WanderState

## El NPC elige un punto aleatorio en la superficie del planeta y camina hacia él.
## Vuelve a IdleState al llegar o al agotar el tiempo máximo.
## Si detecta una amenaza (controller.target dentro del radio) pasa a threat_state (huir, por defecto).

## Distancia máxima del punto de destino respecto a la posición actual.
@export var wander_radius: float = 10.0
## Distancia a la que se considera que el NPC ha llegado al destino.
@export var arrival_threshold: float = 1.0
## Timeout de seguridad para evitar quedarse atascado.
@export var max_wander_time: float = 10.0
## Si > 0, deambula alrededor de su casa (NPCController.get_home()) sin salirse de este radio, en
## vez de ir a la deriva: una manada que comparte casa no se dispersa.
@export var home_radius: float = 0.0
## Radio de detección de amenaza. 0 = sin detección.
@export var flee_trigger_radius: float = 10.0
## Estado al que pasa cuando la amenaza entra en ese radio (huir; defender su territorio…).
@export var threat_state: StringName = &"FleeState"

var _target_pos: Vector3
var _timer: float = 0.0
var _last_dir: Vector3 = Vector3.ZERO


func enter() -> void:
	_target_pos = _pick_wander_target()
	_timer = max_wander_time
	_last_dir = Vector3.ZERO


func update(delta: float) -> StringName:
	if flee_trigger_radius > 0.0 and controller.is_target_within(flee_trigger_radius):
		return threat_state

	_timer -= delta
	if _timer <= 0.0:
		return &"IdleState"

	if controller.is_in_water(controller.npc.global_position):
		var escape := controller.steer_clear_of_water(
			_last_dir if _last_dir.length() > 0.1 else Vector3.FORWARD
		)
		controller.desired_direction = escape
		return &""

	if controller.is_in_water(_target_pos):
		_target_pos = _pick_wander_target()
		if _target_pos == controller.npc.global_position:
			return &"IdleState"

	var to_target := _target_pos - controller.npc.global_position

	if to_target.length() <= arrival_threshold:
		return &"IdleState"

	var dir := controller.project_on_gravity_plane(to_target)
	if dir == Vector3.ZERO:
		return &"IdleState"

	if _last_dir.length() > 0.1 and _last_dir.dot(dir) < 0.0:
		return &"IdleState"

	_last_dir = dir
	controller.desired_direction = controller.steer_clear_of_water(dir)
	return &""


func exit() -> void:
	controller.desired_direction = Vector3.ZERO


## Elige un punto aleatorio dentro de wander_radius en el plano de gravedad, evitando el agua (8 intentos).
func _pick_wander_target() -> Vector3:
	var up  := -controller.gravity_direction.normalized()
	var ref := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := up.cross(ref).normalized()
	var fwd   := right.cross(up).normalized()

	var center := controller.npc.global_position
	var npc := controller.npc as NPCController
	var home := npc.get_home() if home_radius > 0.0 and npc != null else Vector3.INF
	for _i in range(8):
		var angle := randf_range(0.0, TAU)
		var dir   := (right * cos(angle) + fwd * sin(angle)).normalized()
		var candidate := center + dir * randf_range(wander_radius * 0.4, wander_radius)
		if home != Vector3.INF:
			candidate = home + dir * home_radius * sqrt(randf())

		if not controller.is_in_water(candidate):
			return candidate
	return controller.npc.global_position
