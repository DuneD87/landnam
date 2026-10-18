class_name EdibleTrait
extends ItemTrait

## Se come (o se bebe): lo que da a cada necesidad (SurvivalNeeds, de 0 a 1), la vida que cura y,
## si es carne cruda o algo en mal estado, la probabilidad de intoxicarse.

@export_range(-1.0, 1.0) var hunger := 0.0
@export_range(-1.0, 1.0) var thirst := 0.0
@export_range(-1.0, 1.0) var sanity := 0.0
@export var health := 0.0
@export_range(0.0, 1.0) var intoxication_chance := 0.0
## Gravedad de la intoxicación (0-1): cuánto dura (ver data/status/intoxication.tres).
@export_range(0.0, 1.0) var intoxication_severity := 0.5


func describe() -> Array:
	var rows := []
	if hunger != 0.0:
		rows.append(["NEED_HUNGER", percent(hunger)])
	if thirst != 0.0:
		rows.append(["NEED_THIRST", percent(thirst)])
	if sanity != 0.0:
		rows.append(["NEED_SANITY", percent(sanity)])
	if health != 0.0:
		rows.append(["STAT_HEALTH", "%+d" % roundi(health)])
	if intoxication_chance > 0.0:
		rows.append(["TRAIT_INTOXICATES", "%d %%" % roundi(intoxication_chance * 100.0)])
	return rows
