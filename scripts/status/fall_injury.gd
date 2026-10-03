class_name FallInjury
extends RefCounted

## Caer desde alto rompe las piernas: casi siempre que la caída hace daño, siempre desde SURE_SPEED
## (unos 13 m) y las dos desde BOTH_SPEED (unos 20 m). Cuanto más fuerte el golpe, más grave la
## fractura y más tarda en soldar (el rango de duración de broken_leg.tres). Una pierna perdida ya
## no se puede romper.

const EFFECT := &"broken_leg"
const LEGS: Array[StringName] = [&"left_leg", &"right_leg"]
## Probabilidad de romperse una pierna en una caída que hace daño, por debajo de SURE_SPEED.
const CHANCE := 0.85
## Velocidades de impacto (m/s) desde las que se rompe seguro, y las dos.
const SURE_SPEED := 16.0
const BOTH_SPEED := 20.0


## Tras un aterrizaje que ha hecho [damage] de daño: tira los dados y rompe lo que toque. [body]
## puede ser null (una entidad sin miembros que perder). Devuelve las piernas rotas.
static func roll(status: StatusEffects, body: BodyDamage, impact_speed: float, damage: float) -> Array[StringName]:
	var broken: Array[StringName] = []
	if status == null or status.health == null or status.health.is_dead or damage <= 0.0:
		return broken
	if impact_speed < SURE_SPEED and randf() >= CHANCE:
		return broken
	for leg in LEGS:
		if body == null or not body.is_severed(leg):
			broken.append(leg)
	if broken.size() > 1 and impact_speed < BOTH_SPEED:
		var leg: StringName = broken.pick_random()
		broken.clear()
		broken.append(leg)
	var min_speed := status.health.fall_damage_min_speed
	var severity := clampf(inverse_lerp(min_speed, BOTH_SPEED, impact_speed), 0.0, 1.0)
	for leg in broken:
		status.apply(EFFECT, leg, severity)
	return broken
