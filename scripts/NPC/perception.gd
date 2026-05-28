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

## Asignar desde NPCController._ready().
var npc: CharacterBody3D
## Asignar desde NPCController._ready().
var controller: AIController

var _detected: Node3D = null
var _timer: float = 0.0


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
	for candidate in get_tree().get_nodes_in_group("player"):
		if candidate is Node3D and _can_detect(candidate as Node3D):
			return candidate as Node3D
	return null


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
