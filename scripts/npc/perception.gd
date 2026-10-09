extends Node
class_name Perception

## Detecta objetivos (jugador y NPCs hostiles) con un cono de visión (con LOS opcional) y una esfera
## de oído, asignando y limpiando controller.target y emitiendo target_detected / target_lost.
##   - El cono mira hacia donde mira el cuerpo (+Z) y la línea de visión va de los ojos al pecho.
##   - Al objetivo que ya tiene no lo pierde por girarse: mientras lo tenga a la vista (alcance y
##     línea de visión), lo sigue viendo aunque quede fuera del cono.
##   - Con memory_time, al perderlo no lo suelta enseguida: lo recuerda (controller.target_seen
##     apagado, AIController.last_seen_position) y lo busca; si no lo vuelve a ver, lo olvida.

signal target_detected(target: Node3D)
signal target_lost()

@export_group("Vision")
@export var vision_range: float = 15.0
## Semángulo del cono en grados (ángulo total = 2×). 20° → cono de 40°.
@export var vision_half_angle: float = 20.0
## Lanza un rayo para comprobar que no hay terreno bloqueando la visión.
@export var check_line_of_sight: bool = true
## Máscara de colisión para el raycast de LOS (debe incluir la capa del terreno).
@export_flags_3d_physics var los_mask: int = 1
## Altura de los ojos sobre los pies (m): de ahí sale la línea de visión, hacia el pecho del objetivo.
@export var eye_height: float = 1.0

@export_group("Hearing")
@export var hearing_range: float = 4.0

@export_group("Memory")
## Segundos que sigue tras un objetivo que ha dejado de percibir (va a donde lo vio por última vez y
## lo busca) antes de olvidarlo. 0 = lo olvida en cuanto lo pierde.
@export var memory_time: float = 0.0

@export_group("Performance")
## Segundos entre comprobaciones. 0.1-0.3 es suficiente para la mayoría de NPCs.
@export var check_interval: float = 0.2

@export_group("NPC Detection")
## Tipos de NPC que este percibe como amenaza. Vacío = solo detecta al jugador.
@export var hostile_npc_types: Array[StringName] = []
## Si es false, el jugador no es detectado como amenaza.
@export var detect_player: bool = true

var npc: CharacterBody3D
var controller: AIController

var _detected: Node3D = null
var _timer: float = 0.0
var _player_cache: Node3D = null


func _ready() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node3D:
		_player_cache = players[0]


func _physics_process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_physics_step(delta)
	DebugStats.report_cost(&"npc:vision", Time.get_ticks_usec() - _t0)


func _physics_step(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = check_interval

	if not npc or not controller:
		return

	# Con memoria, también recuerda al que le han puesto de objetivo (quien le ha herido): sabe de
	# dónde le vino el golpe aunque no lo vea.
	if memory_time > 0.0 and controller.target != null and controller.target != _detected \
			and is_instance_valid(controller.target):
		_detected = controller.target

	var found := _scan()

	# También si el estado soltó el objetivo (se rindió, se calmó) y lo sigue percibiendo: así los
	# estados que reaccionan por distancia (IdleState, WanderState) lo vuelven a tener.
	if found and (found != _detected or controller.target == null):
		_detected = found
		controller.target = found
		target_detected.emit(found)
	elif found:
		controller.target_seen = true
	elif _detected:
		if controller.target == _detected and controller.unseen_time < memory_time:
			controller.target_seen = false
		else:
			_detected = null
			controller.target = null
			target_lost.emit()


## Olvida al objetivo detectado sin avisar (reaparición del jugador: la criatura se calma).
func forget() -> void:
	_detected = null
	_timer = check_interval


func _scan() -> Node3D:
	if detect_player and is_instance_valid(_player_cache) and _can_detect(_player_cache):
		return _player_cache

	if hostile_npc_types.is_empty():
		return null

	var best: Node3D = null
	var best_dist: float = INF
	# Solo las criaturas en juego de las celdas cercanas (CreatureGrid), no el grupo "npc" entero.
	for other in CreatureGrid.near(npc.global_position, vision_range):
		if other == npc or other.is_dead or other.npc_type not in hostile_npc_types:
			continue
		var dist := npc.global_position.distance_to(other.global_position)
		if dist > vision_range:
			continue
		if _can_detect(other) and dist < best_dist:
			best = other
			best_dist = dist
	return best


func _can_detect(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.is_dead:
		return false

	var to_target := target.global_position - npc.global_position
	var dist := to_target.length()

	if dist <= hearing_range:
		return true

	if dist <= vision_range:
		# Al que ya tiene encarado no lo pierde por girarse.
		var engaged := target == _detected and controller.target == target
		var dir := to_target / maxf(dist, 0.001)
		var angle_deg := rad_to_deg(npc.global_basis.z.normalized().angle_to(dir))
		if engaged or angle_deg <= vision_half_angle:
			if not check_line_of_sight or _has_los(target):
				return true

	return false


func _has_los(target: Node3D) -> bool:
	var up := -controller.gravity_direction.normalized()
	var space := npc.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(npc.global_position + up * eye_height, _chest(target, up))
	query.exclude = [npc.get_rid()]
	query.collision_mask = los_mask
	var result := space.intersect_ray(query)
	return result.is_empty() or result.get("collider") == target


## Adónde mira para verlo: el centro de su cuerpo (el de su cápsula si lo dice), o un metro sobre
## sus pies.
static func _chest(target: Node3D, up: Vector3) -> Vector3:
	if target.has_method(&"get_lock_point"):
		return target.get_lock_point()
	return target.global_position + up
