class_name NpcDevouring
extends Devouring

## Un aldeano o un compañero muerto a manos de una fiera (Villager.die, Companion._die): como al jugador
## (Devouring), la fiera que lo ha matado y las que peleaban con él se lo comen y lo descuartizan, con
## sus gritos (con su voz: la de mujer si lo es) y el gore según SettingsManager.gore_level. Lo que
## cambia:
##   - sin cámara de cine, sin cartel ni saltarlo, y sin muñeco de trapo: el cuerpo cae con su animación
##     de muerte y, pasados BODY_DELAY s (o en cuanto la fiera llega a comer), sus restos (PlayerRemains,
##     npc) se copian de la pose en que ha quedado; en ese momento [on_built] le dice al que muere que
##     se esconda (el nodo se va después: los restos ya no lo necesitan);
##   - sin fiera que se lo coma (killer null, o una que no come carne) los restos se quedan igual, sin
##     despiece;
##   - acabado, a los SEAL_AFTER s los restos se quedan quietos para siempre y esto se va. Los restos no
##     se guardan en la partida (PlayerRemains.npc).

## Lo que tarda el cuerpo en quedarse en el suelo con la animación de muerte (s).
const BODY_DELAY := 1.6
## Acabado de comer, lo que tarda en dejar los restos quietos (s): las fieras comen un rato más.
const SEAL_AFTER := 20.0

var _victim: Node3D
var _frame: Node3D
var _female := false
var _gravity_vec := Vector3.DOWN * 9.8
var _on_built := Callable()
var _body_wait := 0.0


## Empieza: [victim] (el Villager o el Companion) ha muerto; su cuerpo es [skeleton], dentro de [frame]
## (el modelo: +Z adelante); [killer], la fiera que lo ha matado o null; [gravity], la de allí. [on_built]
## se llama cuando sus restos ya ocupan el sitio del cuerpo. null si no se puede (sin escena).
static func begin(victim: Node3D, skeleton: Skeleton3D, frame: Node3D, killer: NPCController, gravity: Vector3,
		female: bool, on_built := Callable()) -> NpcDevouring:
	var host := victim.get_tree().current_scene if victim.is_inside_tree() else null
	if host == null or skeleton == null:
		return null
	var feast := NpcDevouring.new()
	feast.name = "NpcDevouring"
	feast._victim = victim
	feast._skeleton = skeleton
	feast._frame = frame
	feast._female = female
	feast._gravity_vec = gravity
	feast._on_built = on_built
	host.add_child(feast)
	feast.start(killer)
	return feast


## Si [killer] puede comérselo: come carne, sigue vivo y está a menos de PlayerCombat.KILLER_RANGE de [at].
static func eats(killer: NPCController, at: Vector3) -> bool:
	return killer != null and is_instance_valid(killer) and killer.active and not killer.is_dead \
		and killer.feed_profile() != null and killer.global_position.distance_to(at) <= PlayerCombat.KILLER_RANGE


func start(killer: NPCController) -> void:
	_active = true
	_over = false
	_over_time = 0.0
	_progress = 0.0
	_idle = 0.0
	_bites = 0
	_screaming = true
	_plan.clear()
	_guts_done = false
	_body_wait = 0.0
	_pose_requested = false
	var at := _frame.global_transform
	# Junto a esto, no dentro: los restos se quedan cuando esto se va.
	remains = PlayerRemains.spawn(get_parent(), Transform3D(at.basis.orthonormalized(), at.origin), null, true)
	var feeders: Array[NPCController] = []
	if eats(killer, at.origin):
		_killer = killer
		feeders.append(killer)
		for node in CombatDirector.engaged(_victim):
			var npc := node as NPCController
			if feeders.size() >= MAX_FEEDERS:
				break
			if npc == null or npc == killer or not eats(npc, at.origin) \
					or npc.global_position.distance_to(at.origin) > PACK_RADIUS:
				continue
			feeders.append(npc)
	else:
		_screaming = false
	for npc in feeders:
		npc.feed_on.call_deferred(remains)
	set_process(true)


func skip() -> void:
	pass


func cancel() -> void:
	if not _active:
		return
	if is_instance_valid(remains):
		if remains.built:
			remains.seal()
		else:
			remains.queue_free()
	if is_instance_valid(_skeleton) and _skeleton.skeleton_updated.is_connected(_on_pose):
		_skeleton.skeleton_updated.disconnect(_on_pose)
	_active = false
	set_process(false)
	remains = null
	_killer = null
	queue_free()


func _process(delta: float) -> void:
	super._process(delta)
	if _over and _over_time >= SEAL_AFTER:
		cancel()


## El cuerpo cae con su animación: los restos se montan cuando ya está en el suelo (BODY_DELAY) o en
## cuanto una fiera se pone a comer, con la pose que tenga su esqueleto entonces. Se lee al actualizarse
## el esqueleto (con las proporciones y demás modificadores, como Devouring); si no llega, la que haya.
func _await_body(delta: float) -> void:
	_body_wait += delta
	if not is_instance_valid(_skeleton) or not is_instance_valid(_frame):
		cancel()
		return
	if not _pose_requested:
		if _body_wait < BODY_DELAY and remains.eating().is_empty():
			return
		_pose_requested = true
		_pose_wait = 0.0
		_skeleton.skeleton_updated.connect(_on_pose, CONNECT_ONE_SHOT)
		return
	_pose_wait += delta
	if _pose_wait >= POSE_TIMEOUT and _skeleton.skeleton_updated.is_connected(_on_pose):
		_skeleton.skeleton_updated.disconnect(_on_pose)
		_build(_read_pose())


func _build(pose: Array[Transform3D]) -> void:
	if not _active or not is_instance_valid(remains) or remains.built:
		return
	remains.build(_skeleton, pose, _frame, null, _gravity_vec, [])
	if _on_built.is_valid():
		_on_built.call()
	_duration = randf_range(EAT_TIME.x, EAT_TIME.y)
	_bite_timer = 0.3
	_scream_timer = 0.0
	_plan_tears()
	if _killer == null:
		# Nadie se lo come: se queda como ha caído.
		_finish()


func _watch(_point: Variant) -> void:
	pass


func _voice(id: StringName) -> StringName:
	if _female:
		var female := StringName(String(id) + "_female")
		if CombatFx.has_sound(female):
			return female
	return id


func _is_severed(_zone: StringName) -> bool:
	return false


func _up() -> Vector3:
	return -_gravity_vec.normalized()


func _gravity() -> Vector3:
	return _gravity_vec
