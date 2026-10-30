class_name Progression
extends Node

## Nivel y atributos del personaje. Lo que hace en el mundo le da experiencia (reward, reward_kill):
## matar, talar, picar piedra, cavar, fabricar, despellejar, pescar, construir y parar golpes. Al
## llenar la del nivel sube y gana un punto, que se reparte en la ficha de atributos (C) entre seis
## atributos: vitalidad, aguante, fuerza, destreza, dureza y temple. _apply los pasa a la vida, el
## aguante, la armadura natural, el sangrado y las necesidades; PlayerCombat pide los multiplicadores
## del daño, el tensado y la guardia.
##
## Lo que se gana seguido por lo mismo rinde cada vez menos (repeat_cap), y se va olvidando: talar
## un bosque entero da, pero no tanto como talarlo a ratos.
##
## Al morir se pierde la XP del nivel en curso (forfeit), que se queda en la bolsa con lo que se
## llevaba (DeathLoot) y vuelve al recuperarla (recover). Si muere otra vez antes, se pierde con la
## bolsa. Nunca se pierden niveles ni puntos.
##
## Los números están en ProgressionBalance (data/progression/balance.tres); ver docs/progression.md.

signal xp_gained(amount: float, reason: StringName)
signal leveled_up(level: int)
## Cualquier cambio: XP, nivel, puntos o atributos.
signal changed()

const BALANCE_PATH := "res://data/progression/balance.tres"
const ATTRIBUTES: Array[StringName] = [&"vitality", &"endurance", &"strength", &"dexterity",
		&"toughness", &"fortitude"]
const NAMES := {
	&"vitality": "ATTR_VITALITY", &"endurance": "ATTR_ENDURANCE", &"strength": "ATTR_STRENGTH",
	&"dexterity": "ATTR_DEXTERITY", &"toughness": "ATTR_TOUGHNESS", &"fortitude": "ATTR_FORTITUDE",
}
## Lo que da cada atributo, para la ficha.
const TIPS := {
	&"vitality": "ATTR_VITALITY_TIP", &"endurance": "ATTR_ENDURANCE_TIP", &"strength": "ATTR_STRENGTH_TIP",
	&"dexterity": "ATTR_DEXTERITY_TIP", &"toughness": "ATTR_TOUGHNESS_TIP", &"fortitude": "ATTR_FORTITUDE_TIP",
}

var balance: ProgressionBalance
var level := 1
## XP del nivel en curso, hacia el siguiente.
var xp := 0.0
## Puntos sin repartir.
var points := 0
## Atributo → puntos puestos.
var attributes: Dictionary[StringName, int] = {}
## Lo que ya se ha fabricado alguna vez (el id del resultado): la primera da más.
var crafted: Dictionary[StringName, bool] = {}

var _player: PlayerController
## Motivo → [XP ganada seguida, cuándo (ms)]: se va olvidando con repeat_half_life.
var _recent := {}
## Lo que tiene el jugador sin atributos (su escena): vida, aguante, recuperación y armadura natural.
var _base := {}


func _init() -> void:
	balance = load(BALANCE_PATH) as ProgressionBalance


## Toma lo que tiene [player] sin atributos y le aplica los que haya. Después de PlayerCombat (el
## aguante y las partes del cuerpo) y de las necesidades.
func setup(player: PlayerController) -> void:
	_player = player
	var health := player.health_component
	var stamina: StaminaComponent = player.combat.stamina if player.combat != null else null
	_base = {
		"health": health.max_health if health != null else 100.0,
		"armor": Vector3(health.armor_slash, health.armor_blunt, health.armor_pierce) if health != null else Vector3.ZERO,
		"stamina": stamina.max_stamina if stamina != null else 100.0,
		"regen": stamina.regen_rate if stamina != null else 38.0,
	}
	_apply()


# --- Experiencia ----------------------------------------------------------------------------------

## La progresión de [actor] (el jugador), o null si no lleva.
static func of(actor: Node) -> Progression:
	if actor == null or not is_instance_valid(actor):
		return null
	return actor.get(&"progression") as Progression


## Da a [actor], si lleva progresión, la XP de [reason] por [units] (ProgressionBalance.xp).
static func reward(actor: Node, reason: StringName, units := 1.0) -> void:
	var progression := of(actor)
	if progression != null:
		progression.gain(progression.balance.xp.get(reason, 0.0) * units, reason)


## [killer] ha matado a [victim] (su HealthComponent, o el animal pequeño que no lleva): le da su XP
## si lleva progresión.
static func reward_kill(killer: Node, victim: Node) -> void:
	var progression := of(killer)
	if progression != null:
		progression.gain(progression.kill_xp(victim), &"kill")


## Da [amount] de XP por [reason]. Si el motivo tiene límite (repeat_cap), rinde menos cuanto más se
## ha ganado seguido por él. Devuelve la XP ganada.
func gain(amount: float, reason: StringName) -> float:
	if amount <= 0.0:
		return 0.0
	var cap: float = balance.repeat_cap.get(reason, 0.0)
	var earned := amount
	if cap > 0.0:
		var recent := _recent_of(reason)
		earned = amount / (1.0 + recent / cap)
		_recent[reason] = [recent + amount, Time.get_ticks_msec()]
	_add(earned)
	xp_gained.emit(earned, reason)
	return earned


## Ha fabricado [times] veces [recipe]: XP por vez y por ingrediente, y la primera vez, más. Lo que
## se cuece en la hoguera (la tisana de milenrama) no da, como no da asar ni fundir.
func reward_craft(recipe: RecipeData, times: int) -> float:
	if recipe.station == Campfire.ITEM_ID:
		return 0.0
	var inputs := 0
	for id in recipe.inputs:
		inputs += recipe.inputs[id]
	var each: float = balance.xp.get(&"craft", 0.0) + balance.xp.get(&"craft_input", 0.0) * inputs
	var earned := gain(each * times, &"craft")
	if not crafted.has(recipe.result):
		crafted[recipe.result] = true
		# Aprender algo nuevo no se cansa: va aparte del límite de lo repetido.
		earned += gain(each * (balance.craft_first_mult - 1.0), &"craft_first")
	return earned


## La XP de matar a [victim]: la de su especie (HealthComponent.xp_reward) o la que sale de su vida
## y su armadura natural, más si es una fiera que caza. Un animal pequeño sin vida propia, poca.
func kill_xp(victim: Node) -> float:
	var health := victim as HealthComponent
	if health == null:
		return balance.kill_small
	if health.xp_reward >= 0.0:
		return health.xp_reward
	var amount := health.max_health * balance.kill_per_health \
		+ (health.armor_slash + health.armor_blunt + health.armor_pierce) * balance.kill_per_armor
	var npc := health.get_parent() as NPCController
	if npc != null and npc.feed_profile() != null:
		amount *= balance.kill_predator_mult
	return amount


## XP que falta para el siguiente nivel, en total.
func xp_to_next() -> float:
	return balance.xp_to_next(level)


## Lo que lleva del nivel en curso, de 0 a 1.
func xp_ratio() -> float:
	return clampf(xp / maxf(xp_to_next(), 1.0), 0.0, 1.0)


## Al morir: se pierde la XP del nivel en curso. Devuelve cuánta, para dejarla en la bolsa.
func forfeit() -> float:
	var lost := xp
	xp = 0.0
	changed.emit()
	return lost


## Recupera [amount] de XP perdida al morir (sin límite de lo repetido).
func recover(amount: float) -> void:
	if amount <= 0.0:
		return
	_add(amount)
	xp_gained.emit(amount, &"recovered")


func _add(amount: float) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		points += 1
		leveled_up.emit(level)
	changed.emit()


func _recent_of(reason: StringName) -> float:
	if not _recent.has(reason):
		return 0.0
	var entry: Array = _recent[reason]
	var age := float(Time.get_ticks_msec() - int(entry[1])) / 1000.0
	return float(entry[0]) * pow(0.5, age / maxf(balance.repeat_half_life, 1.0))


# --- Atributos ------------------------------------------------------------------------------------

## Pone un punto en [attribute]. false si no quedan puntos o no es un atributo.
func spend(attribute: StringName) -> bool:
	if points <= 0 or not ATTRIBUTES.has(attribute):
		return false
	points -= 1
	attributes[attribute] = attributes.get(attribute, 0) + 1
	_apply()
	changed.emit()
	return true


## Puntos puestos en [attribute].
func get_attribute(attribute: StringName) -> int:
	return attributes.get(attribute, 0)


## Fija [attribute] sin gastar puntos (consola).
func set_attribute(attribute: StringName, value: int) -> void:
	attributes[attribute] = maxi(value, 0)
	_apply()
	changed.emit()


## Fija el nivel (consola): empieza vacío y con los puntos que le tocan menos los ya puestos.
func set_level(value: int) -> void:
	level = maxi(value, 1)
	xp = 0.0
	points = maxi(level - 1 - spent(), 0)
	changed.emit()


## Devuelve todos los puntos puestos para repartirlos otra vez.
func respec() -> void:
	points += spent()
	attributes.clear()
	_apply()
	changed.emit()


## Puntos puestos en total.
func spent() -> int:
	var total := 0
	for attribute in attributes:
		total += attributes[attribute]
	return total


## Lo que rinden los puntos de [attribute] (los de pasado soft_cap, menos).
func effective(attribute: StringName) -> float:
	return balance.effective(get_attribute(attribute))


## Fuerza: lo que se multiplica el daño cuerpo a cuerpo y lanzado, el desgaste de guardia y la
## potencia al talar y picar.
func strength_mult() -> float:
	return 1.0 + effective(&"strength") * balance.strength_per_point


## Destreza: lo que se multiplica el daño con arco y tirachinas.
func ranged_mult() -> float:
	return 1.0 + effective(&"dexterity") * balance.dexterity_damage_per_point


## Destreza: lo que se acelera el tensado.
func draw_speed_mult() -> float:
	return 1.0 + effective(&"dexterity") * balance.dexterity_draw_per_point


## Destreza: lo que gasta sostener la cuerda tensa.
func hold_drain_mult() -> float:
	return maxf(1.0 - effective(&"dexterity") * balance.dexterity_hold_per_point, 0.3)


## Dureza: lo que se suma a la guardia del jugador (lo que aguanta sin tambalearse).
func poise_bonus() -> float:
	return effective(&"toughness") * balance.toughness_poise_per_point


## Pasa los atributos a lo que tiene el jugador. Lo que sube la vida o el aguante máximos también
## se suma a lo que tiene en ese momento; lo que baja (respec) deja lo que había si cabe.
func _apply() -> void:
	if _player == null:
		return
	var health := _player.health_component
	var combat := _player.combat
	if health != null:
		var previous := health.max_health
		health.max_health = float(_base.health) + effective(&"vitality") * balance.health_per_point
		if not health.is_dead:
			health.health = clampf(health.health + maxf(health.max_health - previous, 0.0), 1.0, health.max_health)
		health.health_changed.emit(health.health, health.max_health)
		var armor: Vector3 = _base.armor + Vector3.ONE * effective(&"toughness") * balance.toughness_armor_per_point
		health.armor_slash = armor.x
		health.armor_blunt = armor.y
		health.armor_pierce = armor.z
		if combat != null and combat.body_damage != null:
			combat.body_damage.rescale(previous)
	if combat != null and combat.body_damage != null:
		combat.body_damage.bleed_scale = maxf(1.0 - effective(&"toughness") * balance.toughness_bleed_per_point,
			balance.toughness_bleed_floor)
	var stamina: StaminaComponent = combat.stamina if combat != null else null
	if stamina != null:
		var before := stamina.max_stamina
		stamina.max_stamina = float(_base.stamina) + effective(&"endurance") * balance.stamina_per_point
		stamina.regen_rate = float(_base.regen) * (1.0 + effective(&"endurance") * balance.stamina_regen_per_point)
		stamina.stamina = clampf(stamina.stamina + maxf(stamina.max_stamina - before, 0.0), 0.0, stamina.max_stamina)
		stamina.changed.emit(stamina.stamina, stamina.max_stamina)
	var needs := _player.needs
	if needs != null:
		needs.upkeep_scale = maxf(1.0 - effective(&"fortitude") * balance.fortitude_upkeep_per_point,
			balance.fortitude_upkeep_floor)
		needs.hardiness = effective(&"fortitude") * balance.fortitude_comfort_per_point


# --- Partida --------------------------------------------------------------------------------------

func save_data() -> Dictionary:
	var saved := {}
	for attribute in attributes:
		saved[String(attribute)] = attributes[attribute]
	var made: Array[String] = []
	for id in crafted:
		made.append(String(id))
	return {"level": level, "xp": xp, "points": points, "attributes": saved, "crafted": made}


func load_data(data: Dictionary) -> void:
	level = maxi(int(data.get("level", 1)), 1)
	xp = maxf(float(data.get("xp", 0.0)), 0.0)
	points = maxi(int(data.get("points", 0)), 0)
	attributes.clear()
	var saved: Variant = data.get("attributes", {})
	if saved is Dictionary:
		for key in saved:
			if ATTRIBUTES.has(StringName(key)):
				attributes[StringName(key)] = maxi(int(saved[key]), 0)
	crafted.clear()
	var made: Variant = data.get("crafted", [])
	if made is Array:
		for id in made:
			crafted[StringName(str(id))] = true
	_recent.clear()
	_apply()
	changed.emit()
