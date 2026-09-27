class_name StaminaComponent
extends Node

## Aguante: lo gastan los golpes, las esquivas, tensar y correr. Se recupera solo tras una pausa
## sin gastar, y si se agota del todo hay que esperar a que se rehaga un poco antes de volver a
## gastar (evita encadenar acciones con la barra en cero).

signal changed(current: float, maximum: float)

@export var max_stamina: float = 100.0
## Puntos por segundo al recuperarse.
@export var regen_rate: float = 38.0
## Segundos sin gastar antes de empezar a recuperar.
@export var regen_delay: float = 0.8
## Tras agotarse, cuánto hay que recuperar antes de poder gastar otra vez.
@export var exhausted_threshold: float = 22.0

var stamina: float
var exhausted: bool = false
var _since_spent: float = 999.0


func _ready() -> void:
	stamina = max_stamina


func _physics_process(delta: float) -> void:
	_since_spent += delta
	if _since_spent < regen_delay or stamina >= max_stamina:
		return
	stamina = minf(max_stamina, stamina + regen_rate * delta)
	if exhausted and stamina >= exhausted_threshold:
		exhausted = false
	changed.emit(stamina, max_stamina)


## True si hay aguante para empezar algo que cuesta [amount]. Con algo de barra se permite
## empezar aunque no alcance del todo (como en los souls): lo que falta deja la barra a cero.
func can_spend(amount: float) -> bool:
	return not exhausted and stamina > 0.0 and amount >= 0.0


## Gasta [amount]; devuelve false si no había aguante para empezar.
func spend(amount: float) -> bool:
	if not can_spend(amount):
		return false
	stamina = maxf(0.0, stamina - amount)
	if stamina <= 0.0:
		exhausted = true
	_since_spent = 0.0
	changed.emit(stamina, max_stamina)
	return true


## Gasto continuo (correr, mantener la tensión): [rate] por segundo.
func drain(rate: float, delta: float) -> bool:
	if exhausted or stamina <= 0.0:
		return false
	stamina = maxf(0.0, stamina - rate * delta)
	if stamina <= 0.0:
		exhausted = true
	_since_spent = minf(_since_spent, regen_delay * 0.5)
	changed.emit(stamina, max_stamina)
	return not exhausted


func refill() -> void:
	stamina = max_stamina
	exhausted = false
	_since_spent = 999.0
	changed.emit(stamina, max_stamina)


func get_ratio() -> float:
	return stamina / max_stamina if max_stamina > 0.0 else 0.0
