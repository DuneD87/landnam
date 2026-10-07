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
##   - si le rompen la guardia (poise) se tambalea y deja de atacar un rato;
##   - si ya le atacan otros (CombatDirector reparte los turnos), espera el suyo en corro,
##     repartido con los demás o a la espalda del objetivo (flank_bias); tras atacar, si hay otros
##     esperando, se aparta para cederles el turno;
##   - si lo pierde de vista (Perception.memory_time), va a donde lo vio por última vez y lo busca.
## Vuelve a IdleState si pierde al objetivo o se aleja demasiado de él.

enum Phase {THREATEN, CHASE, ATTACK, RECOVER, CIRCLE, STAGGER, FLANK, SEARCH}

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
## Contra quién está apuntado en el reparto de turnos.
var _joined: Node3D = null
## Dónde del corro quiere esperar (dirección desde el objetivo), y cuándo lo vuelve a pensar.
var _flank_dir: Vector3 = Vector3.ZERO
var _flank_rethink: float = 0.0
var _next_growl: float = 0.0


func enter() -> void:
	var npc := controller.npc as NPCController
	if profile == null:
		push_error("CreatureCombatState '%s' sin profile en %s" % [name, npc.name])
		profile = CreatureCombatProfile.new()
	if runner == null:
		runner = CreatureAttackRunner.new(npc, profile)
	_original_speed = controller.movement.speed
	_poise = _max_poise()
	_poise_idle = 0.0
	_sprint_left = profile.sprint_stamina
	_cooldowns.clear()
	_last_attack = &""
	combo = 0
	if not npc.health_component.hit_received.is_connected(_on_hit):
		npc.health_component.hit_received.connect(_on_hit)
	_join(controller.target)
	if profile.threaten_time > 0.0 and _target_is_player():
		_set_phase(Phase.THREATEN)
		if profile.threaten_anim != &"" and npc.get_action_channel() != null:
			npc.get_action_channel().play(profile.threaten_anim, 1.0, profile.action_fade_in, profile.action_fade_out)
		if profile.threaten_sound != &"":
			CombatFx.play(profile.threaten_sound, npc.global_position, {"pitch": _voice()})
	else:
		_set_phase(Phase.CHASE)


func exit() -> void:
	controller.movement.speed = _original_speed
	controller.desired_direction = Vector3.ZERO
	controller.is_attacking = false
	if runner != null:
		runner.cancel()
	CombatDirector.leave_all(controller.npc)
	_joined = null


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


## Una criatura en corro esperando turno (las pruebas y la consola).
func is_waiting() -> bool:
	return phase == Phase.FLANK


## Una línea para la consola (ia): fase, ataque, combo, guardia, fuelle y lo que lee del objetivo.
func debug_line() -> String:
	var text := String(Phase.keys()[phase]).to_lower()
	var attack := current_attack()
	if attack != null:
		text += " %s %s" % [attack.id, "aviso" if runner.in_tell() else "%.2f/%.2f s" % [runner.time, attack.end]]
	if combo > 1:
		text += " combo %d" % combo
	if _joined != null and is_instance_valid(_joined):
		var engaged := CombatDirector.engaged(_joined).size()
		if engaged > 1:
			text += "  %s (%d/%d atacan, %d en total)" % ["con turno" if CombatDirector.has_turn(_joined, controller.npc)
				else "esperando", CombatDirector.turns(_joined), CombatDirector.MAX_TURNS, engaged]
	if not controller.target_seen:
		text += "  sin verlo %.1f s" % controller.unseen_time
	text += "  guardia %.0f/%.0f" % [_poise, _max_poise()]
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
	if target != _joined:
		_join(target)
	# Sin verlo no ataca ni lo persigue: va a donde lo vio por última vez.
	if not controller.target_seen and phase != Phase.ATTACK and phase != Phase.STAGGER and phase != Phase.SEARCH:
		_release_turn()
		_set_phase(Phase.SEARCH)
	for key in _cooldowns.keys():
		_cooldowns[key] = maxf(0.0, _cooldowns[key] - delta)
	_poise_idle += delta
	if _poise_idle > profile.poise_regen_delay:
		_poise = minf(_max_poise(), _poise + profile.poise_regen * _npc().poise_scale * delta)
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
			# Atacar, o acercarse a donde se ataca, pide turno; sin él, espera en corro.
			if (choice != null or dist < profile.wait_distance) and not _request_turn():
				_enter_flank(Vector2.ZERO)
			elif choice != null:
				_start_attack(choice, false)
			else:
				sprinting = profile.sprint_speed > 0.0 and dist > profile.sprint_distance and _sprint_left > 0.0
				movement.speed = (profile.sprint_speed if sprinting else profile.chase_speed) * _npc().speed_scale
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
				_release_turn()
				if _others_waiting():
					_enter_flank(profile.wait_time)
				elif randf() < profile.circle_chance and controller.distance_to_target() < profile.circle_max_distance:
					_circle_sign = -1.0 if randf() < 0.5 else 1.0
					_set_phase(Phase.CIRCLE)
				else:
					_set_phase(Phase.CHASE)
		Phase.CIRCLE:
			# Rodea al objetivo gruñendo, antes de volver a entrar.
			movement.speed = profile.circle_speed * _npc().speed_scale
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
				_poise = _max_poise()
				_set_phase(Phase.CHASE)
		Phase.FLANK:
			var dist := controller.distance_to_target()
			# Si se le mete encima se defiende, con turno o sin él; si se aleja, lo persigue.
			var defend := _pick_attack(dist, profile.attacks) if dist < profile.wait_distance * 0.5 else null
			if defend != null:
				_start_attack(defend, false)
			elif dist > profile.wait_distance + 4.0:
				_set_phase(Phase.CHASE)
			else:
				_update_flank(delta)
				if _phase_time > _phase_length and _request_turn():
					_set_phase(Phase.CHASE)
		Phase.SEARCH:
			if controller.target_seen:
				_set_phase(Phase.CHASE)
			else:
				_update_search()
	if sprinting:
		_sprint_left = maxf(0.0, _sprint_left - delta)
	else:
		_sprint_left = minf(profile.sprint_stamina, _sprint_left + delta * 0.5)
	return &""


# ---------------------------------------------------------------------------------------------
# Turnos, corro y búsqueda


## Se apunta al reparto de turnos contra [target] (y deja el anterior).
func _join(target: Node3D) -> void:
	CombatDirector.leave_all(controller.npc)
	_joined = target
	if target != null:
		CombatDirector.join(target, controller.npc)


func _request_turn() -> bool:
	return CombatDirector.request_turn(controller.target, controller.npc)


func _release_turn() -> void:
	if controller.target != null:
		CombatDirector.release_turn(controller.target, controller.npc)


## Hay otras criaturas peleando con su objetivo que esperan turno.
func _others_waiting() -> bool:
	var target := controller.target
	var waiting := CombatDirector.engaged(target).size() - CombatDirector.turns(target)
	if not CombatDirector.has_turn(target, controller.npc):
		waiting -= 1
	return waiting > 0


## Al corro: al menos [wait] segundos (al azar entre los dos) antes de pedir turno otra vez.
func _enter_flank(wait: Vector2) -> void:
	_set_phase(Phase.FLANK, randf_range(wait.x, wait.y))
	_flank_rethink = 0.0
	_next_growl = randf_range(profile.wait_growl.x, profile.wait_growl.y) * 0.5


## Ronda al objetivo a wait_distance hacia su sitio del corro (_pick_flank_dir); allí, quieto y
## encarado. Gruñe de vez en cuando.
func _update_flank(delta: float) -> void:
	var npc := controller.npc
	var target := controller.target
	_flank_rethink -= delta
	if _flank_rethink <= 0.0 or _flank_dir == Vector3.ZERO:
		_flank_rethink = 0.5
		_flank_dir = _pick_flank_dir()
	var up := -controller.gravity_direction.normalized()
	var from_target := controller.project_on_gravity_plane(npc.global_position - target.global_position)
	var to_target := -from_target
	var angle := from_target.signed_angle_to(_flank_dir, up) if from_target != Vector3.ZERO else 0.0
	var radial := clampf((controller.distance_to_target() - profile.wait_distance) * 0.5, -1.0, 1.0)
	var move := up.cross(from_target) * signf(angle) * clampf(absf(angle) / deg_to_rad(30.0), 0.0, 1.0) \
		+ to_target * radial
	if move.length() < 0.25:
		controller.movement.speed = AIController.TURN_ONLY_SPEED
		controller.desired_facing = to_target
	else:
		controller.movement.speed = profile.circle_speed * _npc().speed_scale
		controller.desired_direction = controller.steer_clear_of_water(controller.project_on_gravity_plane(move))
	_next_growl -= delta
	if _next_growl <= 0.0:
		_next_growl = randf_range(profile.wait_growl.x, profile.wait_growl.y)
		if profile.wait_sound != &"":
			CombatFx.play(profile.wait_sound, npc.global_position, {"pitch": _voice() * randf_range(0.95, 1.05)})


## Dónde esperar alrededor del objetivo (dirección desde él): lejos de los demás que pelean con
## él, a su espalda cuanto más flank_bias, y sin dar mucha vuelta desde donde está.
func _pick_flank_dir() -> Vector3:
	var npc := controller.npc
	var target := controller.target
	var up := -controller.gravity_direction.normalized()
	var current := controller.project_on_gravity_plane(npc.global_position - target.global_position)
	var facing := controller.project_on_gravity_plane(target.global_basis.z)
	if current == Vector3.ZERO:
		current = -facing if facing != Vector3.ZERO else controller.project_on_gravity_plane(npc.global_basis.z)
	var others: Array[Vector3] = []
	for other in CombatDirector.engaged(target):
		if other != npc:
			var dir := controller.project_on_gravity_plane(other.global_position - target.global_position)
			if dir != Vector3.ZERO:
				others.append(dir)
	var best := current
	var best_score := -INF
	for i in 16:
		var dir := current.rotated(up, TAU * i / 16.0)
		var score := -0.4 * dir.angle_to(current) / PI
		if facing != Vector3.ZERO:
			score -= profile.flank_bias * dir.dot(facing)
		for other in others:
			var gap := rad_to_deg(dir.angle_to(other))
			if gap < 60.0:
				score -= (1.0 - gap / 60.0) * 1.5
		if score > best_score:
			best = dir
			best_score = score
	return best


## Va a donde lo vio por última vez (adelantado lo que iba corriendo); allí mira a un lado y a otro.
func _update_search() -> void:
	var npc := controller.npc
	var up := -controller.gravity_direction.normalized()
	var to := controller.search_position(profile.search_lead) - npc.global_position
	to -= up * to.dot(up)
	if to.length() > 1.5:
		controller.movement.speed = profile.chase_speed * profile.search_speed * _npc().speed_scale
		controller.desired_direction = controller.steer_clear_of_water(to.normalized())
		return
	controller.movement.speed = AIController.TURN_ONLY_SPEED
	var sweep := signf(sin(_phase_time * 1.2))
	controller.desired_facing = controller.project_on_gravity_plane(npc.global_basis.z).rotated(up, sweep * 0.9)
	controller.turn_rate = 70.0


func _npc() -> NPCController:
	return controller.npc as NPCController


## Guardia entera: la del perfil, a la medida de su variante.
func _max_poise() -> float:
	return profile.max_poise * _npc().poise_scale


## Tono de su voz: el de la especie y el de su variante.
func _voice() -> float:
	return profile.voice_pitch * _npc().voice_pitch


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


## Uno de [attacks] que llegue a [dist], que no espere su cooldown, que caiga dentro de su ángulo y
## que su variante sepa hacer, al azar por su peso: el suyo, por lo que haga el objetivo, y menos si
## acaba de usarlo. Las distancias crecen con el tamaño del cuerpo.
func _pick_attack(dist: float, attacks: Array[CreatureAttack], ignore_cooldown: bool = false) -> CreatureAttack:
	var angle := _angle_to_target()
	var npc := _npc()
	var options: Array[CreatureAttack] = []
	for attack in attacks:
		var reach := attack.distance * npc.body_size
		if dist < reach.x or dist > reach.y or angle > attack.max_angle or not npc.can_use_attack(attack.id):
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
	_release_turn()
	_set_phase(Phase.STAGGER, seconds)
	var npc := controller.npc as NPCController
	if not profile.stagger_anims.is_empty() and npc.get_action_channel() != null:
		npc.get_action_channel().play(profile.stagger_anims.pick_random(), 1.0, 0.1, profile.action_fade_out)
	if profile.stagger_sound != &"":
		CombatFx.play(profile.stagger_sound, npc.global_position, {"pitch": _voice()})


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
