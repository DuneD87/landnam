class_name LootEntry
extends Resource

## Una línea de un LootTable: qué objeto, cuántos y con qué probabilidad.

## Id del objeto (Config.get_item).
@export var item: StringName
## Cuántos da, a la escala 1 (un animal adulto de tamaño 1).
@export var amount := 1
## Probabilidad de que salga (0-1).
@export_range(0.0, 1.0) var chance := 1.0
