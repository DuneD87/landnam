extends Node
class_name AIState

## Clase base de los estados de IA. Se añaden como nodos hijo del AIController y se auto-registran
## por su nombre de nodo; cada frame AIController llama update() en el estado activo, que devuelve
## el StringName del estado al que transicionar (o &"" para permanecer).

var controller: AIController


## Llamado una vez al entrar en este estado.
func enter() -> void:
	pass


## Llamado cada frame de física; devuelve el estado al que transicionar (&"" para permanecer).
func update(_delta: float) -> StringName:
	return &""


## Llamado una vez al salir de este estado.
func exit() -> void:
	pass
