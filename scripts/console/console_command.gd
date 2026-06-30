class_name ConsoleCommand
extends RefCounted

## Un comando de la consola de depuración. Cada comando es un objeto autodescriptivo
## (nombre, uso, ayuda) más un Callable que lo ejecuta. El registro de la consola los
## guarda por nombre; añadir un comando nuevo es crear uno de estos y registrarlo. Así
## /help y el autocompletado con Tab se generan solos a partir del registro.

## Nombre por el que se invoca (sin prefijo). Ej: "give".
var name: String
## Línea de uso para /help. Ej: "give <item_id> [cantidad]".
var usage: String
## Descripción corta para el listado de /help.
var description: String
## Nº mínimo de argumentos requeridos; si llegan menos se imprime el uso.
var min_args: int
## Callable(args: PackedStringArray) -> String. Devuelve el texto (BBCode) a imprimir.
var callable: Callable
## Callable opcional() -> PackedStringArray con sugerencias para el primer argumento (Tab).
var completer: Callable

func _init(
	p_name: String,
	p_usage: String,
	p_description: String,
	p_callable: Callable,
	p_min_args: int = 0,
	p_completer: Callable = Callable()
) -> void:
	name = p_name
	usage = p_usage
	description = p_description
	callable = p_callable
	min_args = p_min_args
	completer = p_completer
