class_name SettlementRelations extends RefCounted

## Lo que es el jugador para cada poblado: su confianza (0..100), a quién conoce y cuándo habló con él
## por última vez, y lo que les ha regalado hace poco (que se enfría con las horas). Lleva su propio reloj
## de horas de juego. Lo guarda SettlementManager. Ver docs/villagers.md.

const MAX_TRUST := 100.0
## Los niveles: desde cuánta confianza, y su nombre.
const TIERS := [[0.0, "VILLAGE_TRUST_WARY"], [20.0, "VILLAGE_TRUST_CAUTIOUS"], [40.0, "VILLAGE_TRUST_FRIENDLY"],
	[60.0, "VILLAGE_TRUST_FRIENDS"], [80.0, "VILLAGE_TRUST_KIN"]]
## Hablar con alguien da esto la primera vez cada TALK_COOLDOWN horas, hasta TALK_CAP de confianza: de
## palabras solo no se hacen amigos.
const TALK_GAIN := 1.0
const TALK_CAP := 30.0
const TALK_COOLDOWN := 12.0
## Lo regalado hace poco (en valor, ItemValue) se enfría a la mitad cada tantas horas; cuanto más hay,
## menos cuenta lo siguiente (GIFT_SATURATION: con eso encima, cuenta la mitad).
const GIFT_HALF_LIFE := 12.0
const GIFT_SATURATION := 40.0
## Lo que menos tiene que valer (con su gusto) para que cuente: un leño o una piedra no es un regalo.
const GIFT_MIN := 2.0
## Confianza por unidad de valor, y lo más que sube un regalo.
const GIFT_RATE := 0.35
const GIFT_MAX := 8.0
## La que hace falta para que alguien del poblado se vaya con el jugador (SettlementCompanions): la de
## amigos.
const RECRUIT_TRUST := 60.0

## Horas de juego desde que empezó a contar.
var clock := 0.0
## Poblado -> confianza.
var _trust := {}
## Vecino (SettlementPopulation: "id") -> hora de la última charla que contó.
var _talks := {}
## Poblado -> valor regalado hace poco.
var _gifts := {}


## Pasan [hours] horas de juego.
func advance(hours: float) -> void:
	if hours <= 0.0:
		return
	clock += hours
	var keep := pow(0.5, hours / GIFT_HALF_LIFE)
	for v: int in _gifts.keys():
		_gifts[v] *= keep
		if _gifts[v] < 0.05:
			_gifts.erase(v)


func trust(v: int) -> float:
	return float(_trust.get(v, 0.0))


## El nivel (índice en TIERS) de [v].
func tier(v: int) -> int:
	return tier_of(trust(v))


static func tier_of(value: float) -> int:
	var out := 0
	for i in TIERS.size():
		if value >= float(TIERS[i][0]):
			out = i
	return out


static func tier_name(index: int) -> String:
	return String(TIERS[clampi(index, 0, TIERS.size() - 1)][1])


## Suma [amount] (o resta) a la confianza de [v]: lo que ha cambiado de verdad.
func add(v: int, amount: float) -> float:
	var before := trust(v)
	_trust[v] = clampf(before + amount, 0.0, MAX_TRUST)
	return float(_trust[v]) - before


## Si ya ha hablado alguna vez con [who] (su "id").
func has_met(who: String) -> bool:
	return _talks.has(who)


## Habla con [who], del poblado [v]: lo que sube la confianza.
func talk(v: int, who: String) -> float:
	var first := not _talks.has(who)
	if not first and clock - float(_talks[who]) < TALK_COOLDOWN:
		return 0.0
	_talks[who] = clock
	if trust(v) >= TALK_CAP:
		return 0.0
	return add(v, minf(TALK_GAIN, TALK_CAP - trust(v)))


## Lo que subiría la confianza de [v] un regalo que vale [value] (ItemValue) con el gusto [taste]
## (VillagerTalk.taste: 0 no lo quiere, 1 normal, más si le gusta).
func gift_gain(v: int, value: float, taste: float) -> float:
	var worth := value * taste
	if worth < GIFT_MIN:
		return 0.0
	var tired := 1.0 / (1.0 + float(_gifts.get(v, 0.0)) / GIFT_SATURATION)
	return minf(worth * GIFT_RATE * tired, GIFT_MAX)


## Le regala a [v] algo que vale [value] con el gusto [taste]: lo que ha subido.
func gift(v: int, value: float, taste: float) -> float:
	var gain := gift_gain(v, value, taste)
	if gain > 0.0:
		_gifts[v] = float(_gifts.get(v, 0.0)) + value * taste
	return add(v, gain)


func save_data() -> Dictionary:
	var trust_out := {}
	for v: int in _trust:
		trust_out[str(v)] = _trust[v]
	var gifts_out := {}
	for v: int in _gifts:
		gifts_out[str(v)] = _gifts[v]
	return {"clock": clock, "trust": trust_out, "talks": _talks.duplicate(), "gifts": gifts_out}


func restore(data: Dictionary) -> void:
	clock = float(data.get("clock", 0.0))
	_trust.clear()
	_talks.clear()
	_gifts.clear()
	var trust_in: Dictionary = data.get("trust", {})
	for key in trust_in:
		_trust[int(key)] = float(trust_in[key])
	var talks_in: Dictionary = data.get("talks", {})
	for key in talks_in:
		_talks[str(key)] = float(talks_in[key])
	var gifts_in: Dictionary = data.get("gifts", {})
	for key in gifts_in:
		_gifts[int(key)] = float(gifts_in[key])
