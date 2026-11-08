class_name SettlementTrade extends RefCounted

## El trueque con los aldeanos (VillagerChat): lo que tiene cada uno para cambiar y a cuánto. Cada vecino
## ofrece lo de su oficio (STOCK por "kind" de su puesto; sin oficio, la despensa del poblado), sorteado
## cada día de juego (el reloj de SettlementRelations) y siempre igual el mismo día; lo que el jugador se
## lleva se descuenta hasta el día siguiente. Se paga con cosas: lo que el jugador da cuenta su valor
## (ItemValue) por BUY y lo que se lleva, por SELL, los dos según la confianza del poblado. Lo que da de
## más es un regalo, y cada trato sube un poco la confianza. Lo guarda SettlementManager. Ver
## docs/villagers.md.

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
	&"": [[&"cooked_meat", 1, 4, 0.8], [&"raw_meat", 1, 4, 0.6], [&"cooked_fish", 1, 3, 0.4],
		[&"raw_hide", 1, 3, 0.7], [&"bone", 2, 6, 0.6], [&"sinew", 1, 3, 0.4], [&"feather", 3, 10, 0.4],
		[&"antler", 1, 1, 0.15], [&"fur_mittens", 1, 1, 0.15], [&"fur_moccasins", 1, 1, 0.15],
		[&"deer_moccasins", 1, 1, 0.15]],
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


func _init(trust: SettlementRelations, seed: int) -> void:
	relations = trust
	_seed = seed


## El día de juego (cuenta desde que empezó el reloj de la confianza).
func day() -> int:
	return floori(relations.clock / 24.0)


## Lo que tiene hoy [who] para cambiar: id (StringName) -> cuántos, sin lo que ya se ha llevado el jugador.
func stock(who: Dictionary) -> Dictionary:
	var id := String(who.get("id", ""))
	var today := day()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, id, today, "stock"])
	var kind := StringName(who.get("job", {}).get("kind", ""))
	var taken: Dictionary = _bought.get(id, {}).get("items", {}) if int(_bought.get(id, {}).get("day", -1)) == today \
		else {}
	var out := {}
	for entry: Array in STOCK.get(kind, STOCK[&""]):
		# Las tres tiradas siempre, para que lo de después no cambie con lo de antes.
		var has := rng.randf() < float(entry[3])
		var count := rng.randi_range(int(entry[1]), int(entry[2]))
		if not has or ItemCatalog.get_item(entry[0]) == null:
			continue
		count -= int(taken.get(String(entry[0]), 0))
		if count > 0:
			out[entry[0]] = count
	return out


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
	var record: Dictionary = _bought.get(id, {})
	if int(record.get("day", -1)) != today:
		record = {"day": today, "items": {}}
	for data: ItemData in take:
		record.items[String(data.id)] = int(record.items.get(String(data.id), 0)) + int(take[data])
	_bought[id] = record
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
	return {"bought": bought, "traded": traded}


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
