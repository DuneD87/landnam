class_name CombatTargeting
extends RefCounted

## Selección, cambio lateral y pérdida del objetivo fijado. Actualiza el punto de la cámara
## y expone el blanco al combate y al HUD, sin llevar los estados del ataque.

const LOCK_RANGE := 28.0
const LOCK_BREAK_RANGE := 34.0
## Ratón acumulado (radianes de giro de cámara) para cambiar de objetivo fijado.
const LOCK_SWITCH_THRESHOLD := 0.09
## Penalización de puntuación de la fauna menuda (aves, conejos, peces) frente a los NPCs: con un
## oso y un gorrión en el mismo encuadre, se fija el oso.
const LOCK_SMALL_FAUNA_BIAS := 0.35

var player: PlayerController
var target: Node3D
var _lock_lost_time := 0.0
var _lock_switch_cooldown := 0.0


func lock_on() -> void:
	var found := _find_lock_target(0.0)
	if found != null:
		target = found
		_lock_lost_time = 0.0
		CombatFx.play(&"lock", player.global_position)


func release() -> void:
	target = null
	player.camera_controller.lock_point = null


func point_for(target: Node3D) -> Vector3:
	var creature := target as AmbientAnimal
	if creature != null:
		return creature.lock_point()
	return target.global_position - player.gravity_direction * 0.8


## Cualquier criatura viva (NPCs, aves, fauna menuda) se puede fijar.
func is_lockable(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var creature := target as AmbientAnimal
	return creature != null and creature.lockable()


## Velocidad del objetivo para adelantar el tiro: sin ella, un ave en vuelo es imposible de acertar.
func velocity_of(target: Node3D) -> Vector3:
	var body := target as CharacterBody3D
	return body.velocity if body != null else Vector3.ZERO


## Mejor candidato: el más centrado en pantalla y cerca. [side] != 0 busca solo a ese lado del
## objetivo actual (−1 izquierda, +1 derecha).
func _find_lock_target(side: float) -> Node3D:
	var cam := player.camera
	var cam_forward := -cam.global_basis.z
	var cam_right := cam.global_basis.x
	var best: Node3D = null
	var best_score := INF
	var current_x := 0.0
	if target != null:
		current_x = (point_for(target) - cam.global_position).normalized().dot(cam_right)
	for node in player.get_tree().get_nodes_in_group(AmbientAnimal.GROUP):
		var creature := node as AmbientAnimal
		if not is_lockable(creature) or creature == target:
			continue
		var point := point_for(creature)
		var dist := player.global_position.distance_to(point)
		if dist > LOCK_RANGE:
			continue
		var to := (point - cam.global_position).normalized()
		var facing := to.dot(cam_forward)
		if facing < 0.35:
			continue
		var x := to.dot(cam_right)
		if side != 0.0 and signf(x - current_x) != signf(side):
			continue
		if not _has_line_of_sight(point, creature):
			continue
		var score := acos(clampf(facing, -1.0, 1.0)) * 2.0 + dist / LOCK_RANGE
		if side != 0.0:
			score = absf(x - current_x) * 3.0 + dist / LOCK_RANGE
		if not creature is NPCController:
			score += LOCK_SMALL_FAUNA_BIAS
		if score < best_score:
			best_score = score
			best = creature
	return best


func _has_line_of_sight(point: Vector3, target: Node) -> bool:
	var from := player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, point)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target


func update(delta: float) -> void:
	_lock_switch_cooldown = maxf(0.0, _lock_switch_cooldown - delta)
	if not is_instance_valid(target):
		target = null
	if target == null:
		player.camera_controller.lock_point = null
		return
	var npc := target as NPCController
	if not is_lockable(target) or player.global_position.distance_to(target.global_position) > LOCK_BREAK_RANGE:
		release()
		# Si cae uno, se pasa al siguiente como en los souls.
		if npc != null and npc.is_dead:
			lock_on()
		return
	var point := point_for(target)
	if _has_line_of_sight(point, target):
		_lock_lost_time = 0.0
	else:
		_lock_lost_time += delta
		if _lock_lost_time > 2.0:
			release()
			return
	player.camera_controller.lock_point = point
	var swipe := player.camera_controller.consume_lock_swipe()
	if absf(swipe) > LOCK_SWITCH_THRESHOLD and _lock_switch_cooldown <= 0.0:
		var next := _find_lock_target(-signf(swipe))
		if next != null:
			target = next
			_lock_switch_cooldown = 0.35
