class_name VillagerTalk extends RefCounted

## Lo que dice un aldeano (Villager) al jugador y lo que le parece un regalo. Las frases van en
## localization/translations.csv por montones (VTALK_<MONTÓN>_<n>) y se elige el montón según quién es,
## qué hace, la hora, el tiempo, la confianza del poblado, lo que lleva puesto el jugador y el poblado
## de al lado. Ver docs/villagers.md.

## Cuántas frases tiene cada montón (VTALK_<montón>_1..n).
const POOLS := {
	&"MEET": 4, &"WARY": 5, &"CAUTIOUS": 5, &"FRIENDLY": 5, &"FRIENDS": 5, &"KIN": 4,
	&"WOODPILE": 3, &"GARDEN": 3, &"BENCH": 3,
	&"MORNING": 3, &"LUNCH": 2, &"EVENING": 3,
	&"SNOW": 2, &"STORM": 2, &"FOG": 2, &"WIND": 2,
	&"DANGER": 3, &"NEIGHBOUR": 2, &"PELT": 2, &"BRONZE": 2,
	&"GIFT_LOVE": 3, &"GIFT_LIKE": 3, &"GIFT_TIRED": 2, &"GIFT_MEH": 3,
	&"RECRUIT_YES": 3, &"FOLLOW_OK": 3, &"WAIT_OK": 3, &"HOME_OK": 3, &"ROAD": 5,
	&"TRADE_OPEN": 3, &"TRADE_DONE": 3, &"TRADE_SHORT": 3,
	&"QUEST_FETCH": 3, &"QUEST_HUNT": 3, &"QUEST_YES": 3, &"QUEST_WAITING": 3, &"QUEST_THANKS": 3,
	&"QUEST_DROP": 2,
}
## El montón de cada nivel de confianza (SettlementRelations.TIERS).
const TIER_POOLS: Array[StringName] = [&"WARY", &"CAUTIOUS", &"FRIENDLY", &"FRIENDS", &"KIN"]
## Las cabezas de animal que se reconocen en el jugador, y el nombre del animal.
const PELTS := {&"fur_headdress": "VANIMAL_WOLF", &"fur_hood": "VANIMAL_BEAR", &"boar_headdress": "VANIMAL_BOAR",
	&"deer_headdress": "VANIMAL_DEER"}
## El gusto por encima del cual un regalo le encanta.
const LOVE := 1.5


## Una frase de [villager] para el jugador [player] (PlayerController), traducida. [last]: la clave de la
## anterior, para no repetirla.
static func line(villager: Villager, player: Node, rng: RandomNumberGenerator, last := "") -> Dictionary:
	var village := villager.village
	var who := villager.resident
	var v := village.index
	if not village.relations.has_met(String(who.id)):
		return _pick(&"MEET", rng, last, [who.name, village.name])
	if village.danger:
		return _pick(&"DANGER", rng, last)
	var tier := village.relations.tier(v)
	var pools: Array = [[TIER_POOLS[tier], 3.0]]
	var job: Dictionary = who.get("job", {})
	if not job.is_empty():
		pools.append([StringName(String(job.kind).to_upper()), 2.0 if villager.act == Villager.Act.WORK else 1.0])
	var h := village.hour()
	if h >= Villager.WAKE_HOUR and h < 10.0:
		pools.append([&"MORNING", 1.5])
	elif h >= Villager.LUNCH.x and h < Villager.LUNCH.y:
		pools.append([&"LUNCH", 1.5])
	elif h >= 18.0:
		pools.append([&"EVENING", 1.5])
	var weather := _weather(villager)
	if POOLS.has(weather):
		pools.append([weather, 1.5])
	# Con quien no se fía no se habla de caminos.
	if tier >= 1 and not village.neighbour.is_empty():
		pools.append([&"NEIGHBOUR", 1.0])
	var pelt := _worn_pelt(player)
	if pelt != "":
		pools.append([&"PELT", 1.5])
	if _has_bronze(player):
		pools.append([&"BRONZE", 1.0])
	var pool := _weighted(pools, rng)
	match pool:
		&"NEIGHBOUR":
			var n: Dictionary = village.neighbour
			return _pick(pool, rng, last, [tr_key(_direction(village, n.toward)), tr_key(_distance(n.distance)), n.name])
		&"PELT":
			return _pick(pool, rng, last, [tr_key(pelt)])
	return _pick(pool, rng, last)


## Lo que dice un compañero (Companion) por el camino: del viaje, del tiempo o de lo que lleva el jugador.
static func companion_line(companion: Companion, player: Node, rng: RandomNumberGenerator, last := "") -> Dictionary:
	var pools: Array = [[&"ROAD", 3.0]]
	var weather := _weather(companion)
	if POOLS.has(weather):
		pools.append([weather, 1.5])
	var pelt := _worn_pelt(player)
	if pelt != "":
		pools.append([&"PELT", 1.5])
	if _has_bronze(player):
		pools.append([&"BRONZE", 1.0])
	var pool := _weighted(pools, rng)
	if pool == &"PELT":
		return _pick(pool, rng, last, [tr_key(pelt)])
	return _pick(pool, rng, last)


## Una frase del montón [pool] (POOLS), sin argumentos: las respuestas a lo que se le pide.
static func pick(pool: StringName, rng: RandomNumberGenerator, last := "") -> Dictionary:
	return _pick(pool, rng, last)


## Lo que pide en [quest] (SettlementQuests): traer tantos de algo o acabar con una o unas fieras.
static func quest_line(quest: Dictionary, rng: RandomNumberGenerator, last := "") -> Dictionary:
	var count := int(quest.count)
	if quest.kind == "hunt":
		var key := _prey_key(quest.species)
		var prey := tr_key(key + "_ONE") if count == 1 else tr_key(key + "_MANY") % count
		return _pick(&"QUEST_HUNT", rng, last, [prey])
	var data := ItemCatalog.get_item(StringName(quest.item))
	var item := data.get_display_name().to_lower() if data != null else String(quest.item)
	return _pick(&"QUEST_FETCH", rng, last, [count, item])


## Cómo va [quest]: «Sílex: 1/3» (lo que lleva el jugador en [inventory], si se da) o «Lobos: 1/2».
static func quest_status(quest: Dictionary, inventory: Inventory = null) -> String:
	var count := int(quest.count)
	if quest.kind == "hunt":
		return tr_key("VQUEST_STATUS") % [tr_key(_prey_key(quest.species)), mini(int(quest.done), count), count]
	var data := ItemCatalog.get_item(StringName(quest.item))
	var have := mini(inventory.get_item_count(data), count) if inventory != null and data != null else 0
	return tr_key("VQUEST_STATUS") % [data.get_display_name() if data != null else String(quest.item), have, count]


## La clave del nombre de la fiera [species] (npc_type): VPREY_WOLF; con _ONE, «un lobo», y con _MANY,
## «%d lobos».
static func _prey_key(species: Variant) -> String:
	return "VPREY_" + String(species).to_upper()


## Lo que dice al recibir un regalo: [gain], lo que ha subido la confianza; [taste], su gusto (taste).
static func gift_line(gain: float, taste: float, worth: float, rng: RandomNumberGenerator, last := "") -> Dictionary:
	if worth < SettlementRelations.GIFT_MIN:
		return _pick(&"GIFT_MEH", rng, last)
	if gain < 0.5:
		return _pick(&"GIFT_TIRED", rng, last)
	return _pick(&"GIFT_LOVE" if taste >= LOVE else &"GIFT_LIKE", rng, last)


## Lo que le gusta a quien tiene el oficio [job] ("woodpile", "garden", "bench" o "") recibir [data]: 0 no
## le sirve, 1 normal, más si le viene bien.
static func taste(job: StringName, data: ItemData) -> float:
	if data == null:
		return 0.0
	var group := ItemTaxonomy.group_of(data)
	match data.category:
		ItemData.Category.CONSUMABLE:
			return 1.5 if group == &"cooked" else (1.3 if group == &"remedy" else 1.0)
		ItemData.Category.TOOL:
			var wanted := {&"woodpile": ItemData.ToolType.AXE, &"garden": ItemData.ToolType.HOE,
				&"bench": ItemData.ToolType.HAMMER}
			return 1.8 if wanted.get(job, -1) == data.tool_type else 1.0
		ItemData.Category.ARMOR:
			return 1.2
		ItemData.Category.WEAPON:
			return 1.0
		ItemData.Category.BLOCK:
			return 0.3
	match group:
		&"hunt":
			return 1.2
		&"metal":
			return 2.0 if job == &"bench" else 1.0
		&"wood":
			return 0.5 if job == &"woodpile" else 0.8
	return 1.0


## El oficio de [who] para enseñarlo: "Leñadora", "Vecino"... (clave de traducción).
static func job_title(who: Dictionary) -> String:
	var job: Dictionary = who.get("job", {})
	var kind := String(job.get("kind", "none")).to_upper()
	return "VILLAGER_JOB_%s_%s" % [kind, "F" if StringName(who.get("sex", &"male")) == &"female" else "M"]


## Lo que es para el jugador quien se ha ido con él: "Compañero", "Compañera" (clave de traducción).
static func companion_title(who: Dictionary) -> String:
	return "VILLAGER_COMPANION_%s" % ("F" if StringName(who.get("sex", &"male")) == &"female" else "M")


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)


static func _pick(pool: StringName, rng: RandomNumberGenerator, last: String, args := []) -> Dictionary:
	var count: int = POOLS[pool]
	var n := rng.randi_range(1, count)
	var key := "VTALK_%s_%d" % [pool, n]
	if key == last and count > 1:
		n = n % count + 1
		key = "VTALK_%s_%d" % [pool, n]
	var text := tr_key(key)
	if not args.is_empty():
		text = text % args
	return {"key": key, "text": text}


## Uno de [pools] ([montón, peso]) al azar por su peso.
static func _weighted(pools: Array, rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for p: Array in pools:
		total += float(p[1])
	var roll := rng.randf() * total
	for p: Array in pools:
		roll -= float(p[1])
		if roll <= 0.0:
			return p[0]
	return pools[0][0]


static func _weather(someone: Node) -> StringName:
	var weather := someone.get_tree().get_first_node_in_group("weather") as WeatherController
	return StringName(weather.get_current_weather_name().to_upper()) if weather != null else &""


## La cabeza de animal que lleva puesta el jugador (clave del nombre del animal), o "".
static func _worn_pelt(player: Node) -> String:
	var data := _equipped(player, ItemData.ArmorSlot.HEAD)
	return String(PELTS.get(data.id, "")) if data != null else ""


static func _has_bronze(player: Node) -> bool:
	for slot in [ItemData.ArmorSlot.RIGHT_HAND, ItemData.ArmorSlot.LEFT_HAND]:
		var data := _equipped(player, slot)
		if data != null and String(data.id).begins_with("bronze_"):
			return true
	return false


static func _equipped(player: Node, slot: ItemData.ArmorSlot) -> ItemData:
	var window = player.get("character_window") if player != null else null
	if window == null or not window.equipment_slots.has(slot):
		return null
	var eq: EquipmentSlot = window.equipment_slots[slot]
	return eq.equipped_item.data if eq.has_item() and eq.equipped_item != null else null


## Hacia dónde queda [toward] (tangente en la plaza de [village]), como lo diría: clave del rumbo.
static func _direction(village: SettlementVillage, toward: Vector3) -> String:
	var up := village.center.normalized()
	var north := (Vector3.UP - up * up.y).normalized()
	var heading := fposmod(rad_to_deg(atan2(toward.dot(north.cross(up)), toward.dot(north))), 360.0)
	const NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return "VDIR_" + NAMES[int(round(heading / 45.0)) % 8]


## Lo lejos que queda [distance] m, andando: clave.
static func _distance(distance: float) -> String:
	if distance < 1500.0:
		return "VDIST_NEAR"
	if distance < 3500.0:
		return "VDIST_HOUR"
	if distance < 7000.0:
		return "VDIST_HOURS"
	return "VDIST_FAR"
