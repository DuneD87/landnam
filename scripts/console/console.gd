extends CanvasLayer

## Consola de depuración (autoload): una capa con salida y entrada, abrible con "toggle_console".
## Los comandos son ConsoleCommand autodescriptivos en un registro, así /help y el autocompletado se
## generan solos. Resuelve sus objetivos de forma perezosa (jugador, clima, sol) sin acoplarse.

const config = preload("res://scripts/config.gd")

const COLOR_OK := "#7CFC9A"
const COLOR_ERR := "#FF6B6B"
const COLOR_INFO := "#9AD1FF"
const COLOR_MUTED := "#9aa0a6"
const MAX_HISTORY := 50

var _commands: Dictionary = {}          # name:String -> ConsoleCommand
var _history: Array[String] = []        # comandos introducidos (para ↑/↓)
var _history_index: int = -1

var _output: RichTextLabel
var _input_field: LineEdit
var _is_open: bool = false

var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _prev_input_enabled: bool = false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_register_commands()
	_print("[color=%s]Consola lista. Escribe 'help' para ver los comandos.[/color]" % COLOR_MUTED)
	_set_visible(false)



func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 360
	panel.self_modulate = Color(1, 1, 1, 0.92)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 312)
	_output.add_theme_font_size_override("normal_font_size", 24)
	vbox.add_child(_output)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "Comando…  (Tab autocompleta · ↑/↓ historial)"
	_input_field.clear_button_enabled = true
	_input_field.context_menu_enabled = false
	_input_field.gui_input.connect(_on_input_field_gui_input)
	_input_field.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_input_field)



func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_set_visible(not _is_open)


func _set_visible(open: bool) -> void:
	_is_open = open
	visible = open
	if open:
		_prev_mouse_mode = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		var player := _get_player()
		if player != null:
			_prev_input_enabled = player.input_enabled
			player.input_enabled = false
		_input_field.clear()
		_input_field.grab_focus()
		_history_index = _history.size()
	else:
		Input.set_mouse_mode(_prev_mouse_mode)
		var player := _get_player()
		if player != null:
			player.input_enabled = _prev_input_enabled


func _on_input_field_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_submit()
			_input_field.accept_event()
		KEY_UP:
			_navigate_history(-1)
			_input_field.accept_event()
		KEY_DOWN:
			_navigate_history(1)
			_input_field.accept_event()
		KEY_TAB:
			_autocomplete()
			_input_field.accept_event()


func _navigate_history(dir: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + dir, 0, _history.size())
	if _history_index >= _history.size():
		_input_field.text = ""
	else:
		_input_field.text = _history[_history_index]
	_input_field.caret_column = _input_field.text.length()



func _submit() -> void:
	var line := _input_field.text.strip_edges()
	_input_field.clear()
	if line.is_empty():
		return

	if _history.is_empty() or _history.back() != line:
		_history.append(line)
		if _history.size() > MAX_HISTORY:
			_history.pop_front()
	_history_index = _history.size()

	_print("[color=%s]> %s[/color]" % [COLOR_MUTED, line])
	_run(line)


func _run(line: String) -> void:
	var parts := _tokenize(line)
	if parts.is_empty():
		return
	var cmd_name := parts[0].to_lower()
	var args := parts.slice(1)

	var cmd: ConsoleCommand = _commands.get(cmd_name)
	if cmd == null:
		_err("Comando desconocido: '%s'. Escribe 'help'." % cmd_name)
		return
	if args.size() < cmd.min_args:
		_err("Uso: %s" % cmd.usage)
		return

	var result: Variant = cmd.callable.call(PackedStringArray(args))
	if result is String and not result.is_empty():
		_print(result)


## Tokeniza respetando comillas dobles (para nombres con espacios).
func _tokenize(line: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var current := ""
	var in_quotes := false
	for c in line:
		if c == '"':
			in_quotes = not in_quotes
		elif c == ' ' and not in_quotes:
			if current != "":
				tokens.append(current)
				current = ""
		else:
			current += c
	if current != "":
		tokens.append(current)
	return tokens


func _autocomplete() -> void:
	var line := _input_field.text
	var parts := _tokenize(line)
	if parts.size() <= 1 and not line.ends_with(" "):
		var prefix := "" if parts.is_empty() else parts[0]
		var matches := _commands.keys().filter(func(n): return n.begins_with(prefix))
		matches.sort()
		_apply_completion(prefix, matches, "")
		return
	var cmd: ConsoleCommand = _commands.get(parts[0].to_lower())
	if cmd == null or not cmd.completer.is_valid():
		return
	var arg_prefix := "" if line.ends_with(" ") else parts[parts.size() - 1]
	var options: PackedStringArray = cmd.completer.call()
	var arg_matches := Array(options).filter(func(o): return o.begins_with(arg_prefix))
	arg_matches.sort()
	_apply_completion(arg_prefix, arg_matches, parts[0] + " ")


func _apply_completion(prefix: String, matches: Array, head: String) -> void:
	if matches.is_empty():
		return
	if matches.size() == 1:
		_input_field.text = head + str(matches[0]) + " "
		_input_field.caret_column = _input_field.text.length()
	else:
		_print("[color=%s]%s[/color]" % [COLOR_MUTED, " ".join(matches)])



func _print(msg: String) -> void:
	_output.append_text(msg + "\n")

func _ok(msg: String) -> void:
	_print("[color=%s]%s[/color]" % [COLOR_OK, msg])

func _err(msg: String) -> void:
	_print("[color=%s]%s[/color]" % [COLOR_ERR, msg])

func _info(msg: String) -> void:
	_print("[color=%s]%s[/color]" % [COLOR_INFO, msg])



func _get_player() -> Node:
	return GameManager.player

func _get_weather() -> Node:
	return get_tree().get_first_node_in_group("weather")

func _get_sun() -> Node:
	return get_tree().get_first_node_in_group("sun_controller")



func _add(cmd: ConsoleCommand) -> void:
	_commands[cmd.name] = cmd

func _register_commands() -> void:
	_add(ConsoleCommand.new("help", "help [comando]",
		"Lista los comandos o muestra la ayuda de uno.", _cmd_help))
	_add(ConsoleCommand.new("clear", "clear",
		"Limpia la salida de la consola.", _cmd_clear))
	_add(ConsoleCommand.new("give", "give <item_id> [cantidad]",
		"Añade un item al inventario.", _cmd_give, 1, _complete_item_ids))
	_add(ConsoleCommand.new("items", "items [filtro]",
		"Lista los ids de item disponibles.", _cmd_items))
	_add(ConsoleCommand.new("weather", "weather <evento|reset|list>",
		"Fuerza el clima, lo libera o lista eventos.", _cmd_weather, 1, _complete_weather))
	_add(ConsoleCommand.new("tp", "tp <x> <y> <z>",
		"Teletransporta al jugador a una posición global.", _cmd_tp, 3))
	_add(ConsoleCommand.new("heal", "heal [cantidad]",
		"Cura al jugador (sin argumento, cura al máximo, cierra las heridas y le devuelve los miembros).", _cmd_heal))
	_add(ConsoleCommand.new("suelo", "suelo",
		"Ramas y piedras que se pueden recoger alrededor.", _cmd_litter))
	_add(ConsoleCommand.new("god", "god [on|off]",
		"Invulnerabilidad del jugador (sin argumento, alterna).", _cmd_god))
	_add(ConsoleCommand.new("noclip", "noclip",
		"Alterna el vuelo libre / atravesar terreno.", _cmd_noclip))
	_add(ConsoleCommand.new("sun", "sun <azimuth> [elevación] | sun auto <on|off>",
		"Coloca el sol o (des)activa su rotación automática.", _cmd_sun, 1))
	_add(ConsoleCommand.new("estacion", "estacion [primavera|verano|otoño|invierno|<día>] | estacion velocidad <x>",
		"Fecha y estación donde estás; salta a una estación de tu hemisferio o a un día del año, o acelera el calendario.",
		_cmd_season, 0, _complete_season))
	_add(ConsoleCommand.new("wake", "wake [on|off]",
		"Apaga la espuma de estela, para aislar su coste por píxel.", _cmd_wake))
	_add(ConsoleCommand.new("drift", "drift [factor]",
		"Fuerza de la corriente del mar; sin argumento, informe de cómo la ven barco y jugador.", _cmd_drift))
	_add(ConsoleCommand.new("damage", "damage [julios]",
		"Daña el bloque apuntado con una energía exacta; sin argumento, informa de su vida.", _cmd_damage))
	_add(ConsoleCommand.new("anchors", "anchors [distancia]",
		"De la estructura apuntada: cuántos bloques se apoyan en el suelo y cuántos se caerían.", _cmd_anchors))
	_add(ConsoleCommand.new("derelicts", "derelicts",
		"Estado de la retirada de restos: qué condición bloquea a cada cuerpo dinámico.", _cmd_derelicts))
	_add(ConsoleCommand.new("audio", "audio [evento]",
		"Estado del pool de voces y descartes; con un evento, lo dispara en el jugador.", _cmd_audio, 1))
	_add(ConsoleCommand.new("water", "water",
		"Mezcla del agua: mar/lago/rio, cuanta costa y cuanto temporal.", _cmd_water))
	_add(ConsoleCommand.new("fauna", "fauna",
		"Población de cada especie y por qué se descartan sus puntos de spawn.", _cmd_fauna))
	_add(ConsoleCommand.new("perf", "perf [on|off]",
		"Perfilado por fases: vuelca cada pico a consola con su desglose (sin argumento, alterna).", _cmd_perf))
	_add(ConsoleCommand.new("escala", "escala [0.25-2.0]",
		"Escala de render 3D: bisecciona si el coste de dibujar es de pixel o de envio.", _cmd_escala))
	_add(ConsoleCommand.new("terreno", "terreno [colision <lods>] [normalmap on|off]",
		"Ajustes de coste del terreno en caliente, para comparar picos de 'proc'; sin argumentos, informa.", _cmd_terreno))
	_add(ConsoleCommand.new("spawn", "spawn <oso|ciervo|leon|bufalo> [cantidad] [distancia]",
		"Suelta animales delante del jugador (el oso es hostil: sirve para probar el combate).", _cmd_spawn, 1, _complete_animals))
	_add(ConsoleCommand.new("morir", "morir",
		"Mata al jugador (prueba la muerte y la vuelta al último punto guardado).", _cmd_die))
	_add(ConsoleCommand.new("mutilar", "mutilar [0-1|auto]",
		"Probabilidad de que un tajo en un brazo o una pierna lo cercene (auto: la natural). Sin argumento, informa.", _cmd_mutilate))
	_add(ConsoleCommand.new("sangre", "sangre",
		"Cuántos charcos y salpicaduras de sangre hay y a qué distancia está el más cercano.", _cmd_blood))
	_add(ConsoleCommand.new("cortar", "cortar [brazo|antebrazo|muslo|pierna] [izq|der]",
		"Cercena un miembro del jugador al momento (sin argumentos, uno al azar).", _cmd_cut, 0, _complete_cuts))
	_add(ConsoleCommand.new("fps", "fps [n]",
		"Techo de FPS (0 = sin techo), para fijar el ritmo mientras se mide.", _cmd_fps))




## Los dos factores que cruzan los cuatro loops del mar, mas la ganancia global. Si el mar suena
## raro, aqui se ve si es por la mezcla o por los clips.
## Los factores que cruzan las camas del agua. Si el agua suena rara, aqui se ve si es cosa de la
## mezcla o de los clips.
func _cmd_water(_args: PackedStringArray) -> String:
	# El planeta del jugador es el que se oye; PlanetaryBody ya mantiene cual es el mas cercano.
	var player := _get_player()
	var loader = player.planet if player != null else null
	var amb: WaterAmbience = loader.water_ambience if loader != null else null
	if amb == null:
		return "[color=%s]No hay lecho sonoro de agua montado.[/color]" % COLOR_ERR
	var kind := "lago" if amb.last_is_lake else "mar"
	var out := "[color=%s]Agua[/color]\n" % COLOR_INFO
	out += "  agua quieta: [color=%s]%.2f[/color]  (%s)\n" % [COLOR_OK, amb.last_gain, kind]
	out += "  costa:       [color=%s]%.2f[/color]  (1 = rompiente, 0 = mar abierto)\n" % [COLOR_OK, amb.last_shore]
	out += "  temporal:    [color=%s]%.2f[/color]  (0 = tendida, 1 = pleno)\n" % [COLOR_OK, amb.last_storm]
	out += "  rio:         [color=%s]%.2f[/color]" % [COLOR_OK, amb.last_river]
	return out


## Diagnostico del audio. Sin argumento, el estado del pool y la mezcla del clima: si
## dropped_no_voice sube en juego normal el pool se queda corto, y si sube dropped_budget es que
## un evento se esta pidiendo en rafaga y su cooldown lo esta tapando.
func _cmd_audio(args: PackedStringArray) -> String:
	if args.size() >= 1:
		var event_id := StringName(args[0])
		if not AudioManager.has_event(event_id):
			return "[color=%s]No existe el evento '%s'.[/color]" % [COLOR_ERR, args[0]]
		var player := _get_player()
		if player == null:
			return "[color=%s]No hay jugador.[/color]" % COLOR_ERR
		if AudioManager.play_3d(event_id, player.global_position) == null:
			return "[color=%s]'%s' descartado (mudo, sin voz o en cooldown).[/color]" % [COLOR_INFO, args[0]]
		return "[color=%s]Sonando '%s'.[/color]" % [COLOR_OK, args[0]]

	var out := "[color=%s]Audio[/color]\n" % COLOR_INFO
	for key in AudioManager.get_debug_stats():
		out += "  %s: [color=%s]%s[/color]\n" % [key, COLOR_OK,
			AudioManager.get_debug_stats()[key]]

	var weather := _get_weather()
	var amb: WeatherAmbience = weather.ambience if weather != null else null
	if amb != null:
		var roof := "bajo techo" if amb.last_sheltered else "a cielo abierto"
		out += "[color=%s]Clima[/color]\n" % COLOR_INFO
		out += "  lluvia: [color=%s]%.2f[/color]  (%s)\n" % [COLOR_OK, amb.last_rain, roof]
		out += "  viento: [color=%s]%.2f[/color]\n" % [COLOR_OK, amb.last_wind]
	return out.strip_edges()


func _cmd_help(args: PackedStringArray) -> String:
	if args.size() >= 1:
		var cmd: ConsoleCommand = _commands.get(args[0].to_lower())
		if cmd == null:
			return "[color=%s]No existe el comando '%s'.[/color]" % [COLOR_ERR, args[0]]
		return "[color=%s]%s[/color]\n  %s" % [COLOR_INFO, cmd.usage, cmd.description]
	var names := _commands.keys()
	names.sort()
	var out := "[color=%s]Comandos disponibles:[/color]\n" % COLOR_INFO
	for n in names:
		var c: ConsoleCommand = _commands[n]
		out += "  [color=%s]%s[/color] — %s\n" % [COLOR_OK, c.usage, c.description]
	return out.strip_edges()


func _cmd_clear(_args: PackedStringArray) -> String:
	_output.clear()
	return ""


func _cmd_give(args: PackedStringArray) -> String:
	var player := _get_player()
	if player == null or player.get("inventory") == null:
		return "[color=%s]No hay jugador/inventario activo.[/color]" % COLOR_ERR
	var id := StringName(args[0])
	var item_data: ItemData = config.get_item(id)
	if item_data == null:
		return "[color=%s]Item desconocido: '%s'. Usa 'items' para listarlos.[/color]" % [COLOR_ERR, args[0]]
	var amount := 1
	if args.size() >= 2 and args[1].is_valid_int():
		amount = maxi(1, args[1].to_int())
	var excess: int = player.inventory.add_item(item_data, amount)
	var added := amount - excess
	if excess > 0:
		return "[color=%s]Añadido %s x%d (inventario lleno: %d sin caber).[/color]" % [COLOR_OK, args[0], added, excess]
	return "[color=%s]Añadido %s x%d.[/color]" % [COLOR_OK, args[0], added]


func _cmd_items(args: PackedStringArray) -> String:
	config.get_item(&"")
	var filter := args[0].to_lower() if args.size() >= 1 else ""
	var ids := config.items.keys().map(func(k): return str(k))
	if filter != "":
		ids = ids.filter(func(s): return filter in s.to_lower())
	ids.sort()
	if ids.is_empty():
		return "[color=%s]Sin coincidencias.[/color]" % COLOR_MUTED
	return "[color=%s]%d items:[/color]\n%s" % [COLOR_INFO, ids.size(), " ".join(ids)]


func _cmd_weather(args: PackedStringArray) -> String:
	var wc := _get_weather()
	if wc == null:
		return "[color=%s]No hay sistema de clima activo (¿planeta cargado?).[/color]" % COLOR_ERR
	var sub := args[0].to_lower()
	if sub == "reset":
		wc.clear_force()
		return "[color=%s]Clima liberado (vuelve al control automático).[/color]" % COLOR_OK
	if sub == "list":
		return "[color=%s]Eventos:[/color] %s\n[color=%s]Actual:[/color] %s" % [
			COLOR_INFO, " ".join(wc.get_event_names()), COLOR_INFO, wc.get_current_weather_name()]
	if sub not in wc.get_event_names():
		return "[color=%s]Evento desconocido: '%s'. Usa 'weather list'.[/color]" % [COLOR_ERR, args[0]]
	wc.force_weather(sub)
	return "[color=%s]Clima forzado a '%s'.[/color]" % [COLOR_OK, sub]


func _cmd_tp(args: PackedStringArray) -> String:
	var player := _get_player()
	if player == null:
		return "[color=%s]No hay jugador activo.[/color]" % COLOR_ERR
	for a in args.slice(0, 3):
		if not a.is_valid_float():
			return "[color=%s]Coordenadas inválidas. Uso: tp <x> <y> <z>.[/color]" % COLOR_ERR
	var pos := Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	player.global_position = pos
	return "[color=%s]Teletransportado a %s.[/color]" % [COLOR_OK, str(pos)]


func _cmd_heal(args: PackedStringArray) -> String:
	var hc := _get_health()
	if hc == null:
		return "[color=%s]No hay componente de salud en el jugador.[/color]" % COLOR_ERR
	var amount: float = hc.max_health
	if args.size() >= 1 and args[0].is_valid_float():
		amount = args[0].to_float()
	hc.heal(amount)
	var combat := _get_combat()
	if args.is_empty() and combat != null and combat.body_damage != null:
		combat.body_damage.restore()
	return "[color=%s]Curado +%s (salud: %s/%s).[/color]" % [COLOR_OK, str(amount), str(hc.health), str(hc.max_health)]


func _cmd_god(args: PackedStringArray) -> String:
	var hc := _get_health()
	if hc == null:
		return "[color=%s]No hay componente de salud en el jugador.[/color]" % COLOR_ERR
	if args.size() >= 1:
		hc.invincible = args[0].to_lower() in ["on", "1", "true"]
	else:
		hc.invincible = not hc.invincible
	return "[color=%s]Modo dios: %s.[/color]" % [COLOR_OK, "ON" if hc.invincible else "OFF"]


func _cmd_noclip(_args: PackedStringArray) -> String:
	var player := _get_player()
	if player == null:
		return "[color=%s]No hay jugador activo.[/color]" % COLOR_ERR
	player.free_flight_enabled = not player.free_flight_enabled
	if player.free_flight_enabled and player.get("free_flight_controller") != null and player.camera != null:
		player.free_flight_controller.orientation = Quaternion(player.camera.global_transform.basis)
	return "[color=%s]Noclip (vuelo libre): %s.[/color]" % [COLOR_OK, "ON" if player.free_flight_enabled else "OFF"]


func _cmd_sun(args: PackedStringArray) -> String:
	var sun := _get_sun()
	if sun == null:
		return "[color=%s]No hay controlador de sol activo.[/color]" % COLOR_ERR
	if args[0].to_lower() == "auto":
		var on := args.size() >= 2 and args[1].to_lower() in ["on", "1", "true"]
		sun.auto_rotate = on
		return "[color=%s]Rotación automática del sol: %s.[/color]" % [COLOR_OK, "ON" if on else "OFF"]
	if not args[0].is_valid_float():
		return "[color=%s]Uso: sun <azimuth 0-360> [elevación 0-90] | sun auto on/off.[/color]" % COLOR_ERR
	sun.auto_rotate = false
	sun._set_azimuth(args[0].to_float())
	if args.size() >= 2 and args[1].is_valid_float():
		sun._set_elevation(args[1].to_float())
	return "[color=%s]Sol → azimuth %.1f°, elevación %.1f°.[/color]" % [COLOR_OK, sun.sun_azimuth_deg, sun.sun_elevation_deg]


## Fase local a la que salta cada estación: brotes, pleno verano, pleno color del otoño, pelado.
const SEASON_JUMPS := {"primavera": 0.07, "verano": 0.38, "otoño": 0.6, "otono": 0.6, "invierno": 0.85}


func _cmd_season(args: PackedStringArray) -> String:
	var sun := _get_sun()
	if sun == null:
		return "[color=%s]No hay controlador de sol activo.[/color]" % COLOR_ERR
	var player := _get_player()
	var loader = player.planet if player != null else null
	var local: Vector3 = player.global_position - loader.global_position if loader != null else Vector3.UP
	if not args.is_empty():
		var arg := args[0].to_lower()
		if arg == "velocidad":
			if args.size() < 2 or not args[1].is_valid_float():
				return "[color=%s]Uso: estacion velocidad <x> (1 = normal).[/color]" % COLOR_ERR
			sun.season_speed = maxf(args[1].to_float(), 0.0)
		elif SEASON_JUMPS.has(arg):
			# En el sur la misma estación cae medio año más tarde.
			var phase: float = SEASON_JUMPS[arg] - Seasons.local_phase(local, 0.0)
			sun.set_day_of_year(fposmod(phase, 1.0) * sun.year_days())
		elif arg.is_valid_float():
			sun.set_day_of_year(arg.to_float())
		else:
			return "[color=%s]Uso: estacion [primavera|verano|otoño|invierno|<día>] | estacion velocidad <x>.[/color]" % COLOR_ERR
		sun._update_sun()
		# Tras un salto de fecha el tiempo se sortea con la estación nueva.
		var weather := _get_weather()
		if arg != "velocidad" and weather != null and weather.has_method("reroll"):
			weather.reroll()
	var phase: float = sun.year_phase()
	var here := Seasons.local_phase(local, phase)
	var latitude := Seasons.latitude_deg(local)
	var out := "[color=%s]Día %.1f de %.0f · declinación %+.1f° · calendario ×%.1f[/color]\n" % [
		COLOR_INFO, sun.day_of_year, sun.year_days(), sun.declination_deg(), sun.season_speed]
	out += "  aquí (%.1f° %s): [color=%s]%s[/color] · %.1f h de luz · estaciones al %d %%" % [
		absf(latitude), "N" if latitude >= 0.0 else "S", COLOR_OK, Seasons.NAMES[Seasons.season_index(here)],
		Seasons.daylight_hours(latitude, sun.declination_deg()), roundi(Seasons.strength(local) * 100.0)]
	return out


func _complete_season() -> PackedStringArray:
	return PackedStringArray(["primavera", "verano", "otoño", "invierno", "velocidad"])


## Enciende o apaga el perfilado. Apagado, los report_cost repartidos por el juego no hacen nada
## y el detector de picos ni siquiera pide estadísticas al terreno.
func _cmd_perf(args: PackedStringArray) -> String:
	if args.is_empty():
		DebugStats.profiling = not DebugStats.profiling
	else:
		DebugStats.profiling = args[0].to_lower() in ["on", "1", "true"]
	if not DebugStats.profiling:
		return "[color=%s]Perfilado: OFF.[/color]" % COLOR_MUTED
	return "[color=%s]Perfilado: ON.[/color] Cada pico va a consola con sus fases; F3 enseña el overlay." % COLOR_OK


## Escala de render 3D. Es la biseccion de la fase 'dibujo': si un pico se cae al bajar la escala el
## cuello es de pixel (fill), y si no se mueve es envio de comandos o driver.
func _cmd_escala(args: PackedStringArray) -> String:
	var vp := get_viewport()
	if not args.is_empty():
		if not args[0].is_valid_float():
			return "[color=%s]Uso: escala <0.25-2.0>.[/color]" % COLOR_ERR
		vp.scaling_3d_scale = clampf(args[0].to_float(), 0.25, 2.0)
	var size := vp.get_visible_rect().size
	return "[color=%s]Escala 3D %.2f → %dx%d de %dx%d.[/color]" % [
		COLOR_OK, vp.scaling_3d_scale,
		int(size.x * vp.scaling_3d_scale), int(size.y * vp.scaling_3d_scale),
		int(size.x), int(size.y)]


## Colisión y normalmaps de detalle de todos los VoxelLodTerrain. collision_lod_count 0 = colisión en
## TODOS los LOD (medido); solo afecta a los bloques que se mallen a partir de ahora.
func _cmd_terreno(args: PackedStringArray) -> String:
	var terrains := get_tree().root.find_children("*", "VoxelLodTerrain", true, false)
	if terrains.is_empty():
		return "[color=%s]No hay terrenos cargados.[/color]" % COLOR_ERR
	var i := 0
	while i + 1 < args.size():
		var key := args[i].to_lower()
		var value := args[i + 1].to_lower()
		for t: VoxelLodTerrain in terrains:
			if key == "colision" and value.is_valid_int():
				t.collision_lod_count = maxi(value.to_int(), 0)
			elif key == "normalmap":
				t.normalmap_enabled = value in ["on", "1", "true"]
			else:
				return "[color=%s]Uso: terreno [colision <lods>] [normalmap on|off].[/color]" % COLOR_ERR
		i += 2
	var out := "[color=%s]Terrenos[/color]" % COLOR_INFO
	for t: VoxelLodTerrain in terrains:
		var owner_name: String = t.owner.name if t.owner != null else t.name
		out += "\n  %s: colision %s de %d LOD, normalmap %s" % [owner_name,
			"todos" if t.collision_lod_count == 0 else str(t.collision_lod_count), t.lod_count,
			"on" if t.normalmap_enabled else "off"]
	return out


## Techo de FPS. Sin vsync el frame corre tan rapido como la GPU deje, asi que fijar el ritmo separa
## un paron de verdad de la variacion normal.
func _cmd_fps(args: PackedStringArray) -> String:
	if not args.is_empty():
		if not args[0].is_valid_int():
			return "[color=%s]Uso: fps <n> | fps 0 para quitar el techo.[/color]" % COLOR_ERR
		Engine.max_fps = maxi(args[0].to_int(), 0)
	if Engine.max_fps == 0:
		return "[color=%s]FPS sin techo.[/color]" % COLOR_MUTED
	return "[color=%s]Techo de FPS: %d.[/color]" % [COLOR_OK, Engine.max_fps]


func _cmd_wake(args: PackedStringArray) -> String:
	if not args.is_empty():
		GridManager.wake_enabled = args[0].to_lower() in ["on", "1", "true"]
	return "[color=%s]Estela: %s · %d estelas, %d puntos subidos.[/color]" % [
		COLOR_OK if GridManager.wake_enabled else COLOR_MUTED,
		"ON" if GridManager.wake_enabled else "OFF",
		GridManager.wake_stat_wakes, GridManager.wake_stat_points]


func _cmd_drift(args: PackedStringArray) -> String:
	if not args.is_empty():
		if not args[0].is_valid_float():
			return "[color=%s]Uso: drift [factor >= 0].[/color]" % COLOR_ERR
		WaterHeightSampler.drift_scale = maxf(args[0].to_float(), 0.0)
		return "[color=%s]Arrastre de las olas → %.2f.[/color]" % [COLOR_OK, WaterHeightSampler.drift_scale]
	return _drift_report()


## Lectura de la corriente tal y como la ven jugador y barco: separa "no llega la fuerza" de "la
## fuerza es minúscula", que a ojo son indistinguibles.
func _drift_report() -> String:
	var out := "[color=%s]drift ×%.2f[/color]\n" % [COLOR_INFO, WaterHeightSampler.drift_scale]
	var player := _get_player()
	if player == null:
		return out + "[color=%s]Sin jugador.[/color]" % COLOR_ERR

	var sampler: WaterHeightSampler = player.water_sampler
	if sampler != null:
		out += "  mar: amp %.2f m · steep %.2f · vel %.2f · λ %.1f m\n" % [
			sampler.wave_amplitude, sampler.wave_steepness,
			sampler.wave_speed, sampler.wave_base_length]
		out += "  gates: exposición %.2f · peso oceánico %.2f · orilla %.2f → amp efectiva %.2f m\n" % [
			sampler.last_exposure, sampler.last_ocean_weight,
			sampler.last_shore_presence, sampler.last_amp_effective]

	var flow: Vector3 = player._water_flow
	var up := Vector3.UP
	if player.planet != null:
		up = (player.global_position - player.planet.global_position).normalized()
	var flow_tan := flow - up * flow.dot(up)
	out += "  jugador: corriente %.3f m/s (tangencial %.3f) · nadando %s\n" % [
		flow.length(), flow_tan.length(), "sí" if player.movement.is_swimming else "no"]

	var boat = player._platform_body
	if boat == null or not is_instance_valid(boat):
		return out + "[color=%s]  (no vas en ningún barco)[/color]" % COLOR_MUTED

	var bw: Vector3 = boat.last_water_flow
	var bv: Vector3 = boat.linear_velocity
	var rel := bv - bw
	var accel := 0.0
	if boat.mass > 0.0:
		accel = rel.length() * boat.linear_drag * boat.last_displaced_mass / boat.mass
	out += "  barco: agua %.3f m/s · casco %.3f m/s · relativa %.3f m/s\n" % [
		bw.length(), bv.length(), rel.length()]
	out += "  masa %.0f kg · desplazada %.0f kg · aceleración de arrastre %.3f m/s²\n" % [
		boat.mass, boat.last_displaced_mass, accel]

	# Velocidad horizontal respecto al agua: la que decide si se emite estela.
	var bup: Vector3 = (boat.global_position - boat.planet_node.global_pos).normalized() \
		if boat.planet_node else Vector3.UP
	var rel_h := (rel - bup * rel.dot(bup)).length()
	out += "  estela: %d puntos · %.2f m/s respecto al agua (mínimo %.2f)\n" % [
		boat.get_wake_points().size(), rel_h, DynamicGridBody.WAKE_MIN_SPEED]
	out += "  flotación: %d muestras de ola independientes" % boat.last_wave_samples
	return out


func _get_health() -> Node:
	var player := _get_player()
	if player == null:
		return null
	return player.get("health_component")



const ANIMAL_SCENES := {
	"oso": "res://scenes/animals/Bear.tscn",
	"ciervo": "res://scenes/animals/Deer.tscn",
	"leon": "res://scenes/animals/Lion.tscn",
	"bufalo": "res://scenes/animals/Buffalo.tscn",
}


func _complete_animals() -> PackedStringArray:
	return PackedStringArray(ANIMAL_SCENES.keys())


## Suelta animales sobre el terreno delante del jugador, repartidos en abanico. Quedan fuera del
## pool de fauna (no se reciclan por distancia) y su cadáver dura dos minutos para despellejarlo.
func _cmd_spawn(args: PackedStringArray) -> String:
	var player := _get_player() as PlayerController
	if player == null or player.planet == null:
		return "[color=%s]No hay jugador sobre un planeta.[/color]" % COLOR_ERR
	var kind := args[0].to_lower()
	if not ANIMAL_SCENES.has(kind):
		return "[color=%s]Animal desconocido: %s (%s).[/color]" % [COLOR_ERR, kind, ", ".join(ANIMAL_SCENES.keys())]
	var count := clampi(args[1].to_int(), 1, 12) if args.size() >= 2 and args[1].is_valid_int() else 1
	var distance := clampf(args[2].to_float(), 3.0, 80.0) if args.size() >= 3 and args[2].is_valid_float() else 14.0
	var scene: PackedScene = load(ANIMAL_SCENES[kind])
	var up := -player.gravity_direction.normalized()
	var forward := -player.camera.global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	var side := up.cross(forward)
	var space := player.get_world_3d().direct_space_state
	var placed := 0
	for i in count:
		var spread := (float(i) - (count - 1) * 0.5) * 4.0
		var guess := player.global_position + forward * distance + side * spread
		var query := PhysicsRayQueryParameters3D.create(guess + up * 40.0, guess - up * 60.0)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var animal := scene.instantiate() as NPCController
		get_tree().current_scene.add_child(animal)
		animal.planets = player.planets
		animal.corpse_duration = 120.0
		animal.global_position = hit.position + up * 1.2
		animal.add_to_group("floating_origin")
		placed += 1
	return "[color=%s]%d × %s a %.0f m.[/color]" % [COLOR_OK, placed, kind, distance]


func _cmd_die(_args: PackedStringArray) -> String:
	var hc := _get_health() as HealthComponent
	if hc == null:
		return "[color=%s]No hay componente de salud en el jugador.[/color]" % COLOR_ERR
	hc.invincible = false
	hc.take_damage(hc.health + 1.0)
	return "[color=%s]Has muerto.[/color]" % COLOR_OK


func _get_combat() -> PlayerCombat:
	var player := _get_player() as PlayerController
	return player.combat if player != null else null


func _cmd_blood(_args: PackedStringArray) -> String:
	var player := _get_player() as Node3D
	if player == null:
		return "[color=%s]No hay jugador.[/color]" % COLOR_ERR
	return "[color=%s]%s[/color]" % [COLOR_OK, BloodPool.report(player.global_position)]


func _cmd_litter(_args: PackedStringArray) -> String:
	var player := _get_player() as Node3D
	if player == null:
		return "[color=%s]No hay jugador.[/color]" % COLOR_ERR
	return "[color=%s]%s[/color]" % [COLOR_OK, GroundPickup.report(player)]


func _cmd_mutilate(args: PackedStringArray) -> String:
	if not args.is_empty():
		if args[0].to_lower() == "auto":
			BodyDamage.sever_chance = -1.0
		elif args[0].is_valid_float():
			BodyDamage.sever_chance = clampf(args[0].to_float(), 0.0, 1.0)
		else:
			return "[color=%s]Uso: mutilar [0-1|auto].[/color]" % COLOR_ERR
	var chance := BodyDamage.sever_chance
	if chance < 0.0:
		return "[color=%s]Cercenar: natural (solo si el tajo deja el miembro bajo cero).[/color]" % COLOR_OK
	return "[color=%s]Cercenar: %d %% de los tajos en brazos y piernas.[/color]" % [COLOR_OK, roundi(chance * 100.0)]


const CUT_PARTS := {"brazo": ["arm", true], "antebrazo": ["arm", false], "muslo": ["leg", true],
	"pierna": ["leg", false]}


func _complete_cuts() -> PackedStringArray:
	return PackedStringArray(CUT_PARTS.keys())


func _cmd_cut(args: PackedStringArray) -> String:
	var combat := _get_combat()
	if combat == null or combat.body_damage == null:
		return "[color=%s]No hay jugador.[/color]" % COLOR_ERR
	var part: String = args[0].to_lower() if args.size() >= 1 else CUT_PARTS.keys().pick_random()
	if not CUT_PARTS.has(part):
		return "[color=%s]Parte desconocida. Uso: cortar [brazo|antebrazo|muslo|pierna] [izq|der].[/color]" % COLOR_ERR
	var side: String = args[1].to_lower() if args.size() >= 2 else ["izq", "der"].pick_random()
	var zone := StringName(("left_" if side.begins_with("i") else "right_") + String(CUT_PARTS[part][0]))
	if SettingsManager.gore_level() != SettingsManager.GORE_FULL:
		return "[color=%s]Las mutilaciones están desactivadas en Opciones > Juego.[/color]" % COLOR_ERR
	if not combat.body_damage.sever_zone(zone, CUT_PARTS[part][1]):
		return "[color=%s]Ese miembro ya está cortado (heal lo devuelve).[/color]" % COLOR_ERR
	return "[color=%s]Cercenado: %s %s.[/color]" % [COLOR_OK, part, "izquierdo" if side.begins_with("i") else "derecho"]


func _complete_item_ids() -> PackedStringArray:
	config.get_item(&"")
	var ids := PackedStringArray()
	for k in config.items.keys():
		ids.append(str(k))
	return ids

func _complete_weather() -> PackedStringArray:
	var wc := _get_weather()
	var out := PackedStringArray(["clear", "list"])
	if wc != null:
		for e in wc.get_event_names():
			out.append(str(e))
	return out


## Alcance (m) del rayo de puntería del comando 'damage'.
const DAMAGE_RAY_LEN := 40.0


## Daño controlado sobre el bloque apuntado. Existe porque la ventana en la que un impacto MELLA
## sin romper es estrecha y no se acierta embistiendo: aquí la energía se elige a mano y se puede
## repetir el mismo golpe hasta ver los escalones de daño.
func _cmd_damage(args: PackedStringArray) -> String:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return "[color=%s]Sin cámara activa.[/color]" % COLOR_ERR

	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * DAMAGE_RAY_LEN)
	query.collision_mask = 3
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "[color=%s]No apuntas a nada a menos de %.0f m.[/color]" % [COLOR_ERR, DAMAGE_RAY_LEN]

	var collider = hit["collider"]
	if not (collider is Node) or not (collider as Node).has_meta("grid_id"):
		return "[color=%s]Eso no es una grid (%s).[/color]" % [COLOR_ERR, collider]

	var grid: GridBase = GridManager.get_grid_for_block(collider as Node3D)
	if grid == null:
		return "[color=%s]Grid '%s' no registrada.[/color]" % [
			COLOR_ERR, (collider as Node).get_meta("grid_id")]

	# El punto de impacto cae JUSTO en la cara del bloque: hay que entrar un poco o world_to_cell
	# devuelve la celda vecina, que suele estar vacía.
	var point: Vector3 = hit["position"] + dir * (grid.cell_size * 0.25)
	var cell := grid.world_to_cell(point)
	if not grid.has_block(cell):
		return "[color=%s]Sin bloque en %s de '%s' (¿otra grid del mismo cuerpo?).[/color]" % [
			COLOR_ERR, cell, grid.grid_id]

	if args.is_empty():
		return _damage_report(grid, cell)

	if not args[0].is_valid_float():
		return "[color=%s]Uso: damage [julios].[/color]" % COLOR_ERR

	var energy := maxf(args[0].to_float(), 0.0)
	grid.begin_batch_edit()
	var result: Dictionary = grid.damage_sphere(point, energy)
	grid.end_batch_edit()

	var destroyed: int = (result["destroyed"] as Array).size()
	var out := "[color=%s]%.0f J sobre '%s' %s → %d rotos, %d mellados (gastados %.0f J).[/color]" % [
		COLOR_OK, energy, grid.grid_id, cell, destroyed,
		int(result.get("damaged", 0)), result["spent"]]
	if grid.has_block(cell):
		out += "\n" + _damage_report(grid, cell)
	return out


## Vida del bloque de una celda, con el escalón visual que le corresponde.
func _damage_report(grid: GridBase, cell: Vector3i) -> String:
	var info := grid.get_block(cell)
	var block_id: int = info["block_id"]
	var hp: float = info.get("hp", 1.0)
	var full := grid.impact_cost(block_id)
	return "[color=%s]'%s' %s · bloque %d · vida %.1f%% (%.0f de %.0f J) · escalón %d/%d[/color]" % [
		COLOR_INFO, grid.grid_id, cell, block_id, hp * 100.0, hp * full, full,
		ChunkMeshBuilder.damage_step(hp), ChunkMeshBuilder.DAMAGE_STEPS]


## Por qué NO se está retirando cada resto. Las cinco condiciones se evalúan juntas dentro de
## _update_derelict y desde fuera son indistinguibles entre sí: aquí van una a una.
## Por qué una especie no aparece: cuántos hay vivos, cuántos caben y en qué filtro se cae cada
## candidato. Sin esto, un spawn que no cuaja solo se puede diagnosticar dando vueltas por el mapa.
func _cmd_fauna(_args: PackedStringArray) -> String:
	var spawners := get_tree().get_nodes_in_group(AmbientFaunaSpawner.GROUP)
	if spawners.is_empty():
		return "[color=%s]No hay ningún spawner de fauna en juego.[/color]" % COLOR_ERR
	var lines: Array[String] = []
	for node in spawners:
		var spawner := node as AmbientFaunaSpawner
		if spawner == null or spawner.profile == null:
			continue
		var alive := 0
		for animal in spawner._pool:
			if animal.active:
				alive += 1
		var activity := spawner.activity()
		lines.append("[color=%s]%s[/color]  vivos %d/%d   actividad %d %%   pool %d   radio %.0f m" % [
			COLOR_INFO, spawner.name, alive, mini(spawner.target_population(),
			roundi(spawner.target_population() * activity)), roundi(activity * 100.0),
			spawner._pool.size(), spawner.profile.spawn_radius])
		var ground := spawner.habitat as GroundFaunaHabitat
		if ground == null:
			continue
		lines.append("[color=%s]   %s[/color]" % [COLOR_MUTED, ground.report()])
	return "
".join(lines)


func _cmd_derelicts(_args: PackedStringArray) -> String:
	var bodies := get_tree().get_nodes_in_group("dynamic_grid_body")
	if bodies.is_empty():
		return "[color=%s]No hay cuerpos dinámicos.[/color]" % COLOR_MUTED

	var out := "[color=%s]retirada de restos · tamaño <= %d · quieto < %.1f · lejos > %.0f m · %.0f s[/color]\n" % [
		COLOR_INFO, DynamicGridBody.DERELICT_MAX_BLOCKS, DynamicGridBody.DERELICT_SPEED,
		DynamicGridBody.DERELICT_DISTANCE, DynamicGridBody.DERELICT_SETTLE_TIME]

	for node in bodies:
		var body := node as DynamicGridBody
		var st: Dictionary = body.get_derelict_state()
		var gates := [
			_gate("de rotura", st["from_split"]),
			_gate("sin piloto", not st["controlled"]),
			_gate("tamaño %d" % st["blocks"], int(st["blocks"]) <= DynamicGridBody.DERELICT_MAX_BLOCKS),
			_gate("quieto %.2f/%.2f" % [st["speed"], st["spin"]],
				st["speed"] < DynamicGridBody.DERELICT_SPEED and st["spin"] < DynamicGridBody.DERELICT_SPEED),
			_gate("lejos %.0fm" % st["distance"], st["distance"] > DynamicGridBody.DERELICT_DISTANCE),
		]
		out += "  %s · %s · t %.1f\n" % [body.name, " ".join(gates), st["timer"]]
	return out


## Una condición, verde si pasa y roja si es la que bloquea.
func _gate(label: String, ok: bool) -> String:
	return "[color=%s]%s[/color]" % [COLOR_OK if ok else COLOR_ERR, label]


## Estado de cimentación de la estructura apuntada. Existe porque "se derrumba de más" tiene causas
## opuestas que a ojo son idénticas: o el sondeo no encuentra los apoyos que sí existen, o los
## encuentra pero el alcance del voladizo se queda corto. Y de paso mide lo que cuesta sondear, que
## es lo que se nota como pico en el hilo de física.
func _cmd_anchors(args: PackedStringArray) -> String:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return "[color=%s]Sin cámara activa.[/color]" % COLOR_ERR

	var reach := DAMAGE_RAY_LEN
	if not args.is_empty() and args[0].is_valid_float():
		reach = maxf(args[0].to_float(), 1.0)

	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	query.collision_mask = 3
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "[color=%s]No apuntas a nada a menos de %.0f m. Prueba 'anchors <distancia>'.[/color]" % [
			COLOR_ERR, reach]

	# Decir QUÉ se golpeó, no solo que no servía: apuntando a un casco enterrado lo normal es
	# llevarse el terreno por delante, y "eso no es una grid" a secas no lo distingue de un árbol.
	var collider = hit["collider"]
	var what := "null"
	if collider is Node:
		what = "%s '%s'" % [(collider as Node).get_class(), (collider as Node).name]
	var dist: float = from.distance_to(hit["position"])

	if not (collider is Node) or not (collider as Node).has_meta("grid_id"):
		return "[color=%s]A %.1f m has dado con %s, que no pertenece a ninguna grid.[/color]" % [
			COLOR_ERR, dist, what]

	var aimed := GridManager.get_grid_for_block(collider as Node3D)
	if aimed == null:
		return "[color=%s]%s dice ser de la grid '%s', pero no está registrada.[/color]" % [
			COLOR_ERR, what, (collider as Node).get_meta("grid_id")]
	if not (aimed is PlanetGrid):
		return "[color=%s]'%s' es dinámica; solo las estáticas se cimentan.[/color]" % [
			COLOR_ERR, aimed.grid_id]

	var group: Array = []
	for grid: GridBase in GridManager.get_grid_group(aimed.grid_id):
		if grid is PlanetGrid:
			group.append(grid)

	var grids_data: Array = []
	var anchors: Array = []
	var blocks := 0
	var anchored := 0
	var probe_usec := 0
	var probe_ok := true
	for grid: PlanetGrid in group:
		grids_data.append({"cells": grid.get_all_blocks().keys(), "cell_size": grid.cell_size})
		var t0 := Time.get_ticks_usec()
		var probe: Dictionary = grid.compute_anchor_cells()
		probe_usec += Time.get_ticks_usec() - t0
		probe_ok = probe_ok and probe["ok"]
		var found: Dictionary = probe["cells"]
		anchors.append(found)
		blocks += grid.get_block_count()
		anchored += found.size()

	var falling := GridSplitAnalyzer.analyze_support(grids_data, anchors,
		GridManager.COLLAPSE_MIN_SPAN, GridManager.COLLAPSE_SPAN_PER_ANCHOR, probe_ok)
	var would_fall := 0
	for piece: Dictionary in falling:
		would_fall += int(piece["count"])

	var color := COLOR_OK if anchored > 0 and would_fall == 0 else COLOR_ERR
	var out := "[color=%s]'%s' · %d grids · %d bloques\n" % [color, aimed.grid_id, group.size(), blocks]
	out += "  apoyados en el suelo: %d   (sondeo %.1f ms%s)\n" % [anchored, probe_usec / 1000.0,
		"" if probe_ok else " · SIN PODER CONSULTAR EL TERRENO"]
	out += "  se caerían ahora: %d   (alcance = raiz(apoyos) x %.2f, minimo %d · sondeo %.1f m)[/color]" % [
		would_fall, GridManager.COLLAPSE_SPAN_PER_ANCHOR, GridManager.COLLAPSE_MIN_SPAN,
		PlanetGrid.ANCHOR_PROBE]
	if anchored == 0 and probe_ok and not group.is_empty():
		out += "\n[color=%s]sin un solo apoyo; muestra en crudo del sondeo:\n%s[/color]" % [
			COLOR_MUTED, (group[0] as PlanetGrid).debug_anchor_sample()]
	return out
