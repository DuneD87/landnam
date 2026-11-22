class_name SettlementQuests extends RefCounted

## Los encargos de los aldeanos (VillagerChat): lo que le pide un vecino al jugador. Cada vecino puede
## pedir algo una vez cada PERIOD días de juego (el reloj de SettlementRelations), sorteado y siempre igual
## en ese tiempo. Un encargo abierto por poblado y MAX_OPEN a la vez. Tipos (KINDS):
##   - fetch: traer cosas, según su oficio (FETCH);
##   - hunt: acabar con unas cuantas fieras que rondan el poblado (PREY; cuentan las que caen a menos de
##     HUNT_REACH de la plaza a manos del jugador o de su compañero, SettlementManager.creature_killed);
##   - rescue: un vecino del poblado se ha perdido (malherido) en el monte; hay que encontrarlo (en el
##     mapa sale la zona, no el sitio), traerlo a casa y volver a decírselo;
##   - escort: quien lo pide quiere ir al poblado vecino; hay que acompañarlo por el camino (salen fieras
##     al paso); se cobra al llegar;
##   - errand: llevar un recado a un vecino del poblado vecino y volver con su respuesta (sube la confianza
##     de los dos poblados);
##   - beast: una fiera con nombre, más grande y dura, ronda un sitio marcado; muerta suelta un trofeo.
## Lo del mundo (el perdido, el escoltado, las emboscadas, la fiera) lo lleva QuestDirector.
##
## Cada uno tiene su plazo (HOURS, desde que se acepta). Al aceptarlo se puede regatear (haggle: más paga o,
## si sale mal, algo menos de confianza) y preguntar los detalles. Cumplirlo sube la confianza, sin tope (es
## lo que hace a alguien de la familia), y da algo de lo suyo (SettlementTrade.STOCK). Pasarse del plazo,
## dejar morir al perdido o al escoltado o dejarlo baja la confianza (fail, drop). Lo guarda
## SettlementManager. Ver docs/villagers.md.

## Cada cuántos días puede pedir algo cada vecino, y la probabilidad de que lo haga.
const PERIOD := 2
const CHANCE := 0.5
## Dónde se miran las fieras que rondan (m de la plaza).
const SCOUT_REACH := 400.0
## Encargos abiertos a la vez (uno por poblado).
const MAX_OPEN := 3
## Los tipos y su peso al sortear (los que no se pueden pedir ahí no entran).
const KINDS := {"fetch": 3.0, "hunt": 2.0, "rescue": 1.4, "escort": 1.2, "errand": 1.4, "beast": 1.0}
## El plazo de cada tipo (horas de juego desde que se acepta).
const HOURS := {"fetch": 72.0, "hunt": 48.0, "rescue": 18.0, "escort": 24.0, "errand": 48.0, "beast": 72.0}
## Lo que piden traer, por oficio ("kind" del puesto, "" sin oficio): [id, mínimo, máximo].
const FETCH := {
	&"woodpile": [[&"flint", 2, 4], [&"cooked_meat", 2, 4], [&"raw_hide", 2, 3], [&"sinew", 2, 4]],
	&"garden": [[&"bone", 3, 6], [&"raw_fish", 2, 4], [&"flint", 2, 3], [&"feather", 4, 8]],
	&"bench": [[&"flint", 3, 6], [&"copper_ore", 2, 4], [&"tin_ore", 2, 3], [&"antler", 2, 2], [&"sinew", 2, 4],
		[&"bone", 4, 6]],
	&"forge": [[&"copper_ore", 3, 6], [&"tin_ore", 2, 4], [&"coal", 4, 8], [&"bog_iron", 2, 4]],
	&"stall_food": [[&"raw_fish", 3, 6], [&"raw_meat", 3, 6], [&"yarrow", 3, 6]],
	&"stall_hides": [[&"raw_hide", 3, 5], [&"sinew", 3, 6], [&"antler", 1, 2], [&"feather", 6, 10]],
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
## Rescate y fiera: el sitio, a esta distancia (m) de la plaza, hacia el poblado vecino (por donde hay
## tierra) con hasta OFF_ANGLE grados de desvío; en el mapa sale la zona, a hasta HINT_OFF m del sitio.
const LOST_REACH := Vector2(250.0, 600.0)
const BEAST_REACH := Vector2(300.0, 700.0)
const OFF_ANGLE := 35.0
const HINT_OFF := 70.0
## Escolta y recado: el poblado vecino, a no más de esto (m).
const NEIGHBOUR_REACH := 3000.0
## Lo que valen (para la confianza y la paga): el rescate; la escolta y el recado, más por cada km; la fiera
## con nombre, en veces lo que vale una de su especie.
const RESCUE_WORTH := 40.0
const ESCORT_WORTH := Vector2(25.0, 12.0)
const ERRAND_WORTH := Vector2(16.0, 7.0)
const BEAST_WORTH := 3.0
## Al cumplirlo: confianza por unidad de valor del encargo, entre TRUST_MIN y TRUST_MAX; y lo que da en
## cosas, en veces ese valor.
const TRUST_RATE := 0.3
const TRUST_MIN := 4.0
const TRUST_MAX := 15.0
const REWARD_RATE := 0.8
## Lo que da el del otro poblado en un recado (valor) y lo que sube allí la confianza.
const ERRAND_GIFT := 6.0
const ERRAND_TRUST := 4.0
## Al fallar (plazo, muerte): baja la confianza el valor por FAIL_RATE, entre FAIL_MIN y FAIL_MAX; dejarlo
## a medias, la mitad.
const FAIL_RATE := 0.15
const FAIL_MIN := 3.0
const FAIL_MAX := 10.0
## Regatear: la probabilidad de que salga bien (más con cada nivel de confianza), lo que sube la paga si
## sale y lo que baja la confianza si no.
const HAGGLE_CHANCE := 0.35
const HAGGLE_TIER := 0.1
const HAGGLE_BONUS := 1.35
const HAGGLE_PENALTY := 2.0
## Los nombres de las fieras (VBEAST_<n>) y cuántos hay; y el trofeo de cada especie al matarla.
const BEAST_NAMES := 10
const TROPHY := {&"Wolf": &"fur_headdress", &"Boar": &"boar_headdress", &"Bear": &"fur_hood",
	&"PolarBear": &"fur_hood"}
const TROPHY_FALLBACK := [&"gold", 2]

var relations: SettlementRelations
## Planet.get_settlements().villages: dónde está cada poblado.
var villages: Array = []
## Los vecinos de un poblado (SettlementPopulation.residents): v -> Array[Dictionary]. Lo pone
## SettlementManager.
var residents_of: Callable
var _seed := 1
## Vecino (SettlementPopulation: "id") -> su encargo abierto (ver _roll).
var _open := {}
## Vecino -> {"period", "quest": lo que pide en ese periodo, o {} si nada}.
var _offers := {}
## Vecino -> el periodo en que cumplió (o falló) uno: hasta el siguiente no pide más.
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
	if _open.has(id) or _open.size() >= MAX_OPEN or _village_busy(v) or int(_done.get(id, -1)) == now \
			or _away(id):
		return {}
	var cached: Dictionary = _offers.get(id, {})
	if int(cached.get("period", -1)) == now:
		return cached.quest
	var quest := _roll(who, v, v_name, prey, now)
	_offers[id] = {"period": now, "quest": quest}
	return quest


## Si [id] tiene algo que pedir ahora (sin sortearlo si aún no se ha hecho: entonces, falso).
func asks(id: String) -> bool:
	var cached: Dictionary = _offers.get(id, {})
	return int(cached.get("period", -1)) == period() and not (cached.quest as Dictionary).is_empty() \
		and not _open.has(id) and _open.size() < MAX_OPEN and not _village_busy(int(cached.quest.village))


## El jugador acepta lo que pide [id]: queda abierto, con su plazo. El encargo, o {} si ya no lo pide.
func accept(id: String) -> Dictionary:
	var cached: Dictionary = _offers.get(id, {})
	var quest: Dictionary = cached.get("quest", {})
	if quest.is_empty() or int(cached.get("period", -1)) != period() or _open.has(id) \
			or _open.size() >= MAX_OPEN or _village_busy(int(quest.village)):
		return {}
	var open := quest.duplicate(true)
	open.due = relations.clock + float(HOURS.get(String(open.kind), 48.0))
	open.stage = _first_stage(String(open.kind))
	_open[id] = open
	_offers.erase(id)
	return open


static func _first_stage(kind: String) -> String:
	match kind:
		"rescue":
			return "search"
		"escort":
			return "travel"
		"errand":
			return "go"
		"beast":
			return "hunt"
	return ""


## Regatea lo que ofrece [id] (una vez por oferta): 1 si sube la paga (HAGGLE_BONUS), −1 si sale mal (baja
## la confianza HAGGLE_PENALTY), 0 si no se puede.
func haggle(id: String) -> int:
	var cached: Dictionary = _offers.get(id, {})
	var quest: Dictionary = cached.get("quest", {})
	if quest.is_empty() or bool(quest.get("haggled", false)):
		return 0
	quest.haggled = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(quest.get("seed", 0)), "haggle"])
	var chance := HAGGLE_CHANCE + HAGGLE_TIER * relations.tier(int(quest.village))
	if rng.randf() < chance:
		quest.bonus = HAGGLE_BONUS
		return 1
	relations.add(int(quest.village), -HAGGLE_PENALTY)
	return -1


## El jugador lo deja: se cierra y baja la confianza la mitad de lo que bajaría fallarlo. Lo que ha bajado.
func drop(id: String) -> float:
	var quest: Dictionary = _open.get(id, {})
	if quest.is_empty():
		return 0.0
	_open.erase(id)
	return -relations.add(int(quest.village), -_penalty(quest) * 0.5)


## Falla el de [id] (plazo, el perdido o el escoltado muertos): se cierra, baja la confianza y ese vecino no
## pide más en este periodo. {"quest", "lost": lo que ha bajado}, o {}.
func fail(id: String) -> Dictionary:
	var quest: Dictionary = _open.get(id, {})
	if quest.is_empty():
		return {}
	_open.erase(id)
	_done[id] = period()
	var lost := -relations.add(int(quest.village), -_penalty(quest))
	return {"quest": quest, "lost": lost}


func _penalty(quest: Dictionary) -> float:
	return clampf(float(quest.worth) * FAIL_RATE, FAIL_MIN, FAIL_MAX)


## Los abiertos que se han pasado de plazo (sin cerrarlos: eso es fail).
func overdue() -> Array[String]:
	var out: Array[String] = []
	for id: String in _open:
		var quest: Dictionary = _open[id]
		# La escolta y el rescate que ya están de vuelta no se pierden por el plazo.
		if relations.clock > float(quest.get("due", INF)) and not is_settled(quest):
			out.append(id)
	return out


## Lo que le queda de plazo a [quest] (horas de juego).
func hours_left(quest: Dictionary) -> float:
	return float(quest.get("due", INF)) - relations.clock


## Si [quest] ya no puede fallar (el perdido está en casa, la fiera muerta, el recado entregado): solo falta
## cobrarlo.
static func is_settled(quest: Dictionary) -> bool:
	return String(quest.get("stage", "")) in ["home", "slain", "back", "arrived"]


## Si [quest] está para cobrar: lo que pide, en [inventory]; las fieras, cazadas; el perdido, en casa; la
## fiera con nombre, muerta; el recado, con su respuesta.
func is_ready(quest: Dictionary, inventory: Inventory) -> bool:
	match String(quest.kind):
		"hunt":
			return int(quest.done) >= int(quest.count)
		"fetch":
			return inventory != null and inventory.has_item(ItemCatalog.get_item(StringName(quest.item)), int(quest.count))
		"escort":
			return String(quest.get("stage", "")) == "arrived"
	return is_settled(quest)


## Pasa el de [id] a [stage] (QuestDirector, la charla del recado).
func set_stage(id: String, stage: String) -> void:
	if _open.has(id):
		_open[id].stage = stage


## Se cumple el de [id] (lo traído ya lo ha quitado quien llama): {"gain": lo que ha subido la confianza,
## "reward": id -> cuántos, lo que le da}, o {}.
func complete(id: String) -> Dictionary:
	var quest: Dictionary = _open.get(id, {})
	if quest.is_empty():
		return {}
	_open.erase(id)
	_done[id] = period()
	var gain := relations.add(int(quest.village), clampf(float(quest.worth) * TRUST_RATE, TRUST_MIN, TRUST_MAX))
	return {"gain": gain, "reward": _reward(quest), "quest": quest}


## El recado que lleva el jugador para [to] (su "id"), aún sin entregar, o {}.
func errand_for(to: String) -> Dictionary:
	for quest: Dictionary in _open.values():
		if String(quest.kind) == "errand" and String(quest.get("to", "")) == to and String(quest.stage) == "go":
			return quest
	return {}


## [to] recibe el recado: el encargo pasa a volver, sube la confianza de su poblado y da algo pequeño de lo
## suyo. {"gain", "reward"}, o {}.
func deliver_errand(to: String, job: StringName) -> Dictionary:
	var quest := errand_for(to)
	if quest.is_empty():
		return {}
	quest.stage = "back"
	var gain := relations.add(int(quest.dest), ERRAND_TRUST)
	return {"gain": gain, "reward": _gifts(job, ERRAND_GIFT, int(quest.get("seed", 0)) + 7), "quest": quest}


## Los vecinos que no están en su casa por un encargo (el perdido): su poblado no los saca.
func away_ids() -> Dictionary:
	var out := {}
	for quest: Dictionary in _open.values():
		if String(quest.kind) == "rescue" and String(quest.stage) != "home":
			out[String(quest.lost)] = true
	return out


func _away(id: String) -> bool:
	return away_ids().has(id)


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
		if at.distance_to(center_of(v)) > HUNT_REACH:
			continue
		quest.done = int(quest.done) + 1
		out.append(quest)
	return out


## A dónde hay que ir ahora en [quest]: {"at": marco del terreno, "icon": el de MapMarkers, "area": si es
## una zona (el sitio va por ahí cerca) y no un punto}. Cobrar es en el poblado de quien lo pidió.
func target_of(quest: Dictionary) -> Dictionary:
	var stage := String(quest.get("stage", ""))
	var home := {"at": center_of(int(quest.village)), "icon": "home", "area": false}
	match String(quest.kind):
		"rescue":
			if stage == "search":
				return {"at": vec(quest.hint), "icon": "danger", "area": true}
		"beast":
			if stage == "hunt":
				return {"at": vec(quest.hint), "icon": "danger", "area": true}
		"escort":
			return {"at": center_of(int(quest.dest)), "icon": "flag", "area": false}
		"errand":
			if stage == "go":
				return {"at": center_of(int(quest.dest)), "icon": "flag", "area": false}
	return home


## La plaza de [v] (marco del terreno).
func center_of(v: int) -> Vector3:
	var plan: Dictionary = villages[v]
	return (plan.center as Vector3) * float(plan.ground)


## El poblado más cercano a [v] (a menos de NEIGHBOUR_REACH m), o −1.
func neighbour_of(v: int) -> int:
	var best := -1
	var best_d := NEIGHBOUR_REACH
	var here := center_of(v)
	for o in villages.size():
		if o == v:
			continue
		var d := here.distance_to(center_of(o))
		if d < best_d:
			best = o
			best_d = d
	return best


func _village_busy(v: int) -> bool:
	for quest: Dictionary in _open.values():
		if int(quest.village) == v:
			return true
	return false


## Para probar (consola `village quest <tipo>`): que [who] pida ahora un encargo de [kind] (si se puede ahí:
## si no, el que salga). Lo que pide, o {}.
func force_offer(who: Dictionary, v: int, v_name: String, prey: Array[StringName], kind: String) -> Dictionary:
	var id := String(who.get("id", ""))
	_done.erase(id)
	_open.erase(id)
	var quest := _roll(who, v, v_name, prey, period(), kind)
	_offers[id] = {"period": period(), "quest": quest}
	return quest


func _roll(who: Dictionary, v: int, v_name: String, prey: Array[StringName], now: int, forced := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, String(who.get("id", "")), now, "quest", forced])
	if forced == "" and rng.randf() >= CHANCE:
		return {}
	var job := StringName(who.get("job", {}).get("kind", ""))
	var quest := {"who": String(who.get("id", "")), "name": String(who.get("name", "")), "village": v,
		"village_name": v_name, "job": String(job), "seed": rng.randi(), "bonus": 1.0}
	var known: Array[StringName] = []
	for species in prey:
		if PREY.has(species):
			known.append(species)
	known.sort()
	var neighbour := neighbour_of(v) if v >= 0 and v < villages.size() else -1
	var tier := relations.tier(v)
	# Lo que se puede pedir aquí, con su peso.
	var kinds := {"fetch": KINDS.fetch}
	if not known.is_empty():
		kinds.hunt = KINDS.hunt
		kinds.beast = KINDS.beast
	if neighbour >= 0:
		kinds.rescue = KINDS.rescue
		if tier >= 1:
			kinds.escort = KINDS.escort
			kinds.errand = KINDS.errand
	var total := 0.0
	for kind: String in kinds:
		total += float(kinds[kind])
	var pick := rng.randf() * total
	var kind := "fetch"
	for k: String in kinds:
		pick -= float(kinds[k])
		if pick <= 0.0:
			kind = k
			break
	if kinds.has(forced):
		kind = forced
	var made := {}
	match kind:
		"hunt":
			made = _roll_hunt(rng, known)
		"beast":
			made = _roll_beast(rng, known, v, neighbour)
		"rescue":
			made = _roll_rescue(rng, who, v, neighbour)
		"escort":
			made = _roll_escort(v, neighbour)
		"errand":
			made = _roll_errand(rng, v, neighbour)
	if made.is_empty():
		made = _roll_fetch(rng, job)
	if made.is_empty():
		return {}
	quest.merge(made)
	# Las fieras del rescate y de las emboscadas: de las que rondan (o, sin saberlo, lobos).
	if not known.is_empty() and not quest.has("beasts"):
		quest.beasts = String(known[rng.randi() % known.size()])
	return quest


func _roll_fetch(rng: RandomNumberGenerator, job: StringName) -> Dictionary:
	var options: Array = FETCH.get(job, FETCH[&""])
	var pick: Array = options[rng.randi() % options.size()]
	var data := ItemCatalog.get_item(pick[0])
	if data == null:
		return {}
	var count := rng.randi_range(int(pick[1]), int(pick[2]))
	return {"kind": "fetch", "item": String(pick[0]), "count": count,
		"worth": ItemValue.of(data) * count * FETCH_PREMIUM}


func _roll_hunt(rng: RandomNumberGenerator, known: Array[StringName]) -> Dictionary:
	var species := known[rng.randi() % known.size()]
	var entry: Array = PREY[species]
	var count := rng.randi_range(int(entry[0]), int(entry[1]))
	return {"kind": "hunt", "species": String(species), "count": count, "done": 0, "worth": float(entry[2]) * count}


func _roll_beast(rng: RandomNumberGenerator, known: Array[StringName], v: int, neighbour: int) -> Dictionary:
	var species := known[rng.randi() % known.size()]
	var spot := _spot_toward(rng, v, neighbour, BEAST_REACH)
	return {"kind": "beast", "species": String(species), "beast_name": "VBEAST_%d" % (rng.randi() % BEAST_NAMES + 1),
		"spot": _arr(spot), "hint": _arr(_hint_near(rng, spot)), "worth": float(PREY[species][2]) * BEAST_WORTH}


func _roll_rescue(rng: RandomNumberGenerator, who: Dictionary, v: int, neighbour: int) -> Dictionary:
	if not residents_of.is_valid():
		return {}
	var others: Array = []
	for resident: Dictionary in residents_of.call(v):
		if String(resident.id) != String(who.get("id", "")):
			others.append(resident)
	if others.is_empty():
		return {}
	var lost: Dictionary = others[rng.randi() % others.size()]
	var spot := _spot_toward(rng, v, neighbour, LOST_REACH)
	return {"kind": "rescue", "lost": String(lost.id), "lost_name": String(lost.name), "spot": _arr(spot),
		"hint": _arr(_hint_near(rng, spot)), "worth": RESCUE_WORTH}


func _roll_escort(v: int, neighbour: int) -> Dictionary:
	var km := center_of(v).distance_to(center_of(neighbour)) / 1000.0
	return {"kind": "escort", "dest": neighbour, "dest_name": SettlementPopulation.village_name(neighbour, _seed),
		"worth": ESCORT_WORTH.x + ESCORT_WORTH.y * km}


func _roll_errand(rng: RandomNumberGenerator, v: int, neighbour: int) -> Dictionary:
	if not residents_of.is_valid():
		return {}
	var there: Array = residents_of.call(neighbour)
	if there.is_empty():
		return {}
	var to: Dictionary = there[rng.randi() % there.size()]
	var km := center_of(v).distance_to(center_of(neighbour)) / 1000.0
	return {"kind": "errand", "dest": neighbour, "dest_name": SettlementPopulation.village_name(neighbour, _seed),
		"to": String(to.id), "to_name": String(to.name), "worth": ERRAND_WORTH.x + ERRAND_WORTH.y * km}


## Un sitio a [reach] m de la plaza de [v], hacia [neighbour] (por donde hay tierra: una senda los une) con
## algo de desvío (marco del terreno, a la altura del suelo del poblado).
func _spot_toward(rng: RandomNumberGenerator, v: int, neighbour: int, reach: Vector2) -> Vector3:
	var here := center_of(v)
	var up := here.normalized()
	var toward := Vector3.ZERO
	if neighbour >= 0:
		toward = (center_of(neighbour) - here).slide(up).normalized()
	if toward == Vector3.ZERO:
		toward = up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	toward = toward.rotated(up, deg_to_rad(rng.randf_range(-OFF_ANGLE, OFF_ANGLE)))
	var point := here + toward * rng.randf_range(reach.x, reach.y)
	return point.normalized() * here.length()


func _hint_near(rng: RandomNumberGenerator, spot: Vector3) -> Vector3:
	var up := spot.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var point := spot + side.rotated(up, rng.randf() * TAU) * rng.randf_range(HINT_OFF * 0.3, HINT_OFF)
	return point.normalized() * spot.length()


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func vec(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	var a: Array = raw if raw is Array else []
	return Vector3(a[0], a[1], a[2]) if a.size() == 3 else Vector3.INF


## Lo que da por [quest]: de lo que tiene para cambiar según su oficio, hasta REWARD_RATE (por lo
## regateado) de lo que vale el encargo, de una o dos cosas.
func _reward(quest: Dictionary) -> Dictionary:
	return _gifts(StringName(quest.get("job", "")), float(quest.worth) * REWARD_RATE * float(quest.get("bonus", 1.0)),
		int(quest.get("seed", 0)))


func _gifts(job: StringName, budget: float, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var entries: Array = (SettlementTrade.STOCK.get(job, SettlementTrade.STOCK[&""]) as Array).duplicate()
	for i in range(entries.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = entries[i]
		entries[i] = entries[j]
		entries[j] = swap
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


## El trofeo de la fiera con nombre de [species]: {id: cuántos}.
static func trophy_of(species: StringName) -> Dictionary:
	if TROPHY.has(species) and ItemCatalog.get_item(TROPHY[species]) != null:
		return {TROPHY[species]: 1}
	return {TROPHY_FALLBACK[0]: TROPHY_FALLBACK[1]}


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
			if not quest.has("due"):
				quest.due = relations.clock + float(HOURS.get(String(quest.kind), 48.0))
			if not quest.has("stage"):
				quest.stage = _first_stage(String(quest.kind))
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
	var quest: Dictionary = (raw as Dictionary).duplicate(true)
	for key in ["village", "count", "done", "seed", "dest"]:
		if quest.has(key):
			quest[key] = int(quest[key])
	quest.worth = float(quest.get("worth", 0.0))
	if quest.has("due"):
		quest.due = float(quest.due)
	quest.bonus = float(quest.get("bonus", 1.0))
	return quest
