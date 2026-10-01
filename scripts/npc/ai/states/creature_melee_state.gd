extends AIState
class_name CreatureMeleeState

## Combate cuerpo a cuerpo de una criatura grande (el oso) contra su objetivo, pensado para que
## se pueda leer y esquivar:
##   - persigue; a distancia media embiste, de cerca lanza zarpazos;
##   - cada ataque avisa: la primera parte de la animación va más lenta y el animal se encara;
##     cuando empieza el golpe se compromete (ya no gira), así que apartarse o rodar funciona;
##   - las zarpas y la cabeza hieren por colisión (esferas barridas entre fotogramas contra los
##     Hurtbox), solo dentro de la ventana activa de cada golpe;
##   - tras cada ataque se queda un momento vendido (la ventana para castigarle);
##   - si le rompen la guardia (poise) se tambalea y deja de atacar un rato.
## Vuelve a IdleState si pierde al objetivo o se aleja demasiado de él.

## Ataques. Tiempos en segundos de animación a velocidad 1 (medidos por la velocidad de las
## zarpas en cada clip): hits = ventanas con los huesos que hieren, lunge = (desde, hasta,
## metros) de avance, range = distancias (desde el centro del animal) en las que lo elige,
## pre = segundos que se planta encarado y gruñendo antes de arrancar (el aviso).
const BEAR_ATTACKS := [
	{"name": &"swipe", "anim": &"atk stand2", "range": Vector2(0.0, 3.3), "cooldown": 1.3,
		"pre": 0.30, "windup_speed": 0.62, "speed": 1.05, "end": 1.65, "lunge": Vector3(0.30, 0.85, 1.5),
		"hits": [{"from": 0.42, "to": 0.95, "bones": [&"RigRFLegDigit11", &"RigRFLeg2"], "radius": 0.42,
			"damage": 32.0, "poise": 45.0, "knockback": 1.8}]},
	{"name": &"double", "anim": &"atk stand", "range": Vector2(0.0, 3.0), "cooldown": 1.6,
		"pre": 0.35, "windup_speed": 0.55, "speed": 1.0, "end": 1.75, "lunge": Vector3(0.25, 1.15, 1.9),
		"hits": [{"from": 0.38, "to": 0.70, "bones": [&"RigLFLegDigit11"], "radius": 0.40,
			"damage": 20.0, "poise": 20.0, "knockback": 0.8},
			{"from": 0.90, "to": 1.22, "bones": [&"RigRFLegDigit11", &"RigHead"], "radius": 0.42,
			"damage": 28.0, "poise": 45.0, "knockback": 1.8}]},
	{"name": &"charge", "anim": &"atk run", "range": Vector2(4.5, 10.0), "cooldown": 4.5,
		"pre": 0.55, "windup_speed": 0.8, "speed": 1.0, "end": 1.15, "lunge": Vector3(0.05, 0.85, 7.0),
		"hits": [{"from": 0.15, "to": 0.80, "bones": [&"RigHead", &"RigRFLegDigit11", &"RigLFLegDigit11"],
			"radius": 0.45, "damage": 26.0, "poise": 50.0, "knockback": 2.6}]},
]

enum Phase {ROAR, CHASE, ATTACK, RECOVER, CIRCLE, STAGGER}

## Más allá de esta distancia deja de perseguir.
@export var disengage_distance: float = 45.0
## Velocidad de persecución (m/s) y al rodear al objetivo.
@export var chase_speed: float = 6.2
@export var circle_speed: float = 2.4
## Guardia: el desgaste acumulado que aguanta antes de tambalearse, y cuánto recupera por segundo.
@export var max_poise: float = 85.0
@export var poise_regen: float = 18.0
@export var stagger_time: float = 1.5
## Segundos que se queda quieto tras un ataque (la ventana para castigarle).
@export var recover_time: Vector2 = Vector2(0.55, 1.0)

var _phase: Phase = Phase.CHASE
var _t: float = 0.0
var _phase_time: float = 0.0
var _pre: float = 0.0
var _attack: Dictionary = {}
var _cooldowns: Dictionary = {}
var _poise: float = 0.0
var _poise_idle: float = 0.0
var _circle_sign: float = 1.0
var _original_speed: float = 0.0
var _sweeps: Array = []
var _roared: bool = false

var _tree: AnimationTree
var _tree_ready: bool = false
var _skeleton: Skeleton3D
var _bone_cache: Dictionary = {}


func enter() -> void:
	_original_speed = controller.movement.speed
	_poise = max_poise
	_cooldowns.clear()
	_setup_animation()
	var npc := controller.npc as NPCController
	if npc != null and not npc.health_component.hit_received.is_connected(_on_hit):
		npc.health_component.hit_received.connect(_on_hit)
	if not _roared and _target_is_player():
		_roared = true
		_set_phase(Phase.ROAR)
		CombatFx.play(&"bear_roar", controller.npc.global_position)
	else:
		_set_phase(Phase.CHASE)


func exit() -> void:
	controller.movement.speed = _original_speed
	controller.desired_direction = Vector3.ZERO
	controller.is_attacking = false
	_stop_attack_anim()
	_attack = {}
	_roared = false


func _target_is_player() -> bool:
	return controller.target != null and controller.target.is_in_group("player")


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


func update(delta: float) -> StringName:
	var target := controller.target
	if target == null or not is_instance_valid(target):
		return &"IdleState"
	var target_health := target.get_node_or_null("HealthComponent") as HealthComponent
	if target_health != null and target_health.is_dead:
		controller.target = null
		return &"IdleState"
	if not controller.is_target_within(disengage_distance) and _phase != Phase.ATTACK:
		controller.target = null
		return &"IdleState"
	for key in _cooldowns.keys():
		_cooldowns[key] = maxf(0.0, _cooldowns[key] - delta)
	_poise_idle += delta
	if _poise_idle > 2.0:
		_poise = minf(max_poise, _poise + poise_regen * delta)
	_phase_time += delta
	controller.desired_direction = Vector3.ZERO
	var movement := controller.movement
	match _phase:
		Phase.ROAR:
			# Se planta y ruge: el aviso de que viene a por ti.
			movement.speed = 0.01
			controller.desired_direction = _to_target_flat()
			if _phase_time > 1.1:
				_set_phase(Phase.CHASE)
		Phase.CHASE:
			movement.speed = chase_speed
			var dist := controller.distance_to_target()
			var choice := _pick_attack(dist)
			if not choice.is_empty():
				_start_attack(choice)
			else:
				controller.desired_direction = controller.steer_clear_of_water(_to_target_flat())
		Phase.ATTACK:
			_update_attack(delta)
		Phase.RECOVER:
			movement.speed = 0.01
			if _phase_time > 0.25:
				controller.desired_direction = _to_target_flat()
			if _phase_time > randf_range(recover_time.x, recover_time.y):
				if randf() < 0.35 and controller.distance_to_target() < 6.0:
					_circle_sign = -1.0 if randf() < 0.5 else 1.0
					_set_phase(Phase.CIRCLE)
				else:
					_set_phase(Phase.CHASE)
		Phase.CIRCLE:
			# Rodea al objetivo gruñendo, antes de volver a entrar.
			movement.speed = circle_speed
			var to := _to_target_flat()
			var up := -controller.gravity_direction.normalized()
			var side := up.cross(to) * _circle_sign
			var dist := controller.distance_to_target()
			var radial := to * clampf((dist - 4.5) * 0.4, -0.6, 0.6)
			controller.desired_direction = controller.project_on_gravity_plane(side + radial)
			if _phase_time > 1.6:
				_set_phase(Phase.CHASE)
		Phase.STAGGER:
			movement.speed = 0.01
			if _phase_time > stagger_time:
				_poise = max_poise
				_set_phase(Phase.CHASE)
	return &""


func _to_target_flat() -> Vector3:
	return controller.project_on_gravity_plane(controller.target.global_position - controller.npc.global_position)


func _pick_attack(dist: float) -> Dictionary:
	var options: Array = []
	for attack in BEAR_ATTACKS:
		var range: Vector2 = attack.range
		if dist >= range.x and dist <= range.y and _cooldowns.get(attack.name, 0.0) <= 0.0:
			options.append(attack)
	if options.is_empty():
		return {}
	return options[randi() % options.size()]


# ---------------------------------------------------------------------------------------------
# Ataque


func _start_attack(attack: Dictionary) -> void:
	_attack = attack
	_t = 0.0
	_set_phase(Phase.ATTACK)
	_sweeps.clear()
	var npc := controller.npc as NPCController
	# Un barrido por hueso (cada uno sigue su propio rastro); comparten a quién han golpeado.
	for hit in attack.hits:
		var per_bone: Array[MeleeSweep] = []
		for bone in hit.bones:
			var sweep := MeleeSweep.new(hit.radius)
			for box in npc.hurtboxes:
				sweep.exclude.append(box.get_rid())
			per_bone.append(sweep)
		_sweeps.append(per_bone)
	_pre = attack.get("pre", 0.3)
	CombatFx.play(&"bear_growl", npc.global_position, {"pitch": randf_range(0.9, 1.1)})


## Arranca la animación del golpe, al acabar el aviso.
func _fire_attack_anim() -> void:
	if not _tree_ready:
		return
	var tree_root := _tree.tree_root as AnimationNodeBlendTree
	(tree_root.get_node(&"attack") as AnimationNodeAnimation).animation = _attack.anim
	_tree.set("parameters/atk_speed/scale", _attack.windup_speed)
	_tree.set("parameters/attack_horizontal/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _update_attack(delta: float) -> void:
	var movement := controller.movement
	if _pre > 0.0:
		# Aviso: quieto, encarándose.
		_pre -= delta
		movement.speed = 0.01
		controller.desired_direction = _to_target_flat()
		if _pre <= 0.0:
			_fire_attack_anim()
		return
	var first_hit: float = _attack.hits[0].from
	# Aviso: lento hasta poco antes del primer golpe, luego a su velocidad.
	var speed: float = _attack.windup_speed if _t < first_hit - 0.12 else _attack.speed
	if _tree_ready:
		_tree.set("parameters/atk_speed/scale", speed)
	var prev := _t
	_t += delta * speed
	var lunge: Vector3 = _attack.lunge
	var forward := controller.project_on_gravity_plane(controller.npc.global_basis.z)
	if _t < first_hit - 0.05:
		# Todavía encarándose: gira hacia el objetivo casi sin moverse.
		movement.speed = 0.01
		controller.desired_direction = _to_target_flat()
	else:
		movement.speed = 0.01
		controller.desired_direction = forward
	if _t >= lunge.x and prev <= lunge.y:
		var span := (lunge.y - lunge.x) / maxf(_attack.speed, 0.01)
		var close: bool = controller.distance_to_target() < 1.6 and _attack.name != &"charge"
		if not close:
			movement.speed = lunge.z / span
			controller.desired_direction = forward if _t >= first_hit - 0.05 else _to_target_flat()
	for i in _attack.hits.size():
		var hit: Dictionary = _attack.hits[i]
		if _t >= hit.from and prev <= hit.to:
			if prev < hit.from:
				CombatFx.play(&"bear_swipe", controller.npc.global_position)
			_sweep_hit(hit, _sweeps[i])
	if _t >= _attack.end:
		_cooldowns[_attack.name] = _attack.cooldown
		_stop_attack_anim()
		_attack = {}
		_set_phase(Phase.RECOVER)


func _sweep_hit(hit: Dictionary, sweeps: Array) -> void:
	var npc := controller.npc as NPCController
	var space := npc.get_world_3d().direct_space_state
	for i in hit.bones.size():
		var point := _bone_world(hit.bones[i])
		if point == Vector3.INF:
			continue
		var sweep: MeleeSweep = sweeps[i]
		for result in sweep.sweep_point(space, point):
			var box: Hurtbox = result.hurtbox
			for other in sweeps:
				(other as MeleeSweep).mark_hit(box.owner_body)
			if box.owner_body == npc:
				continue
			var dir := controller.project_on_gravity_plane(box.owner_body.global_position - npc.global_position)
			var info := DamageInfo.create(hit.damage, npc, result.point, dir, hit.poise)
			info.kind = ItemData.DamageKind.SLASH
			info.knockback = hit.knockback
			var applied := box.receive(info)
			if applied > 0.0:
				CombatFx.blood(box.owner_body, result.point, dir, ItemData.DamageKind.SLASH, hit.damage)
				CombatFx.impact(npc, result.point, ItemData.DamageKind.SLASH, true)


func _bone_world(bone: StringName) -> Vector3:
	if _skeleton == null:
		return Vector3.INF
	if not _bone_cache.has(bone):
		_bone_cache[bone] = _skeleton.find_bone(bone)
	var idx: int = _bone_cache[bone]
	if idx < 0:
		return Vector3.INF
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin


func _stop_attack_anim() -> void:
	if _tree_ready:
		_tree.set("parameters/attack_horizontal/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_tree.set("parameters/atk_speed/scale", 1.0)


## Árbol de animación propio de esta criatura (el recurso de la escena lo comparten todas) con
## un escalador de tiempo delante del golpe, que es lo que permite el aviso lento.
func _setup_animation() -> void:
	if _tree_ready:
		return
	var npc := controller.npc as NPCController
	if npc == null or npc.animation_controller == null:
		return
	_tree = npc.animation_controller.animation_tree
	_skeleton = npc.npc_model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if _tree == null or not (_tree.tree_root is AnimationNodeBlendTree):
		return
	var tree_root := (_tree.tree_root as AnimationNodeBlendTree).duplicate(true) as AnimationNodeBlendTree
	if not tree_root.has_node(&"attack") or not tree_root.has_node(&"attack_horizontal"):
		return
	tree_root.add_node(&"atk_speed", AnimationNodeTimeScale.new())
	tree_root.disconnect_node(&"attack_horizontal", 1)
	tree_root.connect_node(&"atk_speed", 0, &"attack")
	tree_root.connect_node(&"attack_horizontal", 1, &"atk_speed")
	_tree.tree_root = tree_root
	_tree_ready = true


# ---------------------------------------------------------------------------------------------
# Golpes recibidos


func _on_hit(info: DamageInfo, _applied: float) -> void:
	if controller.get_current_state() != StringName(name):
		return
	_poise_idle = 0.0
	_poise -= info.poise
	if _poise <= 0.0 and _phase != Phase.STAGGER:
		_stop_attack_anim()
		_attack = {}
		_set_phase(Phase.STAGGER)
		CombatFx.play(&"bear_growl", controller.npc.global_position, {"pitch": 1.25})
