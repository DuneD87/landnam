class_name LootEntry
extends Resource

## Una línea de un LootTable: qué objeto, cuántos y con qué probabilidad.

## Id del objeto (ItemCatalog.get_item).
@export var item: StringName
## Cuántos da, a la escala 1 (un animal adulto de tamaño 1).
@export var amount := 1
## Probabilidad de que salga (0-1).
@export_range(0.0, 1.0) var chance := 1.0
## Crece con el tamaño del animal (y con el cuchillo). Lo que va por piezas no: un par de astas o de
## colmillos es un par en un ciervo pequeño y en uno grande.
@export var scales := true
