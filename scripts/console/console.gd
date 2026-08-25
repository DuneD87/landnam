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
	for grid: PlanetGrid in group:
		grids_data.append({"cells": grid.get_all_blocks().keys(), "cell_size": grid.cell_size})
		var t0 := Time.get_ticks_usec()
		var found := grid.compute_anchor_cells()
		probe_usec += Time.get_ticks_usec() - t0
		anchors.append(found)
		blocks += grid.get_block_count()
		anchored += found.size()

	var falling := GridSplitAnalyzer.analyze_support(grids_data, anchors,
		GridManager.COLLAPSE_MIN_SPAN, GridManager.COLLAPSE_SPAN_FRACTION)
	var would_fall := 0
	for piece: Dictionary in falling:
		would_fall += int(piece["count"])

	var color := COLOR_OK if anchored > 0 and would_fall == 0 else COLOR_ERR
	var out := "[color=%s]'%s' · %d grids · %d bloques\n" % [color, aimed.grid_id, group.size(), blocks]
	out += "  apoyados en el suelo: %d   (sondeo %.1f ms)\n" % [anchored, probe_usec / 1000.0]
	out += "  se caerían ahora: %d   (alcance = lado mayor x %.2f, mínimo %d · sondeo %.1f m)[/color]" % [
		would_fall, GridManager.COLLAPSE_SPAN_FRACTION, GridManager.COLLAPSE_MIN_SPAN,
		PlanetGrid.ANCHOR_PROBE]
	if anchored == 0 and not group.is_empty():
		out += "\n[color=%s]sin un solo apoyo; muestra en crudo del sondeo:\n%s[/color]" % [
			COLOR_MUTED, (group[0] as PlanetGrid).debug_anchor_sample()]
	return out
