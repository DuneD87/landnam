extends Node
class_name AIState

## Base class para todos los estados de IA.
##
## Los estados se añaden como nodos hijo del AIController en la escena y se
## auto-registran por su nombre de nodo (ej: "IdleState", "WanderState").
## Cada frame, AIController llama update(delta) en el estado activo.
## Si update() devuelve un StringName no vacío, AIController transiciona a ese estado.
##
## Patrón de uso:
##   - Añadir como hijo de AIController en la escena.
##   - Nombre del nodo = nombre del estado usado en transition_to().
##   - Acceder al NPC y sus componentes via [member controller].

## Referencia al AIController propietario. Se asigna automáticamente en _ready().
var controller: AIController


## Llamado una vez al entrar en este estado. Inicializa timers, animaciones, etc.
func enter() -> void:
	pass


## Llamado cada frame de física mientras este estado está activo.
## Devolver un StringName no vacío para pedir una transición al estado indicado.
## Devolver [code]&""[/code] para permanecer en el estado actual.
func update(_delta: float) -> StringName:
	return &""


## Llamado una vez al salir de este estado. Limpia lo que sea necesario.
func exit() -> void:
	pass
