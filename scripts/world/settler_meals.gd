class_name SettlerMeals extends RefCounted

## El hambre de un colono (Companion viviendo en la base). Lleva las horas de juego que le quedan
## saciado (fed), que bajan con el reloj del mundo (WorldTime: también mientras el jugador duerme).
## Por debajo de EAT_BELOW horas come: primero de su morral y, si no, de los cofres de la base
## (cualquiera, a menos de SettlerWork.CHEST_REACH m de ella), sin ir hasta ellos. Prefiere lo que no
## intoxica (lo asado) y, de eso, lo que más llena; lo crudo solo si no hay otra cosa. Cada pieza le
## da lo que llena al jugador (EdibleTrait.hunger) por FULL_HOURS, y come hasta tener EAT_UNTIL horas.
##
## Sin nada que comer llega a cero y pasa hambre: trabaja a la mitad de ritmo (SettlerWork.pace) y no
## recupera vida, pero no muere. Se avisa en la barra, como mucho cada NOTIFY_EVERY s entre todos.
## Quien acompaña al jugador no pasa hambre. Ver docs/villagers.md.

## Lo que dura saciado del todo (horas de juego): la mitad de lo que gasta el jugador.
const FULL_HOURS := 36.0
const START_HOURS := 12.0
const EAT_BELOW := 6.0
const EAT_UNTIL := 14.0
const CHECK_EVERY := 10.0
const NOTIFY_EVERY := 180.0

static var _last_notice := -INF

var fed := START_HOURS

var _c: Companion
var _check_left := 0.0
var _starving := false


func _init(companion: Companion) -> void:
	_c = companion


func hungry() -> bool:
	return fed <= 0.0


## Un paso (viviendo en la base, cerca o lejos del jugador).
func tick(delta: float) -> void:
	fed = maxf(fed - WorldTime.hours_elapsed(delta), 0.0)
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	if fed >= EAT_BELOW:
		_starving = false
		return
	eat()
	if fed > 0.0:
		_starving = false
	elif not _starving:
		_starving = true
		var now := SettlerWork._now()
		if now - _last_notice >= NOTIFY_EVERY:
			_last_notice = now
			_c.notify(_c.tr("SETTLER_STARVING") % String(_c.resident.get("name", "")))


## Come de lo que haya hasta tener EAT_UNTIL horas. Devuelve cuántas piezas ha comido.
func eat() -> int:
	var eaten := 0
	while fed < EAT_UNTIL:
		var from := _c.pack
		var food := best_food(from)
		if food == null or _intoxicates(food):
			for bag in _larders():
				var other := best_food(bag)
				if other != null and (food == null or _score(other) > _score(food)):
					food = other
					from = bag
		if food == null or from.remove_item(food, 1) != 1:
			break
		fed += (food.get_trait(EdibleTrait) as EdibleTrait).hunger * FULL_HOURS
		eaten += 1
	return eaten


## Lo mejor que comer de [bag], o null.
static func best_food(bag: Inventory) -> ItemData:
	var best: ItemData
	for item in bag.get_all_items():
		if item != null and _score(item.data) > 0.0 and (best == null or _score(item.data) > _score(best)):
			best = item.data
	return best


## Cuánto apetece [data]: lo que llena, y por delante de todo lo que no intoxica. 0 si no se come.
static func _score(data: ItemData) -> float:
	var edible := data.get_trait(EdibleTrait) as EdibleTrait if data != null else null
	if edible == null or edible.hunger <= 0.0:
		return 0.0
	return edible.hunger + (10.0 if edible.intoxication_chance <= 0.0 else 0.0)


static func _intoxicates(data: ItemData) -> bool:
	return (data.get_trait(EdibleTrait) as EdibleTrait).intoxication_chance > 0.0


## Los cofres de su base.
func _larders() -> Array[Inventory]:
	var out: Array[Inventory] = []
	if not _c.base.is_finite():
		return out
	var home := _c._terrain.global_transform * _c.base
	for node in _c.get_tree().get_nodes_in_group(Storage.GROUP):
		var chest := node as Storage
		if chest != null and chest.is_inside_tree() and not chest.is_queued_for_deletion() \
				and chest.global_position.distance_to(home) <= SettlerWork.CHEST_REACH:
			out.append(chest.inventory)
	return out
