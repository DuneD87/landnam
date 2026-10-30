extends Node
class_name HealthComponent

## Emitido cuando la entidad recibe daño. [source] puede ser null.
signal damaged(amount: float, source: Node)
## Emitido cuando la entidad se cura.
signal healed(amount: float)
## Emitido una sola vez cuando la salud llega a 0.
signal died()
## Emitido en cualquier cambio de salud (útil para actualizar UI).
signal health_changed(current: float, maximum: float)
## Emitido al encajar un golpe de combate (hoja, zarpa, flecha), con el daño ya descontado.
## Va antes que damaged, para que quien reacciona (tambaleo, sangre) tenga el punto y la
## dirección del golpe.
signal hit_received(info: DamageInfo, applied: float)

## Segundos que se le cuenta una muerte a quien la hirió por última vez.
const KILL_CREDIT_TIME := 90.0

@export var max_health: float = 100.0
## Si true, la entidad no puede recibir daño (útil para depuración o cutscenes).
@export var invincible: bool = false
## XP que da matarla (Progression.kill_xp). Negativa: la que sale de su vida y su armadura natural.
@export var xp_reward: float = -1.0

@export_group("Fall Damage")
## Si false, esta entidad ignora el daño por caída (útil para NPCs voladores, etc.).
@export var fall_damage_enabled: bool = true
## Velocidad mínima de impacto (m/s) para empezar a recibir daño por caída.
@export var fall_damage_min_speed: float = 12.0
## Daño por cada m/s por encima del umbral mínimo.
@export var fall_damage_multiplier: float = 5.0

@export_group("Armadura natural")
## Lo que protege la piel, el pelo y la grasa de cada tipo de golpe (Armor.mitigate): un mamut o un
## rinoceronte paran mucho tajo; un lobo, casi nada.
@export var armor_slash: float = 0.0
@export var armor_blunt: float = 0.0
@export var armor_pierce: float = 0.0

## Protección extra según dónde caiga el golpe: (info) -> Vector3 (x tajo, y contundente, z
## perforante). La pone quien lleva armadura por partes (el jugador: lo que tiene puesto donde le dan).
var armor_at: Callable
## Escudo o arma con la que se para (Guard). null = no se defiende: le llega todo.
var guard: Guard

var health: float
var is_dead: bool = false
## Quién la hirió por última vez: si muere en KILL_CREDIT_TIME (desangrada, de una caída), la ha
## matado él (Progression.reward_kill).
var last_attacker: Node
var _last_attack_msec := 0


func _ready() -> void:
	health = max_health


## Aplica [amount] de daño. [source] es opcional (quién causó el daño).
func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or invincible or amount <= 0.0:
		return
	# Lo que se hace a sí misma (NPCController.die) no cuenta como atacante.
	if source != null and source != get_parent():
		last_attacker = source
		_last_attack_msec = Time.get_ticks_msec()
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	damaged.emit(amount, source)
	if health <= 0.0:
		is_dead = true
		_credit_kill()
		died.emit()


## Pierde [amount] de vida sin que sea un golpe (desangrarse): avisa del cambio y de la muerte,
## pero no con damaged, así que quien la lleva no reacciona como a un golpe (respingo, quejido).
func drain(amount: float) -> void:
	if is_dead or invincible or amount <= 0.0:
		return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_dead = true
		_credit_kill()
		died.emit()


## Aplica un golpe de combate: guardia, parte golpeada y armadura (Armor). Devuelve el daño
## descontado.
func receive_hit(info: DamageInfo) -> float:
	if is_dead or invincible:
		return 0.0
	if guard != null and guard.intercept(info) == Guard.Result.PARRIED:
		# Parado en seco: no llega nada y el que lo dio queda vendido.
		if info.source != null and is_instance_valid(info.source) and info.source.has_method(&"on_parried"):
			info.source.on_parried(info)
		return 0.0
	var amount := Armor.mitigate(info.amount * info.part_multiplier,
		Armor.against(armor_for(info), info.kind), info.penetration)
	info.mitigated = amount
	if amount <= 0.0:
		return 0.0
	var applied := minf(amount, health)
	hit_received.emit(info, applied)
	take_damage(amount, info.source)
	return applied


## La protección contra [info] donde cae: la natural más la de armor_at.
func armor_for(info: DamageInfo) -> Vector3:
	var values := Vector3(armor_slash, armor_blunt, armor_pierce)
	if armor_at.is_valid():
		values += armor_at.call(info)
	return values


## Vuelve a la vida con la salud llena (reaparición tras morir).
func revive() -> void:
	is_dead = false
	last_attacker = null
	health = max_health
	health_changed.emit(health, max_health)


## Recupera [amount] de salud, sin superar max_health.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = min(max_health, health + amount)
	health_changed.emit(health, max_health)
	healed.emit(amount)


## Aplica daño por caída según la velocidad de impacto (m/s). Devuelve el daño (0 si no hubo).
func take_fall_damage(impact_speed: float) -> float:
	if not fall_damage_enabled or is_dead or invincible:
		return 0.0
	if impact_speed <= fall_damage_min_speed:
		return 0.0
	var excess := impact_speed - fall_damage_min_speed
	var damage := excess * fall_damage_multiplier
	take_damage(damage)
	return damage


## La muerte se le cuenta a quien la hirió por última vez, si fue hace poco.
func _credit_kill() -> void:
	if last_attacker == null or not is_instance_valid(last_attacker) \
			or Time.get_ticks_msec() - _last_attack_msec > KILL_CREDIT_TIME * 1000.0:
		return
	Progression.reward_kill(last_attacker, self)


func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return health / max_health
