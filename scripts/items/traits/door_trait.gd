class_name DoorTrait
extends ItemTrait

## Una hoja que cierra un hueco de una construcción y se abre con USAR (WoodenDoor): la puerta y la
## trampilla. Se construye a medida en el menú de bloques (DoorDesign), en celdas de la grid en la que
## se pone, así que encaja en el hueco sea cual sea el tamaño de sus bloques.

## Ancho y largo del hueco que cierra, en celdas, con que sale en el menú.
@export var cells := Vector2i(1, 3)
## De pie: su largo va siempre en vertical (una puerta). Si no, se pone en el plano del hueco: en un
## techo o un suelo es una trampilla y en una pared, una contraventana.
@export var upright := true
