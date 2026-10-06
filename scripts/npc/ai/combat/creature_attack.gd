class_name CreatureAttack
extends Resource

## Un ataque de una criatura, como datos: qué animación suena, cuándo hiere y cómo mueve el
## cuerpo. Lo ejecuta CreatureAttackRunner y lo elige CreatureCombatState entre los de su
## CreatureCombatProfile. Las especies con el mismo esqueleto comparten estos recursos.
##
## Tiempos en segundos de la animación a ritmo 1, medidos sobre el clip (por la velocidad de las
## zarpas).

## Si no se dice otra cosa, se compromete este rato (s de animación) antes del primer golpe.
const COMMIT_LEAD := 0.05

## Nombre para los cooldowns, el registro y la consola.
@export var id: StringName = &""
## Animación del AnimationPlayer de la criatura.
@export var anim: StringName = &""
## Distancias (desde el centro del animal, en metros) a las que lo elige.
@export var distance := Vector2(0.0, 3.0)
## Segundos antes de poder repetirlo.
@export var cooldown: float = 1.5
## Peso al elegir entre los ataques posibles.
@export var weight: float = 1.0
## Solo lo elige si el objetivo queda a menos de este ángulo (grados) de hacia donde mira.
@export_range(0.0, 180.0) var max_angle: float = 180.0
## Multiplicadores del peso según lo que esté haciendo el objetivo (ver CombatRead), p. ej.
## {&"recovering": 3.0} para castigar al que acaba de fallar un golpe.
@export var situations: Dictionary[StringName, float] = {}

@export_group("Timing")
## Segundos que se planta encarado antes de arrancar la animación: el aviso.
@export var tell: float = 0.3
## Ritmo de la animación hasta poco antes del primer golpe (el aviso lento), y después.
@export var windup_speed: float = 0.6
@export var speed: float = 1.0
## Dónde acaba el ataque; después viene la recuperación.
@export var end: float = 1.5

@export_group("Tracking")
## Giro máximo (grados/s) hacia el objetivo durante el aviso y la preparación, y una vez
## comprometido. Un giro comprometido bajo es lo que deja esquivar apartándose a tiempo.
@export var track_windup: float = 360.0
@export var track_active: float = 0.0
## Desde cuándo se compromete. <0 = justo antes del primer golpe.
@export var commit: float = -1.0
## Anticipación (s): apunta a donde estará el objetivo si sigue como va, no a donde está.
@export var lead: float = 0.0

@export_group("Movement")
## Avance del cuerpo: (desde, hasta, metros).
@export var lunge := Vector3.ZERO
## El avance se frena para quedarse a esta distancia del objetivo. 0 = avanza siempre entero.
@export var lunge_min_distance: float = 1.6

@export_group("Armor")
## Guardia extra en un tramo (desde, hasta, cantidad): los golpes que encaja ahí la gastan antes
## que la suya, así que no se le interrumpe el ataque con cualquier cosa.
@export var armor := Vector3.ZERO

@export_group("Combo")
## Ataques del mismo perfil (por id) que pueden seguir a este sin recuperación, si llegan.
@export var follow_ups: Array[StringName] = []
@export_range(0.0, 1.0) var follow_up_chance: float = 0.0
## Desde cuándo puede arrancar el siguiente. <0 = al acabar.
@export var follow_up_at: float = -1.0

@export_group("Hits")
@export var hits: Array[CreatureHit] = []

@export_group("Sound")
## Lo que suena al empezar el aviso. Vacío = el attack_sound del perfil.
@export var sound: StringName = &""


## Cuándo se abre la primera ventana de golpe (o el final, si no hiere).
func first_hit() -> float:
	return hits[0].from if not hits.is_empty() else end


## Desde cuándo ya no gira más que track_active.
func commit_time() -> float:
	return commit if commit >= 0.0 else first_hit() - COMMIT_LEAD


## Desde cuándo puede encadenar otro ataque.
func chain_time() -> float:
	return follow_up_at if follow_up_at >= 0.0 else end
