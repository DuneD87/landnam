class_name BaseSupplies
extends RefCounted

## Lo que tiene la base de unos colonos (los de un trono, ThroneView): camas, comida y agua, y para
## cuánto les da. Cuenta lo que usarían ellos:
## - camas: los petates (Bedroll) a menos de Companion.BASE_RADIUS de la base de alguno (donde buscan
##   dónde dormir; sin uno libre, duermen en el suelo);
## - comida: lo que comen, lo de los comederos (Storage.feeder) a menos de SettlerMeals.REACH de su base
##   y lo de sus morrales; y aparte lo que hay en los cofres de la base, que no comen hasta que alguien
##   (el cocinero o el jugador) lo pasa al comedero;
## - agua: los tragos de los bebederos (WaterTrough) a menos de SettlerMeals.REACH.
## Los días: cada colono gasta 24 horas de saciado y de bebido al día (SettlerMeals); cada pieza da
## EdibleTrait.hunger × FULL_HOURS y cada trago, SIP_HOURS.

## A partir de cuántos días va bien (y de cuántos, regular).
const GOOD_DAYS := 3.0
const LOW_DAYS := 1.0

enum Level {GOOD, LOW, BAD}


## Lo de la base de [settlers]: {settlers, beds, hungry, thirsty, feeders, feeder_food, cooked,
## pack_food, chest_food, food_days, troughs, water, water_capacity, water_days}.
static func gather(tree: SceneTree, settlers: Array[Companion]) -> Dictionary:
	var out := {settlers = 0, beds = 0, hungry = 0, thirsty = 0, feeders = 0, feeder_food = 0, cooked = 0,
		pack_food = 0, chest_food = 0, food_days = 0.0, troughs = 0, water = 0, water_capacity = 0,
		water_days = 0.0}
	var bases: Array[Vector3] = []
	var food_hours := 0.0
	for c in settlers:
		if not is_instance_valid(c) or c.dead or not c.base.is_finite():
			continue
		out.settlers += 1
		if c.meals != null:
			out.hungry += int(c.meals.hungry())
			out.thirsty += int(c.meals.thirsty())
		var home: Vector3 = c._terrain.global_transform * c.base
		if not bases.any(func(b: Vector3) -> bool: return b.distance_to(home) < 1.0):
			bases.append(home)
		for item in c.pack.get_all_items():
			var hours := _hours(item)
			if hours > 0.0:
				out.pack_food += item.quantity
				food_hours += hours
	if bases.is_empty():
		return out
	for node in tree.get_nodes_in_group(Bedroll.GROUP):
		var bed := node as Bedroll
		if _alive(bed) and _near(bed.global_position, bases, Companion.BASE_RADIUS):
			out.beds += 1
	for node in tree.get_nodes_in_group(Storage.GROUP):
		var chest := node as Storage
		if not _alive(chest) or chest.inventory == null or not _near(chest.global_position, bases, SettlerMeals.REACH):
			continue
		if chest.feeder:
			out.feeders += 1
		for item in chest.inventory.get_all_items():
			var hours := _hours(item)
			if hours <= 0.0:
				continue
			if not chest.feeder:
				out.chest_food += item.quantity
				continue
			out.feeder_food += item.quantity
			food_hours += hours
			if (item.data.get_trait(EdibleTrait) as EdibleTrait).intoxication_chance <= 0.0:
				out.cooked += item.quantity
	for node in tree.get_nodes_in_group(WaterTrough.GROUP):
		var trough := node as WaterTrough
		if _alive(trough) and _near(trough.global_position, bases, SettlerMeals.REACH):
			out.troughs += 1
			out.water += trough.water
			out.water_capacity += WaterTrough.CAPACITY
	var per_day := 24.0 * maxi(out.settlers, 1)
	out.food_days = food_hours / per_day
	out.water_days = out.water * SettlerMeals.SIP_HOURS / per_day
	return out


## Cómo va algo que dura [days] días.
static func level_of_days(days: float) -> Level:
	if days >= GOOD_DAYS:
		return Level.GOOD
	return Level.LOW if days >= LOW_DAYS else Level.BAD


## Cómo van las camas: una por colono, bien; sin ninguna, mal; si no, regular.
static func level_of_beds(beds: int, settlers: int) -> Level:
	if beds >= settlers:
		return Level.GOOD
	return Level.BAD if beds == 0 else Level.LOW


## Las horas de saciado que da [item] (todas sus piezas), o 0 si no se come.
static func _hours(item: InventoryItem) -> float:
	if item == null or item.data == null:
		return 0.0
	var edible := item.data.get_trait(EdibleTrait) as EdibleTrait
	if edible == null or edible.hunger <= 0.0:
		return 0.0
	return edible.hunger * SettlerMeals.FULL_HOURS * item.quantity


static func _alive(node: Node) -> bool:
	return node != null and node.is_inside_tree() and not node.is_queued_for_deletion()


static func _near(point: Vector3, bases: Array[Vector3], reach: float) -> bool:
	for b in bases:
		if b.distance_to(point) <= reach:
			return true
	return false
