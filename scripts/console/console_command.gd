class_name ConsoleCommand
extends RefCounted


var name: String
var usage: String
## Clave de su ayuda en localization/translations.csv (CON_HELP_<NOMBRE>).
var description: String
var min_args: int
var callable: Callable
var completer: Callable
## Lista contra la que se despliega un argumento con patrón (bear_*, /regex/): con ella, Enter
## ejecuta el comando una vez por coincidencia. Vacía = el comando no acepta patrones.
var expander: Callable

func _init(
	p_name: String,
	p_usage: String,
	p_description: String,
	p_callable: Callable,
	p_min_args: int = 0,
	p_completer: Callable = Callable(),
	p_expander: Callable = Callable()
) -> void:
	name = p_name
	usage = p_usage
	description = p_description
	callable = p_callable
	min_args = p_min_args
	completer = p_completer
	expander = p_expander
