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

@export var max_health: float = 100.0
## Si true, la entidad no puede recibir daño (útil para depuración o cutscenes).
@export var invincible: bool = false

@export_group("Fall Damage")
## Si false, esta entidad ignora el daño por caída (útil para NPCs voladores, etc.).
@export var fall_damage_enabled: bool = true
## Velocidad mínima de impacto (m/s) para empezar a recibir daño por caída.
@export var fall_damage_min_speed: float = 12.0
## Daño por cada m/s por encima del umbral mínimo.
@export var fall_damage_multiplier: float = 5.0

## Reducción porcentual del daño de combate (armadura), de 0 a 80.
var defense: float = 0.0

var health: float
var is_dead: bool = false


func _ready() -> void:
	health = max_health


## Aplica [amount] de daño. [source] es opcional (quién causó el daño).
func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or invincible or amount <= 0.0:
		return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	damaged.emit(amount, source)
	if health <= 0.0:
		is_dead = true
		died.emit()


## Aplica un golpe de combate: parte golpeada y armadura primero. Devuelve el daño descontado.
func receive_hit(info: DamageInfo) -> float:
	if is_dead or invincible:
		return 0.0
	var reduction := clampf(defense, 0.0, 80.0) / 100.0
	var amount := info.amount * info.part_multiplier * (1.0 - reduction)
	if amount <= 0.0:
		return 0.0
	var applied := minf(amount, health)
	hit_received.emit(info, applied)
	take_damage(amount, info.source)
	return applied


## Vuelve a la vida con la salud llena (reaparición tras morir).
func revive() -> void:
	is_dead = false
	health = max_health
	health_changed.emit(health, max_health)


## Recupera [amount] de salud, sin superar max_health.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = min(max_health, health + amount)
	health_changed.emit(health, max_health)
	healed.emit(amount)


## Aplica daño por caída según la velocidad de impacto (m/s).
func take_fall_damage(impact_speed: float) -> void:
	if not fall_damage_enabled:
		return
	if impact_speed <= fall_damage_min_speed:
		return
	var excess := impact_speed - fall_damage_min_speed
	var damage := excess * fall_damage_multiplier
	take_damage(damage)


func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return health / max_health


func is_alive() -> bool:
	return not is_dead
