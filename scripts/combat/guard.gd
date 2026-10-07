class_name Guard
extends RefCounted

## Una guardia: escudo o arma con la que se paran golpes de frente. Cuelga del HealthComponent de
## quien se defiende (el jugador; mañana, un humano) y la consulta antes de descontar cada golpe:
##   - parada: un golpe cuerpo a cuerpo que llega en los primeros parry_window segundos de
##     alzarla no hace nada, y el que lo da queda vendido (on_parried);
##   - bloqueo: el resto, de frente y dentro de guard_arc, se queda en (1 - guard_reduction) del
##     daño y no tambalea, pero cuesta aguante según su fuerza (su desgaste de guardia) y la
##     estabilidad de lo que para;
##   - rotura: si no queda aguante para pararlo, la guardia cede: pasa la parte del golpe que no se
##     ha podido parar y tambalea como un golpe gordo.
## Qué para y cuánto lo dice el ItemData (grupo Guard) del escudo o del arma.

enum Result {NONE, BLOCKED, PARRIED, BROKEN}

## Aguante por cada punto de desgaste de guardia que no absorbe la estabilidad.
const STAMINA_PER_POISE := 0.9
## Aguante por cada punto de daño parado (un golpe flojo pero que hiere también cansa).
const STAMINA_PER_DAMAGE := 0.25
## Desgaste con el que tambalea al que se le rompe la guardia.
const BREAK_POISE := 60.0
## Tras una parada fallida (se alzó y no llegó nada), segundos en los que alzarla otra vez no abre
## ventana de parada: machacar el botón no sirve.
const PARRY_LOCKOUT := 0.6

signal blocked(info: DamageInfo, cost: float)
signal parried(info: DamageInfo)
signal broken(info: DamageInfo)

## Lo que para (escudo o arma). null = no hay guardia.
var item: ItemData
## Quien se defiende: mira por +Z.
var body: Node3D
var stamina: StaminaComponent
var raised: bool = false
## Segundos desde que se alzó.
var raised_time: float = 0.0

var _parry_open: float = 0.0
var _lockout: float = 0.0


## Alza la guardia. Abre la ventana de parada si el objeto la tiene y no se ha machacado el botón.
func raise() -> void:
	if raised:
		return
	raised = true
	raised_time = 0.0
	_parry_open = item.parry_window if item != null and _lockout <= 0.0 else 0.0


## La baja. Si la ventana de parada se abrió y no paró nada, la siguiente tarda en volver.
func lower() -> void:
	if not raised:
		return
	raised = false
	if _parry_open > 0.0:
		_lockout = PARRY_LOCKOUT


func update(delta: float) -> void:
	_lockout = maxf(0.0, _lockout - delta)
	if raised:
		raised_time += delta


## Si ahora mismo un golpe se pararía en seco.
func in_parry_window() -> bool:
	return raised and _parry_open > 0.0 and raised_time <= _parry_open


## Decide qué hace la guardia con [info] y lo rebaja en consecuencia (info.guarded lo cuenta).
func intercept(info: DamageInfo) -> Result:
	if not raised or item == null or item.guard_reduction <= 0.0 or body == null:
		return Result.NONE
	if info.ranged and not item.guard_projectiles:
		return Result.NONE
	if not _in_front(info):
		return Result.NONE
	if not info.ranged and info.parryable and in_parry_window():
		# Parada: la ventana se gasta (no para dos golpes con un solo gesto) y no hay castigo.
		_parry_open = 0.0
		info.guarded = Result.PARRIED
		info.amount = 0.0
		info.poise = 0.0
		info.knockback = 0.0
		parried.emit(info)
		return Result.PARRIED
	var force := info.poise * (1.0 - item.guard_stability / 100.0) * STAMINA_PER_POISE
	var cost := force + info.amount * item.guard_reduction * STAMINA_PER_DAMAGE
	# Agotado (vació la barra y aún no se ha recuperado), los brazos no aguantan nada.
	var left := INF
	if stamina != null:
		left = 0.0 if stamina.exhausted else stamina.stamina
	if cost <= left:
		if stamina != null:
			stamina.spend(cost)
		info.guarded = Result.BLOCKED
		info.amount *= 1.0 - item.guard_reduction
		info.poise = 0.0
		info.knockback *= 0.35
		blocked.emit(info, cost)
		return Result.BLOCKED
	# Sin aguante: lo que no se ha podido pagar del golpe pasa, y la guardia cede.
	var held := clampf(left / maxf(cost, 0.001), 0.0, 1.0)
	if stamina != null and left > 0.0:
		stamina.spend(left)
	info.guarded = Result.BROKEN
	info.amount *= 1.0 - item.guard_reduction * held
	info.poise = maxf(info.poise, BREAK_POISE)
	broken.emit(info)
	return Result.BROKEN


## El golpe viene de delante: su dirección (hacia donde empuja) apunta contra el cuerpo.
func _in_front(info: DamageInfo) -> bool:
	var from := -info.direction
	if from.length_squared() < 1e-6 and info.source != null and is_instance_valid(info.source):
		from = info.source.global_position - body.global_position
	var up := body.global_basis.y.normalized()
	from -= up * from.dot(up)
	var forward := body.global_basis.z
	forward -= up * forward.dot(up)
	if from.length_squared() < 1e-6 or forward.length_squared() < 1e-6:
		return true
	return rad_to_deg(forward.normalized().angle_to(from.normalized())) <= item.guard_arc
