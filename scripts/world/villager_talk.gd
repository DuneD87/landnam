class_name VillagerTalk extends RefCounted

## Lo que dice un aldeano (Villager) al jugador y lo que le parece un regalo. Las frases van en
## localization/translations.csv por montones (VTALK_<MONTÓN>_<n>) y se elige el montón según quién es,
## qué hace, la hora, el tiempo, la confianza del poblado, lo que lleva puesto el jugador y el poblado
## de al lado. Ver docs/villagers.md.

## Cuántas frases tiene cada montón (VTALK_<montón>_1..n).
const POOLS := {
	&"MEET": 4, &"WARY": 5, &"CAUTIOUS": 5, &"FRIENDLY": 5, &"FRIENDS": 5, &"KIN": 4,
	&"WOODPILE": 3, &"GARDEN": 3, &"BENCH": 3,
	&"FORGE": 3, &"SHOP": 3, &"STALL_FOOD": 3, &"STALL_HIDES": 3, &"STALL_WARES": 3, &"GUARD": 3,
	&"MORNING": 3, &"LUNCH": 2, &"EVENING": 3,
	&"SNOW": 2, &"STORM": 2, &"FOG": 2, &"WIND": 2,
	&"DANGER": 3, &"NEIGHBOUR": 2, &"PELT": 2, &"BRONZE": 2,
	&"GIFT_LOVE": 3, &"GIFT_LIKE": 3, &"GIFT_TIRED": 2, &"GIFT_MEH": 3,
	&"RECRUIT_YES": 3, &"FOLLOW_OK": 3, &"WAIT_OK": 3, &"HOME_OK": 3, &"ROAD": 5,
	&"SETTLE_OK": 3, &"BASE": 5,
	&"TRADE_OPEN": 3, &"TRADE_DONE": 3, &"TRADE_SHORT": 3,
	&"QUEST_FETCH": 3, &"QUEST_HUNT": 3, &"QUEST_YES": 3, &"QUEST_WAITING": 3, &"QUEST_THANKS": 3,
	&"QUEST_DROP": 2,
	&"QUEST_RESCUE": 3, &"QUEST_ESCORT": 3, &"QUEST_ERRAND": 3, &"QUEST_BEAST": 3,
	&"QUEST_HAGGLE_YES": 3, &"QUEST_HAGGLE_NO": 3, &"QUEST_LATER": 3, &"QUEST_ERRAND_GOT": 3,
	&"WARD_FOUND": 3, &"WARD_FOLLOW": 3, &"WARD_WAIT": 2, &"WARD_HOME": 3, &"ESCORT_ARRIVED": 3,
	&"CALL": 4, &"QUEST_LATE": 2,
	&"STRUCK": 4, &"THIEF": 3, &"CLOSED": 4,
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
	var pools: Array = [[&"BASE" if companion.mode == Companion.Mode.SETTLE else &"ROAD", 3.0]]
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


## «¿Qué haces?» a un colono [c]: su oficio y dónde, y cómo va (descansa, no le queda nada, está parado
## por algo o lo que lleva sacado), en primera persona.
static func settler_doing(c: Companion) -> Dictionary:
	var w := c.work
	if not w.active():
		return {"key": "SETTLER_SAY_IDLE", "text": tr_key("SETTLER_SAY_IDLE")}
	var where := tr_key("SETTLER_SAY_IN_ZONE" if w.zone.is_finite() else "SETTLER_SAY_AROUND_BASE")
	var key := "SETTLER_SAY_" + String(SettlerWork.Job.keys()[w.job])
	if w.job == SettlerWork.Job.GUARD:
		key += "_NIGHT" if w.shift == 1 else "_DAY"
	var said := tr_key(key)
	var parts: Array[String] = [said % where if said.contains("%s") else said]
	var stuck := w.stuck()
	if not stuck.is_empty():
		parts.append(tr_key("SETTLER_SAY_STUCK"))
		parts.append(w.say_stuck(stuck))
	else:
		match w.status:
			SettlerWork.Status.OFF_HOURS:
				parts.append(tr_key("SETTLER_SAY_OFF_HOURS"))
			SettlerWork.Status.DONE:
				parts.append(tr_key("SETTLER_SAY_DONE"))
			_:
				if w.task == null and w.gathered > 0:
					parts.append(tr_key("SETTLER_SAY_GATHERED") % w.gathered)
	return {"key": key, "text": " ".join(parts)}


## «¿Qué te falta?» a un colono [c]: lo que le para el trabajo, el oficio si no tiene, la comida y el
## agua (las suyas y las de los comederos y bebederos de la base), dónde dormir y la vida; o que nada.
static func settler_needs(c: Companion) -> Dictionary:
	var parts: Array[String] = []
	var stuck := c.work.stuck()
	if not stuck.is_empty():
		parts.append(c.work.say_stuck(stuck))
	if not c.work.active():
		parts.append(tr_key("SETTLER_ME_NO_JOB"))
	if c.meals != null:
		parts.append(_supply_need(c.meals.hungry(), c.meals.feeder_food(), "FOOD"))
		parts.append(_supply_need(c.meals.thirsty(), c.meals.trough_water(), "WATER"))
	if c.base.is_finite() and not c.has_bed():
		parts.append(tr_key("SETTLER_ME_NO_BED"))
	if c.health != null and c.health.health < c.health.max_health * 0.5:
		parts.append(tr_key("SETTLER_ME_HURT"))
	parts = parts.filter(func(text: String) -> bool: return text != "")
	if parts.is_empty():
		return {"key": "SETTLER_ME_FINE", "text": tr_key("SETTLER_ME_FINE")}
	return {"key": "SETTLER_ME_NEEDS", "text": " ".join(parts)}


## Lo que dice de la comida o del agua ([what]: FOOD o WATER): [lacking], si pasa hambre o sed; [left],
## lo que queda en los comederos o bebederos de la base (-1: no hay ninguno). "" si va bien.
static func _supply_need(lacking: bool, left: int, what: String) -> String:
	var state := "NONE" if left < 0 else ("EMPTY" if left == 0 else "")
	if lacking:
		return tr_key("SETTLER_ME_%s_LACKING%s" % [what, "_" + state if state != "" else ""])
	return tr_key("SETTLER_ME_%s_%s" % [what, state]) if state != "" else ""


## Una frase del montón [pool] (POOLS), sin argumentos: las respuestas a lo que se le pide.
static func pick(pool: StringName, rng: RandomNumberGenerator, last := "") -> Dictionary:
	return _pick(pool, rng, last)


## Lo que pide en [quest] (SettlementQuests): traer tantos de algo, acabar con una o unas fieras, buscar al
## perdido, acompañarle, llevar un recado o matar a la fiera con nombre.
static func quest_line(quest: Dictionary, rng: RandomNumberGenerator, last := "", villages: Array = []) -> Dictionary:
	match String(quest.kind):
		"rescue":
			return _pick(&"QUEST_RESCUE", rng, last, [quest.lost_name, tr_key(_toward_key(quest, "hint", villages))])
		"escort":
			return _pick(&"QUEST_ESCORT", rng, last, [quest.dest_name, tr_key(_distance(_dest_distance(quest, villages)))])
		"errand":
			return _pick(&"QUEST_ERRAND", rng, last, [quest.to_name, quest.dest_name])
		"beast":
			return _pick(&"QUEST_BEAST", rng, last, [tr_key(String(quest.beast_name)),
				tr_key(_prey_key(quest.species) + "_ONE"), tr_key(_toward_key(quest, "hint", villages))])
	var count := int(quest.count)
	if quest.kind == "hunt":
		var key := _prey_key(quest.species)
		var prey := tr_key(key + "_ONE") if count == 1 else tr_key(key + "_MANY") % count
		return _pick(&"QUEST_HUNT", rng, last, [prey])
	var data := ItemCatalog.get_item(StringName(quest.item))
	var item := data.get_display_name().to_lower() if data != null else String(quest.item)
	return _pick(&"QUEST_FETCH", rng, last, [count, item])


## Cómo va [quest]: «Sílex: 1/3» (lo que lleva el jugador en [inventory], si se da), «Lobos: 1/2», «Buscar
## a Thora», «Acompañar a Ulf hasta Vatnsgarður»...
static func quest_status(quest: Dictionary, inventory: Inventory = null) -> String:
	var stage := String(quest.get("stage", ""))
	match String(quest.kind):
		"rescue":
			var key := {"search": "VQUEST_RESCUE_SEARCH", "found": "VQUEST_RESCUE_FOUND", "home": "VQUEST_RESCUE_HOME"}
			return tr_key(key.get(stage, "VQUEST_RESCUE_SEARCH")) % quest.lost_name
		"escort":
			return tr_key("VQUEST_ESCORT_DONE" if stage == "arrived" else "VQUEST_ESCORT") % [quest.name, quest.dest_name]
		"errand":
			return tr_key("VQUEST_ERRAND_BACK" if stage == "back" else "VQUEST_ERRAND") % [quest.to_name, quest.dest_name]
		"beast":
			return tr_key("VQUEST_BEAST_SLAIN" if stage == "slain" else "VQUEST_BEAST") % [tr_key(String(quest.beast_name)),
				tr_key(_prey_key(quest.species) + "_ONE")]
	var count := int(quest.count)
	if quest.kind == "hunt":
		return tr_key("VQUEST_STATUS") % [tr_key(_prey_key(quest.species)), mini(int(quest.done), count), count]
	var data := ItemCatalog.get_item(StringName(quest.item))
	var have := mini(inventory.get_item_count(data), count) if inventory != null and data != null else 0
	return tr_key("VQUEST_STATUS") % [data.get_display_name() if data != null else String(quest.item), have, count]


## Lo que cuenta al preguntarle los detalles de [quest] (traducido): dónde, lo lejos, el plazo y lo que hay
## que hacer para cobrarlo.
static func quest_details(quest: Dictionary, villages: Array = []) -> String:
	var hours := float(SettlementQuests.HOURS.get(String(quest.kind), 48.0))
	var due := tr_key("VQUEST_DUE") % _hours_text(hours)
	match String(quest.kind):
		"rescue":
			return tr_key("VQUEST_DETAILS_RESCUE") % [tr_key(_toward_key(quest, "hint", villages)),
				roundi(_spot_distance(quest, "hint", villages) / 50.0) * 50, due]
		"beast":
			return tr_key("VQUEST_DETAILS_BEAST") % [tr_key(_toward_key(quest, "hint", villages)),
				roundi(_spot_distance(quest, "hint", villages) / 50.0) * 50, due]
		"escort":
			return tr_key("VQUEST_DETAILS_ESCORT") % [quest.dest_name, tr_key(_distance(_dest_distance(quest, villages))),
				due]
		"errand":
			return tr_key("VQUEST_DETAILS_ERRAND") % [quest.to_name, quest.dest_name,
				tr_key(_distance(_dest_distance(quest, villages))), due]
		"hunt":
			return tr_key("VQUEST_DETAILS_HUNT") % [roundi(SettlementQuests.HUNT_REACH), due]
	return tr_key("VQUEST_DETAILS_FETCH") % due


## [hours] de juego dichas: «medio día», «un día», «tres días».
static func _hours_text(hours: float) -> String:
	if hours < 20.0:
		return tr_key("VQUEST_HOURS") % roundi(hours)
	var days := roundi(hours / 24.0)
	return tr_key("VQUEST_ONE_DAY") if days <= 1 else tr_key("VQUEST_DAYS") % days


## Lo que le queda a [quest] dicho corto («quedan 5 h», «quedan 2 días»), o "" si ya no corre.
static func time_left(hours: float) -> String:
	if not is_finite(hours):
		return ""
	if hours <= 0.0:
		return tr_key("VQUEST_LATE")
	if hours < 24.0:
		return tr_key("VQUEST_LEFT_HOURS") % maxi(1, ceili(hours))
	return tr_key("VQUEST_LEFT_DAYS") % roundi(hours / 24.0)


## Hacia dónde queda, desde la plaza del poblado de [quest], su punto [key] ("hint", "spot"): VDIR_*.
static func _toward_key(quest: Dictionary, key: String, villages: Array) -> String:
	var v := int(quest.village)
	var at := SettlementQuests.vec(quest.get(key, quest.get("spot", [])))
	if v < 0 or v >= villages.size() or not at.is_finite():
		return "VDIR_N"
	var plan: Dictionary = villages[v]
	var center := (plan.center as Vector3) * float(plan.ground)
	return heading_key(center.normalized(), (at - center).slide(center.normalized()))


static func _spot_distance(quest: Dictionary, key: String, villages: Array) -> float:
	var v := int(quest.village)
	var at := SettlementQuests.vec(quest.get(key, quest.get("spot", [])))
	if v < 0 or v >= villages.size() or not at.is_finite():
		return 0.0
	var plan: Dictionary = villages[v]
	return ((plan.center as Vector3) * float(plan.ground)).distance_to(at)


static func _dest_distance(quest: Dictionary, villages: Array) -> float:
	var v := int(quest.village)
	var d := int(quest.get("dest", -1))
	if v < 0 or d < 0 or v >= villages.size() or d >= villages.size():
		return 0.0
	var a: Dictionary = villages[v]
	var b: Dictionary = villages[d]
	return ((a.center as Vector3) * float(a.ground)).distance_to((b.center as Vector3) * float(b.ground))


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


## Lo que le gusta a quien tiene el oficio [job] ("woodpile", "garden", "bench", "forge"... o "") recibir [data]: 0 no
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
				&"bench": ItemData.ToolType.HAMMER, &"forge": ItemData.ToolType.HAMMER}
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
			return 2.0 if job in [&"bench", &"forge"] else 1.0
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


## Colono o colona: el que vive en la base del jugador.
static func settler_title(who: Dictionary) -> String:
	return "VILLAGER_SETTLER_%s" % ("F" if StringName(who.get("sex", &"male")) == &"female" else "M")


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
	for slot in [ItemData.ArmorSlot.PRIMARY, ItemData.ArmorSlot.RIGHT_HAND, ItemData.ArmorSlot.OFFHAND]:
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
	return heading_key(village.center.normalized(), toward)


## El rumbo (VDIR_*) de [toward] en el suelo de arriba [up] (marco del terreno: el norte es su +Y).
static func heading_key(up: Vector3, toward: Vector3) -> String:
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
