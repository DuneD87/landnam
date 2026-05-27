extends Node
class_name AIController

## Máquina de estados finita (FSM) para NPCs.
##
## Flujo de uso desde NPCController:
##   1. En _ready(): asignar [member npc], [member movement] y [member gravity_direction].
##   2. Llamar [method start] con el estado inicial.
##   3. En _physics_process(delta): actualizar [member gravity_direction], llamar
##      [method update] y luego leer [member desired_direction] para inyectarlo en
##      movement.ai_direction.
##
## Los estados ([AIState]) se añaden como nodos hijo en la escena y se registran
## automáticamente en _ready() por su nombre de nodo.

## Referencia al CharacterBody3D del NPC. Asignar desde NPCController._ready().
var npc: CharacterBody3D

## Referencia al componente Movement del NPC. Asignar desde NPCController._ready().
var movement: Movement

## Dirección de gravedad actualizada cada frame por NPCController.
## Los estados la usan para proyectar direcciones sobre la superficie del planeta.
var gravity_direction: Vector3 = Vector3.DOWN

## Dirección de movimiento deseada calculada por el estado activo (normalizada,
## proyectada sobre el plano de gravedad). NPCController la lee y la inyecta en
## movement.ai_direction cada frame.
var desired_direction: Vector3 = Vector3.ZERO

## Target actual (jugador, amenaza, punto de wander…). Los estados lo leen y escriben.
var target: Node3D = null

var _states: Dictionary = {}       # StringName → AIState
var _current_state: AIState = null
var _current_state_name: StringName = &""


func _ready() -> void:
	# Auto-registrar todos los hijos que sean AIState
	for child in get_children():
		if child is AIState:
			child.controller = self
			_states[StringName(child.name)] = child


## Arranca la FSM con el estado inicial. Llamar desde NPCController._ready()
## una vez que npc y movement estén asignados.
func start(initial_state: StringName) -> void:
	if not _states.has(initial_state):
		push_error("AIController: estado inicial '%s' no encontrado. ¿Está añadido como nodo hijo?" % initial_state)
		return
	_current_state_name = initial_state
	_current_state = _states[initial_state]
	_current_state.enter()


## Llamar desde NPCController._physics_process(delta).
## Actualiza el estado activo y gestiona transiciones.
func update(delta: float) -> void:
	if not _current_state:
		return

	desired_direction = Vector3.ZERO  # el estado activo lo sobreescribe si procede

	var next := _current_state.update(delta)
	if next != &"":
		transition_to(next)


## Fuerza una transición inmediata al estado indicado.
## Los estados también pueden llamarlo directamente via controller.transition_to().
func transition_to(state_name: StringName) -> void:
	if state_name == _current_state_name:
		return
	if not _states.has(state_name):
		push_warning("AIController: intento de transición a estado desconocido '%s'" % state_name)
		return

	if _current_state:
		_current_state.exit()

	_current_state_name = state_name
	_current_state = _states[state_name]
	_current_state.enter()


## Helpers de conveniencia para los estados ----------

## Devuelve el nombre del estado activo.
func get_current_state() -> StringName:
	return _current_state_name


## Proyecta [param dir] sobre el plano perpendicular a gravity_direction.
## Útil para que los estados calculen direcciones de movimiento en superficie esférica.
func project_on_gravity_plane(dir: Vector3) -> Vector3:
	var n := gravity_direction.normalized()
	var projected := dir - n * dir.dot(n)
	if projected.length() < 0.001:
		return Vector3.ZERO
	return projected.normalized()


## Devuelve true si hay target asignado y está dentro de [param radius] metros.
func is_target_within(radius: float) -> bool:
	if not target or not is_instance_valid(target):
		return false
	return npc.global_position.distance_to(target.global_position) <= radius


## Devuelve la distancia al target, o INF si no hay target.
func distance_to_target() -> float:
	if not target or not is_instance_valid(target):
		return INF
	return npc.global_position.distance_to(target.global_position)
