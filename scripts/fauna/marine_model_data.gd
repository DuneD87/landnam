class_name MarineModelData
extends FaunaModelData

## Un animal marino grande con esqueleto de un pack para AmbientMarineAnimal (SkinnedMarineModel):
## además de lo del modelo, qué clip nada de crucero, girando y a la carga, y cuál muerde. Siempre
## nada, así que idle_clip y los de marcha no se usan; la colisión sale de la caja del modelo.

## Nadando de crucero, y girando a la izquierda y a la derecha (cuando gira más deprisa que
## turn_rate, en rad/s). Vacíos = siempre el de crucero.
@export var swim_clip: StringName = &"Swim"
@export var turn_left_clip: StringName = &""
@export var turn_right_clip: StringName = &""
@export var turn_rate: float = 0.05
## Velocidad (m/s del modelo a escala 1) a la que el clip de nadar va a ritmo 1: más deprisa, coletea
## más deprisa, y uno más grande, más despacio.
@export var swim_speed: float = 1.0
## A la carga (atacando y alejándose después): el clip de nadar deprisa y su velocidad a ritmo 1.
## Vacío = el de crucero.
@export var dash_clip: StringName = &""
@export var dash_speed: float = 2.0
## Al morder, una vez: el del lado donde tiene la presa.
@export var bite_left_clip: StringName = &""
@export var bite_right_clip: StringName = &""
## Lo que se aparta del cuerpo en reposo al nadar (aletas, cola), en fracción del largo: lo que
## crece su caja de colisión.
@export var swim_margin: float = 0.05
