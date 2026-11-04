extends Node

## Mando estándar de Godot (Xbox, PlayStation y compatibles). Las acciones del juego siguen
## compartidas con teclado/ratón; en las ventanas el stick izquierdo lleva el cursor existente.
const BUTTONS := {
	&"jump": JOY_BUTTON_A, &"dodge": JOY_BUTTON_B, &"action": JOY_BUTTON_X,
	&"inventory": JOY_BUTTON_Y, &"crouch": JOY_BUTTON_LEFT_SHOULDER,
	&"character_window": JOY_BUTTON_RIGHT_SHOULDER, &"Sprint": JOY_BUTTON_LEFT_STICK,
	&"lock_on": JOY_BUTTON_RIGHT_STICK, &"world_map": JOY_BUTTON_BACK,
	&"ui_cancel": JOY_BUTTON_START, &"open_build_menu": JOY_BUTTON_DPAD_UP,
	&"crafting": JOY_BUTTON_DPAD_DOWN, &"hotbar_previous": JOY_BUTTON_DPAD_LEFT,
	&"hotbar_next": JOY_BUTTON_DPAD_RIGHT,
}
const AXES := {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0], &"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_forward": [JOY_AXIS_LEFT_Y, -1.0], &"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	&"look_left": [JOY_AXIS_RIGHT_X, -1.0], &"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	&"look_up": [JOY_AXIS_RIGHT_Y, -1.0], &"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	&"attack_1": [JOY_AXIS_TRIGGER_RIGHT, 1.0], &"attack_2": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}
const STICK_ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back",
	&"look_left", &"look_right", &"look_up", &"look_down"]
const VIRTUAL_DEVICE := -3
const CURSOR_SPEED := 1000.0
const SCROLL_INTERVAL := 0.10

var active_device := -1
var _trigger_down: Dictionary = {}
var _mouse_buttons: Dictionary = {}
var _scroll_time := 0.0
var _ui_was_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# _input recorre el árbol al revés. El adaptador debe consumir el mando de la GUI
	# antes de que llegue al jugador, incluso después de cambiar de escena.
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)
	_prioritize_input.call_deferred()
	# Godot trae B ligado a ui_cancel. En partida es esquivar; solo lo convertimos
	# en cancelar cuando hay una ventana abierta, para que no abra la pausa al esquivar.
	for event in InputMap.action_get_events(&"ui_cancel"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B:
			InputMap.action_erase_event(&"ui_cancel", event)
	for action: StringName in BUTTONS:
		_ensure_action(action)
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = BUTTONS[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	for action: StringName in AXES:
		_ensure_action(action)
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = AXES[action][0]
		event.axis_value = AXES[action][1]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	_apply_deadzone()
	Settings.changed.connect(_on_setting_changed)
	Input.joy_connection_changed.connect(_on_connection_changed)
	var devices := Input.get_connected_joypads()
	if not devices.is_empty():
		active_device = devices[0]


func _on_root_child_entered(_node: Node) -> void:
	_prioritize_input.call_deferred()


func _prioritize_input() -> void:
	get_tree().root.move_child(self, -1)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _apply_deadzone() -> void:
	var deadzone := clampf(float(SettingsManager.value("controls/gamepad_deadzone")), 0.1, 0.5)
	for action in STICK_ACTIONS:
		InputMap.action_set_deadzone(action, deadzone)


func _on_setting_changed(key: String) -> void:
	if key == "controls/gamepad_deadzone":
		_apply_deadzone()


func _on_connection_changed(device: int, connected: bool) -> void:
	if connected and active_device < 0:
		active_device = device
	elif not connected and device == active_device:
		_release_mouse_buttons()
		_trigger_down.clear()
		var devices := Input.get_connected_joypads()
		devices.erase(device)
		active_device = devices[0] if not devices.is_empty() else -1


func ui_is_open() -> bool:
	return Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event is InputEventJoypadButton or absf(event.axis_value) > 0.2:
		active_device = event.device
	# Un gatillo emite muchos valores al apretarlo: el juego recibe solo el cruce de la
	# zona muerta y su liberación, para no reiniciar la carga ni repetir el golpe.
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		var key := Vector2i(event.device, event.axis)
		var down: bool = event.axis_value >= 0.2
		if down == bool(_trigger_down.get(key, false)):
			get_viewport().set_input_as_handled()
			return
		_trigger_down[key] = down
	if not ui_is_open():
		return
	# Consume también los ui_accept/direcciones que Godot trae por defecto: el clic virtual
	# es el único que activa la GUI, aunque un botón conservara el foco del teclado.
	get_viewport().set_input_as_handled()
	if event is not InputEventJoypadButton:
		return
	match event.button_index:
		JOY_BUTTON_A:
			_mouse_button(MOUSE_BUTTON_LEFT, event.pressed)
		JOY_BUTTON_X:
			_mouse_button(MOUSE_BUTTON_RIGHT, event.pressed)
		JOY_BUTTON_B, JOY_BUTTON_START:
			if event.pressed:
				_send_action(&"ui_cancel")
		JOY_BUTTON_Y:
			if event.pressed:
				_send_action(&"inventory")
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			if event.pressed:
				_scroll(-1.0 if event.button_index == JOY_BUTTON_DPAD_UP else 1.0)


func _process(delta: float) -> void:
	var ui := ui_is_open()
	if ui != _ui_was_open:
		_release_mouse_buttons()
		_scroll_time = 0.0
		_ui_was_open = ui
	if not ui or active_device < 0:
		return
	var stick := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if not stick.is_zero_approx():
		var viewport := get_viewport()
		var old := viewport.get_mouse_position()
		var bounds := viewport.get_visible_rect()
		var scale := bounds.size.y / 1440.0
		var position := (old + stick * CURSOR_SPEED * scale * delta).clamp(bounds.position, bounds.end - Vector2.ONE)
		viewport.warp_mouse(position)
		var motion := InputEventMouseMotion.new()
		motion.device = VIRTUAL_DEVICE
		motion.position = position
		motion.global_position = position
		motion.relative = position - old
		motion.screen_relative = motion.relative
		motion.button_mask = _button_mask()
		Input.parse_input_event(motion)
	_scroll_time -= delta
	var scroll := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).y
	if absf(scroll) > 0.1 and _scroll_time <= 0.0:
		_scroll(signf(scroll))
		_scroll_time = SCROLL_INTERVAL


func _stick(x: JoyAxis, y: JoyAxis) -> Vector2:
	var raw := Vector2(Input.get_joy_axis(active_device, x), Input.get_joy_axis(active_device, y))
	var deadzone := clampf(float(SettingsManager.value("controls/gamepad_deadzone")), 0.1, 0.5)
	return raw.normalized() * clampf((raw.length() - deadzone) / (1.0 - deadzone), 0.0, 1.0)


func _send_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event(release)


func _button_mask() -> int:
	var mask := 0
	for button: int in _mouse_buttons:
		mask |= 1 << (button - 1)
	return mask


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	if pressed:
		_mouse_buttons[button] = true
	else:
		if not _mouse_buttons.has(button):
			return
		_mouse_buttons.erase(button)
	var event := InputEventMouseButton.new()
	event.device = VIRTUAL_DEVICE
	event.button_index = button
	event.pressed = pressed
	event.position = get_viewport().get_mouse_position()
	event.global_position = event.position
	event.button_mask = _button_mask()
	event.shift_pressed = active_device >= 0 and Input.is_joy_button_pressed(active_device, JOY_BUTTON_LEFT_SHOULDER)
	Input.parse_input_event(event)


func _release_mouse_buttons() -> void:
	for button: int in _mouse_buttons.keys():
		_mouse_button(button as MouseButton, false)


func _scroll(direction: float) -> void:
	var button := MOUSE_BUTTON_WHEEL_DOWN if direction > 0.0 else MOUSE_BUTTON_WHEEL_UP
	_mouse_button(button, true)
	_mouse_button(button, false)
