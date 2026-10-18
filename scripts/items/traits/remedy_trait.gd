class_name RemedyTrait
extends ItemTrait

## Cura (un emplasto, un bebedizo, una tablilla): vida al momento, vida poco a poco (el estado
## «Recuperándose», data/status/recovering.tres), corta el sangrado de las heridas, cierra las partes
## heridas (BodyDamage.treat) y quita los estados que respondan a [cures] (StatusEffects.cure).
## Se usa como la comida: clic con él en la barra o doble clic en el inventario.

const RECOVERING := &"recovering"
## Cómo se llama en la ficha lo que cura cada etiqueta de [cures].
const CURE_NAMES := {
	&"poison": "Intoxicación",
	&"fracture": "Fracturas",
}

## Vida que da al momento.
@export var health := 0.0
## Segundos de «Recuperándose» que da (su vida por segundo la pone el estado).
@export var recovery_time := 0.0
## Parte del sangrado de las heridas que corta (0-1). En un muñón, algo más de la mitad.
@export_range(0.0, 1.0) var stanch := 0.0
## Parte de la vida de cada parte del cuerpo herida que le devuelve (0-1). Lo perdido no vuelve.
@export_range(0.0, 1.0) var mend := 0.0
## Estados que quita (StatusEffectData.cure_tags): poison (intoxicación), fracture (pierna rota)...
@export var cures: Array[StringName] = []
## Lo que se dice al usarlo: «Te pones un emplasto de milenrama».
@export var use_text := ""


func describe() -> Array:
	var rows := []
	if health != 0.0:
		rows.append(["Vida", "%+d" % roundi(health)])
	if recovery_time > 0.0:
		var data := StatusEffectData.find(RECOVERING)
		var per_second := data.health_per_second if data != null else 1.0
		rows.append(["Recuperación", "+%d en %d s" % [roundi(per_second * recovery_time), roundi(recovery_time)]])
	if stanch > 0.0:
		rows.append(["Corta el sangrado", "%d %%" % roundi(stanch * 100.0)])
	if mend > 0.0:
		rows.append(["Cierra heridas", "%d %%" % roundi(mend * 100.0)])
	for tag in cures:
		rows.append(["Cura", CURE_NAMES.get(tag, String(tag))])
	return rows
