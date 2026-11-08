class_name SettlementQuests extends RefCounted

## Los encargos de los aldeanos (VillagerChat): lo que le pide un vecino al jugador, que lo trae o lo caza
## y vuelve a decírselo. Cada vecino puede pedir algo una vez cada PERIOD días de juego (el reloj de
## SettlementRelations), sorteado y siempre igual en ese tiempo: traer cosas (FETCH, según su oficio) o,
## si rondan fieras cerca del poblado (SettlementVillage.prey_near), acabar con unas cuantas (PREY). Un
## encargo abierto por poblado y MAX_OPEN a la vez. Las fieras cuentan si las mata el jugador o su
## compañero a menos de HUNT_REACH del poblado (SettlementManager.creature_killed). Cumplirlo sube la
## confianza, sin tope (es lo que hace a alguien de la familia), y le da algo de lo suyo
## (SettlementTrade.STOCK). Lo guarda SettlementManager. Ver docs/villagers.md.

## Cada cuántos días puede pedir algo cada vecino, y la probabilidad de que lo haga.
const PERIOD := 2
const CHANCE := 0.45
## Si rondan fieras, la probabilidad de que el encargo sea de caza; y dónde se miran (m de la plaza).
const HUNT_SHARE := 0.5
const SCOUT_REACH := 400.0
## Encargos abiertos a la vez (uno por poblado).
const MAX_OPEN := 3
## Lo que piden traer, por oficio ("kind" del puesto, "" sin oficio): [id, mínimo, máximo].
const FETCH := {
	&"woodpile": [[&"flint", 2, 4], [&"cooked_meat", 2, 4], [&"raw_hide", 2, 3], [&"sinew", 2, 4]],
	&"garden": [[&"bone", 3, 6], [&"raw_fish", 2, 4], [&"flint", 2, 3], [&"feather", 4, 8]],
	&"bench": [[&"flint", 3, 6], [&"copper_ore", 2, 4], [&"tin_ore", 2, 3], [&"antler", 2, 2], [&"sinew", 2, 4],
		[&"bone", 4, 6]],
	&"": [[&"cooked_meat", 2, 5], [&"raw_hide", 2, 4], [&"yarrow", 3, 6], [&"cooked_fish", 2, 4],
		[&"raw_meat", 3, 5]],
}
## Lo que vale traerlo, en veces lo que vale lo traído (ItemValue): el camino también cuenta.
const FETCH_PREMIUM := 1.5
## Las fieras que piden cazar (SettlementVillage.THREATS): [mínimo, máximo, lo que vale cada una].
const PREY := {
	&"Wolf": [2, 3, 12.0], &"Hyena": [2, 3, 12.0], &"Boar": [1, 2, 12.0], &"Lynx": [1, 2, 14.0],
	&"Puma": [1, 1, 25.0], &"Alligator": [1, 1, 30.0], &"Lioness": [1, 1, 35.0], &"Lion": [1, 1, 40.0],
	&"Bear": [1, 1, 40.0], &"PolarBear": [1, 1, 45.0],
}
## Cuentan las que caen a menos de esto (m) de la plaza.
const HUNT_REACH := 600.0
## Al cumplirlo: confianza por unidad de valor del encargo, entre TRUST_MIN y TRUST_MAX; y lo que da en
## cosas, en veces ese valor.
const TRUST_RATE := 0.3
const TRUST_MIN := 4.0
const TRUST_MAX := 15.0
const REWARD_RATE := 0.8

var relations: SettlementRelations
## Planet.get_settlements().villages: dónde está cada poblado.
var villages: Array = []
var _seed := 1
## Vecino (SettlementPopulation: "id") -> su encargo abierto: {"who", "name", "village", "village_name",
## "job", "seed", "kind": "fetch" o "hunt", "item" o "species", "count", "done" (las cazadas), "worth"}.
var _open := {}
## Vecino -> {"period", "quest": lo que pide en ese periodo, o {} si nada}.
var _offers := {}
## Vecino -> el periodo en que cumplió uno: hasta el siguiente no pide más.
var _done := {}


func _init(trust: SettlementRelations, seed: int) -> void:
	relations = trust
	_seed = seed


func period() -> int:
	return floori(relations.clock / 24.0 / PERIOD)


## El encargo abierto de [id], o {}.
func open_of(id: String) -> Dictionary:
	return _open.get(id, {})


## Todos los abiertos.
func open_list() -> Array:
	return _open.values()


## Lo que pide ahora [who], del poblado [v] ([v_name]), si se le pregunta, o {}: nada si ya tiene uno
## abierto, si su poblado ya tiene otro o si ya van MAX_OPEN. [prey]: las fieras que rondan
## (SettlementVillage.prey_near). Se sortea la primera vez que se le pregunta en el periodo.
func offer(who: Dictionary, v: int, v_name: String, prey: Array[StringName]) -> Dictionary:
	var id := String(who.get("id", ""))
	var now := period()
	if _open.has(id) or _open.size() >= MAX_OPEN or _village_busy(v) or int(_done.get(id, -1)) == now:
		return {}
	var cached: Dictionary = _offers.get(id, {})
	if int(cached.get("period", -1)) == now:
		return cached.quest
	var quest := _roll(who, v, v_name, prey, now)
	_offers[id] = {"period": now, "quest": quest}
	return quest


## El jugador acepta lo que pide [id]: queda abierto. El encargo, o {} si ya no lo pide.
func accept(id: String) -> Dictionary:
	var cached: Dictionary = _offers.get(id, {})
	var quest: Dictionary = cached.get("quest", {})
	if quest.is_empty() or int(cached.get("period", -1)) != period() or _open.has(id) \
			or _open.size() >= MAX_OPEN or _village_busy(int(quest.village)):
		return {}
	_open[id] = quest.duplicate()
	_offers.erase(id)
	return _open[id]


## El jugador lo deja: se cierra sin más (lo puede volver a pedir).
func drop(id: String) -> void:
	_open.erase(id)


## Si [quest] está para entregar: lo que pide, en [inventory]; las fieras, cazadas.
func is_ready(quest: Dictionary, inventory: Inventory) -> bool:
	if quest.kind == "hunt":
		return int(quest.done) >= int(quest.count)
	return inventory != null and inventory.has_item(ItemCatalog.get_item(StringName(quest.item)), int(quest.count))


## Se cumple el de [id] (lo traído ya lo ha quitado quien llama): {"gain": lo que ha subido la confianza,
## "reward": id -> cuántos, lo que le da}, o {}.
func complete(id: String) -> Dictionary:
	var quest: Dictionary = _open.get(id, {})
	if quest.is_empty():
		return {}
	_open.erase(id)
	_done[id] = period()
	var gain := relations.add(int(quest.village), clampf(float(quest.worth) * TRUST_RATE, TRUST_MIN, TRUST_MAX))
	return {"gain": gain, "reward": _reward(quest)}


## Ha caído una [species] en [at] (marco del terreno) a manos del jugador o de su compañero: los encargos
## que han avanzado.
func killed(species: StringName, at: Vector3) -> Array:
	var out: Array = []
	for id: String in _open:
		var quest: Dictionary = _open[id]
		if quest.kind != "hunt" or StringName(quest.species) != species or int(quest.done) >= int(quest.count):
			continue
		var v := int(quest.village)
		if v < 0 or v >= villages.size():
			continue
		var plan: Dictionary = villages[v]
		if at.distance_to((plan.center as Vector3) * float(plan.ground)) > HUNT_REACH:
			continue
		quest.done = int(quest.done) + 1
		out.append(quest)
	return out


func _village_busy(v: int) -> bool:
	for quest: Dictionary in _open.values():
		if int(quest.village) == v:
			return true
	return false


func _roll(who: Dictionary, v: int, v_name: String, prey: Array[StringName], now: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, String(who.get("id", "")), now, "quest"])
	if rng.randf() >= CHANCE:
		return {}
	var job := StringName(who.get("job", {}).get("kind", ""))
	var quest := {"who": String(who.get("id", "")), "name": String(who.get("name", "")), "village": v,
		"village_name": v_name, "job": String(job), "seed": rng.randi()}
	var known: Array[StringName] = []
	for species in prey:
		if PREY.has(species):
			known.append(species)
	known.sort()
	if not known.is_empty() and rng.randf() < HUNT_SHARE:
		var species := known[rng.randi() % known.size()]
		var entry: Array = PREY[species]
		var count := rng.randi_range(int(entry[0]), int(entry[1]))
		quest.merge({"kind": "hunt", "species": String(species), "count": count, "done": 0,
			"worth": float(entry[2]) * count})
		return quest
	var options: Array = FETCH.get(job, FETCH[&""])
	var pick: Array = options[rng.randi() % options.size()]
	var data := ItemCatalog.get_item(pick[0])
	if data == null:
		return {}
	var count := rng.randi_range(int(pick[1]), int(pick[2]))
	quest.merge({"kind": "fetch", "item": String(pick[0]), "count": count,
		"worth": ItemValue.of(data) * count * FETCH_PREMIUM})
	return quest


## Lo que da por [quest]: de lo que tiene para cambiar según su oficio, hasta REWARD_RATE de lo que vale
## el encargo, de una o dos cosas.
func _reward(quest: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(quest.get("seed", 0))
	var entries: Array = (SettlementTrade.STOCK.get(StringName(quest.get("job", "")), SettlementTrade.STOCK[&""]) \
		as Array).duplicate()
	for i in range(entries.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = entries[i]
		entries[i] = entries[j]
		entries[j] = swap
	var budget := float(quest.worth) * REWARD_RATE
	var out := {}
	for entry: Array in entries:
		var data := ItemCatalog.get_item(entry[0])
		var value := ItemValue.of(data)
		if data == null or value <= 0.0 or value > budget:
			continue
		var count := mini(floori(budget / value), int(entry[2]))
		out[entry[0]] = count
		budget -= value * count
		if out.size() >= 2:
			break
	return out


func save_data() -> Dictionary:
	var now := period()
	var offers := {}
	for id: String in _offers:
		if int(_offers[id].get("period", -1)) == now:
			offers[id] = _offers[id]
	var done := {}
	for id: String in _done:
		if int(_done[id]) == now:
			done[id] = now
	return {"open": _open.duplicate(true), "offers": offers, "done": done}


func restore(data: Dictionary) -> void:
	_open.clear()
	_offers.clear()
	_done.clear()
	var open: Dictionary = data.get("open", {})
	for id in open:
		var quest := _clean(open[id])
		if not quest.is_empty():
			_open[str(id)] = quest
	var offers: Dictionary = data.get("offers", {})
	for id in offers:
		var entry: Dictionary = offers[id]
		_offers[str(id)] = {"period": int(entry.get("period", -1)), "quest": _clean(entry.get("quest", {}))}
	var done: Dictionary = data.get("done", {})
	for id in done:
		_done[str(id)] = int(done[id])


## [raw] de una partida guardada, con sus números como números (el JSON los vuelve decimales), o {} si no
## es un encargo.
static func _clean(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not (raw as Dictionary).has("kind"):
		return {}
	var quest: Dictionary = (raw as Dictionary).duplicate()
	for key in ["village", "count", "done", "seed"]:
		if quest.has(key):
			quest[key] = int(quest[key])
	quest.worth = float(quest.get("worth", 0.0))
	return quest
