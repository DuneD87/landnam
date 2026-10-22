extends Node

## Ritmo del mundo compartido por el sol, las necesidades, el clima, las hogueras y los estados.
## La física, el movimiento, las animaciones y la interfaz conservan su ritmo normal.
const DEFAULT_DAY_SECONDS := 3600.0
const MAX_SPEED := 120.0

var _base_speed := 1.0
var _requests: Dictionary = {}

var speed: float:
	get:
		var result := _base_speed
		for id: int in _requests.keys():
			if not is_instance_id_valid(id):
				_requests.erase(id)
			else:
				result = maxf(result, _requests[id])
		return result


func set_speed(value: float) -> void:
	if is_finite(value):
		_base_speed = clampf(value, 1.0, MAX_SPEED)


## Aceleración temporal: al terminar de dormir se retira solo la petición de quien dormía.
func request_speed(owner_node: Node, value: float) -> void:
	if owner_node != null and is_finite(value):
		_requests[owner_node.get_instance_id()] = clampf(value, 1.0, MAX_SPEED)


func release_speed(owner_node: Node) -> void:
	if owner_node != null:
		_requests.erase(owner_node.get_instance_id())


func reset() -> void:
	_base_speed = 1.0
	_requests.clear()


func scaled_delta(delta: float) -> float:
	return delta * speed


func calendar() -> Node:
	return get_tree().get_first_node_in_group("sun_controller")


## Segundos a ritmo normal por vuelta del sol: cambiar su rotación cambia también la jornada.
func day_seconds() -> float:
	var sun := calendar()
	if sun == null:
		return DEFAULT_DAY_SECONDS
	return 360.0 / maxf(absf(float(sun.rotation_speed_deg)), 0.0001)


func hours_elapsed(delta: float) -> float:
	var sun := calendar()
	if sun != null and not sun.auto_rotate:
		return 0.0
	return scaled_delta(delta) / day_seconds() * 24.0


func is_clock_running() -> bool:
	var sun := calendar()
	return sun != null and sun.auto_rotate and absf(float(sun.rotation_speed_deg)) > 0.0001
