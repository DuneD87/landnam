class_name CreatureHit
extends Resource

## Una ventana de golpe de un CreatureAttack: entre [member from] y [member to] (segundos de la
## animación a ritmo 1) los huesos de [member bones] hieren barriendo una esfera de
## [member radius] contra los Hurtbox. Cada hueso sigue su propio rastro; todos los de la ventana
## comparten a quién han golpeado.

@export var from: float = 0.0
@export var to: float = 0.0
## Huesos que hieren (zarpas, cabeza, cuernos), por su nombre en el esqueleto de la criatura.
@export var bones: Array[StringName] = []
## Radio de la esfera barrida alrededor de cada hueso, en metros.
@export var radius: float = 0.4
@export var damage: float = 20.0
## Desgaste de la guardia del que lo recibe.
@export var poise: float = 20.0
## Metros que desplaza al que lo recibe si le hace tambalearse.
@export var knockback: float = 1.0
@export var kind: ItemData.DamageKind = ItemData.DamageKind.SLASH
## Lo que suena al abrirse la ventana. Vacío = el swing_sound del perfil.
@export var sound: StringName = &""
