extends Node

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var saved_locale := TranslationServer.get_locale()
	var saved_state: Dictionary = Console._toon.duplicate()
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		var help := Console._cmd_help(["toon"])
		check(help.contains("threshold") and not help.contains("CON_HELP_TOON"),
			"%s: la ayuda se traduce y conserva la sintaxis en inglés" % locale)
		check(help.contains("Banded direct lighting" if locale == "en" else "Luz directa por bandas"),
			"%s: la ayuda corresponde al idioma seleccionado" % locale)
		var response := Console._cmd_toon(["on", "threshold", "0.2", "softness", "0.03", "gradient", "0.4"])
		check(response.contains("Toon lighting" if locale == "en" else "Luz por bandas"),
			"%s: el resultado corresponde al idioma seleccionado" % locale)
		check(is_equal_approx(Console._toon[&"toon_amount"], 1.0)
			and is_equal_approx(Console._toon[&"toon_threshold"], 0.2)
			and is_equal_approx(Console._toon[&"toon_softness"], 0.03)
			and is_equal_approx(Console._toon[&"toon_gradient"], 0.4), "Se aplican los parámetros del comando")
		var before: Dictionary = Console._toon.duplicate()
		for args in [["off", "threshold", "0.9", "unknown"], ["softness"], ["gradient", "invalid"]]:
			var error := Console._cmd_toon(PackedStringArray(args))
			check(error.contains("Usage:" if locale == "en" else "Uso:"), "El error de uso está traducido")
			check(Console._toon == before, "Un comando inválido no deja cambios parciales")
		Console._cmd_toon([])
		check(Console._toon[&"toon_amount"] == 0.0, "Sin argumentos alterna el último estado válido")
		Console._cmd_toon(["2", "gradient", "2"])
		check(Console._toon[&"toon_amount"] == 1.0 and Console._toon[&"toon_gradient"] == 1.0,
			"La mezcla y el degradado se acotan para no producir luz negativa")
		Console._cmd_toon(["umbral", "0.2", "suave", "0.03", "degradado", "0.4"])
		check(is_equal_approx(Console._toon[&"toon_threshold"], 0.2)
			and is_equal_approx(Console._toon[&"toon_softness"], 0.03)
			and is_equal_approx(Console._toon[&"toon_gradient"], 0.4), "Siguen funcionando los alias del prototipo")
	var completions := Console._complete_toon()
	check(completions.has("threshold") and completions.has("softness") and completions.has("gradient")
		and not completions.has("umbral"), "Tab ofrece los parámetros en inglés")
	for key in Console._toon:
		RenderingServer.global_shader_parameter_set(key,
			saved_state.get(key, ProjectSettings.get_setting("shader_globals/" + key)["value"]))
	Console._toon = saved_state
	TranslationServer.set_locale(saved_locale)
	print("TOON COMMAND: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
