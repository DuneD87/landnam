extends Node
class_name AIController

## Máquina de estados finita (FSM) para NPCs. Los estados (AIState) se añaden como nodos hijo y se
## auto-registran por su nombre; cada frame update() avanza el estado activo y gestiona transiciones.
## Expone helpers para los estados: proyección sobre la gravedad, distancias al target y evitar agua.

## Velocidad con la que el cuerpo aún gira hacia desired_direction casi sin desplazarse.
const TURN_ONLY_SPEED := 0.01

var npc: CharacterBody3D
var movement: Movement
var gravity_direction: Vector3 = Vector3.DOWN
var desired_direction: Vector3 = Vector3.ZERO
## Hacia dónde quiere mirar el cuerpo cuando no es hacia donde anda (seguir al objetivo durante un
## golpe, encararlo mientras se mueve de lado). ZERO = hacia donde anda. Se limpia en cada update().
var desired_facing: Vector3 = Vector3.ZERO
## Giro máximo hacia desired_facing, en grados/s. 0 = el giro normal del cuerpo.
var turn_rate: float = 0.0
var target: Node3D = null
var is_attacking: bool = false
## Velocidad del objetivo (m/s), medida de una actualización de IA a la siguiente.
var target_velocity: Vector3 = Vector3.ZERO

var _tracked: Node3D = null
var _tracked_pos: Vector3 = Vector3.ZERO

var _states: Dictionary = {}
var _current_state: AIState = null
var _current_state_name: StringName = &""


func _ready() -> void:
	for child in get_children():
		if child is AIState:
			child.controller = self
			_states[StringName(child.name)] = child


## Arranca la FSM con el estado inicial (tras asignar npc y movement).
func start(initial_state: StringName) -> void:
	if not _states.has(initial_state):
		push_error("AIController: estado inicial '%s' no encontrado. ¿Está añadido como nodo hijo?" % initial_state)
		return
	_current_state_name = initial_state
	_current_state = _states[initial_state]
	_current_state.enter()


## Avanza el estado activo y gestiona transiciones. Llamar desde NPCController._physics_process.
func update(delta: float) -> void:
	if not _current_state:
		return

	desired_direction = Vector3.ZERO
	desired_facing = Vector3.ZERO
	turn_rate = 0.0
	_track_target(delta)

	var next := _current_state.update(delta)
	if next != &"":
		transition_to(next)


## Fuerza una transición inmediata al estado indicado.
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


## Devuelve el nombre del estado activo.
func get_current_state() -> StringName:
	return _current_state_name


## Proyecta dir sobre el plano perpendicular a gravity_direction.
func project_on_gravity_plane(dir: Vector3) -> Vector3:
	var n := gravity_direction.normalized()
	var projected := dir - n * dir.dot(n)
	if projected.length() < 0.001:
		return Vector3.ZERO
	return projected.normalized()


## Devuelve true si hay target asignado y está dentro de radius metros.
func is_target_within(radius: float) -> bool:
	if not target or not is_instance_valid(target):
		return false
	return npc.global_position.distance_to(target.global_position) <= radius


## Devuelve la distancia al target, o INF si no hay target.
func distance_to_target() -> float:
	if not target or not is_instance_valid(target):
		return INF
	return npc.global_position.distance_to(target.global_position)


## Dónde estará el objetivo dentro de [seconds] si sigue como va, sin pasar de [max_offset] metros
## de donde está.
func predicted_target_position(seconds: float, max_offset: float = 4.0) -> Vector3:
	if not target or not is_instance_valid(target):
		return npc.global_position
	return target.global_position + (target_velocity * seconds).limit_length(max_offset)


func _track_target(delta: float) -> void:
	if not target or not is_instance_valid(target):
		_tracked = null
		target_velocity = Vector3.ZERO
		return
	var pos := target.global_position
	if target != _tracked or delta <= 0.0:
		target_velocity = Vector3.ZERO
	else:
		# Suavizado: un tirón de un fotograma (rebase del origen, un golpe) no es una carrera.
		var measured := (pos - _tracked_pos) / delta
		if measured.length() < 40.0:
			target_velocity = target_velocity.lerp(measured, clampf(delta * 8.0, 0.0, 1.0))
	_tracked = target
	_tracked_pos = pos


## Devuelve true si pos está sumergida en el agua del planeta del NPC.
func is_in_water(pos: Vector3) -> bool:
	var p := _get_planet()
	if not p or not p.has_water:
		return false
	return pos.distance_to(p.global_position) <= (p.radius - p.water_radius)


## Margen de elevación sobre el nivel del agua por debajo del cual se activan los raycasts de agua.
@export var water_check_margin: float = 20.0

var _planet_has_water: bool = false
var _planet_water_checked: bool = false

## Devuelve la instancia Planet del NPC, o null.
func _get_planet() -> Planet:
	if not npc is NPCController:
		return null
	var loader = (npc as NPCController).planet
	if not loader:
		return null
	return loader.planet

## Devuelve true si el NPC está cerca del nivel del agua (chequeo geométrico, sin raycast).
func _near_water_zone() -> bool:
	var p := _get_planet()
	if not _planet_water_checked:
		_planet_has_water = p != null and p.has_water
		_planet_water_checked = true
	if not _planet_has_water or not p:
		return false
	var npc_height := npc.global_position.distance_to(p.global_position)
	var water_surface := p.radius - p.water_radius
	return npc_height <= water_surface + water_check_margin


## Raycast vertical desde surface_pos para comprobar si estaría sumergido (tras _near_water_zone()).
func _probe_in_water(surface_pos: Vector3) -> bool:
	var p := _get_planet()
	if not p:
		return false
	var up := -gravity_direction.normalized()
	var space_state := npc.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		surface_pos + up * 50.0,
		surface_pos - up * 100.0
	)
	query.exclude = [npc.get_rid()]
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return hit.position.distance_to(p.global_position) <= (p.radius - p.water_radius)


## Escanea 8 direcciones con radios crecientes para hallar la tierra más cercana; ZERO si no hay salida.
func _find_water_exit(origin: Vector3, base_lookahead: float) -> Vector3:
	var up  := -gravity_direction.normalized()
	var ref := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := up.cross(ref).normalized()
	var fwd   := right.cross(up).normalized()
	for dist in [base_lookahead * 0.5, base_lookahead, base_lookahead * 3.0, base_lookahead * 7.0]:
		for i in range(8):
			var angle := i * PI * 0.25
			var d := (right * cos(angle) + fwd * sin(angle)).normalized()
			if not _probe_in_water(origin + d * dist):
				return project_on_gravity_plane(d)
	return Vector3.ZERO


## Redirige dir para evitar el agua; si el NPC ya está en agua, busca la salida más cercana.
func steer_clear_of_water(dir: Vector3, lookahead: float = 4.0) -> Vector3:
	if dir == Vector3.ZERO or not _near_water_zone():
		return dir
	var origin := npc.global_position
	if is_in_water(origin):
		var exit := _find_water_exit(origin, lookahead)
		return exit if exit != Vector3.ZERO else dir
	if not _probe_in_water(origin + dir * lookahead):
		return dir
	var far  := lookahead * 5.0
	var up   := -gravity_direction.normalized()
	var perp := dir.cross(up).normalized()
	for i in range(1, 5):
		var a     := i * PI * 0.25
		var dir_l := (dir * cos(a) - perp * sin(a)).normalized()
		var dir_r := (dir * cos(a) + perp * sin(a)).normalized()
		if not _probe_in_water(origin + dir_l * far):
			return project_on_gravity_plane(dir_l)
		if not _probe_in_water(origin + dir_r * far):
			return project_on_gravity_plane(dir_r)
	return dir
