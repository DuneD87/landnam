class_name SettlerMeals extends RefCounted

## El hambre y la sed de un colono (Companion viviendo en la base). Lleva las horas de juego que le
## quedan saciado (fed) y bebido (watered), que bajan con el reloj del mundo (WorldTime: también
## mientras el jugador duerme).
##
## Come por debajo de EAT_BELOW horas: primero de su morral y, si ahí solo hay algo que intoxica (lo
## crudo) o nada, del comedero de la base (Storage.feeder, a menos de REACH m de ella). Prefiere lo que
## no intoxica (lo asado) y, de eso, lo que más llena. Cada pieza le da lo que llena al jugador
## (EdibleTrait.hunger) por FULL_HOURS, y come hasta tener EAT_UNTIL horas. Los cofres normales ya no
## le dan de comer.
##
## Bebe por debajo de DRINK_BELOW horas, del bebedero de la base (WaterTrough): cada trago le da
## SIP_HOURS, hasta DRINK_UNTIL.
##
## Cerca del jugador va andando hasta el comedero o el bebedero (trip: lo lleva Companion._go_eat) y
## come o bebe al llegar (arrive); lejos, sin moverse.
##
## Sin comida o sin agua llega a cero y pasa hambre o sed: trabaja a la mitad de ritmo (con las dos, a
## un cuarto: pace) y no recupera vida, pero no muere. Se avisa en la barra, como mucho cada
## NOTIFY_EVERY s entre todos. Quien acompaña al jugador no pasa hambre ni sed. Ver docs/villagers.md.

## Lo que dura saciado del todo (horas de juego): la mitad de lo que gasta el jugador.
const FULL_HOURS := 36.0
const START_HOURS := 12.0
const EAT_BELOW := 6.0
const EAT_UNTIL := 14.0
## Lo que dura bebido del todo, al empezar, cuándo bebe, hasta cuánto y lo que da cada trago (horas).
## Así gasta un trago y medio al día.
const WATER_HOURS := 24.0
const START_WATER := 16.0
const DRINK_BELOW := 8.0
const DRINK_UNTIL := 20.0
const SIP_HOURS := 16.0
## Hasta dónde de la base valen el comedero y el bebedero (m).
const REACH := SettlerWork.CHEST_REACH
const CHECK_EVERY := 10.0
const NOTIFY_EVERY := 180.0

static var _last_notice := -INF

var fed := START_HOURS
var watered := START_WATER
## Cerca del jugador, a dónde va a comer o beber (el comedero o el bebedero), o null.
var trip: Node3D

var _c: Companion
var _check_left := 0.0
var _starving := false
var _parched := false


func _init(companion: Companion) -> void:
	_c = companion


func hungry() -> bool:
	return fed <= 0.0


func thirsty() -> bool:
	return watered <= 0.0


## Le falta algo (comida o agua): no recupera vida.
func wanting() -> bool:
	return hungry() or thirsty()


## Lo saciado y lo bebido que va (0-1, lleno a EAT_UNTIL y DRINK_UNTIL horas): las barras de las
## tarjetas (CompanionCards).
func food_ratio() -> float:
	return clampf(fed / EAT_UNTIL, 0.0, 1.0)


func water_ratio() -> float:
	return clampf(watered / DRINK_UNTIL, 0.0, 1.0)


## El ritmo al que trabaja: con hambre o con sed, a la mitad; con las dos, a un cuarto.
func pace() -> float:
	return (SettlerWork.HUNGRY_PACE if hungry() else 1.0) * (SettlerWork.HUNGRY_PACE if thirsty() else 1.0)


## Un paso (viviendo en la base). [near]: cerca del jugador, va andando a comer y a beber.
func tick(delta: float, near := false) -> void:
	var hours := WorldTime.hours_elapsed(delta)
	fed = maxf(fed - hours, 0.0)
	watered = maxf(watered - hours, 0.0)
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	if not near:
		trip = null
		if fed < EAT_BELOW:
			eat(_feeders())
		if watered < DRINK_BELOW:
			drink(_troughs())
	else:
		# Lo de su morral, sin ir a ningún sitio.
		if fed < EAT_BELOW and _pack_meal() != null:
			eat([])
		if not _trip_valid():
			trip = _next_trip()
	_notices()


## Ha llegado a [trip] (o no llega): come o bebe allí y mira si le falta ir a otro.
func arrive() -> void:
	var at := trip
	trip = null
	if at is Storage:
		eat([at as Storage])
	elif at is WaterTrough:
		drink([at as WaterTrough])
	trip = _next_trip()
	_notices()


## Come de lo que haya (su morral y [from]) hasta tener EAT_UNTIL horas. Devuelve cuántas piezas ha
## comido.
func eat(from: Array[Storage]) -> int:
	var eaten := 0
	while fed < EAT_UNTIL:
		var bag := _c.pack
		var food := best_food(bag)
		if food == null or _intoxicates(food):
			for feeder in from:
				var other := best_food(feeder.inventory)
				if other != null and (food == null or _score(other) > _score(food)):
					food = other
					bag = feeder.inventory
		if food == null or bag.remove_item(food, 1) != 1:
			break
		fed += (food.get_trait(EdibleTrait) as EdibleTrait).hunger * FULL_HOURS
		eaten += 1
	return eaten


## Bebe de [from] hasta tener DRINK_UNTIL horas. Devuelve cuántos tragos ha bebido.
func drink(from: Array[WaterTrough]) -> int:
	var sips := 0
	for trough in from:
		while watered < DRINK_UNTIL and trough.take(1) == 1:
			watered = minf(watered + SIP_HOURS, WATER_HOURS)
			sips += 1
	return sips


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


## Lo que tiene para comer en los comederos de su base (piezas que se comen), o -1 si no hay comedero.
## Para la charla (VillagerTalk.settler_needs).
func feeder_food() -> int:
	var feeders := _feeders()
	if feeders.is_empty():
		return -1
	var count := 0
	for feeder in feeders:
		for item in feeder.inventory.get_all_items():
			if item != null and _score(item.data) > 0.0:
				count += item.quantity
	return count


## Los tragos que quedan en los bebederos de su base, o -1 si no hay bebedero.
func trough_water() -> int:
	var troughs := _troughs()
	if troughs.is_empty():
		return -1
	var sips := 0
	for trough in troughs:
		sips += trough.water
	return sips


## Lo que comería de su morral sin ir al comedero (lo que no intoxica), o null.
func _pack_meal() -> ItemData:
	var food := best_food(_c.pack)
	return food if food != null and not _intoxicates(food) else null


## A dónde ir ahora: al comedero con comida si tiene hambre y, si no, al bebedero con agua si tiene
## sed; el más cercano. Null si no le hace falta o no hay.
func _next_trip() -> Node3D:
	if fed < EAT_BELOW:
		for feeder in _feeders():
			if best_food(feeder.inventory) != null:
				return feeder
	if watered < DRINK_BELOW:
		for trough in _troughs():
			if trough.water > 0:
				return trough
	return null


func _trip_valid() -> bool:
	return is_instance_valid(trip) and trip.is_inside_tree() and not trip.is_queued_for_deletion()


## Los comederos y los bebederos de su base, del más cercano a él al más lejano.
func _feeders() -> Array[Storage]:
	var home := _home()
	if not home.is_finite():
		return []
	return Storage.feeders(_c.get_tree(), home, REACH, _c.global_position)


func _troughs() -> Array[WaterTrough]:
	var home := _home()
	if not home.is_finite():
		return []
	return WaterTrough.around(_c.get_tree(), home, REACH, _c.global_position)


func _home() -> Vector3:
	return _c._terrain.global_transform * _c.base if _c.base.is_finite() else Vector3.INF


## Los avisos al quedarse sin comida o sin agua (uno de cada cada NOTIFY_EVERY s entre todos).
func _notices() -> void:
	var name := String(_c.resident.get("name", ""))
	if fed > 0.0:
		_starving = false
	elif not _starving:
		_starving = true
		_notify(_c.tr("SETTLER_STARVING") % name)
	if watered > 0.0:
		_parched = false
	elif not _parched:
		_parched = true
		_notify(_c.tr("SETTLER_PARCHED") % name)


func _notify(text: String) -> void:
	var now := SettlerWork._now()
	if now - _last_notice >= NOTIFY_EVERY:
		_last_notice = now
		_c.notify(text)
