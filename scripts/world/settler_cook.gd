class_name SettlerCook extends SettlerTask

## El colono cocinero: asa en la hoguera de la base (Campfire, la más cercana a ella a menos de
## Companion.BASE_RADIUS m) lo crudo que haya en los cofres y guarda lo asado. No necesita
## herramienta. Va y viene entre dos sitios:
## - en el cofre deja lo asado que trae (en el que acepte su oficio) y coge lo crudo que quepa en los
##   huecos libres de la hoguera y, si al fuego le queda poco (FUEL_LOW s), leña (FUEL_LOAD de lo que
##   arda: madera antes que otra cosa);
## - en la hoguera recoge lo ya asado, pone lo crudo (una pieza por hueco), echa la leña y la
##   enciende si hay algo que asar.
## Sin nada que hacer se queda junto al fuego. Trabaja en el horario de los demás y sigue hasta la
## hora de acostarse: desde el atardecer mantiene la hoguera encendida aunque no ase nada, para los
## que se sientan alrededor.
##
## Lejos del jugador hace lo mismo sin andar, una vez cada AWAY_EVERY s (la hoguera asa sola). Ver
## docs/villagers.md.

enum Phase {SEEK, CHEST, FIRE}

const FUEL_LOW := 90.0
const FUEL_LOAD := 6
const FIRE_REACH := 2.0
const THINK_EVERY := 3.0
const AWAY_EVERY := 30.0

var _phase := Phase.SEEK
var _chest: Storage
var _think_left := 0.0
var _away_left := 0.0
## Lo que carga de camino a la hoguera (id -> cantidad): crudo y leña.
var _load := {}
## Lo asado que trae de la hoguera (id -> cantidad).
var _done := {}


func save_data() -> Dictionary:
	return {"load": _load.duplicate(), "done": _done.duplicate()}


func restore(data: Dictionary) -> void:
	_load = (data.get("load", {}) as Dictionary).duplicate()
	_done = (data.get("done", {}) as Dictionary).duplicate()


func on_duty(hour: float) -> bool:
	return Villager._work_hour(hour) or (hour >= Villager.WORK_HOURS[Villager.WORK_HOURS.size() - 1].y
		and hour < Villager.BED_HOUR)


func describe() -> String:
	var what := c.tr("SETTLER_JOB_COOK")
	match w.status:
		SettlerWork.Status.OFF_HOURS:
			return c.tr("SETTLER_OFF_HOURS") % [what, w.gathered]
		SettlerWork.Status.AWAY:
			return c.tr("SETTLER_AWAY") % [what, w.gathered]
	return c.tr("SETTLER_WORKING") % [what, w.gathered]


func step(delta: float) -> Array:
	var fire := _fire()
	if fire == null:
		w.block(c.tr("SETTLER_NO_FIRE"))
		return still()
	w.status = SettlerWork.Status.WORKING
	match _phase:
		Phase.CHEST:
			if not is_instance_valid(_chest) or not _chest.is_inside_tree():
				_phase = Phase.SEEK
				return still()
			if walk(_chest.global_position, SettlerWork.DEPOSIT_REACH, delta, _chest) == Walk.GOING:
				return [heading, SettlerWork.WALK_SPEED]
			_at_chest(_chest, fire)
			_phase = Phase.SEEK
			_think_left = 0.0
			return still()
		Phase.FIRE:
			if walk(fire.global_position, FIRE_REACH, delta, fire) == Walk.GOING:
				return [heading, SettlerWork.WALK_SPEED]
			c._face(fire.global_position - c.global_position, delta)
			_at_fire(fire)
			_phase = Phase.SEEK
			_think_left = THINK_EVERY
			return still()
	_think_left -= delta * w.pace()
	if _think_left > 0.0:
		if flat_to(fire.global_position) < FIRE_REACH * 1.5:
			c._face(fire.global_position - c.global_position, delta)
		return still()
	_think_left = THINK_EVERY
	_chest = _pick_chest(fire)
	if _chest != null:
		_phase = Phase.CHEST
	elif _fire_work(fire) or flat_to(fire.global_position) > FIRE_REACH:
		_phase = Phase.FIRE
	return still()


func away(delta: float, _hour: float) -> void:
	var fire := _fire()
	if fire == null:
		w.block(c.tr("SETTLER_NO_FIRE"))
		return
	w.status = SettlerWork.Status.AWAY
	_away_left -= delta * w.pace()
	if _away_left > 0.0:
		return
	_away_left = AWAY_EVERY
	_at_fire(fire)
	for chest in chests():
		_at_chest(chest, fire)
	_at_fire(fire)


# --- En el cofre y en la hoguera ------------------------------------------------------------------

## El cofre al que ir ahora: el que tiene lo crudo que cabe en la hoguera, el que tiene leña si hace
## falta o, con lo asado encima, el que lo admite. Null si no hay nada que hacer en ninguno.
func _pick_chest(fire: Campfire) -> Storage:
	var all := chests()
	if _free_slots(fire) > _count(_load, true) and _count(_load, true) == 0:
		for chest in all:
			if _raw_in(chest.inventory) != null:
				return chest
	if _needs_fuel(fire) and _count(_load, false) == 0:
		for chest in all:
			if _fuel_in(chest.inventory) != null:
				return chest
	if not _done.is_empty():
		for chest in chests(SettlerWork.JOB_IDS[SettlerWork.Job.COOK], true):
			for id: StringName in _done:
				if SettlerWork._room(chest.inventory, ItemCatalog.get_item(id)):
					return chest
	return null


## En [chest]: deja lo asado (si acepta su oficio) y coge lo crudo que cabe en la hoguera y la leña
## que le falta.
func _at_chest(chest: Storage, fire: Campfire) -> void:
	if chest.accepts_job(SettlerWork.JOB_IDS[SettlerWork.Job.COOK]):
		for id: StringName in _done.keys():
			var item := ItemCatalog.get_item(id)
			var have := mini(int(_done[id]), carried(item))
			var left := have - move(c.pack, chest.inventory, item, have)
			if left <= 0:
				_done.erase(id)
			else:
				_done[id] = left
	var want := _free_slots(fire) - _count(_load, true)
	while want > 0:
		var raw := _raw_in(chest.inventory)
		if raw == null:
			break
		var got := move(chest.inventory, c.pack, raw, want)
		if got <= 0:
			break
		_load[raw.id] = int(_load.get(raw.id, 0)) + got
		want -= got
	if _needs_fuel(fire) and _count(_load, false) == 0:
		var fuel := _fuel_in(chest.inventory)
		if fuel != null:
			var got := move(chest.inventory, c.pack, fuel, FUEL_LOAD)
			if got > 0:
				_load[fuel.id] = int(_load.get(fuel.id, 0)) + got


## En la hoguera: recoge lo asado, pone lo crudo, echa la leña y la enciende si hay algo que asar (o
## ya atardece).
func _at_fire(fire: Campfire) -> void:
	var bag := fire.inventory
	for i in Campfire.COOK_SLOTS:
		var slot := 1 + i
		var item := bag.items[slot]
		if item == null or item.data.get_trait(CookableTrait) != null:
			continue
		if c.pack.add_item(item.data, item.quantity) == 0:
			bag.items[slot] = null
			fire.progress[i] = 0.0
			_done[item.data.id] = int(_done.get(item.data.id, 0)) + item.quantity
			w.gathered += item.quantity
	for id: StringName in _load.keys():
		var data := ItemCatalog.get_item(id)
		var have := mini(int(_load[id]), carried(data))
		if data.get_trait(CookableTrait) != null:
			for i in Campfire.COOK_SLOTS:
				if have <= 0:
					break
				if bag.items[1 + i] == null and bag.accepts(1 + i, data) and c.pack.remove_item(data, 1) == 1:
					bag.items[1 + i] = InventoryItem.new(data, 1)
					fire.progress[i] = 0.0
					have -= 1
		elif bag.accepts(Campfire.FUEL_SLOT, data):
			var stock := bag.items[Campfire.FUEL_SLOT]
			if stock == null:
				var amount := mini(have, bag.capacity(Campfire.FUEL_SLOT, data))
				amount = c.pack.remove_item(data, amount)
				if amount > 0:
					bag.items[Campfire.FUEL_SLOT] = InventoryItem.new(data, amount)
					have -= amount
			elif stock.data == data:
				var amount := mini(have, bag.capacity(Campfire.FUEL_SLOT, data) - stock.quantity)
				amount = c.pack.remove_item(data, amount) if amount > 0 else 0
				stock.quantity += amount
				have -= amount
		if have <= 0:
			_load.erase(id)
		else:
			_load[id] = have
	bag.inventory_changed.emit()
	if not fire.lit and (_cooking(fire) or _evening()):
		fire.ignite()


## Si en la hoguera hay algo que hacer con lo que lleva o con lo que ya está asado.
func _fire_work(fire: Campfire) -> bool:
	if not _load.is_empty():
		return true
	for i in Campfire.COOK_SLOTS:
		var item := fire.inventory.items[1 + i]
		if item != null and item.data.get_trait(CookableTrait) == null:
			return true
	return not fire.lit and fire.has_fuel() and (_cooking(fire) or _evening())


func _free_slots(fire: Campfire) -> int:
	var count := 0
	for i in Campfire.COOK_SLOTS:
		if fire.inventory.items[1 + i] == null:
			count += 1
	return count


## Si en la hoguera se asa algo.
func _cooking(fire: Campfire) -> bool:
	for i in Campfire.COOK_SLOTS:
		var item := fire.inventory.items[1 + i]
		if item != null and item.data.get_trait(CookableTrait) != null:
			return true
	return false


## Le queda poco fuego y hace falta: se asa algo, lo va a asar o ya atardece.
func _needs_fuel(fire: Campfire) -> bool:
	return fire.burn_seconds_left() < FUEL_LOW and (_cooking(fire) or _count(_load, true) > 0 or _evening())


func _evening() -> bool:
	var hour := c._hour()
	return hour >= Villager.EVENING_HOUR - 0.5 and hour < Villager.BED_HOUR


## Cuánto lleva en _load de lo crudo ([raw]) o de leña.
func _count(load: Dictionary, raw: bool) -> int:
	var count := 0
	for id: StringName in load:
		var data := ItemCatalog.get_item(id)
		if (data.get_trait(CookableTrait) != null) == raw:
			count += int(load[id])
	return count


## Lo primero crudo (que se asa) de [bag], o null.
static func _raw_in(bag: Inventory) -> ItemData:
	for item in bag.get_all_items():
		if item != null and item.data.get_trait(CookableTrait) != null:
			return item.data
	return null


## Lo que arde de [bag]: la madera antes que otra cosa; solo materiales. O null.
static func _fuel_in(bag: Inventory) -> ItemData:
	var other: ItemData
	for item in bag.get_all_items():
		if item == null or item.data.category != ItemData.Category.MATERIAL or item.data.get_trait(FuelTrait) == null:
			continue
		if item.data.id == SettlerWork.WOOD_ID:
			return item.data
		if other == null:
			other = item.data
	return other


## La hoguera de la base: la más cercana a ella a menos de Companion.BASE_RADIUS m, o null.
func _fire() -> Campfire:
	if not c.base.is_finite():
		return null
	var home := c._terrain.global_transform * c.base
	var best: Campfire
	var best_d := Companion.BASE_RADIUS
	for node in c.get_tree().get_nodes_in_group(Campfire.GROUP):
		var fire := node as Campfire
		if fire == null or not fire.is_inside_tree() or fire.is_queued_for_deletion():
			continue
		var d := fire.global_position.distance_to(home)
		if d < best_d:
			best = fire
			best_d = d
	return best
