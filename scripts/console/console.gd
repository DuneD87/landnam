extends CanvasLayer

## Consola de depuración (autoload): una capa con salida y entrada, abrible con "toggle_console".
## Los comandos son ConsoleCommand autodescriptivos en un registro, así /help y el autocompletado se
## generan solos. Resuelve sus objetivos de forma perezosa (jugador, clima, sol) sin acoplarse.
## Los comandos y sus argumentos son en inglés en todos los idiomas; su ayuda (claves CON_HELP_*) y
## lo que contestan (CON_*) salen de localization/translations.csv.

const config = preload("res://scripts/config.gd")

const COLOR_OK := "#7CFC9A"
const COLOR_ERR := "#FF6B6B"
const COLOR_INFO := "#9AD1FF"
const COLOR_MUTED := "#9aa0a6"
const MAX_HISTORY := 50
## Palabras de `toon` y el global uniform de toon_light.gdshaderinc que ajusta cada una.
const TOON_KEYS := {"threshold": &"toon_threshold", "softness": &"toon_softness", "gradient": &"toon_gradient"}
## Alias del prototipo para conservar los comandos ya usados; la ayuda y Tab usan inglés.
const TOON_ALIASES := {"umbral": "threshold", "suave": "softness", "degradado": "gradient"}
const TOON_USAGE := "toon [on|off|<0-1>] [threshold <x>] [softness <x>] [gradient <0-1>]"

var _commands: Dictionary = {}          # name:String -> ConsoleCommand
var _history: Array[String] = []        # comandos introducidos (para ↑/↓)
var _history_index: int = -1

var _output: RichTextLabel
var _input_field: LineEdit
var _is_open: bool = false

var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _prev_input_enabled: bool = false
## Valores de la luz por bandas tal como se subieron (global uniform -> float); vacío hasta el
## primer `toon`, que parte de los de project.godot.
var _toon: Dictionary = {}


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_register_commands()
	# Diferido: el autoload Settings, que pone el idioma elegido, arranca después que este.
	(func() -> void: _print(_paint(COLOR_MUTED, tr("CON_READY")))).call_deferred()
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
	_input_field.placeholder_text = "CON_PLACEHOLDER"
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
		_err(tr("CON_UNKNOWN_COMMAND") % cmd_name)
		return
	if args.size() < cmd.min_args:
		_err(tr("CON_USAGE") % cmd.usage)
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


## [text] (ya traducido) en [color], para devolverlo como respuesta.
func _paint(color: String, text: String) -> String:
	return "[color=%s]%s[/color]" % [color, text]



func _get_player() -> Node:
	return GameManager.player

func _get_weather() -> Node:
	return get_tree().get_first_node_in_group("weather")

func _get_sun() -> Node:
	return get_tree().get_first_node_in_group("sun_controller")



func _add(cmd: ConsoleCommand) -> void:
	_commands[cmd.name] = cmd

## Cada comando con su sintaxis (en inglés, como el comando) y la clave de su ayuda.
func _register_commands() -> void:
	_add(ConsoleCommand.new("help", "help [command]", "CON_HELP_HELP", _cmd_help))
	_add(ConsoleCommand.new("clear", "clear", "CON_HELP_CLEAR", _cmd_clear))
	_add(ConsoleCommand.new("give", "give <item_id> [amount]", "CON_HELP_GIVE", _cmd_give, 1, _complete_item_ids))
	_add(ConsoleCommand.new("items", "items [filter]", "CON_HELP_ITEMS", _cmd_items))
	_add(ConsoleCommand.new("weather", "weather <event|reset|list>", "CON_HELP_WEATHER", _cmd_weather, 1,
		_complete_weather))
	_add(ConsoleCommand.new("tp", "tp <x> <y> <z>", "CON_HELP_TP", _cmd_tp, 3))
	_add(ConsoleCommand.new("heal", "heal [amount]", "CON_HELP_HEAL", _cmd_heal))
	_add(ConsoleCommand.new("litter", "litter", "CON_HELP_LITTER", _cmd_litter))
	_add(ConsoleCommand.new("god", "god [on|off]", "CON_HELP_GOD", _cmd_god))
	_add(ConsoleCommand.new("noclip", "noclip", "CON_HELP_NOCLIP", _cmd_noclip))
	_add(ConsoleCommand.new("sun", "sun <azimuth> [elevation] | sun auto <on|off>", "CON_HELP_SUN", _cmd_sun, 1))
	_add(ConsoleCommand.new("season", SEASON_USAGE, "CON_HELP_SEASON", _cmd_season, 0, _complete_season))
	_add(ConsoleCommand.new("wake", "wake [on|off]", "CON_HELP_WAKE", _cmd_wake))
	_add(ConsoleCommand.new("shadows", "shadows [on|off]", "CON_HELP_SHADOWS", _cmd_shadows))
	_add(ConsoleCommand.new("drift", "drift [factor]", "CON_HELP_DRIFT", _cmd_drift))
	_add(ConsoleCommand.new("damage", "damage [joules]", "CON_HELP_DAMAGE", _cmd_damage))
	_add(ConsoleCommand.new("anchors", "anchors [distance]", "CON_HELP_ANCHORS", _cmd_anchors))
	_add(ConsoleCommand.new("derelicts", "derelicts", "CON_HELP_DERELICTS", _cmd_derelicts))
	_add(ConsoleCommand.new("audio", "audio [event]", "CON_HELP_AUDIO", _cmd_audio))
	_add(ConsoleCommand.new("water", "water", "CON_HELP_WATER", _cmd_water))
	_add(ConsoleCommand.new("fauna", "fauna", "CON_HELP_FAUNA", _cmd_fauna))
	_add(ConsoleCommand.new("perf", "perf [on|off]", "CON_HELP_PERF", _cmd_perf))
	_add(ConsoleCommand.new("scale", "scale [0.25-2.0]", "CON_HELP_SCALE", _cmd_scale))
	_add(ConsoleCommand.new("terrain", TERRAIN_USAGE, "CON_HELP_TERRAIN", _cmd_terrain))
	_add(ConsoleCommand.new("spawn", "spawn <animal> [amount] [distance] [variant]", "CON_HELP_SPAWN", _cmd_spawn, 1,
		_complete_animals))
	_add(ConsoleCommand.new("ai", "ai [radius]", "CON_HELP_AI", _cmd_ai))
	_add(ConsoleCommand.new("die", "die", "CON_HELP_DIE", _cmd_die))
	_add(ConsoleCommand.new("sever", "sever [0-1|auto]", "CON_HELP_SEVER", _cmd_sever))
	_add(ConsoleCommand.new("blood", "blood", "CON_HELP_BLOOD", _cmd_blood))
	_add(ConsoleCommand.new("cut", CUT_USAGE, "CON_HELP_CUT", _cmd_cut, 0, _complete_cuts))
	_add(ConsoleCommand.new("status", "status [<id> [left|right|zone] [seconds] | remove [id]]", "CON_HELP_STATUS",
		_cmd_status, 0, _complete_status))
	_add(ConsoleCommand.new("toon", TOON_USAGE, "CON_HELP_TOON", _cmd_toon, 0, _complete_toon))
	_add(ConsoleCommand.new("needs", "needs [<name> <value> | fill | empty | pause [on|off] | rate <x>]",
		"CON_HELP_NEEDS", _cmd_needs, 0, _complete_needs))
	_add(ConsoleCommand.new("fps", "fps [n]", "CON_HELP_FPS", _cmd_fps))


const SEASON_USAGE := "season [spring|summer|autumn|winter|<day>] | season speed <x> | season perf [leaves|cold|meadow|none]"
const TERRAIN_USAGE := "terrain [collision <lods>] [normalmap on|off]"
const CUT_USAGE := "cut [arm|forearm|thigh|shin] [left|right]"


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
		return _paint(COLOR_ERR, tr("CON_WATER_NO_BED"))
	var kind := tr("CON_WATER_LAKE" if amb.last_is_lake else "CON_WATER_SEA")
	var out := _paint(COLOR_INFO, tr("CON_WATER_TITLE")) + "\n"
	out += "  %-13s [color=%s]%.2f[/color]  (%s)\n" % [tr("CON_WATER_STILL"), COLOR_OK, amb.last_gain, kind]
	out += "  %-13s [color=%s]%.2f[/color]  (%s)\n" % [tr("CON_WATER_SHORE"), COLOR_OK, amb.last_shore, tr("CON_WATER_SHORE_RANGE")]
	out += "  %-13s [color=%s]%.2f[/color]  (%s)\n" % [tr("CON_WATER_STORM"), COLOR_OK, amb.last_storm, tr("CON_WATER_STORM_RANGE")]
	out += "  %-13s [color=%s]%.2f[/color]" % [tr("CON_WATER_RIVER"), COLOR_OK, amb.last_river]
	return out


## Diagnostico del audio. Sin argumento, el estado del pool y la mezcla del clima: si
## dropped_no_voice sube en juego normal el pool se queda corto, y si sube dropped_budget es que
## un evento se esta pidiendo en rafaga y su cooldown lo esta tapando.
func _cmd_audio(args: PackedStringArray) -> String:
	if args.size() >= 1:
		var event_id := StringName(args[0])
		if not AudioManager.has_event(event_id):
			return _paint(COLOR_ERR, tr("CON_AUDIO_NO_EVENT") % args[0])
		var player := _get_player()
		if player == null:
			return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
		if AudioManager.play_3d(event_id, player.global_position) == null:
			return _paint(COLOR_INFO, tr("CON_AUDIO_DROPPED") % args[0])
		return _paint(COLOR_OK, tr("CON_AUDIO_PLAYING") % args[0])

	var out := _paint(COLOR_INFO, tr("CON_AUDIO_TITLE")) + "\n"
	for key in AudioManager.get_debug_stats():
		out += "  %s: [color=%s]%s[/color]\n" % [key, COLOR_OK,
			AudioManager.get_debug_stats()[key]]

	var weather := _get_weather()
	var amb: WeatherAmbience = weather.ambience if weather != null else null
	if amb != null:
		var roof := tr("CON_AUDIO_SHELTERED" if amb.last_sheltered else "CON_AUDIO_OPEN_SKY")
		out += _paint(COLOR_INFO, tr("CON_AUDIO_WEATHER")) + "\n"
		out += "  %s [color=%s]%.2f[/color]  (%s)\n" % [tr("CON_AUDIO_RAIN"), COLOR_OK, amb.last_rain, roof]
		out += "  %s [color=%s]%.2f[/color]\n" % [tr("CON_AUDIO_WIND"), COLOR_OK, amb.last_wind]
	return out.strip_edges()


func _cmd_help(args: PackedStringArray) -> String:
	if args.size() >= 1:
		var cmd: ConsoleCommand = _commands.get(args[0].to_lower())
		if cmd == null:
			return _paint(COLOR_ERR, tr("CON_NO_COMMAND") % args[0])
		return "[color=%s]%s[/color]\n  %s" % [COLOR_INFO, cmd.usage, tr(cmd.description)]
	var names := _commands.keys()
	names.sort()
	var out := _paint(COLOR_INFO, tr("CON_COMMANDS")) + "\n"
	for n in names:
		var c: ConsoleCommand = _commands[n]
		out += "  [color=%s]%s[/color] — %s\n" % [COLOR_OK, c.usage, tr(c.description)]
	return out.strip_edges()


func _cmd_clear(_args: PackedStringArray) -> String:
	_output.clear()
	return ""


func _cmd_give(args: PackedStringArray) -> String:
	var player := _get_player()
	if player == null or player.get("inventory") == null:
		return _paint(COLOR_ERR, tr("CON_NO_INVENTORY"))
	var id := StringName(args[0])
	var item_data: ItemData = config.get_item(id)
	if item_data == null:
		return _paint(COLOR_ERR, tr("CON_UNKNOWN_ITEM") % args[0])
	var amount := 1
	if args.size() >= 2 and args[1].is_valid_int():
		amount = maxi(1, args[1].to_int())
	var excess: int = player.inventory.add_item(item_data, amount)
	var added := amount - excess
	if excess > 0:
		return _paint(COLOR_OK, tr("CON_ADDED_FULL") % [args[0], added, excess])
	return _paint(COLOR_OK, tr("CON_ADDED") % [args[0], added])


func _cmd_items(args: PackedStringArray) -> String:
	config.get_item(&"")
	var filter := args[0].to_lower() if args.size() >= 1 else ""
	var ids := config.items.keys().map(func(k): return str(k))
	if filter != "":
		ids = ids.filter(func(s): return filter in s.to_lower())
	ids.sort()
	if ids.is_empty():
		return _paint(COLOR_MUTED, tr("CON_NO_MATCHES"))
	return _paint(COLOR_INFO, tr("CON_ITEMS_COUNT") % ids.size()) + "\n" + " ".join(ids)


func _cmd_weather(args: PackedStringArray) -> String:
	var wc := _get_weather()
	if wc == null:
		return _paint(COLOR_ERR, tr("CON_NO_WEATHER"))
	var sub := args[0].to_lower()
	if sub == "reset":
		wc.clear_force()
		return _paint(COLOR_OK, tr("CON_WEATHER_RELEASED"))
	if sub == "list":
		return "%s %s\n%s %s" % [_paint(COLOR_INFO, tr("CON_WEATHER_EVENTS")), " ".join(wc.get_event_names()),
			_paint(COLOR_INFO, tr("CON_WEATHER_CURRENT")), wc.get_current_weather_name()]
	if sub not in wc.get_event_names():
		return _paint(COLOR_ERR, tr("CON_UNKNOWN_WEATHER") % args[0])
	wc.force_weather(sub)
	return _paint(COLOR_OK, tr("CON_WEATHER_FORCED") % sub)


func _cmd_tp(args: PackedStringArray) -> String:
	var player := _get_player()
	if player == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
	for a in args.slice(0, 3):
		if not a.is_valid_float():
			return _paint(COLOR_ERR, tr("CON_TP_INVALID"))
	var pos := Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	player.global_position = pos
	return _paint(COLOR_OK, tr("CON_TP_DONE") % str(pos))


func _cmd_heal(args: PackedStringArray) -> String:
	var hc := _get_health()
	if hc == null:
		return _paint(COLOR_ERR, tr("CON_NO_HEALTH"))
	var amount: float = hc.max_health
	if args.size() >= 1 and args[0].is_valid_float():
		amount = args[0].to_float()
	hc.heal(amount)
	var combat := _get_combat()
	if args.is_empty() and combat != null and combat.body_damage != null:
		combat.body_damage.restore()
		combat.status.restore()
	return _paint(COLOR_OK, tr("CON_HEALED") % [str(amount), str(hc.health), str(hc.max_health)])


func _cmd_needs(args: PackedStringArray) -> String:
	var player := _get_player()
	var needs: SurvivalNeeds = player.get("needs") if player != null else null
	if needs == null:
		return _paint(COLOR_ERR, tr("CON_NO_NEEDS"))
	if args.is_empty():
		var lines := PackedStringArray()
		for need in SurvivalNeeds.NAMES:
			lines.append("  %s: %.2f" % [need, needs.get_value(need)])
		var title := tr("CON_NEEDS_TITLE_PAUSED" if needs.paused else "CON_NEEDS_TITLE") % str(needs.rate)
		return "%s\n%s\n  %s\n  %s" % [_paint(COLOR_INFO, title), "\n".join(lines),
			tr("CON_NEEDS_FELT") % [needs.felt_temperature, needs.temperature_word(),
				tr("UI_YES" if needs.submerged else "UI_NO")],
			tr("CON_NEEDS_WATER") % [needs.water, needs.water_capacity(), _water_word(player)]]
	var sub := args[0].to_lower()
	match sub:
		"fill":
			needs.refill()
			return _paint(COLOR_OK, tr("CON_NEEDS_FILLED"))
		"empty":
			for need in ["hunger", "thirst", "rest", "sanity", "oxygen"]:
				needs.set_value(need, 0.0)
			return _paint(COLOR_OK, tr("CON_NEEDS_EMPTIED"))
		"pause":
			needs.paused = args[1].to_lower() in ["on", "1", "true"] if args.size() >= 2 else not needs.paused
			return _paint(COLOR_OK, tr("CON_NEEDS_PAUSED" if needs.paused else "CON_NEEDS_RUNNING"))
		"rate":
			if args.size() < 2 or not args[1].is_valid_float():
				return _paint(COLOR_ERR, tr("CON_NEEDS_RATE_USAGE"))
			needs.rate = maxf(args[1].to_float(), 0.0)
			return _paint(COLOR_OK, tr("CON_NEEDS_RATE") % str(needs.rate))
	var need := sub
	if not SurvivalNeeds.NAMES.has(need):
		return _paint(COLOR_ERR, tr("CON_UNKNOWN_NEED") % [args[0], ", ".join(SurvivalNeeds.NAMES)])
	if args.size() < 2 or not args[1].is_valid_float():
		return _paint(COLOR_INFO, "%s: %.2f" % [need, needs.get_value(need)])
	needs.set_value(need, args[1].to_float())
	return _paint(COLOR_OK, "%s → %.2f." % [need, needs.get_value(need)])


func _water_word(player: Node) -> String:
	var survival: SurvivalActions = player.get("survival")
	if survival == null:
		return "?"
	match survival.water_here():
		&"fresh":
			return tr("CON_WATER_FRESH")
		&"salt":
			return tr("CON_WATER_SALT")
	return tr("CON_WATER_NONE")


func _complete_needs() -> PackedStringArray:
	var options := PackedStringArray(SurvivalNeeds.NAMES)
	options.append_array(["fill", "empty", "pause", "rate"])
	return options


func _cmd_god(args: PackedStringArray) -> String:
	var hc := _get_health()
	if hc == null:
		return _paint(COLOR_ERR, tr("CON_NO_HEALTH"))
	if args.size() >= 1:
		hc.invincible = args[0].to_lower() in ["on", "1", "true"]
	else:
		hc.invincible = not hc.invincible
	return _paint(COLOR_OK, tr("CON_GOD") % ("ON" if hc.invincible else "OFF"))


func _cmd_noclip(_args: PackedStringArray) -> String:
	var player := _get_player()
	if player == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
	player.free_flight_enabled = not player.free_flight_enabled
	if player.free_flight_enabled and player.get("free_flight_controller") != null and player.camera != null:
		player.free_flight_controller.orientation = Quaternion(player.camera.global_transform.basis)
	return _paint(COLOR_OK, tr("CON_NOCLIP") % ("ON" if player.free_flight_enabled else "OFF"))


func _cmd_sun(args: PackedStringArray) -> String:
	var sun := _get_sun()
	if sun == null:
		return _paint(COLOR_ERR, tr("CON_NO_SUN"))
	if args[0].to_lower() == "auto":
		var on := args.size() >= 2 and args[1].to_lower() in ["on", "1", "true"]
		sun.auto_rotate = on
		return _paint(COLOR_OK, tr("CON_SUN_AUTO") % ("ON" if on else "OFF"))
	if not args[0].is_valid_float():
		return _paint(COLOR_ERR, tr("CON_USAGE") % "sun <azimuth 0-360> [elevation 0-90] | sun auto on/off")
	sun.auto_rotate = false
	sun._set_azimuth(args[0].to_float())
	if args.size() >= 2 and args[1].is_valid_float():
		sun._set_elevation(args[1].to_float())
	return _paint(COLOR_OK, tr("CON_SUN_PLACED") % [sun.sun_azimuth_deg, sun.sun_elevation_deg])


## Fase local a la que salta cada estación: brotes, pleno verano, pleno color del otoño, pelado.
const SEASON_JUMPS := {"spring": 0.07, "summer": 0.38, "autumn": 0.6, "winter": 0.85}


func _cmd_season(args: PackedStringArray) -> String:
	var sun := _get_sun()
	if sun == null:
		return _paint(COLOR_ERR, tr("CON_NO_SUN"))
	var player := _get_player()
	var loader = player.planet if player != null else null
	var local: Vector3 = player.global_position - loader.global_position if loader != null else Vector3.UP
	if not args.is_empty() and args[0].to_lower() == "perf":
		return _season_perf(args)
	if not args.is_empty():
		var arg := args[0].to_lower()
		if arg == "speed":
			if args.size() < 2 or not args[1].is_valid_float():
				return _paint(COLOR_ERR, tr("CON_USAGE") % "season speed <x> (1 = normal)")
			sun.season_speed = maxf(args[1].to_float(), 0.0)
		elif SEASON_JUMPS.has(arg):
			# En el sur la misma estación cae medio año más tarde.
			var phase: float = SEASON_JUMPS[arg] - Seasons.local_phase(local, 0.0)
			sun.set_day_of_year(fposmod(phase, 1.0) * sun.year_days())
		elif arg.is_valid_float():
			sun.set_day_of_year(arg.to_float())
		else:
			return _paint(COLOR_ERR, tr("CON_USAGE") % SEASON_USAGE)
		sun._update_sun()
		# Tras un salto de fecha el tiempo se sortea con la estación nueva.
		var weather := _get_weather()
		if arg != "speed" and weather != null and weather.has_method("reroll"):
			weather.reroll()
	var phase: float = sun.year_phase()
	var here := Seasons.local_phase(local, phase)
	var latitude := Seasons.latitude_deg(local)
	var out := _paint(COLOR_INFO, tr("CON_SEASON_DATE") % [sun.day_of_year, sun.year_days(), sun.declination_deg(),
		sun.season_speed]) + "\n"
	var season_name := tr("SEASON_" + String(Seasons.KEYS[Seasons.season_index(here)]).to_upper())
	out += "  " + tr("CON_SEASON_HERE") % [absf(latitude), tr("COMPASS_N" if latitude >= 0.0 else "COMPASS_S"),
		_paint(COLOR_OK, season_name), Seasons.daylight_hours(latitude, sun.declination_deg()),
		roundi(Seasons.strength(local) * 100.0)]
	return out


## season perf [leaves|cold|meadow|none]: alterna esa parte de la estación como en verano (solo en
## los shaders) para aislar lo que cuesta; none la vuelve a poner entera. Sin parte, dice cuáles están
## apagadas.
func _season_perf(args: PackedStringArray) -> String:
	if args.size() >= 2:
		var part := args[1].to_lower()
		if part == "none":
			Seasons.set_debug_off(0)
		elif Seasons.DEBUG_OFF.has(part):
			Seasons.set_debug_off(Seasons.debug_off ^ int(Seasons.DEBUG_OFF[part]))
		else:
			return _paint(COLOR_ERR, tr("CON_USAGE") % "season perf [leaves|cold|meadow|none]")
	var off := PackedStringArray()
	for part: String in Seasons.DEBUG_OFF:
		if Seasons.debug_off & int(Seasons.DEBUG_OFF[part]):
			off.append(part)
	if off.is_empty():
		return _paint(COLOR_MUTED, tr("CON_SEASON_FULL"))
	return _paint(COLOR_OK, tr("CON_SEASON_AS_SUMMER") % ", ".join(off))


func _complete_season() -> PackedStringArray:
	return PackedStringArray(Seasons.KEYS + ["speed", "perf"])


## Enciende o apaga el perfilado. Apagado, los report_cost repartidos por el juego no hacen nada
## y el detector de picos ni siquiera pide estadísticas al terreno.
func _cmd_perf(args: PackedStringArray) -> String:
	if args.is_empty():
		DebugStats.profiling = not DebugStats.profiling
	else:
		DebugStats.profiling = args[0].to_lower() in ["on", "1", "true"]
	if not DebugStats.profiling:
		return _paint(COLOR_MUTED, tr("CON_PERF_OFF"))
	return "%s %s" % [_paint(COLOR_OK, tr("CON_PERF_ON")), tr("CON_PERF_ON_HINT")]


## Escala de render 3D. Es la biseccion de la fase 'dibujo': si un pico se cae al bajar la escala el
## cuello es de pixel (fill), y si no se mueve es envio de comandos o driver.
func _cmd_scale(args: PackedStringArray) -> String:
	var vp := get_viewport()
	if not args.is_empty():
		if not args[0].is_valid_float():
			return _paint(COLOR_ERR, tr("CON_USAGE") % "scale <0.25-2.0>")
		vp.scaling_3d_scale = clampf(args[0].to_float(), 0.25, 2.0)
	var size := vp.get_visible_rect().size
	return _paint(COLOR_OK, tr("CON_SCALE") % [vp.scaling_3d_scale,
		int(size.x * vp.scaling_3d_scale), int(size.y * vp.scaling_3d_scale),
		int(size.x), int(size.y)])


## Colisión y normalmaps de detalle de todos los VoxelLodTerrain. collision_lod_count 0 = colisión en
## TODOS los LOD (medido); solo afecta a los bloques que se mallen a partir de ahora.
func _cmd_terrain(args: PackedStringArray) -> String:
	var terrains := get_tree().root.find_children("*", "VoxelLodTerrain", true, false)
	if terrains.is_empty():
		return _paint(COLOR_ERR, tr("CON_NO_TERRAIN"))
	var i := 0
	while i + 1 < args.size():
		var key := args[i].to_lower()
		var value := args[i + 1].to_lower()
		for t: VoxelLodTerrain in terrains:
			if key == "collision" and value.is_valid_int():
				t.collision_lod_count = maxi(value.to_int(), 0)
			elif key == "normalmap":
				t.normalmap_enabled = value in ["on", "1", "true"]
			else:
				return _paint(COLOR_ERR, tr("CON_USAGE") % TERRAIN_USAGE)
		i += 2
	var out := _paint(COLOR_INFO, tr("CON_TERRAINS"))
	for t: VoxelLodTerrain in terrains:
		var owner_name: String = t.owner.name if t.owner != null else t.name
		out += "\n  %s: %s" % [owner_name, tr("CON_TERRAIN_LINE") % [
			tr("CON_TERRAIN_ALL") if t.collision_lod_count == 0 else str(t.collision_lod_count), t.lod_count,
			"on" if t.normalmap_enabled else "off"]]
	return out


## Techo de FPS. Sin vsync el frame corre tan rapido como la GPU deje, asi que fijar el ritmo separa
## un paron de verdad de la variacion normal.
func _cmd_fps(args: PackedStringArray) -> String:
	if not args.is_empty():
		if not args[0].is_valid_int():
			return _paint(COLOR_ERR, tr("CON_FPS_USAGE"))
		Engine.max_fps = maxi(args[0].to_int(), 0)
	if Engine.max_fps == 0:
		return _paint(COLOR_MUTED, tr("CON_FPS_UNCAPPED"))
	return _paint(COLOR_OK, tr("CON_FPS_CAP") % Engine.max_fps)


func _cmd_toon(args: PackedStringArray) -> String:
	if _toon.is_empty():
		for key: StringName in [&"toon_amount", &"toon_threshold", &"toon_softness", &"toon_gradient"]:
			_toon[key] = float(ProjectSettings.get_setting("shader_globals/" + key)["value"])
	var next := _toon.duplicate()
	if args.is_empty():
		next[&"toon_amount"] = 0.0 if next[&"toon_amount"] > 0.0 else 1.0
	var i := 0
	while i < args.size():
		var word := args[i].to_lower()
		word = TOON_ALIASES.get(word, word)
		if word in ["on", "off"]:
			next[&"toon_amount"] = 1.0 if word == "on" else 0.0
			i += 1
		elif word.is_valid_float():
			next[&"toon_amount"] = clampf(word.to_float(), 0.0, 1.0)
			i += 1
		elif TOON_KEYS.has(word) and i + 1 < args.size() and args[i + 1].is_valid_float():
			var key: StringName = TOON_KEYS[word]
			var value := maxf(args[i + 1].to_float(), 0.0)
			next[key] = minf(value, 1.0) if key == &"toon_gradient" else value
			i += 2
		else:
			return _paint(COLOR_ERR, tr("CON_USAGE") % TOON_USAGE)
	_toon = next
	for key: StringName in _toon:
		RenderingServer.global_shader_parameter_set(key, _toon[key])
	var amount: float = _toon[&"toon_amount"]
	return _paint(COLOR_OK if amount > 0.0 else COLOR_MUTED, tr("CON_TOON_STATUS") % [
		amount, _toon[&"toon_threshold"], _toon[&"toon_softness"], _toon[&"toon_gradient"]])


func _complete_toon() -> PackedStringArray:
	return PackedStringArray(["on", "off"] + TOON_KEYS.keys())


func _cmd_wake(args: PackedStringArray) -> String:
	if not args.is_empty():
		GridManager.wake_enabled = args[0].to_lower() in ["on", "1", "true"]
	return _paint(COLOR_OK if GridManager.wake_enabled else COLOR_MUTED, tr("CON_WAKE") % [
		"ON" if GridManager.wake_enabled else "OFF", GridManager.wake_stat_wakes, GridManager.wake_stat_points])


func _cmd_shadows(args: PackedStringArray) -> String:
	var sun := _get_sun()
	var light: DirectionalLight3D = sun.get("sun_light") if sun != null else null
	if light == null:
		return _paint(COLOR_ERR, tr("CON_NO_SUN"))
	if not args.is_empty():
		light.shadow_enabled = args[0].to_lower() in ["on", "1", "true"]
	var elevation := rad_to_deg(asin(clampf(light.global_basis.z.normalized().dot(_local_up()), -1.0, 1.0))) if _local_up() != Vector3.ZERO else NAN
	return _paint(COLOR_OK if light.shadow_enabled else COLOR_MUTED, tr("CON_SHADOWS") % [
		"ON" if light.shadow_enabled else "OFF", elevation])


## Arriba local del jugador (desde el centro de su planeta), o cero sin jugador.
func _local_up() -> Vector3:
	var player := _get_player()
	var loader = player.planet if player != null else null
	if loader == null:
		return Vector3.ZERO
	return (player.global_position - loader.global_position).normalized()


func _cmd_drift(args: PackedStringArray) -> String:
	if not args.is_empty():
		if not args[0].is_valid_float():
			return _paint(COLOR_ERR, tr("CON_USAGE") % "drift [factor >= 0]")
		WaterHeightSampler.drift_scale = maxf(args[0].to_float(), 0.0)
		return _paint(COLOR_OK, tr("CON_DRIFT_SET") % WaterHeightSampler.drift_scale)
	return _drift_report()


## Lectura de la corriente tal y como la ven jugador y barco: separa "no llega la fuerza" de "la
## fuerza es minúscula", que a ojo son indistinguibles.
func _drift_report() -> String:
	var out := "[color=%s]drift ×%.2f[/color]\n" % [COLOR_INFO, WaterHeightSampler.drift_scale]
	var player := _get_player()
	if player == null:
		return out + _paint(COLOR_ERR, tr("CON_NO_PLAYER"))

	var sampler: WaterHeightSampler = player.water_sampler
	if sampler != null:
		out += "  " + tr("CON_DRIFT_SEA") % [
			sampler.wave_amplitude, sampler.wave_steepness,
			sampler.wave_speed, sampler.wave_base_length] + "\n"
		out += "  " + tr("CON_DRIFT_GATES") % [
			sampler.last_exposure, sampler.last_ocean_weight,
			sampler.last_shore_presence, sampler.last_amp_effective] + "\n"

	var flow: Vector3 = player._water_flow
	var up := Vector3.UP
	if player.planet != null:
		up = (player.global_position - player.planet.global_position).normalized()
	var flow_tan := flow - up * flow.dot(up)
	out += "  " + tr("CON_DRIFT_PLAYER") % [
		flow.length(), flow_tan.length(), tr("UI_YES" if player.movement.is_swimming else "UI_NO")] + "\n"

	var boat = player._platform_body
	if boat == null or not is_instance_valid(boat):
		return out + _paint(COLOR_MUTED, "  " + tr("CON_DRIFT_NO_BOAT"))

	var bw: Vector3 = boat.last_water_flow
	var bv: Vector3 = boat.linear_velocity
	var rel := bv - bw
	var accel := 0.0
	if boat.mass > 0.0:
		accel = rel.length() * boat.linear_drag * boat.last_displaced_mass / boat.mass
	out += "  " + tr("CON_DRIFT_BOAT") % [bw.length(), bv.length(), rel.length()] + "\n"
	out += "  " + tr("CON_DRIFT_MASS") % [boat.mass, boat.last_displaced_mass, accel] + "\n"

	# Velocidad horizontal respecto al agua: la que decide si se emite estela.
	var bup: Vector3 = (boat.global_position - boat.planet_node.global_pos).normalized() \
		if boat.planet_node else Vector3.UP
	var rel_h := (rel - bup * rel.dot(bup)).length()
	out += "  " + tr("CON_DRIFT_WAKE") % [boat.get_wake_points().size(), rel_h, DynamicGridBody.WAKE_MIN_SPEED] + "\n"
	out += "  " + tr("CON_DRIFT_BUOYANCY") % boat.last_wave_samples
	return out


func _get_health() -> Node:
	var player := _get_player()
	if player == null:
		return null
	return player.get("health_component")



const ANIMAL_SCENES := {
	"bear": "res://scenes/animals/Bear.tscn",
	"deer": "res://scenes/animals/Deer.tscn",
	"lion": "res://scenes/animals/Lion.tscn",
	"buffalo": "res://scenes/animals/Buffalo.tscn",
	"wolf": "res://scenes/animals/Wolf.tscn",
	"hind": "res://scenes/animals/Hind.tscn",
	"boar": "res://scenes/animals/Boar.tscn",
	"moose": "res://scenes/animals/Moose.tscn",
	"lynx": "res://scenes/animals/Lynx.tscn",
	"mountain_goat": "res://scenes/animals/MountainGoat.tscn",
	"bighorn": "res://scenes/animals/Bighorn.tscn",
	"puma": "res://scenes/animals/Puma.tscn",
	"lioness": "res://scenes/animals/Lioness.tscn",
	"wildebeest": "res://scenes/animals/Wildebeest.tscn",
	"pronghorn": "res://scenes/animals/Pronghorn.tscn",
	"hyena": "res://scenes/animals/Hyena.tscn",
	"alligator": "res://scenes/animals/Alligator.tscn",
	"donkey": "res://scenes/animals/Donkey.tscn",
	"horse": "res://scenes/animals/Horse.tscn",
	"rhinoceros": "res://scenes/animals/Rhinoceros.tscn",
	"elephant": "res://scenes/animals/Elephant.tscn",
	"mammoth": "res://scenes/animals/Mammoth.tscn",
	"cow": "res://scenes/animals/Cow.tscn",
	"calf": "res://scenes/animals/Calf.tscn",
	"goat": "res://scenes/animals/Goat.tscn",
	"labrador": "res://scenes/animals/Labrador.tscn",
	"bloodhound": "res://scenes/animals/Bloodhound.tscn",
}


func _complete_animals() -> PackedStringArray:
	return PackedStringArray(ANIMAL_SCENES.keys())


## Suelta animales sobre el terreno delante del jugador, repartidos en abanico. Quedan fuera del
## pool de fauna (no se reciclan por distancia) y su cadáver dura dos minutos para despellejarlo.
## Salen como una manada (join_group); una palabra que no sea número es la variante para todos.
func _cmd_spawn(args: PackedStringArray) -> String:
	var player := _get_player() as PlayerController
	if player == null or player.planet == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER_PLANET"))
	var kind := args[0].to_lower()
	if not ANIMAL_SCENES.has(kind):
		return _paint(COLOR_ERR, tr("CON_UNKNOWN_ANIMAL") % [kind, ", ".join(ANIMAL_SCENES.keys())])
	var numbers: Array[String] = []
	var variant_id := ""
	for arg in args.slice(1):
		if arg.is_valid_float():
			numbers.append(arg)
		else:
			variant_id = arg.to_lower()
	var count := clampi(numbers[0].to_int(), 1, 12) if numbers.size() >= 1 and numbers[0].is_valid_int() else 1
	var distance := clampf(numbers[1].to_float(), 3.0, 80.0) if numbers.size() >= 2 else 14.0
	var scene: PackedScene = load(ANIMAL_SCENES[kind])
	var up := -player.gravity_direction.normalized()
	var forward := -player.camera.global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	var side := up.cross(forward)
	var space := player.get_world_3d().direct_space_state
	var placed := 0
	var leader: NPCController = null
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
		if leader == null:
			leader = animal
		else:
			animal.join_group(leader)
		if variant_id != "":
			var known: Array[String] = []
			for v in animal.variants:
				known.append(String(v.id))
				if String(v.id) == variant_id:
					animal.apply_variant(v, randf_range(v.size.x, v.size.y))
			if not variant_id in known:
				animal.queue_free()
				return _paint(COLOR_ERR, tr("CON_NO_VARIANT") % [kind, variant_id,
					", ".join(known) if not known.is_empty() else tr("CON_NONE")])
		placed += 1
	return _paint(COLOR_OK, tr("CON_SPAWNED") % [placed, kind + (" " + variant_id if variant_id != "" else ""),
		distance])


func _cmd_ai(args: PackedStringArray) -> String:
	var player := _get_player() as Node3D
	if player == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
	var radius := clampf(args[0].to_float(), 5.0, 500.0) if args.size() >= 1 and args[0].is_valid_float() else 80.0
	var found: Array = []
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as NPCController
		if npc == null or not npc.active:
			continue
		var dist := npc.global_position.distance_to(player.global_position)
		if dist <= radius:
			found.append([dist, npc])
	if found.is_empty():
		return _paint(COLOR_MUTED, tr("CON_AI_NONE") % radius)
	found.sort_custom(func(a, b): return a[0] < b[0])
	var lines: Array[String] = []
	for entry in found:
		var npc: NPCController = entry[1]
		var ai := npc.ai_controller
		var line := "[color=%s]%s[/color] %.0f m  %s" % [COLOR_INFO, ("%s %s" % [npc.npc_type, npc.describe_variant()]).strip_edges(),
			entry[0], ai.get_current_state()]
		var state := ai.get_node_or_null(NodePath(ai.get_current_state()))
		if state != null and state.has_method(&"debug_line"):
			line += "  " + state.debug_line()
		lines.append(line)
	return "\n".join(lines)


func _cmd_die(_args: PackedStringArray) -> String:
	var hc := _get_health() as HealthComponent
	if hc == null:
		return _paint(COLOR_ERR, tr("CON_NO_HEALTH"))
	hc.invincible = false
	hc.take_damage(hc.health + 1.0)
	return _paint(COLOR_OK, tr("CON_DIED"))


func _get_combat() -> PlayerCombat:
	var player := _get_player() as PlayerController
	return player.combat if player != null else null


func _cmd_blood(_args: PackedStringArray) -> String:
	var player := _get_player() as Node3D
	if player == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
	return _paint(COLOR_OK, BloodPool.report(player.global_position))


func _cmd_litter(_args: PackedStringArray) -> String:
	var player := _get_player() as Node3D
	if player == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
	return _paint(COLOR_OK, GroundPickup.report(player))


func _cmd_sever(args: PackedStringArray) -> String:
	if not args.is_empty():
		if args[0].to_lower() == "auto":
			BodyDamage.sever_chance = -1.0
		elif args[0].is_valid_float():
			BodyDamage.sever_chance = clampf(args[0].to_float(), 0.0, 1.0)
		else:
			return _paint(COLOR_ERR, tr("CON_USAGE") % "sever [0-1|auto]")
	var chance := BodyDamage.sever_chance
	if chance < 0.0:
		return _paint(COLOR_OK, tr("CON_SEVER_NATURAL"))
	return _paint(COLOR_OK, tr("CON_SEVER_CHANCE") % roundi(chance * 100.0))


## Por dónde corta cada parte: el miembro (BodyDamage) y si es por arriba (el brazo entero desde el
## hombro, la pierna desde el muslo) o por abajo (el antebrazo, la espinilla).
const CUT_PARTS := {"arm": ["arm", true], "forearm": ["arm", false], "thigh": ["leg", true],
	"shin": ["leg", false]}


func _complete_cuts() -> PackedStringArray:
	return PackedStringArray(CUT_PARTS.keys())


func _cmd_cut(args: PackedStringArray) -> String:
	var combat := _get_combat()
	if combat == null or combat.body_damage == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
	var part: String = args[0].to_lower() if args.size() >= 1 else CUT_PARTS.keys().pick_random()
	if not CUT_PARTS.has(part):
		return _paint(COLOR_ERR, tr("CON_CUT_UNKNOWN") % CUT_USAGE)
	var side: String = args[1].to_lower() if args.size() >= 2 else ["left", "right"].pick_random()
	var left := side != "right"
	var zone := StringName(("left_" if left else "right_") + String(CUT_PARTS[part][0]))
	if SettingsManager.gore_level() != SettingsManager.GORE_FULL:
		return _paint(COLOR_ERR, tr("CON_CUT_GORE_OFF"))
	if not combat.body_damage.sever_zone(zone, CUT_PARTS[part][1]):
		return _paint(COLOR_ERR, tr("CON_CUT_ALREADY"))
	return _paint(COLOR_OK, tr("CON_CUT_DONE").format({"part": tr("CON_PART_" + part.to_upper()),
		"side": tr("CON_SIDE_LEFT" if left else "CON_SIDE_RIGHT")}))


func _complete_status() -> PackedStringArray:
	var out := StatusEffectData.ids()
	out.append("remove")
	return out


func _cmd_status(args: PackedStringArray) -> String:
	var combat := _get_combat()
	if combat == null or combat.status == null:
		return _paint(COLOR_ERR, tr("CON_NO_PLAYER"))
	var status := combat.status
	var known := ", ".join(StatusEffectData.ids())
	if args.is_empty():
		if status.effects().is_empty():
			return _paint(COLOR_OK, tr("CON_STATUS_NONE_AVAILABLE") % known)
		var lines := PackedStringArray()
		for effect in status.effects():
			lines.append(tr("CON_STATUS_LINE") % [effect.label(), ceili(effect.remaining), effect.severity])
		return _paint(COLOR_OK, "\n".join(lines))
	if args[0].to_lower() == "remove":
		if args.size() < 2:
			status.restore()
			return _paint(COLOR_OK, tr("CON_STATUS_NONE"))
		if not status.remove(StringName(args[1])):
			return _paint(COLOR_ERR, tr("CON_STATUS_NOT_HAD") % args[1])
		return _paint(COLOR_OK, tr("CON_STATUS_CURED") % args[1])
	var data := StatusEffectData.find(StringName(args[0]))
	if data == null:
		return _paint(COLOR_ERR, tr("CON_STATUS_UNKNOWN") % known)
	var zone := &""
	var seconds := -1.0
	for arg in args.slice(1):
		if arg.is_valid_float():
			seconds = arg.to_float()
		elif arg.to_lower() == "left":
			zone = &"left_leg"
		elif arg.to_lower() == "right":
			zone = &"right_leg"
		elif BodyDamage.ZONES.has(StringName(arg)):
			zone = StringName(arg)
		else:
			return _paint(COLOR_ERR, tr("CON_STATUS_UNKNOWN_ZONE") % [arg, ", ".join(PackedStringArray(BodyDamage.ZONES))])
	if data.per_zone and zone == &"":
		zone = [&"left_leg", &"right_leg"].pick_random()
	var effect := status.apply(data.id, zone, 0.5, seconds)
	if effect == null:
		return _paint(COLOR_ERR, tr("CON_STATUS_FAILED"))
	return _paint(COLOR_OK, "%s: %d s." % [effect.label(), ceili(effect.remaining)])


func _complete_item_ids() -> PackedStringArray:
	config.get_item(&"")
	var ids := PackedStringArray()
	for k in config.items.keys():
		ids.append(str(k))
	return ids

func _complete_weather() -> PackedStringArray:
	var wc := _get_weather()
	var out := PackedStringArray(["reset", "list"])
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
		return _paint(COLOR_ERR, tr("CON_NO_CAMERA"))

	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * DAMAGE_RAY_LEN)
	query.collision_mask = 3
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _paint(COLOR_ERR, tr("CON_AIM_NOTHING") % DAMAGE_RAY_LEN)

	var collider = hit["collider"]
	if not (collider is Node) or not (collider as Node).has_meta("grid_id"):
		return _paint(COLOR_ERR, tr("CON_NOT_A_GRID") % str(collider))

	var grid: GridBase = GridManager.get_grid_for_block(collider as Node3D)
	if grid == null:
		return _paint(COLOR_ERR, tr("CON_GRID_UNREGISTERED") % (collider as Node).get_meta("grid_id"))

	# El punto de impacto cae JUSTO en la cara del bloque: hay que entrar un poco o world_to_cell
	# devuelve la celda vecina, que suele estar vacía.
	var point: Vector3 = hit["position"] + dir * (grid.cell_size * 0.25)
	var cell := grid.world_to_cell(point)
	if not grid.has_block(cell):
		return _paint(COLOR_ERR, tr("CON_NO_BLOCK") % [str(cell), grid.grid_id])

	if args.is_empty():
		return _damage_report(grid, cell)

	if not args[0].is_valid_float():
		return _paint(COLOR_ERR, tr("CON_USAGE") % "damage [joules]")

	var energy := maxf(args[0].to_float(), 0.0)
	grid.begin_batch_edit()
	var result: Dictionary = grid.damage_sphere(point, energy)
	grid.end_batch_edit()

	var destroyed: int = (result["destroyed"] as Array).size()
	var out := _paint(COLOR_OK, tr("CON_DAMAGE_DONE") % [energy, grid.grid_id, str(cell), destroyed,
		int(result.get("damaged", 0)), result["spent"]])
	if grid.has_block(cell):
		out += "\n" + _damage_report(grid, cell)
	return out


## Vida del bloque de una celda, con el escalón visual que le corresponde.
func _damage_report(grid: GridBase, cell: Vector3i) -> String:
	var info := grid.get_block(cell)
	var block_id: int = info["block_id"]
	var hp: float = info.get("hp", 1.0)
	var full := grid.impact_cost(block_id)
	return _paint(COLOR_INFO, tr("CON_DAMAGE_REPORT") % [grid.grid_id, str(cell), block_id, hp * 100.0, hp * full, full,
		ChunkMeshBuilder.damage_step(hp), ChunkMeshBuilder.DAMAGE_STEPS])


## Por qué NO se está retirando cada resto. Las cinco condiciones se evalúan juntas dentro de
## _update_derelict y desde fuera son indistinguibles entre sí: aquí van una a una.
## Por qué una especie no aparece: cuántos hay vivos, cuántos caben y en qué filtro se cae cada
## candidato. Sin esto, un spawn que no cuaja solo se puede diagnosticar dando vueltas por el mapa.
func _cmd_fauna(_args: PackedStringArray) -> String:
	var spawners := get_tree().get_nodes_in_group(AmbientFaunaSpawner.GROUP)
	if spawners.is_empty():
		return _paint(COLOR_ERR, tr("CON_NO_SPAWNERS"))
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
		lines.append("%s  %s" % [_paint(COLOR_INFO, spawner.name), tr("CON_FAUNA_LINE") % [alive,
			mini(spawner.target_population(), roundi(spawner.target_population() * activity)),
			roundi(activity * 100.0), spawner._pool.size(), spawner.profile.spawn_radius]])
		var ground := spawner.habitat as GroundFaunaHabitat
		if ground == null:
			continue
		lines.append("[color=%s]   %s[/color]" % [COLOR_MUTED, ground.report()])
	return "
".join(lines)


func _cmd_derelicts(_args: PackedStringArray) -> String:
	var bodies := get_tree().get_nodes_in_group("dynamic_grid_body")
	if bodies.is_empty():
		return _paint(COLOR_MUTED, tr("CON_NO_DYNAMIC"))

	var out := _paint(COLOR_INFO, tr("CON_DERELICTS_TITLE") % [DynamicGridBody.DERELICT_MAX_BLOCKS,
		DynamicGridBody.DERELICT_SPEED, DynamicGridBody.DERELICT_DISTANCE, DynamicGridBody.DERELICT_SETTLE_TIME]) + "\n"

	for node in bodies:
		var body := node as DynamicGridBody
		var st: Dictionary = body.get_derelict_state()
		var gates := [
			_gate(tr("CON_GATE_SPLIT"), st["from_split"]),
			_gate(tr("CON_GATE_NO_PILOT"), not st["controlled"]),
			_gate(tr("CON_GATE_SIZE") % st["blocks"], int(st["blocks"]) <= DynamicGridBody.DERELICT_MAX_BLOCKS),
			_gate(tr("CON_GATE_STILL") % [st["speed"], st["spin"]],
				st["speed"] < DynamicGridBody.DERELICT_SPEED and st["spin"] < DynamicGridBody.DERELICT_SPEED),
			_gate(tr("CON_GATE_FAR") % st["distance"], st["distance"] > DynamicGridBody.DERELICT_DISTANCE),
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
		return _paint(COLOR_ERR, tr("CON_NO_CAMERA"))

	var reach := DAMAGE_RAY_LEN
	if not args.is_empty() and args[0].is_valid_float():
		reach = maxf(args[0].to_float(), 1.0)

	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	query.collision_mask = 3
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _paint(COLOR_ERR, tr("CON_AIM_NOTHING") % reach + " " + tr("CON_ANCHORS_TRY_DISTANCE"))

	# Decir QUÉ se golpeó, no solo que no servía: apuntando a un casco enterrado lo normal es
	# llevarse el terreno por delante, y "eso no es una grid" a secas no lo distingue de un árbol.
	var collider = hit["collider"]
	var what := "null"
	if collider is Node:
		what = "%s '%s'" % [(collider as Node).get_class(), (collider as Node).name]
	var dist: float = from.distance_to(hit["position"])

	if not (collider is Node) or not (collider as Node).has_meta("grid_id"):
		return _paint(COLOR_ERR, tr("CON_ANCHORS_HIT_NOT_GRID") % [dist, what])

	var aimed := GridManager.get_grid_for_block(collider as Node3D)
	if aimed == null:
		return _paint(COLOR_ERR, tr("CON_ANCHORS_UNREGISTERED") % [what, (collider as Node).get_meta("grid_id")])
	if not (aimed is PlanetGrid):
		return _paint(COLOR_ERR, tr("CON_ANCHORS_DYNAMIC") % aimed.grid_id)

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
	var lines := PackedStringArray([
		tr("CON_ANCHORS_TITLE") % [aimed.grid_id, group.size(), blocks],
		"  " + tr("CON_ANCHORS_ANCHORED") % [anchored, probe_usec / 1000.0]
			+ ("" if probe_ok else " · " + tr("CON_ANCHORS_NO_TERRAIN_QUERY")),
		"  " + tr("CON_ANCHORS_WOULD_FALL") % [would_fall, GridManager.COLLAPSE_SPAN_PER_ANCHOR,
			GridManager.COLLAPSE_MIN_SPAN, PlanetGrid.ANCHOR_PROBE],
	])
	var out := _paint(color, "\n".join(lines))
	if anchored == 0 and probe_ok and not group.is_empty():
		out += "\n" + _paint(COLOR_MUTED, tr("CON_ANCHORS_SAMPLE") + "\n" + (group[0] as PlanetGrid).debug_anchor_sample())
	return out
