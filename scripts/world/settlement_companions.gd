class_name SettlementCompanions extends Node

## Los aldeanos que se han ido con el jugador (Companion): los que lo acompañan y los que viven en su
## base (colonos, Companion.Mode.SETTLE). Se recluta en la charla (VillagerChat) a quien
## sea de un poblado que se fía bastante (SettlementRelations.RECRUIT_TRUST): el aldeano deja su poblado,
## que ya no lo saca mientras vaya con el jugador (SettlementVillagers), y se lleva su humano. Se guardan
## con la partida (categoría "npc"): su poblado, su vecino (que se vuelve a sacar del plano, como en el
## poblado), si sigue, espera o vive en la base (y dónde la tiene), dónde está (en el marco del
## terreno), lo que lleva, su vida y su trabajo (SettlerWork). Los que mueren (Companion.crush) no vuelven a
## salir en su poblado.
##
## Los que acompañan forman un grupo (hasta MAX) que sigue al jugador en formación: en cuña detrás de él,
## en fila por donde ha pasado o sueltos. Aquí se lleva el rastro del jugador y hacia dónde va, y de ahí
## sale el hueco de cada uno (slot_of). Las órdenes al grupo (GroupCommand: la rueda) pasan por aquí:
## seguid, esperad, atacad, retirada y volved a la base. Ver docs/villagers.md.

enum Formation {WEDGE, FILE, LOOSE}

## Cuántos acompañan a la vez, y cuántos viven en la base.
const MAX := 6
const MAX_SETTLERS := 20
const FORMATION_NAMES := {Formation.WEDGE: "GROUP_FORMATION_WEDGE", Formation.FILE: "GROUP_FORMATION_FILE",
	Formation.LOOSE: "GROUP_FORMATION_LOOSE"}
## La cuña: cada fila, ROW m más atrás y SIDE m más abierta; uno solo va a ALONE m, justo detrás.
const ROW := 1.7
const SIDE := 1.3
const ALONE := 2.2
## La fila: cada uno a GAP m del anterior por el rastro, que guarda un punto cada CRUMB m (hasta CRUMBS).
## Un salto del jugador de más de TRAIL_BREAK m (reaparece, viaja) lo empieza de cero.
const GAP := 1.7
const CRUMB := 0.5
const CRUMBS := 48
const TRAIL_BREAK := 20.0
## Hacia dónde va el jugador: de donde estaba HEADING_BACK m atrás a donde está.
const HEADING_BACK := 1.5
## Sueltos: cada uno se para LOOSE_STEP m más lejos que el anterior.
const LOOSE_STEP := 0.6
## Para que la charla (VillagerChat) lo encuentre.
const GROUP := &"settlement_companions"

var entity_id := ""
var save_category := "npc"

var _manager: SettlementManager
var _host: Node3D
var _terrain: Node3D
var _player: Node3D
var _villages: Array = []
var _prefabs := {}
var _seed := 1
var _list: Array[Companion] = []
## Cómo va el grupo que acompaña.
var formation := Formation.WEDGE
## Por dónde ha pasado el jugador (marco del terreno, lo último al final) y hacia dónde va (marco del
## terreno; cero si aún no se ha movido).
var _trail := PackedVector3Array()
var _heading := Vector3.ZERO
## Los vecinos (SettlementPopulation: "id") que han muerto.
var _dead := {}


## Como SettlementVillagers.setup.
func setup(manager: SettlementManager, host: Node3D, terrain: Node3D, player: Node3D, field: Dictionary,
		prefabs: Dictionary, cfg: Dictionary) -> void:
	_manager = manager
	_host = host
	_terrain = terrain
	_player = player
	_villages = field.get("villages", [])
	_prefabs = prefabs
	_seed = int(SettlementField.settings(cfg).seed)
	add_to_group(GameManager.SAVEABLE_GROUP)
	add_to_group(GROUP)


## Los de ahora (también el que se está yendo a casa; no los muertos).
func get_companions() -> Array[Companion]:
	var out: Array[Companion] = []
	for c in _list:
		if is_instance_valid(c) and not c.dead:
			out.append(c)
	return out


## Los encargos (los de SettlementManager), para la charla con un compañero.
func quests() -> SettlementQuests:
	return _manager.quests if _manager != null else null


## Si el vecino [id] (SettlementPopulation: "id") va con el jugador, se está yendo o ha muerto: su poblado no
## lo saca.
func has(id: String) -> bool:
	if _dead.has(id):
		return true
	for c in _list:
		if not is_instance_valid(c):
			continue
		if c.dead:
			_dead[String(c.resident.get("id", ""))] = true
		if String(c.resident.get("id", "")) == id:
			return true
	return false


## Si ya van todos los que caben (MAX), sin contar al que se va a casa ni a los colonos.
func is_full() -> bool:
	return party().size() >= MAX


## El grupo: los que acompañan al jugador o lo esperan.
func party() -> Array[Companion]:
	var out: Array[Companion] = []
	for c in get_companions():
		if c.mode == Companion.Mode.FOLLOW or c.mode == Companion.Mode.WAIT:
			out.append(c)
	return out


## Los que siguen al jugador ahora, en el orden de la formación.
func followers() -> Array[Companion]:
	var out: Array[Companion] = []
	for c in _list:
		if is_instance_valid(c) and not c.dead and c.mode == Companion.Mode.FOLLOW:
			out.append(c)
	return out


## El puesto de [c] entre los que siguen (0 el primero), o -1.
func follower_index(c: Companion) -> int:
	return followers().find(c)


# --- Formación ------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _terrain == null or not is_instance_valid(_terrain):
		return
	var here := _terrain.global_transform.affine_inverse() * _player.global_position
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(here) > TRAIL_BREAK:
		_trail = PackedVector3Array([here])
		return
	if _trail[_trail.size() - 1].distance_to(here) < CRUMB:
		return
	_trail.append(here)
	if _trail.size() > CRUMBS:
		_trail = _trail.slice(_trail.size() - CRUMBS)
	var back := _trail_point(HEADING_BACK)
	var up := here.normalized()
	var way := (here - back).slide(up)
	if way.length() > 0.3:
		_heading = way.normalized()


## El hueco de [c] en la formación (mundo), o Vector3.INF si va suelto (o el jugador aún no se ha movido).
func slot_of(c: Companion) -> Vector3:
	if formation == Formation.LOOSE or _heading == Vector3.ZERO or _trail.is_empty():
		return Vector3.INF
	var group := followers()
	var i := group.find(c)
	if i < 0:
		return Vector3.INF
	var to_world := _terrain.global_transform
	if formation == Formation.FILE:
		return to_world * _trail_point(GAP * (i + 1))
	var here := _trail[_trail.size() - 1]
	var up := here.normalized()
	var back := -(_heading.slide(up)).normalized()
	var right := up.cross(back)
	if group.size() == 1:
		return to_world * (here + back * ALONE)
	@warning_ignore("integer_division")
	var row := i / 2 + 1
	var side := -1.0 if i % 2 == 0 else 1.0
	return to_world * (here + back * ROW * row + right * side * SIDE * row)


## El punto del rastro a [behind] m del jugador (marco del terreno); si el rastro no llega, sigue recto
## hacia atrás.
func _trail_point(behind: float) -> Vector3:
	var last := _trail[_trail.size() - 1]
	var left := behind
	for i in range(_trail.size() - 2, -1, -1):
		var step := _trail[i].distance_to(last)
		if step >= left:
			return last.lerp(_trail[i], left / step) if step > 0.0 else last
		left -= step
		last = _trail[i]
	var up := last.normalized()
	var back := -(_heading.slide(up))
	return last + (back.normalized() * left if back.length() > 0.01 else Vector3.ZERO)


## Sueltos: lo que [c] se para más lejos del jugador que el primero (m).
func loose_margin(c: Companion) -> float:
	return LOOSE_STEP * maxi(follower_index(c), 0)


## Hacia dónde se aparta [c] de los otros del grupo que tiene encima (unitario en el plano, o cero).
func apart_from(c: Companion, up: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for other in _list:
		if other == c or not is_instance_valid(other) or other.dead or other.mode != Companion.Mode.FOLLOW:
			continue
		var away := (c.global_position - other.global_position).slide(up)
		var d := away.length()
		if d < Companion.APART and d > 0.01:
			push += away / d * (1.0 - d / Companion.APART)
	return push.normalized() if push.length() > 0.01 else Vector3.ZERO


# --- Órdenes al grupo ------------------------------------------------------------------------------

## Que sigan los que esperan. Cuántos han echado a andar.
func order_follow() -> int:
	var count := 0
	for c in party():
		if c.mode == Companion.Mode.WAIT:
			c.follow()
			count += 1
	return count


## Que esperen aquí los que siguen. Cuántos se quedan.
func order_wait() -> int:
	var count := 0
	for c in party():
		if c.mode == Companion.Mode.FOLLOW:
			c.wait_here()
			count += 1
	return count


## A por [creature], todo el grupo. Cuántos van.
func order_attack(creature: NPCController) -> int:
	var count := 0
	for c in party():
		if c.order_attack(creature):
			count += 1
	return count


## Retirada: dejan la pelea y vuelven con el jugador (también los que esperaban). Cuántos.
func order_retreat() -> int:
	var count := 0
	for c in party():
		c.order_retreat()
		if c.mode == Companion.Mode.WAIT:
			c.follow()
		count += 1
	return count


## Vuelven a su base los que la tienen (con el trabajo que dejaron). [cuántos vuelven, cuántos no tienen].
func order_home() -> Array:
	var went := 0
	var homeless := 0
	for c in party():
		if c.return_to_base():
			went += 1
		else:
			homeless += 1
	return [went, homeless]


## Pasa a la formación siguiente y la devuelve.
func next_formation() -> Formation:
	formation = ((int(formation) + 1) % Formation.size()) as Formation
	return formation


## Los que viven en la base.
func settler_count() -> int:
	var count := 0
	for c in get_companions():
		if c.mode == Companion.Mode.SETTLE:
			count += 1
	return count


func settlers_full() -> bool:
	return settler_count() >= MAX_SETTLERS


## [villager] se va con el jugador: el compañero que lo sustituye, donde estaba y con su humano.
func recruit(villager: Villager) -> Companion:
	var v := villager.village.index
	var who := villager.resident
	var at := villager.global_transform
	var model := villager.leave_with_player()
	villager.queue_free()
	return _add(v, who, model, at, Companion.Mode.FOLLOW)


func _add(v: int, who: Dictionary, model: Node3D, at: Transform3D, mode: Companion.Mode) -> Companion:
	var plan: Dictionary = _villages[v]
	var companion := Companion.new()
	companion.setup(who, v, SettlementPopulation.village_name(v, _seed), _manager.relations, model, _terrain,
		_player, (plan.center as Vector3) * float(plan.ground))
	companion.gravity = float(_host.get("gravity_strength")) if _host.get("gravity_strength") != null else 9.8
	companion.mode = mode
	companion.transform = _host.global_transform.affine_inverse() * at
	companion.tree_exiting.connect(func() -> void:
		_list.erase(companion)
		if companion.dead:
			_dead[String(companion.resident.get("id", ""))] = true)
	_list.append(companion)
	_host.add_child(companion)
	companion.reset_physics_interpolation()
	return companion


func get_save_data() -> Dictionary:
	var out: Array = []
	var to_local := _terrain.global_transform.affine_inverse()
	for c in get_companions():
		# El que vuelve a casa ya es del poblado.
		if c.mode == Companion.Mode.LEAVE:
			continue
		var at := to_local * c.global_position
		var facing := to_local.basis * c.facing()
		var entry := {"village": c.village, "id": String(c.resident.get("id", "")), "mode": int(c.mode),
			"at": [at.x, at.y, at.z], "facing": [facing.x, facing.y, facing.z], "pack": c.pack.get_save_data(),
			"health": c.health.health, "fed": c.meals.fed}
		if c.mode == Companion.Mode.SETTLE:
			entry.base = [c.base.x, c.base.y, c.base.z]
			var work := c.work.save_data()
			if not work.is_empty():
				entry.work = work
			if c.homing:
				entry.homing = true
		elif c.has_return_base():
			entry.return_base = [c.return_base.x, c.return_base.y, c.return_base.z]
			if not c.return_work.is_empty():
				entry.return_work = c.return_work
		out.append(entry)
	for c in _list:
		if is_instance_valid(c) and c.dead:
			_dead[String(c.resident.get("id", ""))] = true
	return {"companions": out, "dead": _dead.keys(), "formation": int(formation)}


## Antes de cargar una partida: los de ahora se van (si la partida no trae ninguno, no queda ninguno).
func prepare_restore() -> void:
	for c in get_companions():
		_list.erase(c)
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
		c.queue_free()


## Cada uno, vestido aquí mismo (es al cargar: un humano son ~100 ms), donde estaba.
func restore_save_data(data: Dictionary) -> void:
	prepare_restore()
	_dead.clear()
	for id in data.get("dead", []):
		_dead[str(id)] = true
	formation = clampi(int(data.get("formation", Formation.WEDGE)), 0, Formation.size() - 1) as Formation
	_trail = PackedVector3Array()
	_heading = Vector3.ZERO
	AppearanceCatalog.categories()
	for entry: Dictionary in data.get("companions", []):
		var v := int(entry.get("village", -1))
		if v < 0 or v >= _villages.size():
			continue
		var who := _resident(v, str(entry.get("id", "")))
		if who.is_empty():
			continue
		var raw: Array = entry.get("at", [])
		var facing_raw: Array = entry.get("facing", [])
		if raw.size() != 3:
			continue
		var local := Vector3(raw[0], raw[1], raw[2])
		var up := local.normalized()
		var forward := Vector3(facing_raw[0], facing_raw[1], facing_raw[2]) if facing_raw.size() == 3 \
			else Vector3.FORWARD
		forward = (forward - up * forward.dot(up)).normalized()
		if not forward.is_finite() or forward.is_zero_approx():
			forward = (Vector3.FORWARD - up * up.z).normalized()
		var at := _terrain.global_transform * Transform3D(Basis(up.cross(forward), up, forward), local)
		var model := Villager.build_model(who, SettlementVillagers.pieces_of(who), SettlementVillagers.tool_of(who))
		var saved_mode := int(entry.get("mode", 0))
		var mode := Companion.Mode.WAIT if saved_mode == Companion.Mode.WAIT else Companion.Mode.FOLLOW
		var companion := _add(v, who, model, at, mode)
		var base_raw: Array = entry.get("base", [])
		if saved_mode == Companion.Mode.SETTLE and base_raw.size() == 3:
			companion.settle_here(Vector3(base_raw[0], base_raw[1], base_raw[2]))
			companion.work.restore(entry.get("work", {}))
			companion.homing = bool(entry.get("homing", false))
		var return_raw: Array = entry.get("return_base", [])
		if saved_mode != Companion.Mode.SETTLE and return_raw.size() == 3:
			companion.return_base = Vector3(return_raw[0], return_raw[1], return_raw[2])
			companion.return_work = entry.get("return_work", {})
		if entry.has("pack"):
			companion.pack.restore_save_data(entry.pack)
		companion.restore_health(float(entry.get("health", -1.0)))
		companion.meals.fed = float(entry.get("fed", SettlerMeals.START_HOURS))


## El vecino [id] del poblado [v], como lo saca su poblado, o {}.
func _resident(v: int, id: String) -> Dictionary:
	for who in SettlementPopulation.residents(_villages[v], v, _prefabs, _seed):
		if String(who.id) == id:
			return who
	return {}
