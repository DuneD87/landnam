class_name CreatureVariant
extends Resource

## Una variante dentro de una especie (un joven, un adulto, el macho grande de la manada): cuánto
## mide y lo que cambia con ello. Cada criatura (AmbientAnimal.roll_variant) sortea una al aparecer,
## por su peso, y dentro de ella el tamaño entre size.x y size.y, así que no hay dos iguales. Las de
## las criaturas con escena propia (NPCController) van en su escena; las de la fauna ambiental, en
## su perfil (AmbientFaunaProfile) o en su especie (FishSpecies). Varias especies pueden compartir
## las mismas (las de los peces, las de las aves). Los multiplicadores son sobre lo de la especie
## para el tamaño medio de la variante; dentro de ella la vida, el daño y la guardia van además con
## el cuadrado del tamaño (la fuerza va con la sección del músculo), así que el más grande de los
## adultos pega algo más que el más chico.

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
## Vida (HealthComponent.max_health, si tiene; la fauna sin él muere de un golpe).
@export var health: float = 1.0
## Daño y desgaste de guardia que hacen sus golpes (y los mordiscos del tiburón al casco).
@export var damage: float = 1.0
## Guardia: lo que aguanta antes de tambalearse (max_poise del perfil).
@export var poise: float = 1.0
## Velocidades: al deambular, persiguiendo, esprintando y rondando (la fauna, al nadar o andar).
@export var speed: float = 1.0
## Ataques del perfil (por id) que esta variante no hace.
@export var excluded_attacks: Array[StringName] = []

@export_group("Sound")
## Tono de su voz (amenaza, gruñidos, quejidos): más grave el grande.
@export var voice_pitch: float = 1.0


## Tamaño medio de la variante: con él valen los multiplicadores tal cual.
func mid_size() -> float:
	return (size.x + size.y) * 0.5


## Lo que crece la fuerza (vida, daño, guardia) de uno de [body_size] respecto al medio de la
## variante: con la sección del músculo, el cuadrado.
func strength(body_size: float) -> float:
	var ratio := body_size / mid_size() if mid_size() > 0.0 else 1.0
	return ratio * ratio


## Un tamaño al azar dentro de la variante.
func roll_size(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(size.x, size.y)


## Una de [options] por su peso, entre las que [allowed] (si se da) deja. null si no queda ninguna.
static func pick(options: Array[CreatureVariant], rng: RandomNumberGenerator,
		allowed: Callable = Callable()) -> CreatureVariant:
	var valid: Array[CreatureVariant] = []
	var total := 0.0
	for v in options:
		if v == null or v.weight <= 0.0 or (allowed.is_valid() and not allowed.call(v)):
			continue
		valid.append(v)
		total += v.weight
	if valid.is_empty():
		return null
	var roll := rng.randf() * total
	for v in valid:
		roll -= v.weight
		if roll <= 0.0:
			return v
	return valid.back()
