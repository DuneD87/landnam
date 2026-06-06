extends Node
class_name Perception

## Detecta objetivos (jugador, amenazas) mediante dos zonas:
##  - Visión: cono estrecho de largo alcance, con comprobación opcional de LOS.
##  - Oído:   esfera omnidireccional de corto alcance.
##
## Uso desde NPCController._ready():
##   perception.npc = self
##   perception.controller = ai_controller
##
## Los estados de la FSM (FleeState, ChaseState…) reaccionan a controller.target,
## que este componente asigna y limpia automáticamente.

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

@export_group("Hearing")
@export var hearing_range: float = 4.0

@export_group("Performance")
## Segundos entre comprobaciones. 0.1-0.3 es suficiente para la mayoría de NPCs.
@export var check_interval: float = 0.2

@export_group("NPC Detection")
## Tipos de NPC que este NPC percibe como amenaza. Vacío = solo detecta al jugador.
## Ej: un oso con ["deer"] atacará ciervos; un ciervo con ["bear"] huirá de osos.
@export var hostile_npc_types: Array[StringName] = []
## Si es false, el jugador no es detectado como amenaza.
@export var detect_player: bool = true

## Asignar desde NPCController._ready().
var npc: CharacterBody3D
## Asignar desde NPCController._ready().
var controller: AIController

var _detected: Node3D = null
var _timer: float = 0.0
var _player_cache: Node3D = null


func _ready() -> void:
	# Cachear referencia al player una sola vez en vez de escanear el árbol cada tick.
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node3D:
		_player_cache = players[0]


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = check_interval

	if not npc or not controller:
		return

	var found := _scan()

	if found and found != _detected:
		_detected = found
		controller.target = found
		target_detected.emit(found)
	elif not found and _detected:
		_detected = null
		controller.target = null
		target_lost.emit()


func _scan() -> Node3D:
	if detect_player and is_instance_valid(_player_cache) and _can_detect(_player_cache):
		return _player_cache

	if hostile_npc_types.is_empty():
		return null

	var best: Node3D = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node) or node == npc:
			continue
		var other := node as NPCController
		if not other or other.is_dead or other.npc_type not in hostile_npc_types:
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

	var to_target := target.global_position - npc.global_position
	var dist := to_target.length()

	# Oído: esfera omnidireccional
	if dist <= hearing_range:
		return true

	# Visión: cono orientado hacia el frente del NPC
	if dist <= vision_range:
		var dir := to_target / dist
		var forward := -npc.global_transform.basis.z
		var angle_deg := rad_to_deg(acos(clamp(forward.dot(dir), -1.0, 1.0)))
		if angle_deg <= vision_half_angle:
			if not check_line_of_sight or _has_los(target):
				return true

	return false


func _has_los(target: Node3D) -> bool:
	var space := npc.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		npc.global_position, target.global_position
	)
	query.exclude = [npc.get_rid()]
	query.collision_mask = los_mask
	var result := space.intersect_ray(query)
	# Vacío: camino libre. Colisiona con el propio target: también libre.
	return result.is_empty() or result.get("collider") == target
