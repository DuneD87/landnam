class_name StatusEffect
extends RefCounted

## Un estado en curso: su definición (StatusEffectData), en qué parte del cuerpo, lo que le queda y
## lo grave que es. Lo lleva StatusEffects, que le cuenta el tiempo.

const SIDE_LABEL := {&"left": "izq.", &"right": "der."}

var data: StatusEffectData
## Parte del cuerpo (BodyDamage.ZONES), o &"" si es de todo el cuerpo.
var zone: StringName = &""
## Segundos de juego que le quedan y los que lleva.
var remaining: float = 0.0
var elapsed: float = 0.0
## De 0 a 1: lo grave que es (una caída más alta rompe peor y tarda más en soldar).
var severity: float = 0.5


func _init(data_: StatusEffectData, zone_: StringName = &"", severity_: float = 0.5,
		time: float = -1.0) -> void:
	data = data_
	zone = zone_
	severity = clampf(severity_, 0.0, 1.0)
	remaining = time if time >= 0.0 else data.duration_for(severity)


## Para el HUD: "Pierna rota (izq.)".
func label() -> String:
	if zone == &"":
		return data.display_name
	var side := StringName(String(zone).get_slice("_", 0))
	return "%s (%s)" % [data.display_name, SIDE_LABEL.get(side, String(zone))]


func to_dict() -> Dictionary:
	return {"id": String(data.id), "zone": String(zone), "remaining": remaining, "elapsed": elapsed,
		"severity": severity}


## De to_dict(); null si el estado ya no existe o se le había acabado el tiempo.
static func from_dict(entry: Dictionary) -> StatusEffect:
	var found := StatusEffectData.find(StringName(entry.get("id", "")))
	var time := float(entry.get("remaining", 0.0))
	if found == null or time <= 0.0:
		return null
	var effect := StatusEffect.new(found, StringName(entry.get("zone", "")),
		float(entry.get("severity", 0.5)), time)
	effect.elapsed = float(entry.get("elapsed", 0.0))
	return effect
