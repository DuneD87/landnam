class_name SettlementTrade extends RefCounted

## El trueque con los aldeanos (VillagerChat): lo que tiene cada uno para cambiar y a cuánto. Cada vecino
## ofrece lo de su oficio (STOCK por "kind" de su puesto; sin oficio, la despensa del poblado), sorteado
## cada día de juego (el reloj de SettlementRelations) y siempre igual el mismo día; lo que el jugador se
## lleva se descuenta hasta el día siguiente. Se paga con cosas: lo que el jugador da cuenta su valor
## (ItemValue) por BUY y lo que se lleva, por SELL, los dos según la confianza del poblado. Lo que da de
## más es un regalo, y cada trato sube un poco la confianza. Lo guarda SettlementManager. Ver
## docs/villagers.md.
##
## Lo que el jugador le da a un vecino (regalos y lo que entrega en un trato) pasa a su género (receive): lo
## vende como lo suyo, y se le va gastando (la mitad cada día). Lleva también lo que hay en los arcones,
## cajas, barriles y sacos de las casas (stash, SettlementStash): sale de STASH cada día, menos lo que se
## ha llevado el jugador ese día.

## Por oficio ("kind" del puesto, "" sin oficio): [id, mínimo, máximo, probabilidad de tenerlo ese día].
const STOCK := {
	&"woodpile": [[&"wood_01", 10, 25, 1.0], [&"branch_01", 6, 15, 1.0], [&"plant_fiber", 2, 6, 0.5],
		[&"torch_01", 1, 3, 0.4], [&"stone_axe_01", 1, 1, 0.25]],
	&"garden": [[&"plant_fiber", 8, 20, 1.0], [&"yarrow", 2, 6, 1.0], [&"yarrow_poultice", 1, 2, 0.5],
		[&"yarrow_draught", 1, 1, 0.3], [&"stone_hoe_01", 1, 1, 0.2]],
	&"bench": [[&"stone_axe_01", 1, 1, 0.6], [&"stone_pickaxe_01", 1, 1, 0.6], [&"stone_hammer_01", 1, 1, 0.4],
		[&"stone_hoe_01", 1, 1, 0.3], [&"flint_knife", 1, 1, 0.5], [&"flint_spear", 1, 1, 0.4],
		[&"hunting_bow", 1, 1, 0.25], [&"arrow", 5, 15, 0.5], [&"wooden_shield", 1, 1, 0.3],
		[&"waterskin", 1, 1, 0.4], [&"rope_ladder_01", 1, 1, 0.2], [&"bronze_axe", 1, 1, 0.1],
		[&"bronze_pickaxe", 1, 1, 0.08], [&"bronze_sword", 1, 1, 0.05]],
	&"forge": [[&"bronze_ingot", 1, 3, 0.7], [&"bronze_axe", 1, 1, 0.5], [&"bronze_pickaxe", 1, 1, 0.5],
		[&"bronze_hoe", 1, 1, 0.4], [&"bronze_sword", 1, 1, 0.3], [&"seax", 1, 1, 0.25], [&"spear", 1, 1, 0.3],
		[&"copper_ore", 2, 6, 0.5], [&"tin_ore", 1, 4, 0.4], [&"coal", 3, 8, 0.6], [&"fishing_hook", 2, 5, 0.4]],
	&"shop": [[&"waterskin", 1, 2, 0.7], [&"rope_ladder_01", 1, 1, 0.4], [&"torch_01", 2, 5, 0.8],
		[&"bedroll", 1, 1, 0.4], [&"skin_backpack", 1, 1, 0.3], [&"hide_backpack", 1, 1, 0.15],
		[&"fishing_rod", 1, 1, 0.4], [&"fishing_bait", 3, 8, 0.5], [&"arrow", 10, 20, 0.6],
		[&"hunting_bow", 1, 1, 0.3], [&"wooden_shield", 1, 1, 0.3], [&"yarrow_poultice", 1, 3, 0.5],
		[&"splint", 1, 2, 0.4], [&"glass_01", 2, 6, 0.3], [&"cooked_meat", 2, 5, 0.6]],
	&"stall_food": [[&"cooked_meat", 3, 8, 1.0], [&"cooked_fish", 2, 6, 0.9], [&"raw_fish", 2, 6, 0.7],
		[&"raw_meat", 2, 6, 0.7], [&"yarrow", 2, 5, 0.5], [&"yarrow_draught", 1, 2, 0.3]],
	&"stall_hides": [[&"raw_hide", 2, 6, 1.0], [&"sinew", 2, 6, 0.8], [&"fur_mantle", 1, 1, 0.4],
		[&"fur_moccasins", 1, 1, 0.4], [&"fur_mittens", 1, 1, 0.4], [&"deer_mantle", 1, 1, 0.3],
		[&"fur_coat", 1, 1, 0.2], [&"fur_boots", 1, 1, 0.25], [&"fur_hood", 1, 1, 0.3], [&"antler", 1, 2, 0.4],
		[&"horn", 1, 2, 0.3], [&"feather", 5, 15, 0.6]],
	&"stall_wares": [[&"waterskin", 1, 2, 0.6], [&"plant_fiber", 6, 15, 0.9], [&"bone", 3, 8, 0.6],
		[&"flint", 3, 8, 0.8], [&"flint_knife", 1, 1, 0.5], [&"bone_dagger", 1, 1, 0.3], [&"stone_club", 1, 1, 0.3],
		[&"torch_01", 2, 5, 0.7], [&"arrow", 5, 15, 0.5], [&"slingshot", 1, 1, 0.3], [&"fishing_hook", 1, 3, 0.4]],
	&"": [[&"cooked_meat", 1, 4, 0.8], [&"raw_meat", 1, 4, 0.6], [&"cooked_fish", 1, 3, 0.4],
		[&"raw_hide", 1, 3, 0.7], [&"bone", 2, 6, 0.6], [&"sinew", 1, 3, 0.4], [&"feather", 3, 10, 0.4],
		[&"antler", 1, 1, 0.15], [&"fur_mittens", 1, 1, 0.15], [&"fur_moccasins", 1, 1, 0.15],
		[&"deer_moccasins", 1, 1, 0.15]],
}
## Lo que guardan las casas, por lo que lo guarda (SettlementProp.kind): como STOCK.
const STASH := {
	&"chest": [[&"fur_mantle", 1, 1, 0.3], [&"fur_moccasins", 1, 1, 0.3], [&"fur_mittens", 1, 1, 0.3],
		[&"deer_moccasins", 1, 1, 0.2], [&"fur_hood", 1, 1, 0.2], [&"waterskin", 1, 1, 0.3],
		[&"flint_knife", 1, 1, 0.3], [&"bone_dagger", 1, 1, 0.2], [&"torch_01", 1, 3, 0.5],
		[&"sinew", 1, 4, 0.4], [&"bronze_ingot", 1, 2, 0.15], [&"bedroll", 1, 1, 0.1]],
	&"crate": [[&"flint", 2, 6, 0.6], [&"bone", 2, 6, 0.5], [&"plant_fiber", 4, 10, 0.7], [&"sinew", 1, 3, 0.4],
		[&"arrow", 3, 10, 0.3], [&"fishing_hook", 1, 3, 0.3], [&"torch_01", 1, 3, 0.4], [&"stone_axe_01", 1, 1, 0.15]],
	&"barrel": [[&"cooked_meat", 1, 4, 0.6], [&"raw_meat", 1, 3, 0.4], [&"raw_fish", 1, 4, 0.4],
		[&"cooked_fish", 1, 3, 0.4], [&"yarrow", 1, 4, 0.3]],
	&"sack": [[&"plant_fiber", 5, 15, 0.8], [&"yarrow", 2, 6, 0.5], [&"feather", 3, 10, 0.5], [&"raw_hide", 1, 2, 0.3]],
}
## Por nivel de confianza (SettlementRelations.TIERS): lo que cobran por lo suyo y lo que dan por lo del
## jugador, en veces su valor. Nunca dan más de lo que cobran: comprar y revender no deja nada.
const SELL: Array[float] = [1.6, 1.35, 1.15, 1.0, 0.95]
const BUY: Array[float] = [0.55, 0.65, 0.75, 0.85, 0.95]
## Un trato de al menos TRADE_MIN (lo que se lleva, a su precio) sube la confianza TRADE_GAIN, una vez al
## día por vecino y hasta TRADE_CAP: comerciando se llega a amigos, no a familia.
const TRADE_MIN := 4.0
const TRADE_GAIN := 2.0
const TRADE_CAP := 60.0

var relations: SettlementRelations
var _seed := 1
## Vecino (SettlementPopulation: "id") -> {"day", "items": id -> lo que se ha llevado el jugador ese día}.
var _bought := {}
## Vecino -> el día del último trato que subió la confianza.
var _traded := {}
## Vecino -> {"day", "items": id -> cuántos}: lo que le ha dado el jugador, contado el día "day".
var _given := {}


func _init(trust: SettlementRelations, seed: int) -> void:
	relations = trust
	_seed = seed


## El día de juego (cuenta desde que empezó el reloj de la confianza).
func day() -> int:
	return floori(relations.clock / 24.0)


## Lo que tiene hoy [who] para cambiar: id (StringName) -> cuántos, sin lo que ya se ha llevado el jugador
## y con lo que le ha dado (receive).
func stock(who: Dictionary) -> Dictionary:
	var id := String(who.get("id", ""))
	var kind := StringName(who.get("job", {}).get("kind", ""))
	var out := _roll(STOCK.get(kind, STOCK[&""]), id, "stock")
	for item: String in _received(id):
		var key := StringName(item)
		if ItemCatalog.get_item(key) != null:
			out[key] = int(out.get(key, 0)) + int(_given[id].items[item])
	return out


## Lo de [table] (STOCK o STASH) para [id] hoy, sin lo que ya se ha llevado el jugador.
func _roll(table: Array, id: String, salt: String) -> Dictionary:
	var today := day()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, id, today, salt])
	var taken: Dictionary = _bought.get(id, {}).get("items", {}) if int(_bought.get(id, {}).get("day", -1)) == today \
		else {}
	var out := {}
	for entry: Array in table:
		# Las tres tiradas siempre, para que lo de después no cambie con lo de antes.
		var has := rng.randf() < float(entry[3])
		var count := rng.randi_range(int(entry[1]), int(entry[2]))
		if not has or ItemCatalog.get_item(entry[0]) == null:
			continue
		count -= int(taken.get(String(entry[0]), 0))
		if count > 0:
			out[entry[0]] = count
	return out


## Lo que le queda hoy a [id] de lo que le ha dado el jugador (id -> cuántos, en _given): la mitad por
## cada día que ha pasado.
func _received(id: String) -> Dictionary:
	if not _given.has(id):
		return {}
	var record: Dictionary = _given[id]
	var days := day() - int(record.get("day", 0))
	if days > 0:
		var items: Dictionary = record.items
		for item: String in items.keys():
			items[item] = int(items[item]) >> mini(days, 30)
			if int(items[item]) <= 0:
				items.erase(item)
		record.day = day()
		if items.is_empty():
			_given.erase(id)
			return {}
	return record.items


## [who] recibe [items] (id -> cuántos) del jugador: pasa a su género.
func receive(who: Dictionary, items: Dictionary) -> void:
	var id := String(who.get("id", ""))
	_received(id)
	var record: Dictionary = _given.get_or_add(id, {"day": day(), "items": {}})
	for item in items:
		record.items[String(item)] = int(record.items.get(String(item), 0)) + int(items[item])


## Lo que hay hoy en el arcón, caja, barril o saco [key] ("<poblado>:<casa>:<adorno>") de clase [kind]
## (SettlementProp.kind): id (StringName) -> cuántos, sin lo que se ha llevado el jugador hoy.
func stash(key: String, kind: StringName) -> Dictionary:
	return _roll(STASH.get(kind, STASH[&"crate"]), "stash:" + key, "stash")


## El jugador se lleva [items] (id -> cuántos) de [key] (stash).
func take_stash(key: String, items: Dictionary) -> void:
	_take("stash:" + key, items)


func _take(id: String, items: Dictionary) -> void:
	var today := day()
	var record: Dictionary = _bought.get(id, {})
	if int(record.get("day", -1)) != today:
		record = {"day": today, "items": {}}
	for item in items:
		record.items[String(item)] = int(record.items.get(String(item), 0)) + int(items[item])
	_bought[id] = record


## Lo que cobra el poblado [v] por [data] (en piezas de leña, ItemValue) y lo que da por él.
func sell_price(v: int, data: ItemData) -> float:
	return ItemValue.of(data) * SELL[relations.tier(v)]


func buy_price(v: int, data: ItemData) -> float:
	return ItemValue.of(data) * BUY[relations.tier(v)]


## Lo que vale para el poblado [v] llevarse [take] y dar [give] (ItemData -> cuántos): {"cost", "credit"}.
func balance(v: int, take: Dictionary, give: Dictionary) -> Dictionary:
	var cost := 0.0
	for data: ItemData in take:
		cost += sell_price(v, data) * int(take[data])
	var credit := 0.0
	for data: ItemData in give:
		credit += buy_price(v, data) * int(give[data])
	return {"cost": cost, "credit": credit}


## Cierra el trato con [who] del poblado [v]: se apunta lo que se lleva el jugador, lo que da de más es
## un regalo y, si es el primero del día con él, sube la confianza. Lo que ha subido.
func deal(who: Dictionary, v: int, take: Dictionary, give: Dictionary) -> float:
	var sums := balance(v, take, give)
	var id := String(who.get("id", ""))
	var today := day()
	# Lo que se lleva sale antes de lo que le dio el jugador; el resto, de lo suyo.
	var given := _received(id)
	var taken := {}
	for data: ItemData in take:
		var count := int(take[data])
		var back := mini(count, int(given.get(String(data.id), 0)))
		if back > 0:
			given[String(data.id)] = int(given[String(data.id)]) - back
			if int(given[String(data.id)]) <= 0:
				given.erase(String(data.id))
		if count > back:
			taken[data.id] = count - back
	_take(id, taken)
	var handed := {}
	for data: ItemData in give:
		handed[data.id] = int(give[data])
	receive(who, handed)
	var gain := 0.0
	var surplus := float(sums.credit) - float(sums.cost)
	if surplus > 0.0:
		gain += relations.gift(v, surplus, 1.0)
	if float(sums.cost) >= TRADE_MIN and int(_traded.get(id, -1)) != today and relations.trust(v) < TRADE_CAP:
		_traded[id] = today
		gain += relations.add(v, minf(TRADE_GAIN, TRADE_CAP - relations.trust(v)))
	return gain


func save_data() -> Dictionary:
	var today := day()
	var bought := {}
	for id: String in _bought:
		if int(_bought[id].get("day", -1)) == today:
			bought[id] = _bought[id]
	var traded := {}
	for id: String in _traded:
		if int(_traded[id]) == today:
			traded[id] = today
	var given := {}
	for id: String in _given.keys():
		if not _received(id).is_empty():
			given[id] = _given[id].duplicate(true)
	return {"bought": bought, "traded": traded, "given": given}


func restore(data: Dictionary) -> void:
	_bought.clear()
	_traded.clear()
	var bought: Dictionary = data.get("bought", {})
	for id in bought:
		var entry: Dictionary = bought[id]
		var items := {}
		for item in entry.get("items", {}):
			items[str(item)] = int(entry.items[item])
		_bought[str(id)] = {"day": int(entry.get("day", -1)), "items": items}
	var traded: Dictionary = data.get("traded", {})
	for id in traded:
		_traded[str(id)] = int(traded[id])
	_given.clear()
	var given: Dictionary = data.get("given", {})
	for id in given:
		var entry: Dictionary = given[id]
		var items := {}
		for item in entry.get("items", {}):
			items[str(item)] = int(entry.items[item])
		_given[str(id)] = {"day": int(entry.get("day", 0)), "items": items}
