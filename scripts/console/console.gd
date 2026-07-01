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
		"Cura al jugador (sin argumento, cura al máximo).", _cmd_heal))
	_add(ConsoleCommand.new("god", "god [on|off]",
		"Invulnerabilidad del jugador (sin argumento, alterna).", _cmd_god))
	_add(ConsoleCommand.new("noclip", "noclip",
		"Alterna el vuelo libre / atravesar terreno.", _cmd_noclip))
	_add(ConsoleCommand.new("sun", "sun <azimuth> [elevación] | sun auto <on|off>",
		"Coloca el sol o (des)activa su rotación automática.", _cmd_sun, 1))



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


func _get_health() -> Node:
	var player := _get_player()
	if player == null:
		return null
	return player.get("health_component")



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
