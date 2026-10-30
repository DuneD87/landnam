class_name ProgressionBalance
extends Resource

## Los números de la progresión del personaje (Progression): la curva de niveles, lo que da cada
## acción y lo que rinde cada punto de atributo. Los de la partida están en
## data/progression/balance.tres; ver docs/progression.md.

@export_group("Niveles")
## XP para pasar del nivel n al siguiente: xp_base · n^xp_exponent.
@export var xp_base := 80.0
@export var xp_exponent := 1.5
## Puntos de un atributo que rinden enteros; cada uno de los que pasan rinde soft_cap_rate.
@export var soft_cap := 15
@export var soft_cap_rate := 0.5

@export_group("Experiencia")
## XP por acción, o por unidad de lo que da (una piedra, un material de construcción, un
## ingrediente). Las claves son los motivos con que se llama a Progression.reward.
@export var xp: Dictionary[StringName, float] = {
	&"fell_tree": 15.0,
	&"quarry": 2.0,
	&"dig": 1.0,
	&"craft": 4.0,
	&"craft_input": 1.5,
	&"butcher": 10.0,
	&"fish": 12.0,
	&"build": 1.0,
	&"parry": 3.0,
}
## La XP de un motivo que se puede ganar seguida antes de que rinda la mitad (luego un tercio, un
## cuarto...). Se va olvidando con una vida media de repeat_half_life (s). Sin entrada, no se limita.
@export var repeat_cap: Dictionary[StringName, float] = {
	&"fell_tree": 120.0,
	&"quarry": 60.0,
	&"dig": 20.0,
	&"craft": 80.0,
	&"build": 80.0,
	&"parry": 15.0,
}
@export var repeat_half_life := 300.0
## Lo que se multiplica la XP de una receta la primera vez que se fabrica.
@export var craft_first_mult := 3.0
## Matar: XP por punto de vida y de armadura natural de la presa, lo que se multiplica si es una
## fiera que caza (la que come carne), y lo que da un animal pequeño sin vida propia (pájaros,
## conejos). HealthComponent.xp_reward lo fija por especie.
@export var kill_per_health := 0.25
@export var kill_per_armor := 1.0
@export var kill_predator_mult := 1.6
@export var kill_small := 3.0

@export_group("Atributos")
## Vitalidad: vida máxima.
@export var health_per_point := 5.0
## Aguante: aguante máximo y recuperación (fracción de la base).
@export var stamina_per_point := 4.0
@export var stamina_regen_per_point := 0.02
## Fuerza: daño cuerpo a cuerpo y lanzado, desgaste de guardia y potencia al talar y picar.
@export var strength_per_point := 0.03
## Destreza: daño con arco y tirachinas, rapidez al tensar y menos gasto de aguante con la cuerda tensa.
@export var dexterity_damage_per_point := 0.03
@export var dexterity_draw_per_point := 0.02
@export var dexterity_hold_per_point := 0.03
## Dureza: armadura natural contra cada tipo de golpe, guardia (lo que aguanta sin tambalearse) y
## menos sangrado (fracción, hasta toughness_bleed_floor).
@export var toughness_armor_per_point := 0.5
@export var toughness_poise_per_point := 1.0
@export var toughness_bleed_per_point := 0.02
@export var toughness_bleed_floor := 0.5
## Temple: menos hambre y sed (fracción, hasta fortitude_upkeep_floor) y más aguante del frío y del
## calor: lo que se ensancha por cada lado la franja en que se está a gusto (°C).
@export var fortitude_upkeep_per_point := 0.02
@export var fortitude_upkeep_floor := 0.5
@export var fortitude_comfort_per_point := 0.3


## XP para pasar del nivel [level] al siguiente.
func xp_to_next(level: int) -> float:
	return roundf(xp_base * pow(float(maxi(level, 1)), xp_exponent))


## Lo que rinden [points] puntos de un atributo, con los de pasado soft_cap a soft_cap_rate.
func effective(points: int) -> float:
	return float(mini(points, soft_cap)) + float(maxi(points - soft_cap, 0)) * soft_cap_rate
