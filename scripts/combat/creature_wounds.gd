class_name CreatureWounds
extends Node

## Las heridas de una criatura (NPCController). Cada golpe que encaja abre una que sangra según el
## daño y el tipo de golpe (los de BodyDamage.BLEED_PER_DAMAGE: tajos y flechas mucho, porrazos
## poco) y se va cerrando sola. Mientras sangra le va quitando vida, sin el respingo ni el quejido
## de un golpe (HealthComponent.drain), y deja gotas en el suelo por donde pasa, más juntas y más
## grandes cuanto más sangra, y un charco donde se para. Es el rastro de una presa herida: un ciervo
## con una flecha en el costado se va, y se le sigue por la sangre.
##
## Herida va más despacio (pace). Mientras su rastro siga fresco (tracked), el spawner no la recicla
## por lejos que se vaya, y su cadáver no desaparece antes que el rastro.

## Vida media del sangrado de una herida (s). Una flecha en el costado de un ciervo (unos 35 de
## daño) sangra 0,35 vida/s al principio, le quita una veintena de vida en total y deja rastro
## un par de minutos.
const HALF_LIFE := 45.0
## Por debajo de esto (vida/s) una herida ya no sangra.
const BLEED_STOP := 0.03
## Sangrado (vida/s) con el que el rastro sale más espeso: gotas más juntas y más grandes.
const FULL_RATE := 0.5
## Cada cuánto (m andados) cae una gota sangrando poco (x) y mucho (y), y su tamaño (m).
const DROP_STEP := Vector2(5.0, 1.2)
const DROP_SIZE := Vector2(0.2, 0.45)
## Lo que se aparta una gota del sitio de la herida (m).
const DROP_SCATTER := 0.15
## Parada más de esto (s) deja un charco, de este tamaño sangrando poco y mucho (m), que tarda en
## extenderse POOL_GROW (s). Uno por sitio: el siguiente, cuando se haya movido más de STILL_REACH (m).
const POOL_AFTER := 2.5
const POOL_SIZE := Vector2(0.5, 1.1)
const POOL_GROW := 20.0
const STILL_REACH := 0.6
## Cada cuánto se repasa (s).
const TICK := 0.1

var npc: NPCController
var health: HealthComponent
## Gotas y charcos que ha dejado (consola, `ai`).
var drops := 0

## Heridas abiertas: {rate (vida/s), local (por dónde sangra, en el marco del cuerpo)}.
var _wounds: Array[Dictionary] = []
var _bleed_debt := 0.0
var _tick := 0.0
## Dónde cayó la última gota y dónde lleva parada, en el marco del planeta (sobreviven a los rebases
## del origen flotante). INF = aún no.
var _last_drop := Vector3.INF
var _still_at := Vector3.INF
var _still_time := 0.0
var _pooled := false
## Hasta cuándo (ms) se ve lo último que ha sangrado.
var _trail_until := 0


static func attach(body: NPCController, health_: HealthComponent) -> CreatureWounds:
	var wounds := CreatureWounds.new()
	wounds.name = "CreatureWounds"
	wounds.npc = body
	wounds.health = health_
	body.add_child(wounds)
	health_.hit_received.connect(wounds._on_hit)
	wounds.set_process(false)
	return wounds


## Sana del todo (al salir del pool).
func restore() -> void:
	_wounds.clear()
	_bleed_debt = 0.0
	_last_drop = Vector3.INF
	_still_at = Vector3.INF
	_trail_until = 0
	drops = 0
	set_process(false)


## Lo que le deja moverse estar herido, como factor de su velocidad: a vida v (0-1),
## 1 - (1 - v) × NPCController.wound_slowdown.
func pace() -> float:
	return 1.0 - (1.0 - health.get_health_ratio()) * npc.wound_slowdown


## Vida por segundo que se le va en sangre.
func bleed_rate() -> float:
	var total := 0.0
	for wound in _wounds:
		total += wound.rate
	return total


## Si aún se ve lo último que ha sangrado: hay rastro que seguir hasta ella (o hasta su cadáver).
func tracked() -> bool:
	return _trail_until > Time.get_ticks_msec()


func _on_hit(info: DamageInfo, _applied: float) -> void:
	var rate := info.mitigated * float(BodyDamage.BLEED_PER_DAMAGE.get(info.kind, 0.01))
	if rate <= BLEED_STOP:
		return
	if _wounds.is_empty():
		# El rastro empieza aquí: donde encaja el golpe ya salpica el suelo (CombatFx.blood).
		_last_drop = _where()
		_still_at = _last_drop
		_still_time = 0.0
		_pooled = false
	_wounds.append({rate = rate, local = npc.global_transform.affine_inverse() * info.point})
	set_process(true)


func _process(delta: float) -> void:
	_tick += delta
	if _tick < TICK:
		return
	var dt := _tick
	_tick = 0.0
	if health.is_dead or _wounds.is_empty():
		_wounds.clear()
		set_process(false)
		return
	var rate := 0.0
	var worst: Dictionary = _wounds[0]
	for wound in _wounds:
		wound.rate *= pow(0.5, dt / HALF_LIFE)
		rate += wound.rate
		if wound.rate > worst.rate:
			worst = wound
	_wounds = _wounds.filter(func(wound: Dictionary) -> bool: return wound.rate > BLEED_STOP)
	_trail_until = Time.get_ticks_msec() + int(BloodPool.TRAIL_LIFETIME * 1000.0)
	_drip(worst, rate, dt)
	_bleed_debt += rate * dt
	if _bleed_debt >= 1.0:
		var amount := floorf(_bleed_debt)
		_bleed_debt -= amount
		health.drain(amount)


## Una gota cada tanto según lo que anda, o un charco si se queda parada.
func _drip(wound: Dictionary, rate: float, dt: float) -> void:
	var here := _where()
	if npc.movement.is_swimming or _last_drop == Vector3.INF:
		# En el agua no queda nada; al salir, el rastro sigue desde la orilla.
		_last_drop = here
		_still_at = here
		return
	var thick := clampf(rate / FULL_RATE, 0.0, 1.0)
	if here.distance_to(_still_at) > STILL_REACH:
		_still_at = here
		_still_time = 0.0
		_pooled = false
	else:
		_still_time += dt
	if here.distance_to(_last_drop) >= lerpf(DROP_STEP.x, DROP_STEP.y, thick):
		_last_drop = here
		_bleed(wound, lerpf(DROP_SIZE.x, DROP_SIZE.y, thick) * randf_range(0.8, 1.2), 0.15, true)
	elif _still_time >= POOL_AFTER and not _pooled:
		_pooled = true
		_bleed(wound, lerpf(POOL_SIZE.x, POOL_SIZE.y, thick), POOL_GROW, false)


## Sangre en el suelo bajo [wound]: una gota de [size] m ([splat]) o un charco que se extiende en
## [grow] s.
func _bleed(wound: Dictionary, size: float, grow: float, splat: bool) -> void:
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * DROP_SCATTER
	var at: Vector3 = npc.global_transform * (wound.local + scatter)
	if BloodPool.spawn(npc, at, npc.gravity_direction * 9.8, size, grow, PhysicsLayers.WORLD, splat, true) != null:
		drops += 1


func _where() -> Vector3:
	return npc.planet.to_local(npc.global_position) if npc.planet != null else npc.global_position
