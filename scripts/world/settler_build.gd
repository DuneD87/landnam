class_name SettlerBuild extends SettlerTask

## El colono constructor: levanta las obras (BlueprintSite: los blueprints que el jugador deja
## colocados, y las reparaciones, RepairSite) de su zona. Hace lo que el jugador con la E y el
## martillo: coge de los cofres de la base (los que aceptan su oficio) lo que le falta a la obra, lo
## lleva, se lo aporta (BlueprintSite.deposit) y la martillea desde fuera (BlueprintSite.work) hasta
## acabarla; lo que sobra vuelve al cofre. Necesita un martillo en el morral. Si en los cofres no
## hay nada de lo que falta, se queda parado diciendo qué. Varios pueden compartir obra: cada uno
## descuenta lo que ya traen los otros (_hauls). Lo que lleva hecho (gathered) son los bloques
## puestos.
##
## Lejos del jugador hace lo mismo sin moverse: un viaje del cofre a la obra cada TRIP_TIME s y un
## martillazo cada AWAY_HIT s. Ver docs/villagers.md.

enum Phase {SEEK, FETCH, HAUL, HAMMER, RETURN}

## Lo que carga en un viaje (unidades), y a qué distancia de la caja de la obra se pone (m).
const CARRY := 60
const STAND_OFF := 0.9
const STAND_REACH := 0.7
## Si no llega a su sitio pero está a menos de esto de la obra (el alcance del jugador), martillea
## desde donde está.
const FAR_REACH := 8.0
const HIT_PAUSE := Vector2(0.25, 0.6)
const HIT_SPEED := 1.1
## Lejos: cada cuánto hace un viaje y da un martillazo (s).
const TRIP_TIME := 30.0
const AWAY_HIT := 2.5

## Lo que trae cada uno de camino a una obra: instance_id del Companion -> {"site": instance_id de
## la obra, "items": {id: cantidad}}.
static var _hauls := {}

var _site: BlueprintSite
var _phase := Phase.SEEK
var _chest: Storage
var _swing_left := 0.0
var _impact_at := -1.0
var _pause_left := 0.0
var _wait_left := 0.0
var _skip := {}
var _trip_left := 0.0
var _hit_left := 0.0
## Lo que falta y no hay en los cofres: {id: cantidad} (para decirlo).
var _short := {}


func stop() -> void:
	_hauls.erase(c.get_instance_id())
	_site = null
	_swing_left = 0.0


func describe() -> String:
	var what := c.tr("SETTLER_JOB_BUILD")
	match w.status:
		SettlerWork.Status.OFF_HOURS:
			return c.tr("SETTLER_BUILD_OFF") % [what, w.gathered]
		SettlerWork.Status.AWAY:
			return c.tr("SETTLER_BUILD_AWAY") % [what, w.gathered]
	if _site_ok():
		return c.tr("SETTLER_BUILD_WORKING") % [what, _site.get_title(), roundi(_site.progress() * 100.0)]
	return c.tr("SETTLER_BUILD_IDLE") % [what, w.gathered]


# --- Cerca ----------------------------------------------------------------------------------------

func step(delta: float) -> Array:
	if _swing_left > 0.0:
		_swing_left -= delta
		if _impact_at >= 0.0:
			_impact_at -= delta
			if _impact_at < 0.0:
				_impact()
		return still()
	var hammer := _hammer()
	if hammer == null:
		w.block(c.tr("SETTLER_NEED_HAMMER"))
		return still()
	if not _site_ok():
		_hauls.erase(c.get_instance_id())
		_site = _find_site()
		_phase = Phase.SEEK
		if _site == null:
			# Sin obra: lo que le haya quedado en el morral, al cofre.
			if _leftovers() > 0:
				var going := _returning(delta)
				if _phase == Phase.RETURN:
					return going
			w.rest_done()
			return still()
	# Parado (sin material) sigue parado hasta que vuelva a mirar (_decide).
	if _phase != Phase.SEEK or w.status != SettlerWork.Status.BLOCKED:
		w.status = SettlerWork.Status.WORKING
	match _phase:
		Phase.FETCH:
			return _fetching(delta)
		Phase.HAUL:
			return _hauling(delta)
		Phase.HAMMER:
			return _hammering(delta, hammer)
		Phase.RETURN:
			return _returning(delta)
	return _decide(delta)


## Qué toca: martillear si la obra tiene con qué, llevarle lo que ya carga o ir al cofre a por lo que
## falta.
func _decide(delta: float) -> Array:
	_wait_left -= delta
	if _wait_left > 0.0:
		return still()
	w.status = SettlerWork.Status.WORKING
	var problem := _site.work_problem(_bodies())
	if problem == &"" or problem == &"blocked":
		_phase = Phase.HAMMER
		return still()
	if _carrying_for(_site) > 0:
		_phase = Phase.HAUL
		return still()
	var wanted := _wanted(_site)
	if wanted.is_empty():
		# Lo que falta ya lo traen otros.
		_wait_left = SettlerWork.SEEK_EVERY
		return still()
	var from := chests(SettlerWork.JOB_IDS[SettlerWork.Job.BUILD], true)
	_chest = null
	_short = {}
	for chest in from:
		for id: StringName in wanted:
			if chest.inventory.get_item_count(ItemCatalog.get_item(id)) > 0:
				_chest = chest
				break
		if _chest != null:
			break
	if _chest == null:
		_short = wanted
		w.block(_short_text(from.is_empty()))
		_wait_left = SettlerWork.SEEK_EVERY
		return still()
	_phase = Phase.FETCH
	return still()


func _fetching(delta: float) -> Array:
	if not is_instance_valid(_chest) or not _chest.is_inside_tree():
		_phase = Phase.SEEK
		return still()
	# Si no llega al cofre (atascado), coge igual: que no se quede parado.
	if walk(_chest.global_position, SettlerWork.DEPOSIT_REACH, delta, _chest) == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	_load(_chest.inventory)
	_phase = Phase.HAUL if _carrying_for(_site) > 0 else Phase.SEEK
	return still()


## Coge de [from] lo que quiere la obra, hasta CARRY, y lo apunta como de camino.
func _load(from: Inventory) -> void:
	var wanted := _wanted(_site)
	var room := CARRY
	var mine := {}
	for id: StringName in wanted:
		if room <= 0:
			break
		var data := ItemCatalog.get_item(id)
		var got := move(from, c.pack, data, mini(int(wanted[id]), room))
		if got > 0:
			mine[id] = got
			room -= got
	if not mine.is_empty():
		_hauls[c.get_instance_id()] = {"site": _site.get_instance_id(), "items": mine}


func _hauling(delta: float) -> Array:
	var state := walk(_stand_point(), STAND_REACH, delta, _site)
	if state == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	_site.deposit(c.pack)
	_hauls.erase(c.get_instance_id())
	_phase = Phase.SEEK
	_wait_left = 0.0
	return still()


func _hammering(delta: float, hammer: ItemData) -> Array:
	var spot := _stand_point()
	var state := walk(spot, STAND_REACH, delta, _site)
	if state == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	if state == Walk.GAVE_UP and flat_to(spot) > FAR_REACH:
		_skip[_site.get_instance_id()] = SettlerWork._now() + SettlerWork.SKIP_TIME
		_site = null
		return still()
	var to := _site.get_center() - c.global_position
	c._face(to, delta)
	_pause_left -= delta
	var toward := c._tangent(to)
	if _pause_left > 0.0 or toward == Vector3.ZERO or c.facing().angle_to(toward) > deg_to_rad(30.0):
		return still()
	# Sin nada que poner ahora (falta material, o estorba alguien): a ver qué toca.
	if _site.work_problem(_bodies()) != &"":
		_phase = Phase.SEEK
		_wait_left = 1.0
		return still()
	c.hold_work_tool(hammer)
	var move_data: Dictionary = MeleeMoveset.VERTICAL
	c.play_work(move_data.anim, HIT_SPEED)
	var hit: Vector2 = move_data.hit
	_impact_at = (hit.x + hit.y) * 0.5 / HIT_SPEED
	_swing_left = float(move_data.end) / HIT_SPEED
	c.set_busy(_swing_left)
	_pause_left = c._rng.randf_range(HIT_PAUSE.x, HIT_PAUSE.y) / w.pace()
	return still()


## El martillazo llega: pone lo que toca y suena como poner un bloque.
func _impact() -> void:
	if not _site_ok():
		return
	var site := _site
	# El último bloque retira la obra del árbol: conserva antes el punto donde suena el golpe.
	var point := site.get_center()
	var result := site.work(_bodies())
	_count(site, result, true, point)


## Apunta lo puesto y, acabada la obra, recoge lo que sobra y avisa.
func _count(site: BlueprintSite, result: Dictionary, sound: bool, point := Vector3.ZERO) -> void:
	var placed := int(result["placed"])
	if placed == 0:
		return
	w.gathered += placed
	if sound:
		AudioManager.play_material(&"block_place", result["sound"], point)
	if not result["finished"]:
		return
	var title := site.get_title()
	var leftover := site.take_deposited()
	for id: StringName in leftover:
		c.pack.add_item(ItemCatalog.get_item(id), int(leftover[id]))
	c.notify(c.tr("SETTLER_REPAIR_DONE" if site is RepairSite else "SETTLER_BUILD_DONE") % [who(), title])
	_site = null
	_phase = Phase.RETURN if _leftovers() > 0 else Phase.SEEK


## Lo que le ha sobrado (materiales en el morral), de vuelta al cofre.
func _returning(delta: float) -> Array:
	var data := _leftover_item()
	if data == null:
		_phase = Phase.SEEK
		return still()
	var chest := chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.BUILD], true), data)
	if chest == null:
		_phase = Phase.SEEK
		return still()
	_phase = Phase.RETURN
	if walk(chest.global_position, SettlerWork.DEPOSIT_REACH, delta, chest) == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	w._store(chest)
	_phase = Phase.SEEK
	return still()


# --- Lejos ----------------------------------------------------------------------------------------

func away(delta: float, _hour: float) -> void:
	_swing_left = 0.0
	if _hammer() == null:
		w.block(c.tr("SETTLER_NEED_HAMMER"))
		return
	if not _site_ok():
		_hauls.erase(c.get_instance_id())
		_site = _find_site()
		if _site == null:
			w.rest_done()
			return
	w.status = SettlerWork.Status.AWAY
	var pace := w.pace()
	_trip_left -= delta * pace
	_hit_left -= delta * pace
	if _trip_left <= 0.0:
		_trip_left = TRIP_TIME
		for chest in chests(SettlerWork.JOB_IDS[SettlerWork.Job.BUILD], true):
			_load(chest.inventory)
		_site.deposit(c.pack)
		_hauls.erase(c.get_instance_id())
		# Lo que no haya querido la obra, de vuelta.
		if _leftovers() > 0:
			var data := _leftover_item()
			var chest := chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.BUILD], true), data)
			if chest != null:
				w._store(chest)
		if _site.work_problem() == &"missing" and not _wanted(_site).is_empty():
			_short = _wanted(_site)
			w.block(_short_text(false))
	if _hit_left <= 0.0:
		_hit_left = AWAY_HIT
		if _site.work_problem() == &"":
			var site := _site
			_count(site, site.work(), false)
			if _leftovers() > 0:
				var data := _leftover_item()
				var chest := chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.BUILD], true), data)
				if chest != null:
					w._store(chest)
			_phase = Phase.SEEK


# --- Qué, con qué y dónde -------------------------------------------------------------------------

func _hammer() -> ItemData:
	return best_in_pack(func(data: ItemData) -> float:
		return 1.0 if data.tool_type == ItemData.ToolType.HAMMER else 0.0)


func _site_ok() -> bool:
	return SettlerWork._valid(_site) and not _site.is_complete()


## La obra sin acabar de su zona más cercana a él, o null.
func _find_site() -> BlueprintSite:
	var middle := center()
	var best: BlueprintSite
	var best_d := INF
	for node in c.get_tree().get_nodes_in_group(BlueprintSite.GROUP):
		var site := node as BlueprintSite
		if site == null or not SettlerWork._valid(site) or site.is_complete() \
				or float(_skip.get(site.get_instance_id(), 0.0)) > SettlerWork._now():
			continue
		if site.get_center().distance_to(middle) > w.zone_radius + site.get_radius():
			continue
		var d := site.get_center().distance_to(c.global_position)
		if d < best_d:
			best = site
			best_d = d
	return best


## Dónde se pone para aportar y martillear (mundo): el punto más cercano a él de la caja de la obra
## agrandada STAND_OFF m (si está dentro, sale por la cara más cercana), a su altura.
func _stand_point() -> Vector3:
	var frame := _site.global_transform
	var box := _site.get_box().grow(STAND_OFF)
	var local := frame.affine_inverse() * c.global_position
	var p := Vector3(clampf(local.x, box.position.x, box.end.x), local.y, clampf(local.z, box.position.z, box.end.z))
	if local.x > box.position.x and local.x < box.end.x and local.z > box.position.z and local.z < box.end.z:
		var exits := [[local.x - box.position.x, Vector3(box.position.x, local.y, local.z)],
			[box.end.x - local.x, Vector3(box.end.x, local.y, local.z)],
			[local.z - box.position.z, Vector3(local.x, local.y, box.position.z)],
			[box.end.z - local.z, Vector3(local.x, local.y, box.end.z)]]
		var nearest := INF
		for exit in exits:
			if float(exit[0]) < nearest:
				nearest = exit[0]
				p = exit[1]
	return frame * p


## Los pies de quien anda por la obra (el jugador y los compañeros): nada se pone encima de ellos.
func _bodies() -> Array:
	var out := []
	var reach := _site.get_radius() + 3.0
	var middle := _site.get_center()
	for node in c.get_tree().get_nodes_in_group(Companion.GROUP):
		var other := node as Node3D
		if other != null and other.global_position.distance_to(middle) < reach:
			out.append(other.global_position)
	if c._player != null and is_instance_valid(c._player) and c._player.global_position.distance_to(middle) < reach:
		out.append(c._player.global_position)
	return out


## Lo que le falta a [site] y no trae ya otro (id -> cantidad).
func _wanted(site: BlueprintSite) -> Dictionary:
	var out := site.get_missing()
	for key in _hauls.keys():
		var other := instance_from_id(key) as Companion
		if other == null or not is_instance_valid(other) or other.dead or not other.is_inside_tree():
			_hauls.erase(key)
			continue
		var haul: Dictionary = _hauls[key]
		if other == c or int(haul.site) != site.get_instance_id():
			continue
		for id: StringName in haul.items:
			if out.has(id):
				out[id] = int(out[id]) - int(haul.items[id])
				if int(out[id]) <= 0:
					out.erase(id)
	return out


## Lo que lleva en el morral de lo que le falta a [site].
func _carrying_for(site: BlueprintSite) -> int:
	var count := 0
	var missing := site.get_missing()
	for id: StringName in missing:
		count += mini(carried(ItemCatalog.get_item(id)), int(missing[id]))
	return count


## Los materiales que lleva en el morral (lo que sobró de una obra).
func _leftovers() -> int:
	return w._carried()


func _leftover_item() -> ItemData:
	return w._carried_item()


## «faltan 12 de Madera» (lo primero que falta), o que no hay cofre.
func _short_text(no_chest: bool) -> String:
	if no_chest:
		return c.tr("SETTLER_BUILD_NO_CHEST")
	for id: StringName in _short:
		var data := ItemCatalog.get_item(id)
		return c.tr("SETTLER_BUILD_SHORT") % [int(_short[id]), data.get_display_name() if data != null else String(id)]
	return ""
