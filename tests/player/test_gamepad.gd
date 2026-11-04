extends Node3D

class TestAdapter extends "res://scripts/autoload/gamepad.gd":
	# DisplayServerHeadless no captura el ratón. Solo se sustituye esa dependencia;
	# eventos, acciones, orden de _input y GUI pasan por el motor de verdad.
	var ui_open := false
	func ui_is_open() -> bool:
		return ui_open

## Eventos por el árbol real: prioridad del adaptador, zona muerta, movimiento proporcional,
## gatillos sin repetición, rueda, cursor y compatibilidad con reasignaciones de teclado.
const DEVICE := 7
var failures := 0
var checks := 0
var attacks := 0
var releases := 0
var uses := 0
var cancels := 0
var clicks := 0
var raw_buttons := 0
var mouse_releases := 0
var adapter: TestAdapter


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack_1"):
		attacks += 1
	if event.is_action_released("attack_1"):
		releases += 1
	if event.is_action_pressed("action"):
		uses += 1
	if event.is_action_pressed("ui_cancel"):
		cancels += 1
	if event is InputEventJoypadButton:
		raw_buttons += 1
	if event is InputEventMouseButton and not event.pressed:
		mouse_releases += 1


func _button(button: JoyButton, pressed := true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _run() -> void:
	await get_tree().process_frame
	Gamepad.set_process_input(false)
	Gamepad.set_process(false)
	adapter = TestAdapter.new()
	get_tree().root.add_child(adapter)
	adapter.set_process(false)
	await get_tree().process_frame
	GameManager.current_state = GameManager.State.PLAYING
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	check(get_tree().root.get_child(-1) == adapter, "el adaptador recibe el mando antes que la escena")
	_button(JOY_BUTTON_X)
	check(uses == 1 and Input.is_action_pressed("action"), "X comparte la acción de usar del teclado")
	_button(JOY_BUTTON_X, false)
	check(not Input.is_action_pressed("action"), "soltar X libera la acción")
	var previous_cancel := cancels
	_button(JOY_BUTTON_B)
	check(Input.is_action_pressed("dodge") and cancels == previous_cancel,
		"B en partida esquiva sin abrir la pausa de ui_cancel")
	_button(JOY_BUTTON_B, false)
	await _movement()
	_triggers()
	await _radial()
	await _cursor()
	_bindings()
	adapter._on_connection_changed(DEVICE, false)
	check(adapter.active_device != DEVICE and (adapter.active_device < 0 \
		or Input.get_connected_joypads().has(adapter.active_device)),
		"desconectar deja otro mando conectado o desactiva el cursor")
	print("GAMEPAD: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _movement() -> void:
	var movement := Movement.new()
	var camera := Camera3D.new()
	add_child(camera)
	_axis(JOY_AXIS_LEFT_X, 0.1)
	check(movement.get_input_direction(camera, Vector3.DOWN).is_zero_approx(), "la zona muerta elimina la deriva")
	_axis(JOY_AXIS_LEFT_X, 0.6)
	var half := movement.get_input_direction(camera, Vector3.DOWN)
	check(is_equal_approx(half.length(), 0.5) and half.x > 0.0, "medio stick produce media velocidad")
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	check(is_equal_approx(movement.get_input_direction(camera, Vector3.DOWN).length(), 1.0),
		"la diagonal no supera la velocidad máxima")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	Input.action_press("move_forward")
	check(movement.get_input_direction(camera, Vector3.DOWN).is_equal_approx(Vector3.FORWARD),
		"el teclado conserva dirección y velocidad completas")
	Input.action_release("move_forward")
	movement.use_ai_input = true
	movement.ai_direction = Vector3(0.2, 0.0, 0.3)
	check(movement.get_input_direction(camera, Vector3.DOWN) == movement.ai_direction, "la IA conserva su entrada")
	movement.free()
	camera.queue_free()
	await get_tree().process_frame


func _triggers() -> void:
	attacks = 0
	releases = 0
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.1)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.3)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.7)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	check(attacks == 1 and Input.is_action_pressed("attack_1"), "el gatillo mantenido inicia una sola carga")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.6)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(releases == 1 and not Input.is_action_pressed("attack_1"), "soltar el gatillo termina la carga una sola vez")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.4)
	check(attacks == 2, "el gatillo vuelve a responder en la siguiente pulsación")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)


func _radial() -> void:
	var radial := BuildRadialMenu.new()
	add_child(radial)
	var chosen: Array = []
	radial.option_chosen.connect(func(option: BuildRadialMenu.Option) -> void: chosen.append(option))
	radial.open(BuildRadialMenu.Option.ADD, null)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	check(radial._hovered == 0, "el stick derecho apunta a añadir en la rueda")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(not radial.is_open() and chosen == [BuildRadialMenu.Option.ADD], "soltar LT confirma la opción")
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	radial.open(BuildRadialMenu.Option.ADD, null)
	_button(JOY_BUTTON_B)
	check(not radial.is_open() and chosen.size() == 1, "B cancela la rueda sin elegir")
	_button(JOY_BUTTON_B, false)
	radial.queue_free()
	await get_tree().process_frame


func _cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	adapter.ui_open = true
	adapter._process(0.0)
	var target := Button.new()
	target.position = Vector2.ZERO
	target.size = Vector2(200, 100)
	target.pressed.connect(func() -> void: clicks += 1)
	add_child(target)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(80, 60)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var previous_raw := raw_buttons
	var previous_use := uses
	_button(JOY_BUTTON_A)
	_button(JOY_BUTTON_A, false)
	check(clicks == 1, "A activa el botón de la interfaz una sola vez")
	check(raw_buttons == previous_raw, "la interfaz no filtra botones del mando al jugador")
	_button(JOY_BUTTON_X)
	_button(JOY_BUTTON_X, false)
	check(uses == previous_use, "X en la interfaz no ejecuta usar en el mundo")
	var previous_cancel := cancels
	_button(JOY_BUTTON_B)
	_button(JOY_BUTTON_B, false)
	check(cancels == previous_cancel + 1, "B cierra por ui_cancel sin esquivar")
	var before_release := mouse_releases
	_button(JOY_BUTTON_A)
	adapter._on_connection_changed(DEVICE, false)
	Input.flush_buffered_events()
	check(adapter._mouse_buttons.is_empty() and mouse_releases > before_release,
		"desconectar mientras se arrastra suelta el clic virtual")
	_button(JOY_BUTTON_A, false)
	target.queue_free()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	adapter.ui_open = false
	adapter._process(0.0)
	await get_tree().process_frame


func _bindings() -> void:
	var before := SettingsManager._values.duplicate(true)
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_U
	SettingsManager._values["controls/bindings"] = {"action": [{"key": KEY_U}]}
	Settings._apply_bindings()
	_button(JOY_BUTTON_X)
	check(Input.is_action_pressed("action"), "reasignar teclado conserva X del mando")
	_button(JOY_BUTTON_X, false)
	check(InputMap.action_has_event("action", rebound), "la tecla nueva se aplica")
	SettingsManager._values["controls/gamepad_deadzone"] = 0.4
	Gamepad._apply_deadzone()
	_axis(JOY_AXIS_LEFT_X, 0.3)
	check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").is_zero_approx(),
		"cambiar la zona muerta se aplica al movimiento")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	SettingsManager._values = before
	Settings._apply_bindings()
	Gamepad._apply_deadzone()
