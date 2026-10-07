class_name CreatureVariant
extends Resource

## Una variante dentro de una especie (un joven, un adulto, el macho grande de la manada): cuánto
## mide y lo que cambia con ello. NPCController sortea una al aparecer, por su peso, y dentro de
## ella el tamaño entre size.x y size.y, así que no hay dos iguales. Los multiplicadores son sobre
## lo de la especie (su escena y su CreatureCombatProfile) para el tamaño medio de la variante;
## dentro de ella la vida, el daño y la guardia van además con el cuadrado del tamaño (la fuerza va
## con la sección del músculo), así que el más grande de los adultos pega algo más que el más chico.

## Nombre en la consola (spawn lobo grande) y en la depuración.
@export var id: StringName = &""
## Peso al sortearla entre las de su especie.
@export var weight: float = 1.0
## Como mucho estas por grupo (manada) que salen juntos; 0 = sin tope.
@export var max_per_group: int = 0
## Escala del cuerpo respecto al modelo, al azar entre los dos. Con ella crecen la cápsula, la
## cabeza que se golpea, el alcance y el avance de los ataques y la zancada.
@export var size := Vector2(1.0, 1.0)

@export_group("Stats")
## Vida (HealthComponent.max_health).
@export var health: float = 1.0
## Daño y desgaste de guardia que hacen sus golpes.
@export var damage: float = 1.0
## Guardia: lo que aguanta antes de tambalearse (max_poise del perfil).
@export var poise: float = 1.0
## Velocidades: al deambular, persiguiendo, esprintando y rondando.
@export var speed: float = 1.0
## Ataques del perfil (por id) que esta variante no hace.
@export var excluded_attacks: Array[StringName] = []

@export_group("Sound")
## Tono de su voz (amenaza, gruñidos, quejidos): más grave el grande.
@export var voice_pitch: float = 1.0


## Tamaño medio de la variante: con él valen los multiplicadores tal cual.
func mid_size() -> float:
	return (size.x + size.y) * 0.5
