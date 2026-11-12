class_name SettlerHunt extends SettlerTask

## El colono cazador: caza las presas de su zona (las criaturas que huyen al herirlas: ciervos,
## cabras...; a las fieras no va) y trae la carne y las pieles. Necesita un arma en el morral (o la
## herramienta de su oficio). Va a por la presa más cercana como en una pelea (Companion.order_attack:
## corre hasta tenerla a tiro y golpea); la que se le escapa de la zona la deja SettlerWork.SKIP_TIME
## s. Muerta, va hasta ella, la despieza (BUTCHER_TIME s; lo que da es lo del jugador, HuntingLoot,
## con el cuchillo que lleve) y lo lleva al cofre de la base que acepte su oficio. También despieza
## los animales muertos que encuentre en su zona (los que mata un guardia o el jugador y deja sin
## despellejar). Sin cofre con sitio no caza.
##
## Lejos del jugador no hay criaturas: da una pieza corriente (AWAY_MEAT de carne y AWAY_HIDE de
## piel) cada AWAY_KILL s. Ver docs/villagers.md.

enum Phase {SEEK, CHASE, BUTCHER, DEPOSIT}

const BUTCHER_TIME := 6.0
const BUTCHER_REACH := 1.5
## Persigue hasta esto (m) más allá de su zona.
const CHASE_MARGIN := 25.0
const AWAY_KILL := 480.0
const AWAY_MEAT := 4
const AWAY_HIDE := 1

var _phase := Phase.SEEK
var _prey: NPCController
var _body: NPCController
var _butcher_left := -1.0
## Lo que lleva de las piezas (id -> cantidad), para dejar en el cofre solo eso.
var _haul := {}
var _seek_left := 0.0
var _empty_seeks := 0
var _skip := {}
var _owed := 0.0


func save_data() -> Dictionary:
	return {"haul": _haul.duplicate(), "owed": _owed}


func restore(data: Dictionary) -> void:
	_haul = (data.get("haul", {}) as Dictionary).duplicate()
	_owed = float(data.get("owed", 0.0))
	_phase = Phase.DEPOSIT if not _haul.is_empty() else Phase.SEEK


func start() -> void:
	c.order_leash = w.zone_radius + CHASE_MARGIN


func stop() -> void:
	c.order_leash = Companion.ORDER_LEASH
	if SettlerWork._valid(_prey) and c.is_fighting():
		c.order_retreat()
		c._retreat_left = 0.0


func describe() -> String:
	var what := c.tr("SETTLER_JOB_HUNT")
	match w.status:
		SettlerWork.Status.OFF_HOURS:
			return c.tr("SETTLER_OFF_HOURS") % [what, w.gathered]
		SettlerWork.Status.AWAY:
			return c.tr("SETTLER_AWAY") % [what, w.gathered]
	return c.tr("SETTLER_WORKING") % [what, w.gathered]


func step(delta: float) -> Array:
	if c._weapon == null:
		w.block(c.tr("SETTLER_NEED_WEAPON"))
		return still()
	if _phase != Phase.SEEK or w.status != SettlerWork.Status.BLOCKED:
		w.status = SettlerWork.Status.WORKING
	match _phase:
		Phase.CHASE:
			# Aquí solo llega acabada la pelea: muerta, a despiezarla; si no, se le ha escapado.
			if SettlerWork._valid(_prey) and _prey.is_dead:
				_body = _prey
				_butcher_left = -1.0
				_phase = Phase.BUTCHER
			else:
				if SettlerWork._valid(_prey):
					_skip[_prey.get_instance_id()] = SettlerWork._now() + SettlerWork.SKIP_TIME
				_phase = Phase.SEEK
			_prey = null
			return still()
		Phase.BUTCHER:
			return _butchering(delta)
		Phase.DEPOSIT:
			return _depositing(delta)
	return _seek()


func _seek() -> Array:
	if not _haul.is_empty():
		_phase = Phase.DEPOSIT
		return still()
	if SettlerWork._now() < _seek_left:
		return still()
	_seek_left = SettlerWork._now() + SettlerWork.SEEK_EVERY
	w.status = SettlerWork.Status.WORKING
	if not _has_chest():
		return still()
	_body = _find(true)
	if _body != null:
		_butcher_left = -1.0
		_phase = Phase.BUTCHER
		return still()
	_prey = _find(false)
	if _prey == null or not c.order_attack(_prey):
		_prey = null
		_empty_seeks += 1
		if _empty_seeks >= SettlerWork.EMPTY_SEEKS:
			_empty_seeks = 0
			w.rest_done()
		return still()
	_empty_seeks = 0
	_phase = Phase.CHASE
	return still()


func _butchering(delta: float) -> Array:
	if not SettlerWork._valid(_body) or not _body.is_dead or _body.butchered:
		_body = null
		_phase = Phase.SEEK
		return still()
	if _butcher_left < 0.0:
		var state := walk(_body.global_position, BUTCHER_REACH, delta, _body)
		if state == Walk.GOING:
			return [heading, SettlerWork.WALK_SPEED]
		if state == Walk.GAVE_UP:
			_skip[_body.get_instance_id()] = SettlerWork._now() + SettlerWork.SKIP_TIME
			_body = null
			_phase = Phase.SEEK
			return still()
		_butcher_left = BUTCHER_TIME / w.pace()
		c.play_work(Villager.ANIM_DIG, 1.0)
		c.set_busy(_butcher_left)
	c._face(_body.global_position - c.global_position, delta)
	_butcher_left -= delta
	if _butcher_left <= 0.0:
		_strip()
	return still()


## Despiezada: lo que da pasa a su morral (lo que no quepa se queda en el animal).
func _strip() -> void:
	var knife := best_in_pack(func(data: ItemData) -> float:
		var skins := data.get_trait(SkinningTrait) as SkinningTrait
		return skins.yield_mult if skins != null else 0.0)
	var skinning := knife.get_trait(SkinningTrait) as SkinningTrait if knife != null else null
	HuntingLoot.fill(_body, skinning.yield_mult if skinning != null else 1.0)
	_body.butchered = true
	var bag: Inventory = _body.inventory
	for item in bag.get_all_items():
		if item == null:
			continue
		var got := move(bag, c.pack, item.data, item.quantity)
		if got > 0:
			_haul[item.data.id] = int(_haul.get(item.data.id, 0)) + got
			w.gathered += got
	_body = null
	_butcher_left = -1.0
	_phase = Phase.DEPOSIT if not _haul.is_empty() else Phase.SEEK


func _depositing(delta: float) -> Array:
	var data := _haul_item()
	if data == null:
		_haul.clear()
		_phase = Phase.SEEK
		return still()
	var from := chests(SettlerWork.JOB_IDS[SettlerWork.Job.HUNT], true)
	var chest := chest_with_room(from, data)
	if chest == null:
		w.block(c.tr("SETTLER_CHEST_FULL_SHORT") if not from.is_empty()
			else c.tr("SETTLER_NO_CHEST_SHORT") % c.tr("SETTLER_JOB_HUNT"))
		return still()
	if walk(chest.global_position, SettlerWork.DEPOSIT_REACH, delta, chest) == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	# Lo que este cofre no admita se queda en el morral: el paso siguiente busca otro con sitio.
	for id: StringName in _haul.keys():
		var item := ItemCatalog.get_item(id)
		var have := mini(int(_haul[id]), carried(item))
		var left := have - move(c.pack, chest.inventory, item, have)
		if left <= 0:
			_haul.erase(id)
		else:
			_haul[id] = left
	if _haul.is_empty():
		_phase = Phase.SEEK
	return still()


func away(delta: float, _hour: float) -> void:
	if c._weapon == null:
		w.block(c.tr("SETTLER_NEED_WEAPON"))
		return
	var meat := ItemCatalog.get_item(HuntingLoot.MEAT)
	var chest := chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.HUNT], true), meat)
	if chest == null:
		_has_chest()
		return
	w.status = SettlerWork.Status.AWAY
	_owed += delta * w.pace() / AWAY_KILL
	if _owed < 1.0:
		return
	_owed -= 1.0
	w.gathered += AWAY_MEAT - chest.inventory.add_item(meat, AWAY_MEAT)
	var hide := ItemCatalog.get_item(HuntingLoot.HIDE)
	if hide != null:
		w.gathered += AWAY_HIDE - chest.inventory.add_item(hide, AWAY_HIDE)


## Si hay cofre con sitio para la carne; si no, se queda parado diciendo por qué.
func _has_chest() -> bool:
	var from := chests(SettlerWork.JOB_IDS[SettlerWork.Job.HUNT], true)
	if chest_with_room(from, ItemCatalog.get_item(HuntingLoot.MEAT)) != null:
		return true
	w.block(c.tr("SETTLER_CHEST_FULL_SHORT") if not from.is_empty()
		else c.tr("SETTLER_NO_CHEST_SHORT") % c.tr("SETTLER_JOB_HUNT"))
	return false


func _haul_item() -> ItemData:
	for id: StringName in _haul:
		var item := ItemCatalog.get_item(id)
		if item != null and carried(item) > 0:
			return item
	return null


## Lo más cercano a él en su zona: con [dead], un animal muerto sin despellejar; si no, una presa
## viva. O null.
func _find(dead: bool) -> NPCController:
	var middle := center()
	var best: NPCController
	var best_d := INF
	var now := SettlerWork._now()
	var candidates: Array = c.get_tree().get_nodes_in_group(AmbientAnimal.GROUP) if dead \
		else CreatureGrid.near(middle, w.zone_radius)
	for node in candidates:
		var creature := node as NPCController
		if creature == null or not SettlerWork._valid(creature) or float(_skip.get(creature.get_instance_id(), 0.0)) > now \
				or creature.global_position.distance_to(middle) > w.zone_radius:
			continue
		if dead:
			if not creature.is_dead or creature.butchered or creature.inventory == null:
				continue
		elif not Companion._alive(creature) or not creature._prey:
			continue
		var d := creature.global_position.distance_to(c.global_position)
		if d < best_d:
			best = creature
			best_d = d
	return best
