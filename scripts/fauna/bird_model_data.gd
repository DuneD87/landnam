class_name BirdModelData
extends FaunaModelData

## Un ave con esqueleto de un pack para AmbientBird (SkinnedBirdModel): además de lo del modelo,
## qué clip va posada, al despegar, volando y al llegar. idle_clip es el de posada mientras no se
## sortea otro de perched_clips.

## Posada y quieta: uno al azar cada vez que se posa (el pato flotando, a ratos zambulléndose).
@export var perched_clips: Array[StringName] = []
## Posada y moviéndose (el pato nadando con la deriva). Vacío = el de quieta.
@export var swim_clip: StringName = &""
## Al tomar tierra (o agua): una vez, antes del de posada. Vacío = directo.
@export var touchdown_clip: StringName = &""
## Al despegar: una vez, antes del de volar. Vacío = directo.
@export var takeoff_clip: StringName = &""
## Volando: aleteando, a flap_rate; y planeando, si tiene clip y el ave planea.
@export var fly_clip: StringName = &""
@export var flap_rate: float = 1.0
@export var glide_clip: StringName = &""
## Planea con las alas abiertas entre aleteos (AmbientBird lo pregunta con soars()).
@export var soars: bool = false
## Llegando a posarse: frena en el aire (se queda en el último fotograma hasta tocar).
@export var brake_clip: StringName = &""
## Posada en el agua flota hundida esto (m): sus clips de nadar llevan el cuerpo a la altura de pie.
@export var float_depth: float = 0.0
