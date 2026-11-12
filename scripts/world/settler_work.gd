class_name SettlerWork extends RefCounted

## El trabajo de un colono (Companion en Companion.Mode.SETTLE): talar, picar o limpiar una zona. Lo
## lleva su Companion, que lo llama en su horario de trabajo (Villager.WORK_HOURS) y lo deja para
## dormir, pelear o charlar. Trabaja como el jugador: con lo que lleva en el morral (un hacha para
## talar, un pico para picar; sin ella no hace nada), va en línea recta hasta el árbol o la roca, lo
## golpea con los mismos golpes (MeleeMoveset) y la misma tala y picada (TreeFelling, RockMining):
## el árbol cae (se aparta), lo parte y parte sus trozos en leña; la roca suelta sus trozos y los
## pica hasta que dan piedras. Lo que saca entra en su morral y, al acabar cada árbol o roca, lo
## lleva al cofre (Storage) más cercano de la base que acepte su oficio (Storage.jobs). Sin cofre, o con
## todos llenos, tampoco trabaja. Si la línea recta no avanza (una pared, una casa), va por un camino
## (Companion.steer, GroundPath).
##
## Nunca comparten árbol ni roca: cada uno reserva lo suyo (_claims) y el siguiente va al siguiente.
## Busca alrededor de su base (WORK_RADIUS) o en la zona que se le dé (zone, zone_radius).
##
## Lejos del jugador (Companion.FREEZE) no hay colisión ni cuerpos que talar: lo que tenía a medias
## se da por hecho (se quita del mundo y lo que daba va al cofre) y desde ahí produce sin moverse, a
## su ritmo (rate: precalculado con su herramienta y corregido con lo que ha tardado de verdad), con
## su herramienta, en su horario y mientras quepa en el cofre. Limpiar una zona solo avanza cerca.
##
## Los demás oficios (construir, hacer guardia, cazar, pescar, cocinar) los lleva cada uno su
## SettlerTask, que este crea al mandarlo (assign) y al que pasa cada paso; aquí queda lo común: el
## oficio, la zona, el estado, el guardado y las reservas. Con hambre (SettlerMeals) todos van a la
## mitad de ritmo (pace). Ver docs/villagers.md.

enum Job {NONE, FELL, MINE, CLEAR, BUILD, GUARD, HUNT, FISH, COOK}
## Cómo va, para la charla (y en el futuro, lo que se ve sobre él). BLOCKED: parado por lo que dice
## reason (los oficios de SettlerTask).
enum Status {IDLE, WORKING, NO_TOOL, NO_CHEST, CHEST_FULL, DONE, OFF_HOURS, AWAY, BLOCKED}
## Lo que hace dentro del trabajo: buscar, ir y golpear lo que tiene, apartarse del árbol que cae,
## esperar a que caigan los trozos y llevar lo sacado al cofre.
enum Step {SEEK, STRIKE, CLEAR_OF, SETTLE, DEPOSIT}

## El oficio de cada trabajo, el que se marca en los cofres (Storage.jobs).
## El guardia no usa cofres.
const JOB_IDS := {Job.FELL: &"fell", Job.MINE: &"mine", Job.CLEAR: &"clear", Job.BUILD: &"build",
	Job.HUNT: &"hunt", Job.FISH: &"fish", Job.COOK: &"cook"}
const JOB_NAMES := {Job.FELL: "SETTLER_JOB_FELL", Job.MINE: "SETTLER_JOB_MINE", Job.CLEAR: "SETTLER_JOB_CLEAR",
	Job.BUILD: "SETTLER_JOB_BUILD", Job.GUARD: "SETTLER_JOB_GUARD", Job.HUNT: "SETTLER_JOB_HUNT",
	Job.FISH: "SETTLER_JOB_FISH", Job.COOK: "SETTLER_JOB_COOK"}
## Con hambre trabaja a este ritmo.
const HUNGRY_PACE := 0.5
## Dónde busca (m): alrededor de la base, o la zona que se limpia.
const WORK_RADIUS := 60.0
const CLEAR_RADIUS := 12.0
## Los cofres de la base: a menos de esto (m) de ella.
const CHEST_REACH := 60.0
## Sin nada a la vista, vuelve a mirar cada SEEK_EVERY s. Va por Companion.steer (en línea recta y, si no
## avanza, por un camino). Lo que no se acerca al menos PROGRESS m (por el camino) en GIVE_UP s lo deja
## SKIP_TIME s.
const SEEK_EVERY := 3.0
## Sin nada que hacer en su zona, vuelve a mirar cada DONE_RECHECK s (mientras, hace su vida).
const DONE_RECHECK := 30.0
## Para darla por vacía: tantas búsquedas seguidas sin nada, con la zona entera a menos de LOADED_REACH m
## de la cámara (VoxelInstancer.collision_distance de los árboles y las rocas: 200-256 m).
const EMPTY_SEEKS := 3
const LOADED_REACH := 180.0
const GIVE_UP := 12.0
const SKIP_TIME := 120.0
const PROGRESS := 0.3
## Golpea con la superficie de lo que tala o pica a menos de STRIKE_GAP m de su cuerpo; deja las cosas
## en el cofre a menos de DEPOSIT_REACH m.
const STRIKE_GAP := 0.9
const DEPOSIT_REACH := 1.8
## Al caer su árbol se aparta CLEAR_DISTANCE m (o CLEAR_TIME s) del tocón.
const CLEAR_DISTANCE := 4.0
const CLEAR_TIME := 3.0
## Los trozos del árbol (a menos de LOG_SEARCH m de su eje) y de la roca (a menos de FRAGMENT_SEARCH m
## de su centro) son suyos. Espera a que caigan hasta SETTLE_TIME s.
const LOG_SEARCH := 2.5
const FRAGMENT_SEARCH := 6.0
const SETTLE_TIME := 2.5
## Entre golpe y golpe.
const SWING_PAUSE := Vector2(0.25, 0.6)
const WALK_SPEED := 1.8
const WOOD_ID := &"wood_01"
const STONE_ID := &"stone_01"
## El ritmo sin medir: lo que da un árbol o una roca corriente, el trabajo que piden (lo de tumbarlo o
## soltar sus trozos y lo de partirlos) y lo que se va en andar y llevarlo al cofre (s).
const TREE_WOOD := 12.0
const TREE_WORK := 260.0
const ROCK_STONES := 45.0
const ROCK_WORK := 320.0
const TRIP_TIME := 30.0
## Lo que pesa cada medida nueva en el ritmo.
const RATE_BLEND := 0.3

## Lo que tiene cada uno: instance_id de lo que tala o pica -> el Companion.
static var _claims := {}

var job := Job.NONE
var status := Status.IDLE
## La zona (marco del terreno; Vector3.INF: alrededor de la base) y su radio.
var zone := Vector3.INF
var zone_radius := WORK_RADIUS
## Lo que lleva sacado desde que se le dio el trabajo.
var gathered := 0
## Lo que saca por segundo con cada oficio (medido; sin medir, rate lo calcula).
var rates := {}
## El turno del guardia (0 de día, 1 de noche) y, parado (Status.BLOCKED), por qué (ya traducido).
var shift := 0
var reason := ""
## Quien lleva el oficio si no es talar, picar ni limpiar; si no, null.
var task: SettlerTask

var _c: Companion
var _step := Step.SEEK
## Lo que golpea ahora: un árbol en pie (VoxelInstancerRigidBody), uno caído (FallingTree), un trozo
## de tronco (TreeLog), una roca (del instancer), una a medio picar (FracturedRock) o un trozo suyo
## (RockFragment).
var _target: Node3D
## El árbol o la roca de ahora: su centro y su eje (marco del terreno; el de un árbol caído) y lo que
## llevaba sacado al empezar, y cuándo empezó (para el ritmo).
var _site := Vector3.INF
var _site_axis := PackedVector3Array()
var _site_rocks := false
var _site_gathered := 0
var _site_time := 0.0
var _seek_left := 0.0
var _stuck_left := GIVE_UP
## Lo más cerca que ha llegado de [_approach_for] (lo que busca ahora).
var _best_distance := INF
var _approach_for: Object
var _skip := {}
var _swing_left := 0.0
var _impact_at := -1.0
var _pause_left := 0.0
var _step_left := 0.0
var _combo := 0
var _away := false
var _owed := 0.0
var _chest: Storage
var _empty_seeks := 0


func _init(companion: Companion) -> void:
	_c = companion
	_c.pack.item_added.connect(_on_pack_added)


## Lo que saca de verdad (la leña y las piedras entran en su morral al partir y al picar) cuenta en
## gathered; lo que le da el jugador en la charla, no (no trabaja mientras charla).
func _on_pack_added(data: ItemData, quantity: int) -> void:
	if task == null and active() and status == Status.WORKING and not _c.is_chatting() and data.category == ItemData.Category.MATERIAL:
		gathered += quantity


func active() -> bool:
	return job != Job.NONE


## Trabajando ahora mismo (va a algo, lo golpea, se aparta, lleva lo sacado).
func busy() -> bool:
	return active() and status == Status.WORKING


## Empieza [what] (en [at], marco del terreno, si es limpiar: si no, alrededor de la base). [turn]: el
## turno del guardia (0 de día, 1 de noche).
func assign(what: Job, at := Vector3.INF, radius := -1.0, turn := 0) -> void:
	stop()
	job = what
	zone = at
	zone_radius = radius if radius > 0.0 else (CLEAR_RADIUS if what == Job.CLEAR else WORK_RADIUS)
	shift = turn
	gathered = 0
	status = Status.WORKING
	task = _make_task(what)
	if task != null:
		task.start()


func _make_task(what: Job) -> SettlerTask:
	match what:
		Job.BUILD:
			return SettlerBuild.new(self)
		Job.GUARD:
			return SettlerGuard.new(self)
		Job.HUNT:
			return SettlerHunt.new(self)
		Job.FISH:
			return SettlerFish.new(self)
		Job.COOK:
			return SettlerCook.new(self)
	return null


## Lo deja: suelta lo que tenía.
func stop() -> void:
	if task != null:
		task.stop()
		task = null
	_release()
	job = Job.NONE
	status = Status.IDLE
	reason = ""
	_step = Step.SEEK
	_swing_left = 0.0
	_impact_at = -1.0


## Si toca trabajar a la hora [hour] de la base.
func on_duty(hour: float) -> bool:
	if not active():
		return false
	if not (task.on_duty(hour) if task != null else Villager._work_hour(hour)):
		if status != Status.DONE:
			status = Status.OFF_HOURS
		return false
	return status != Status.DONE or _now() >= _seek_left


## Si a la hora [hour] duerme (el guardia de noche, de día).
func sleeps(hour: float) -> bool:
	return task.sleeps(hour) if task != null else Villager._is_night(hour)


## El ritmo al que trabaja: con hambre, a la mitad.
func pace() -> float:
	return HUNGRY_PACE if _c.meals != null and _c.meals.hungry() else 1.0


## Parado por [why] (ya traducido).
func block(why: String) -> void:
	status = Status.BLOCKED
	reason = why


## Nada que hacer por ahora: vuelve a mirar a los DONE_RECHECK s (mientras, hace su vida).
func rest_done() -> void:
	status = Status.DONE
	_seek_left = _now() + DONE_RECHECK


## Lo que guarda peleando (mundo): el guardia y el cazador, su zona; los demás, la base. Y hasta dónde
## va a por lo que ataca (m).
func guard_point() -> Vector3:
	var at := zone if zone.is_finite() and (job == Job.GUARD or job == Job.HUNT) else _c.base
	return _c._terrain.global_transform * at


func defend_radius() -> float:
	return zone_radius + SettlerGuard.ALERT if job == Job.GUARD else Companion.DEFEND


## Si [creature] es cosa suya aunque no ataque a nadie: el guardia de turno, a las fieras que atacan a
## la vista.
func is_threat(creature: NPCController) -> bool:
	return task is SettlerGuard and (task as SettlerGuard).is_threat(creature)


## Ha salido a por [creature] (Companion._scan): el guardia da la alarma.
func on_engage(creature: NPCController) -> void:
	if task is SettlerGuard:
		(task as SettlerGuard).alarm(creature)


# --- Cerca: de verdad ------------------------------------------------------------------------------

## Un paso de trabajo: [hacia dónde, a qué velocidad].
func step(delta: float) -> Array:
	_away = false
	# Lo que golpeaba ya no está (un cuerpo del instancer que se ha ido): se suelta.
	if _target != null and not is_instance_valid(_target):
		_target = null
		_release()
	if status == Status.OFF_HOURS or status == Status.AWAY:
		status = Status.WORKING
	if task != null:
		return task.step(delta)
	if _swing_left > 0.0:
		return _swinging(delta)
	match _step:
		Step.CLEAR_OF:
			return _clearing(delta)
		Step.SETTLE:
			_step_left -= delta
			var piece := _next_piece()
			if piece != null:
				_target = piece
				_step = Step.STRIKE
			elif _step_left <= 0.0:
				_finish_site()
			return _still()
		Step.DEPOSIT:
			return _depositing(delta)
		Step.STRIKE:
			if _valid(_target):
				return _striking(delta)
			_target = _next_piece()
			if _target == null:
				_finish_site()
			return _still()
	return _seek()


func _seek() -> Array:
	if _now() < _seek_left:
		return _still()
	_seek_left = _now() + SEEK_EVERY
	var trees := job != Job.MINE and _tool(true) != null
	var rocks := job != Job.FELL and _tool(false) != null
	if not trees and not rocks:
		status = Status.NO_TOOL
		return _still()
	if not _has_chest():
		return _still()
	if _carried() > 0:
		_begin_deposit()
		return _still()
	_target = _find(trees, rocks)
	if _target == null:
		# Sin la zona cerca de la cámara (al cargar, al mirar lejos) los árboles y las rocas no tienen
		# cuerpo: no se da por acabada hasta verla vacía EMPTY_SEEKS veces seguidas estando cerca.
		_empty_seeks = _empty_seeks + 1 if _zone_loaded() else 0
		if _empty_seeks < EMPTY_SEEKS:
			return _still()
		_empty_seeks = 0
		status = Status.DONE
		_seek_left = _now() + DONE_RECHECK
		if job == Job.CLEAR:
			_c.notify(_c.tr("SETTLER_CLEAR_DONE") % String(_c.resident.get("name", "")))
			stop()
			status = Status.DONE
		return _still()
	status = Status.WORKING
	_empty_seeks = 0
	_claim(_target)
	_site = _local(_center(_target))
	_site_rocks = _is_rockish(_target)
	_site_axis = PackedVector3Array()
	_site_gathered = gathered
	_site_time = _now()
	_approach_for = null
	_step = Step.STRIKE
	return _still()


## Va hasta lo que golpea y, a tiro, lo encara y golpea.
func _striking(delta: float) -> Array:
	var center := _center(_target)
	var to := center - _c.global_position
	var up := _c.up_direction
	var flat := to - up * to.dot(up)
	var gap := flat.length() - _radius(_target) - Villager.BODY_RADIUS
	if gap > STRIKE_GAP:
		var reach := _radius(_target) + Villager.BODY_RADIUS + STRIKE_GAP * 0.8
		var heading := _c.steer(center, reach, delta)
		if not _approaching(_target, _c.steer_remaining(center), delta):
			_skip[_target.get_instance_id()] = _now() + SKIP_TIME
			_release()
			_step = Step.SEEK
			return _still()
		return [heading, WALK_SPEED]
	_approach_for = null
	_c._face(to, delta)
	_pause_left -= delta
	var toward := _c._tangent(to)
	if _pause_left <= 0.0 and toward != Vector3.ZERO and _c.facing().angle_to(toward) < deg_to_rad(25.0):
		_swing()
	return _still()


## Si se va acercando a [target]: [distance] (lo que le falta) baja al menos PROGRESS m de lo mejor cada
## GIVE_UP s. Con otro objetivo, empieza de cero.
func _approaching(target: Object, distance: float, delta: float) -> bool:
	if target != _approach_for:
		_approach_for = target
		_best_distance = INF
		_stuck_left = GIVE_UP
	if distance < _best_distance - PROGRESS:
		_best_distance = distance
		_stuck_left = GIVE_UP
		return true
	_stuck_left -= delta
	return _stuck_left > 0.0


func _swing() -> void:
	var tool := _tool(not _is_rockish(_target))
	if tool == null:
		status = Status.NO_TOOL
		_step = Step.SEEK
		return
	_c.hold_work_tool(tool)
	var move := MeleeMoveset.move(MeleeMoveset.family_for(tool), "light", _combo)
	_combo += 1
	var speed := maxf(tool.attack_speed, 0.3) * float(move.get("speed", 1.0))
	var hit: Vector2 = move.hit
	_c.play_work(move.anim, speed)
	_impact_at = lerpf(hit.x, hit.y, PlayerCombat.CHOP_IMPACT) / speed
	_swing_left = float(move.end) / speed
	_c.set_busy(_swing_left)
	_pause_left = _c._rng.randf_range(SWING_PAUSE.x, SWING_PAUSE.y) / pace()


func _swinging(delta: float) -> Array:
	_swing_left -= delta
	if _impact_at >= 0.0:
		_impact_at -= delta
		if _impact_at < 0.0:
			_impact()
	return _still()


## El golpe llega a lo que tiene delante.
func _impact() -> void:
	if not _valid(_target):
		return
	var rock := _is_rockish(_target)
	var tool := _tool(not rock)
	if tool == null:
		return
	var center := _center(_target)
	var toward := (_c.global_position - center)
	toward = (toward - _c.up_direction * toward.dot(_c.up_direction)).normalized()
	var point := center + toward * _radius(_target) * 0.8
	if rock:
		var power := RockMining.mine_power(tool)
		if _target is RockFragment:
			(_target as RockFragment).hit(power, _c)
		elif _target is FracturedRock:
			(_target as FracturedRock).hit(point, power, _c)
		else:
			var was := _target
			RockMining.hit_any(was, point, power, _c)
			# La roca entera se cambia por sus trozos en el primer golpe.
			_release_one(was)
			_target = _nearest_in(FracturedRock.GROUP, center, 1.5)
			if _target != null:
				_claim(_target)
		if not _valid(_target):
			_after_piece()
		return
	var chop := TreeFelling.chop_power(tool)
	if _is_tree(_target):
		var felling := TreeFelling.for_body(_target)
		if felling != null:
			felling.chop(_target, chop, _c)
		# Si ha caído, on_felled ya ha cambiado lo que tiene.
		return
	if _target is FallingTree:
		var falling := _target as FallingTree
		_site_axis = _to_local_points(falling._axis_world())
		falling.hack(_on_axis(falling._axis_world(), 0.3), chop, _c)
		if falling._split:
			_release_one(falling)
			_target = null
			_step = Step.SETTLE
			_step_left = SETTLE_TIME
		return
	if _target is TreeLog:
		(_target as TreeLog).hack(_target.global_position, chop, _c)
		if not _valid(_target):
			_after_piece()


## Su árbol ha caído (TreeFelling): se aparta y, tumbado, lo parte.
func on_felled(falling: FallingTree) -> void:
	_release()
	_target = falling
	_claim(falling)
	_step = Step.CLEAR_OF
	_step_left = CLEAR_TIME


func _clearing(delta: float) -> Array:
	_step_left -= delta
	var away := _c.global_position - _c._terrain.global_transform * _site
	var up := _c.up_direction
	var flat := away - up * away.dot(up)
	if _step_left > 0.0 and flat.length() < CLEAR_DISTANCE:
		return [_c._tangent(away), Companion.JOG_SPEED]
	if not _valid(_target):
		_after_piece()
	elif (_target as FallingTree)._resting:
		_step = Step.STRIKE
	return _still()


## Acabado un trozo: el siguiente del mismo árbol o roca, o espera a que caigan.
func _after_piece() -> void:
	_release_one(_target)
	_target = _next_piece()
	if _target == null:
		_step = Step.SETTLE
		_step_left = SETTLE_TIME * 0.5
	else:
		_step = Step.STRIKE


## Lo siguiente del árbol o la roca de ahora: un trozo de tronco junto a su eje o un trozo de roca
## junto a su centro (ya en el suelo), libre; o null.
func _next_piece() -> Node3D:
	if not _site.is_finite():
		return null
	var best: Node3D
	var best_d := INF
	if _site_rocks:
		var center := _c._terrain.global_transform * _site
		for node in _c.get_tree().get_nodes_in_group(RockFragment.GROUP):
			var fragment := node as RockFragment
			if fragment == null or not fragment.is_ready() or _taken(fragment):
				continue
			var d := fragment.center().distance_to(center)
			if d < FRAGMENT_SEARCH and d < best_d:
				best = fragment
				best_d = d
		var rest := _nearest_in(FracturedRock.GROUP, center, 1.5)
		if best == null and rest != null and not _taken(rest):
			best = rest
	elif _site_axis.size() == 2:
		var to_world := _c._terrain.global_transform
		var a := to_world * _site_axis[0]
		var b := to_world * _site_axis[1]
		for node in _c.get_tree().get_nodes_in_group(TreeLog.GROUP):
			var chunk := node as TreeLog
			if chunk == null or not chunk.is_ready() or _taken(chunk):
				continue
			var d := Geometry3D.get_closest_point_to_segment(chunk.global_position, a, b).distance_to(chunk.global_position)
			if d < LOG_SEARCH and d < best_d:
				best = chunk
				best_d = d
	if best != null:
		_claim(best)
	return best


## Acabado el árbol o la roca: el ritmo medido y, al cofre.
func _finish_site() -> void:
	var made := gathered - _site_gathered
	var took := _now() - _site_time + TRIP_TIME
	if made > 0 and took > 1.0:
		var key := JOB_IDS[Job.MINE if _site_rocks else Job.FELL] as StringName
		rates[key] = lerpf(rate(Job.MINE if _site_rocks else Job.FELL), float(made) / took, RATE_BLEND)
	_site = Vector3.INF
	_site_axis = PackedVector3Array()
	_release()
	_step = Step.SEEK
	_seek_left = 0.0
	if _carried() > 0:
		_begin_deposit()


func _begin_deposit() -> void:
	_chest = _find_chest(_carried_item())
	_step = Step.DEPOSIT if _chest != null else Step.SEEK
	_approach_for = null


func _depositing(delta: float) -> Array:
	if not is_instance_valid(_chest) or not _chest.is_inside_tree():
		_begin_deposit()
		return _still()
	var to := _chest.global_position - _c.global_position
	var up := _c.up_direction
	var distance := (to - up * to.dot(up)).length()
	# Si no llega (atascado), lo deja igual: que no se quede parado con el morral lleno.
	if distance > DEPOSIT_REACH:
		var heading := _c.steer(_chest.global_position, DEPOSIT_REACH * 0.8, delta)
		if _approaching(_chest, _c.steer_remaining(_chest.global_position), delta):
			return [heading, WALK_SPEED]
	_approach_for = null
	_store(_chest)
	_step = Step.SEEK
	_seek_left = 0.0
	return _still()


## Pasa al cofre lo sacado que lleva (no las herramientas ni la comida). Lo que no cabe, lo sigue
## llevando (y el cofre ya no le vale: está lleno).
func _store(chest: Storage) -> void:
	for item in _c.pack.get_all_items():
		if item == null or item.data.category != ItemData.Category.MATERIAL:
			continue
		var amount := item.quantity
		var left := chest.inventory.add_item(item.data, amount)
		if amount - left > 0:
			_c.pack.remove_item(item.data, amount - left)


## Lo que lleva sacado (de MATERIAL) en el morral.
func _carried() -> int:
	var count := 0
	for item in _c.pack.get_all_items():
		if item != null and item.data.category == ItemData.Category.MATERIAL:
			count += item.quantity
	return count


func _carried_item() -> ItemData:
	for item in _c.pack.get_all_items():
		if item != null and item.data.category == ItemData.Category.MATERIAL:
			return item.data
	return null


func _still() -> Array:
	return [Vector3.ZERO, 0.0]


# --- Lejos: producción sin moverse ----------------------------------------------------------------

## Un paso lejos del jugador, a la hora [hour] de la base.
func away(delta: float, hour: float) -> void:
	if task != null:
		_away = true
		if task.on_duty(hour):
			task.away(delta, hour)
		elif status != Status.DONE:
			status = Status.OFF_HOURS
		return
	if not _away:
		_away = true
		_settle_debts()
	if job != Job.FELL and job != Job.MINE:
		if active():
			status = Status.AWAY
		return
	if not Villager._work_hour(hour):
		status = Status.OFF_HOURS
		return
	if _tool(job == Job.FELL) == null:
		status = Status.NO_TOOL
		return
	var data := ItemCatalog.get_item(WOOD_ID if job == Job.FELL else STONE_ID)
	var chest := _find_chest(data)
	if chest == null:
		return
	status = Status.AWAY
	_owed += rate(job) * delta * pace()
	if _owed < 1.0:
		return
	var amount := floori(_owed)
	_owed -= amount
	var left := chest.inventory.add_item(data, amount)
	gathered += amount - left


## Al irse lejos: lo que tenía a medias se da por hecho (se quita del mundo) y lo que daba, con lo que
## lleva sacado, va al cofre.
func _settle_debts() -> void:
	_swing_left = 0.0
	_impact_at = -1.0
	var owed := {}
	for id in _claims.keys():
		if _claims[id] != _c:
			continue
		var node := instance_from_id(id) as Node3D
		if not _valid(node):
			continue
		var yield_of := _yield_of(node)
		if not yield_of.is_empty():
			owed[yield_of[0]] = int(owed.get(yield_of[0], 0)) + int(yield_of[1])
		if node is VoxelInstancerRigidBody:
			(node as VoxelInstancerRigidBody).queue_free_and_notify_instancer()
		else:
			node.queue_free()
	_release()
	_target = null
	_site = Vector3.INF
	_step = Step.SEEK
	for data: ItemData in owed:
		_c.pack.add_item(data, owed[data])
	var chest := _find_chest(_carried_item())
	if chest != null:
		_store(chest)


## [lo que da, cuánto] de un árbol, roca o trozo a medias; [] si nada.
func _yield_of(node: Node3D) -> Array:
	if node is TreeLog:
		return [(node as TreeLog)._wood, (node as TreeLog)._amount] if (node as TreeLog)._wood != null else []
	if node is FallingTree:
		var falling := node as FallingTree
		return [falling._wood, falling._wood_amount] if falling._wood != null else []
	if node is RockFragment:
		var fragment := node as RockFragment
		return [fragment._stone, fragment._stones] if fragment._stone != null else []
	if node is FracturedRock:
		var stones := 0
		for entry in (node as FracturedRock)._pieces.values():
			stones += int(entry.stones)
		return [(node as FracturedRock)._item, stones]
	var felling := TreeFelling.for_body(node)
	if felling != null and felling.is_choppable(node):
		var info := felling._species_of(node as VoxelInstancerRigidBody)
		var scale := node.global_basis.y.length()
		var wood := clampi(roundi(TreeFelling.WOOD_PER_M2 * float(info.radius) * scale * 2.0 * float(info.height) * scale)
			+ TreeFelling.MIN_WOOD, TreeFelling.MIN_WOOD, TreeFelling.MAX_WOOD)
		return [info.wood, wood]
	var found := RockMining.rock_of(node)
	if not found.is_empty():
		var shape := (found[1] as RockMining)._shape_of(found[0])
		var stones := clampi(roundi(RockMining.STONES_PER_METER * float(shape.size) * float(shape.ore_yield)),
			RockMining.STONES.x, RockMining.STONES.y)
		return [shape.item, stones]
	return []


## Lo que saca por segundo con [what]: lo medido o, sin medir, lo que da su herramienta.
func rate(what: Job) -> float:
	var key: StringName = JOB_IDS.get(what, &"")
	if rates.has(key):
		return float(rates[key])
	var trees := what != Job.MINE
	var tool := _tool(trees)
	if tool == null:
		return 0.0
	var move := MeleeMoveset.move(MeleeMoveset.family_for(tool), "light", 0)
	var speed := maxf(tool.attack_speed, 0.3) * float(move.get("speed", 1.0))
	var swing := float(move.end) / speed + (SWING_PAUSE.x + SWING_PAUSE.y) * 0.5
	var power := TreeFelling.chop_power(tool) if trees else RockMining.mine_power(tool)
	if power <= 0.0:
		return 0.0
	var work := TREE_WORK if trees else ROCK_WORK
	return (TREE_WOOD if trees else ROCK_STONES) / (work / power * swing + TRIP_TIME)


# --- Qué, con qué y dónde -------------------------------------------------------------------------

## La mejor herramienta del morral para talar ([trees]) o picar, o null.
func _tool(trees: bool) -> ItemData:
	var best: ItemData
	var best_power := 0.0
	for item in _c.pack.get_all_items():
		if item == null:
			continue
		var fits := TreeFelling.fells(item.data) if trees else RockMining.mines(item.data)
		var power := TreeFelling.chop_power(item.data) if trees else RockMining.mine_power(item.data)
		if fits and power > best_power:
			best = item.data
			best_power = power
	return best


## Si la zona entera está cerca de la cámara (sus árboles y rocas tienen cuerpo).
func _zone_loaded() -> bool:
	var camera := _c.get_viewport().get_camera_3d()
	if camera == null:
		return true
	var center := _c._terrain.global_transform * (zone if zone.is_finite() else _c.base)
	return camera.global_position.distance_to(center) + zone_radius <= LOADED_REACH


## Si hay cofre con sitio para lo de su oficio; si no, el estado dice por qué.
func _has_chest() -> bool:
	var data := ItemCatalog.get_item(STONE_ID if job == Job.MINE else WOOD_ID)
	if _find_chest(data) != null:
		return true
	status = Status.CHEST_FULL if _find_chest(null) != null else Status.NO_CHEST
	return false


## El cofre de la base para su oficio con sitio para [data] (sin [data], cualquiera que lo acepte): los
## marcados con su oficio antes que los que aceptan todo, y de ellos el más cercano a él. O null.
func _find_chest(data: ItemData) -> Storage:
	if not _c.base.is_finite():
		return null
	var center := _c._terrain.global_transform * _c.base
	var id: StringName = JOB_IDS.get(job, &"")
	var best: Storage
	var best_score := INF
	for node in _c.get_tree().get_nodes_in_group(Storage.GROUP):
		var chest := node as Storage
		if chest == null or not chest.is_inside_tree() or chest.is_queued_for_deletion() \
				or chest.global_position.distance_to(center) > CHEST_REACH or not chest.accepts_job(id):
			continue
		if data != null and not _room(chest.inventory, data):
			continue
		var score := chest.global_position.distance_to(_c.global_position) + (0.0 if chest.jobs.has(id) else 1000.0)
		if score < best_score:
			best = chest
			best_score = score
	return best


static func _room(inventory: Inventory, data: ItemData) -> bool:
	for i in inventory.items.size():
		var item := inventory.items[i]
		if item == null:
			if inventory.accepts(i, data):
				return true
		elif item.data == data and item.quantity < inventory.capacity(i, data):
			return true
	return false


## Lo más cercano a él que talar ([trees]) o picar ([rocks]) en su zona, libre y alcanzable: árboles y
## rocas del instancer y lo que haya quedado a medias (troncos caídos, trozos).
func _find(trees: bool, rocks: bool) -> Node3D:
	var center := _c._terrain.global_transform * (zone if zone.is_finite() else _c.base)
	var best: Node3D
	var best_d := INF
	# Los árboles y las rocas con cuerpo cuelgan del instancer del terreno (cerca de la cámara). Una
	# consulta de física no vale: la colisión del terreno son cientos de trozos y se come el cupo.
	var candidates: Array[Node3D] = []
	for instancer in _c._terrain.get_children():
		if not (instancer is VoxelInstancer and instancer.has_meta(TreeFelling.META)):
			continue
		for child in instancer.get_children():
			var body := child as Node3D
			if body == null or body.global_position.distance_to(center) > zone_radius:
				continue
			if _is_tree(body):
				if trees:
					candidates.append(body)
			elif rocks and not RockMining.rock_of(body).is_empty():
				candidates.append(body)
	var groups: Array[StringName] = []
	if trees:
		groups.append_array([FallingTree.GROUP, TreeLog.GROUP])
	if rocks:
		groups.append_array([FracturedRock.GROUP, RockFragment.GROUP])
	for group in groups:
		for node in _c.get_tree().get_nodes_in_group(group):
			if node is Node3D and (node as Node3D).global_position.distance_to(center) < zone_radius:
				candidates.append(node)
	for node in candidates:
		if not _valid(node) or _taken(node) or _skip.get(node.get_instance_id(), 0.0) > _now():
			continue
		if node is TreeLog and not (node as TreeLog).is_ready():
			continue
		if node is RockFragment and not (node as RockFragment).is_ready():
			continue
		if node is FallingTree and not (node as FallingTree)._resting:
			continue
		var d := _center(node).distance_to(_c.global_position)
		if d < best_d:
			best = node
			best_d = d
	return best


func _is_rockish(node: Node3D) -> bool:
	if node is RockFragment or node is FracturedRock:
		return true
	if node == null or node is FallingTree or node is TreeLog:
		return false
	return not _is_tree(node)


## Un árbol en pie del instancer (las rocas también cuelgan de él, pero no se talan).
static func _is_tree(node: Node) -> bool:
	var felling := TreeFelling.for_body(node) if node is VoxelInstancerRigidBody else null
	return felling != null and felling.is_choppable(node)


## Por dónde se le golpea (mundo).
func _center(node: Node3D) -> Vector3:
	if node is FallingTree:
		return _on_axis((node as FallingTree)._axis_world(), 0.3)
	if node is RockFragment:
		return (node as RockFragment).center()
	if _is_tree(node):
		return node.global_position + node.global_basis.y.normalized() * 1.0
	var found := RockMining.rock_of(node)
	if not found.is_empty():
		return (found[1] as RockMining)._shape_of(found[0]).center
	return node.global_position


## Lo que mide de radio (m).
func _radius(node: Node3D) -> float:
	if node is FallingTree:
		return (node as FallingTree)._radius
	if node is TreeLog:
		return (node as TreeLog).radius
	if node is RockFragment:
		return (node as RockFragment).radius
	if _is_tree(node):
		var felling := TreeFelling.for_body(node)
		if felling != null:
			return float(felling._species_of(node as VoxelInstancerRigidBody).get("radius", 0.2)) * node.global_basis.y.length()
	var found := RockMining.rock_of(node)
	if not found.is_empty():
		return float((found[1] as RockMining)._shape_of(found[0]).size) * 0.5
	return 0.8


static func _on_axis(axis: PackedVector3Array, t: float) -> Vector3:
	return axis[0].lerp(axis[1], t) if axis.size() == 2 else Vector3.ZERO


func _to_local_points(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		out.append(_local(p))
	return out


func _local(world: Vector3) -> Vector3:
	return _c._terrain.global_transform.affine_inverse() * world


static func _nearest_in(group: StringName, at: Vector3, reach: float) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	var best: Node3D
	var best_d := reach
	for node in tree.get_nodes_in_group(group):
		var n := node as Node3D
		if n != null and not n.is_queued_for_deletion() and n.global_position.distance_to(at) < best_d:
			best = n
			best_d = n.global_position.distance_to(at)
	return best


## Sin tipo: lo que golpea puede haberse liberado (un cuerpo del instancer se va cuando la cámara se
## aleja, el trono la mueve), y un argumento con tipo falla con un objeto liberado.
static func _valid(node: Variant) -> bool:
	return node != null and is_instance_valid(node) and node is Node and (node as Node).is_inside_tree() \
		and not (node as Node).is_queued_for_deletion()


# --- Reservas -------------------------------------------------------------------------------------

func _taken(node: Node) -> bool:
	var owner: Variant = _claims.get(node.get_instance_id())
	return owner != null and owner != _c and is_instance_valid(owner) and (owner as Companion).is_inside_tree()


func _claim(node: Node) -> void:
	if node != null:
		_claims[node.get_instance_id()] = _c


func _release_one(node: Variant) -> void:
	if node != null and is_instance_valid(node) and _claims.get((node as Object).get_instance_id()) == _c:
		_claims.erase(node.get_instance_id())


## Suelta todo lo suyo (y lo de los que ya no están).
func _release() -> void:
	for id in _claims.keys():
		var owner: Variant = _claims[id]
		if owner == _c or owner == null or not is_instance_valid(owner) or not is_instance_valid(instance_from_id(id)):
			_claims.erase(id)
	_target = null


# --- Charla y guardado ----------------------------------------------------------------------------

## Cómo va, para la charla: "Talando · 14 sacados", "Parado: necesita un hacha"...
func describe() -> String:
	if not active() and status != Status.DONE:
		return ""
	var text := _describe()
	return text + _c.tr("SETTLER_HUNGRY") if text != "" and pace() < 1.0 else text


func _describe() -> String:
	var what := _c.tr(JOB_NAMES.get(job, "SETTLER_JOB_NONE"))
	if task != null:
		match status:
			Status.BLOCKED:
				return _c.tr("SETTLER_BLOCKED") % reason
			Status.DONE:
				return _c.tr("SETTLER_NOTHING_LEFT") % what
		return task.describe()
	match status:
		Status.NO_TOOL:
			return _c.tr("SETTLER_NO_TOOL_MINE" if job == Job.MINE else "SETTLER_NO_TOOL_FELL")
		Status.NO_CHEST:
			return _c.tr("SETTLER_NO_CHEST") % what
		Status.CHEST_FULL:
			return _c.tr("SETTLER_CHEST_FULL")
		Status.DONE:
			return _c.tr("SETTLER_NOTHING_LEFT") % what
		Status.OFF_HOURS:
			return _c.tr("SETTLER_OFF_HOURS") % [what, gathered]
		Status.AWAY:
			return _c.tr("SETTLER_AWAY") % [what, gathered]
	return _c.tr("SETTLER_WORKING") % [what, gathered]


func save_data() -> Dictionary:
	if not active() and rates.is_empty():
		return {}
	var out := {"job": int(job), "radius": zone_radius, "gathered": gathered, "rates": rates.duplicate()}
	if zone.is_finite():
		out.zone = [zone.x, zone.y, zone.z]
	if shift != 0:
		out.shift = shift
	if task != null:
		var extra := task.save_data()
		if not extra.is_empty():
			out.task = extra
	return out


func restore(data: Dictionary) -> void:
	var raw: Array = data.get("zone", [])
	var what := int(data.get("job", 0)) as Job
	if what != Job.NONE:
		assign(what, Vector3(raw[0], raw[1], raw[2]) if raw.size() == 3 else Vector3.INF,
			float(data.get("radius", -1.0)), int(data.get("shift", 0)))
		if task != null:
			task.restore(data.get("task", {}))
	gathered = int(data.get("gathered", 0))
	var saved: Dictionary = data.get("rates", {})
	for key in saved:
		rates[StringName(key)] = float(saved[key])


static func _now() -> float:
	return Time.get_ticks_msec() * 0.001
