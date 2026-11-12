class_name SettlerGuard extends SettlerTask

## El colono de guardia: vigila la zona que se le marca. Con una zona pequeña (hasta POST_RADIUS m)
## es un puesto: va a su centro y se queda allí, mirando a un lado y a otro. Con una mayor hace la
## ronda: recorre POINTS puntos de su borde, parándose un rato en cada uno a mirar hacia fuera.
##
## Hace un turno (SettlerWork.shift): el de día, desde que se levanta hasta que se acuesta; el de
## noche, mientras los demás duermen, y él duerme de día (NIGHT_REST). De turno no espera a que
## ataquen: va a por las fieras que atacan a la vista (lobos, osos, leones...) en cuanto entran en su
## zona o a menos de ALERT m de ella, da la alarma (aviso en la barra, como mucho cada ALARM_EVERY s)
## y los otros guardias de la base acuden. Fuera de turno defiende como cualquier colono.
##
## Lejos del jugador no pasa nada: allí no hay fieras. Ver docs/villagers.md.

## Va a por las fieras a menos de esto (m) del borde de su zona.
const ALERT := 12.0
const POST_RADIUS := 5.0
const POINTS := 8
## La ronda va por dentro del borde, a esta parte del radio; y en cada punto se para esto (s).
const RING := 0.8
const PAUSE := Vector2(4.0, 9.0)
const ARRIVE := 0.8
## El guardia de noche duerme de día, entre estas horas.
const NIGHT_REST := Vector2(9.0, 17.0)
const ALARM_EVERY := 45.0
## Los guardias de las bases a menos de esto (m) de la suya acuden a la alarma.
const ALARM_REACH := 80.0

static var _last_alarm := -INF

var _point := 0
var _turn := 1
var _pause_left := 0.0
## Hacia dónde mira parado (marco del terreno).
var _look := Vector3.ZERO


func start() -> void:
	_point = c._rng.randi() % POINTS
	_turn = 1 if c._rng.randf() < 0.5 else -1


func on_duty(hour: float) -> bool:
	return Villager._is_night(hour) if w.shift == 1 else not Villager._is_night(hour)


func sleeps(hour: float) -> bool:
	if w.shift == 1:
		return hour >= NIGHT_REST.x and hour < NIGHT_REST.y
	return Villager._is_night(hour)


func describe() -> String:
	var what := c.tr("SETTLER_JOB_GUARD_NIGHT" if w.shift == 1 else "SETTLER_JOB_GUARD_DAY")
	match w.status:
		SettlerWork.Status.OFF_HOURS:
			return c.tr("SETTLER_GUARD_OFF") % what
		SettlerWork.Status.AWAY:
			return c.tr("SETTLER_GUARD_AWAY") % what
	return c.tr("SETTLER_GUARD_POST" if is_post() else "SETTLER_GUARD_ROUND") % what


## Un puesto fijo (zona pequeña) y no una ronda.
func is_post() -> bool:
	return w.zone_radius <= POST_RADIUS


func step(delta: float) -> Array:
	w.status = SettlerWork.Status.WORKING
	if _pause_left > 0.0:
		_pause_left -= delta
		if _look != Vector3.ZERO:
			c._face(c._terrain.global_transform.basis * _look, delta)
		if _pause_left <= 0.0 and not is_post():
			_point = posmod(_point + _turn, POINTS)
		return still()
	var middle := center()
	var up := (middle - c._terrain.global_position).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var out := side.rotated(up, TAU * _point / POINTS)
	var dest := middle if is_post() else middle + out * w.zone_radius * RING
	if walk(dest, ARRIVE, delta, self) == Walk.GOING:
		return [heading, Companion.WALK_SPEED]
	# Ha llegado (o no puede acercarse más): mira hacia fuera un rato.
	_pause_left = c._rng.randf_range(PAUSE.x, PAUSE.y)
	if is_post():
		out = side.rotated(up, c._rng.randf() * TAU)
	_look = c._terrain.global_transform.basis.inverse() * out
	return still()


## De turno, [creature] es cosa suya si ataca a la vista (su detect_state es de pelea).
func is_threat(creature: NPCController) -> bool:
	if w.status != SettlerWork.Status.WORKING or creature.detect_state == &"":
		return false
	var ai := creature.ai_controller
	return ai != null and ai.get_node_or_null(NodePath(String(creature.detect_state))) is CreatureCombatState


## Ha salido a por [creature]: avisa al jugador y los otros guardias de la base acuden.
func alarm(creature: NPCController) -> void:
	for node in c.get_tree().get_nodes_in_group(Companion.GROUP):
		var other := node as Companion
		if other == null or other == c or other.dead or other.mode != Companion.Mode.SETTLE \
				or other.work.job != SettlerWork.Job.GUARD or other.is_fighting() \
				or other.global_position.distance_to(c.global_position) > ALARM_REACH:
			continue
		other.order_attack(creature)
	var now := SettlerWork._now()
	if now - _last_alarm < ALARM_EVERY:
		return
	_last_alarm = now
	c.notify(c.tr("SETTLER_ALARM") % who())
