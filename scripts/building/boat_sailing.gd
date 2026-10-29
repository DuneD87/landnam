class_name BoatSailing
extends RefCounted

## La física no depende de quién gobierne. El despliegue vive en cada prop para que viaje
## con su bloque al guardar, convertir la grid o separarse una pieza del casco.
const AIR_DENSITY := 1.225
## Potencia de juego para dar arrancada a los cascos grandes incluso con brisa suave.
const SAIL_POWER := 90.0
## Evita que una vela grande lance un casco pequeño al recibir una racha (m/s²).
const MAX_SAIL_ACCELERATION := 4.0
const HOIST_TIME := 2.0
const NO_GO_ANGLE := PI / 4.0
## Remo: marcha lenta que no depende del viento, para salir de puerto y costear. Es una marcha
## más del aparejo (ciar, parado, remar y los tres tercios de vela), no gasta aguante.
const ROW_SPEED := 3.5
const BACK_SPEED := 1.6
## Aceleración del remo (m/s²), igual para cualquier casco: la tripulación crece con el barco.
const ROW_ACCELERATION := 1.1
## Margen de velocidad (m/s) en el que el empuje se suaviza antes de llegar al tope.
const ROW_EASE := 0.5

var sails: Array[Dictionary] = []
var level := 0
var deployment := 0.0
var area := 0.0
var wind := Vector3.ZERO
var apparent_wind := Vector3.ZERO
var efficiency := 0.0
var force := Vector3.ZERO
var wind_angle := 0.0
## -1 ciar, 0 remos dentro, 1 remar. Solo empuja con alguien a bordo; con vela izada vale 0.
var row := 0
var rowing := false


func rebuild(grids: Array) -> void:
	sails.clear()
	level = 0
	area = 0.0
	for grid: GridBase in grids:
		for info: Dictionary in grid.get_all_props().values():
			var item := ItemCatalog.get_item(info["item_id"])
			var sail_data := item.get_trait(SailTrait) as SailTrait if item else null
			if sail_data == null:
				continue
			var state: Dictionary = info.get("state", {})
			state["level"] = clampi(int(state.get("level", 0)), 0, 3)
			state["deployment"] = clampf(float(state.get("deployment", 0.0)), 0.0, 1.0)
			state["design"] = SailDesign.from_state(state)
			info["state"] = state
			var visual: HideSailVisual
			var anchor = info["node"]
			if is_instance_valid(anchor):
				for child: Node in anchor.get_children():
					if child is HideSailVisual:
						visual = child
						break
			var sail_area := SailDesign.area(state["design"])
			sails.append({"info": info, "trait": sail_data, "visual": visual, "area": sail_area})
			area += sail_area
			level = maxi(level, state["level"])
	if sails.is_empty():
		deployment = 0.0
		force = Vector3.ZERO


func set_level(value: int) -> void:
	level = clampi(value, 0, 3) if not sails.is_empty() else 0
	for sail: Dictionary in sails:
		sail["info"]["state"]["level"] = level


## Marcha única de ↑/↓: -1 ciar, 0 parado, 1 remar y 2..4 los tercios de vela.
func gear() -> int:
	return level + 1 if level > 0 else row


func shift(step: int) -> void:
	set_gear(gear() + step)


func set_gear(value: int) -> void:
	value = clampi(value, -1, 1 if sails.is_empty() else 4)
	row = value if value <= 1 else 0
	set_level(maxi(value - 1, 0))


## Curva de juego simétrica en ambas amuras: zona muerta de 45°, buen través y empopada.
static func polar(apparent: Vector3, forward: Vector3) -> float:
	if apparent.length_squared() < 0.0001 or forward.is_zero_approx():
		return 0.0
	var angle := acos(clampf(-apparent.normalized().dot(forward.normalized()), -1.0, 1.0))
	var entry := smoothstep(NO_GO_ANGLE, NO_GO_ANGLE + PI / 12.0, angle)
	return entry * lerpf(0.85, 1.0, sin(angle))


static func drive_force(apparent: Vector3, forward: Vector3, effective_area: float) -> Vector3:
	var power := 0.5 * AIR_DENSITY * SAIL_POWER * maxf(effective_area, 0.0) * apparent.length_squared() * polar(apparent, forward)
	var side := apparent - forward * apparent.dot(forward)
	return forward * power + side.normalized() * power * 0.12


## Aceleración del remo sobre la proa (m/s², con signo). Solo empuja hacia la velocidad de la
## marcha: ciar frena un barco lanzado, pero remar no frena al que ya va más rápido.
static func rowing_acceleration(direction: int, forward_speed: float) -> float:
	if direction == 0:
		return 0.0
	var target := ROW_SPEED if direction > 0 else -BACK_SPEED
	var push := clampf((target - forward_speed) / ROW_EASE, -1.0, 1.0)
	return ROW_ACCELERATION * push if push * direction > 0.0 else 0.0


func step(delta: float, air: Vector3, velocity: Vector3, forward: Vector3, up: Vector3) -> Vector3:
	wind = air.slide(up)
	apparent_wind = (wind - velocity).slide(up)
	efficiency = polar(apparent_wind, forward)
	wind_angle = forward.signed_angle_to(wind.normalized(), up) if not wind.is_zero_approx() else 0.0
	var effective_area := 0.0
	var deployed_area := 0.0
	for sail: Dictionary in sails:
		var info: Dictionary = sail["info"]
		var state: Dictionary = info["state"]
		var sail_data: SailTrait = sail["trait"]
		state["deployment"] = move_toward(float(state["deployment"]), float(state["level"]) / 3.0, delta / HOIST_TIME)
		var amount: float = state["deployment"]
		effective_area += float(sail["area"]) * sail_data.efficiency * amount
		deployed_area += float(sail["area"]) * amount
		var visual = sail["visual"]
		if is_instance_valid(visual) and not visual.is_queued_for_deletion():
			visual.set_sailing_state(amount, apparent_wind, efficiency)
	deployment = deployed_area / area if area > 0.0 else 0.0
	force = drive_force(apparent_wind, forward, effective_area)
	return force
