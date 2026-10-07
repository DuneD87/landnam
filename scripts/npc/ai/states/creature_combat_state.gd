extends AIState
class_name CreatureCombatState

## Combate de una criatura contra controller.target, con los ataques y el temperamento de su
## CreatureCombatProfile. Sirve a cualquier especie: lo propio de cada una está en el perfil.
##   - al empezar contra el jugador se planta amenazando (el aviso de que viene a por ti);
##   - persigue hacia donde va a estar el objetivo, a fondo si está lejos y le queda fuelle;
##   - en cuanto alguno de sus ataques llega lo lanza, elegido por lo que esté haciendo el
##     objetivo (CombatRead): castiga al que falla, embiste al que huye o apunta;
##   - puede encadenar ataques (follow_ups) y, si no, se queda un momento vendido y a veces rodea
##     al objetivo;
##   - si le rompen la guardia (poise) se tambalea y deja de atacar un rato.
## Vuelve a IdleState si pierde al objetivo o se aleja demasiado de él.

enum Phase {THREATEN, CHASE, ATTACK, RECOVER, CIRCLE, STAGGER}

@export var profile: CreatureCombatProfile

var phase: Phase = Phase.CHASE
## Ejecuta el ataque en curso; lo leen también las pruebas y la depuración.
var runner: CreatureAttackRunner
## Ataques seguidos en el combo actual.
var combo: int = 0

var _phase_time: float = 0.0
## Lo que dura la fase actual, si se sortea al entrar (la recuperación).
var _phase_length: float = 0.0
var _cooldowns: Dictionary = {}
var _last_attack: StringName = &""
## Si ya se ha decidido si este ataque encadena otro.
var _chain_decided: bool = false
var _poise: float = 0.0
var _poise_idle: float = 0.0
var _sprint_left: float = 0.0
var _circle_sign: float = 1.0
var _original_speed: float = 0.0


func enter() -> void:
	var npc := controller.npc as NPCController
	if profile == null:
		push_error("CreatureCombatState '%s' sin profile en %s" % [name, npc.name])
		profile = CreatureCombatProfile.new()
	if runner == null:
		runner = CreatureAttackRunner.new(npc, profile)
	_original_speed = controller.movement.speed
	_poise = profile.max_poise
	_poise_idle = 0.0
	_sprint_left = profile.sprint_stamina
	_cooldowns.clear()
	_last_attack = &""
	combo = 0
	if not npc.health_component.hit_received.is_connected(_on_hit):
		npc.health_component.hit_received.connect(_on_hit)
	if profile.threaten_time > 0.0 and _target_is_player():
		_set_phase(Phase.THREATEN)
		if profile.threaten_anim != &"" and npc.get_action_channel() != null:
			npc.get_action_channel().play(profile.threaten_anim, 1.0, profile.action_fade_in, profile.action_fade_out)
		if profile.threaten_sound != &"":
			CombatFx.play(profile.threaten_sound, npc.global_position, {"pitch": profile.voice_pitch})
	else:
		_set_phase(Phase.CHASE)


func exit() -> void:
	controller.movement.speed = _original_speed
	controller.desired_direction = Vector3.ZERO
	controller.is_attacking = false
	if runner != null:
		runner.cancel()


## El ataque en curso, o null.
func current_attack() -> CreatureAttack:
	return runner.attack if runner != null else null


## Lo que está haciendo, para quien pelea con ella (CombatRead, vía NPCController).
func get_situation() -> StringName:
	match phase:
		Phase.ATTACK:
			if runner.in_tell() or not runner.past_windup():
				return &"windup"
			return &"active" if runner.next_hit_time() >= 0.0 or _in_hit_window() else &"recovering"
		Phase.RECOVER:
			return &"recovering"
		Phase.STAGGER:
			return &"staggered"
	return &""


## Una línea para la consola (ia): fase, ataque, combo, guardia, fuelle y lo que lee del objetivo.
func debug_line() -> String:
	var text := String(Phase.keys()[phase]).to_lower()
	var attack := current_attack()
	if attack != null:
		text += " %s %s" % [attack.id, "aviso" if runner.in_tell() else "%.2f/%.2f s" % [runner.time, attack.end]]
	if combo > 1:
		text += " combo %d" % combo
	text += "  guardia %.0f/%.0f" % [_poise, profile.max_poise]
	if profile.sprint_speed > 0.0:
		text += "  fuelle %.1f s" % _sprint_left
	var target := controller.target
	if target != null and is_instance_valid(target):
		text += "  → %s a %.1f m %s" % [target.name, controller.distance_to_target(),
			CombatRead.situations(controller.npc, target, controller.target_velocity)]
	return text


func _in_hit_window() -> bool:
	for hit in runner.attack.hits:
		if runner.time >= hit.from and runner.time <= hit.to:
			return true
	return false


func _target_is_player() -> bool:
	return controller.target != null and controller.target.is_in_group("player")


func _set_phase(next: Phase, length: float = 0.0) -> void:
	phase = next
	_phase_time = 0.0
	_phase_length = length


func update(delta: float) -> StringName:
	var target := controller.target
	if target == null or not is_instance_valid(target):
		return &"IdleState"
	var target_health := target.get_node_or_null("HealthComponent") as HealthComponent
	if target_health != null and target_health.is_dead:
		controller.target = null
		return &"IdleState"
	if phase != Phase.ATTACK and (not controller.is_target_within(profile.disengage_distance) or _past_leash()):
		controller.target = null
		return &"IdleState"
	for key in _cooldowns.keys():
		_cooldowns[key] = maxf(0.0, _cooldowns[key] - delta)
	_poise_idle += delta
	if _poise_idle > profile.poise_regen_delay:
		_poise = minf(profile.max_poise, _poise + profile.poise_regen * delta)
	_phase_time += delta
	var movement := controller.movement
	var sprinting := false
	match phase:
		Phase.THREATEN:
			movement.speed = AIController.TURN_ONLY_SPEED
			controller.desired_facing = _to_target_flat()
			if _phase_time > profile.threaten_time:
				_set_phase(Phase.CHASE)
		Phase.CHASE:
			var dist := controller.distance_to_target()
			var choice := _pick_attack(dist, profile.attacks)
			if choice != null:
				_start_attack(choice, false)
			else:
				sprinting = profile.sprint_speed > 0.0 and dist > profile.sprint_distance and _sprint_left > 0.0
				movement.speed = profile.sprint_speed if sprinting else profile.chase_speed
				controller.desired_direction = controller.steer_clear_of_water(_chase_dir(dist, movement.speed))
		Phase.ATTACK:
			var current := runner.attack
			var running := current != null and runner.update(delta)
			if current != null and not _chain_decided and (not running or runner.can_chain()):
				_chain_decided = true
				var next := _pick_follow_up(current)
				if next != null:
					_cooldowns[current.id] = current.cooldown
					_start_attack(next, true)
					running = true
			if not running:
				if current != null:
					_cooldowns[current.id] = current.cooldown
				combo = 0
				_set_phase(Phase.RECOVER, randf_range(profile.recover_time.x, profile.recover_time.y))
		Phase.RECOVER:
			movement.speed = AIController.TURN_ONLY_SPEED
			if _phase_time > 0.25:
				controller.desired_facing = _to_target_flat()
				controller.turn_rate = profile.recover_turn_rate
			if _phase_time > _phase_length:
				if randf() < profile.circle_chance and controller.distance_to_target() < profile.circle_max_distance:
					_circle_sign = -1.0 if randf() < 0.5 else 1.0
					_set_phase(Phase.CIRCLE)
				else:
					_set_phase(Phase.CHASE)
		Phase.CIRCLE:
			# Rodea al objetivo gruñendo, antes de volver a entrar.
			movement.speed = profile.circle_speed
			var to := _to_target_flat()
			var up := -controller.gravity_direction.normalized()
			var side := up.cross(to) * _circle_sign
			var radial := to * clampf((controller.distance_to_target() - profile.circle_distance) * 0.4, -0.6, 0.6)
			controller.desired_direction = controller.project_on_gravity_plane(side + radial)
			if _phase_time > profile.circle_time:
				_set_phase(Phase.CHASE)
		Phase.STAGGER:
			movement.speed = AIController.TURN_ONLY_SPEED
			if _phase_time > _phase_length:
				_poise = profile.max_poise
				_set_phase(Phase.CHASE)
	if sprinting:
		_sprint_left = maxf(0.0, _sprint_left - delta)
	else:
		_sprint_left = minf(profile.sprint_stamina, _sprint_left + delta * 0.5)
	return &""


func _to_target_flat() -> Vector3:
	return controller.project_on_gravity_plane(controller.target.global_position - controller.npc.global_position)


## Si el objetivo se ha ido más allá de la correa de su territorio.
func _past_leash() -> bool:
	if profile.leash_distance <= 0.0:
		return false
	var home := (controller.npc as NPCController).get_home()
	return home != Vector3.INF and controller.target.global_position.distance_to(home) > profile.leash_distance


## Hacia donde va a estar el objetivo cuando llegue, como mucho chase_lead segundos por delante:
## corta el paso al que huye en vez de ir detrás de él.
func _chase_dir(dist: float, speed: float) -> Vector3:
	if profile.chase_lead <= 0.0:
		return _to_target_flat()
	var ahead := minf(dist / maxf(speed, 0.1), profile.chase_lead)
	var aim := controller.predicted_target_position(ahead, dist * 0.5)
	return controller.project_on_gravity_plane(aim - controller.npc.global_position)


func _start_attack(attack: CreatureAttack, chained: bool) -> void:
	_set_phase(Phase.ATTACK)
	_chain_decided = false
	_last_attack = attack.id
	combo += 1
	runner.start(attack, chained)


## Uno de [attacks] que llegue a [dist], que no espere su cooldown y que caiga dentro de su ángulo,
## al azar por su peso: el suyo, por lo que haga el objetivo, y menos si acaba de usarlo.
func _pick_attack(dist: float, attacks: Array[CreatureAttack], ignore_cooldown: bool = false) -> CreatureAttack:
	var angle := _angle_to_target()
	var options: Array[CreatureAttack] = []
	for attack in attacks:
		if dist < attack.distance.x or dist > attack.distance.y or angle > attack.max_angle:
			continue
		if not ignore_cooldown and _cooldowns.get(attack.id, 0.0) > 0.0:
			continue
		options.append(attack)
	if options.is_empty():
		return null
	var situations := CombatRead.situations(controller.npc, controller.target, controller.target_velocity)
	var weights: Array[float] = []
	var total := 0.0
	for attack in options:
		var weight := attack.weight
		for situation in situations:
			weight *= attack.situations.get(situation, 1.0)
		if attack.id == _last_attack:
			weight *= profile.repeat_penalty
		weights.append(maxf(weight, 0.0))
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return null
	var roll := randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0 and weights[i] > 0.0:
			return options[i]
	return options.back()


## El ataque que encadena tras [attack], si toca: su probabilidad, el tope del combo y alguno de
## sus follow_ups que llegue.
func _pick_follow_up(attack: CreatureAttack) -> CreatureAttack:
	if attack.follow_ups.is_empty() or combo >= profile.max_combo or randf() >= attack.follow_up_chance:
		return null
	var candidates: Array[CreatureAttack] = []
	for other in profile.attacks:
		if other.id in attack.follow_ups:
			candidates.append(other)
	return _pick_attack(controller.distance_to_target(), candidates, true)


## Grados entre hacia donde mira y el objetivo.
func _angle_to_target() -> float:
	var forward := controller.project_on_gravity_plane(controller.npc.global_basis.z)
	var to := _to_target_flat()
	if forward == Vector3.ZERO or to == Vector3.ZERO:
		return 0.0
	return rad_to_deg(forward.angle_to(to))


## Le han parado el golpe en seco: corta el ataque y se queda vendido parried_time.
func on_parried(_info: DamageInfo) -> void:
	runner.cancel()
	combo = 0
	_poise_idle = 0.0
	_stagger(profile.parried_time)


func _stagger(seconds: float) -> void:
	_set_phase(Phase.STAGGER, seconds)
	var npc := controller.npc as NPCController
	if not profile.stagger_anims.is_empty() and npc.get_action_channel() != null:
		npc.get_action_channel().play(profile.stagger_anims.pick_random(), 1.0, 0.1, profile.action_fade_out)
	if profile.stagger_sound != &"":
		CombatFx.play(profile.stagger_sound, npc.global_position, {"pitch": profile.voice_pitch})


func _on_hit(info: DamageInfo, _applied: float) -> void:
	if controller.get_current_state() != StringName(name):
		return
	_poise_idle = 0.0
	var poise := runner.absorb_poise(info.poise) if phase == Phase.ATTACK else info.poise
	_poise -= poise
	if _poise <= 0.0 and phase != Phase.STAGGER:
		runner.cancel()
		combo = 0
		_stagger(profile.stagger_time)
