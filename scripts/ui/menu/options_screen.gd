class_name OptionsScreen
extends CanvasLayer

## Pantalla de opciones (pantalla, gráficos, audio y controles). Se abre desde el menú principal,
## que en partida hace de menú de pausa. Los cambios se aplican al momento para poder verlos;
## "Aceptar" (o Escape) los guarda y "Cancelar" deja todo como estaba al abrir. Los cambios de
## ventana piden confirmación y se deshacen solos si no llega, por si la dejan inservible.

signal closed

const TABS: Array[String] = ["Pantalla", "Gráficos", "Audio", "Controles", "Juego"]
## Prefijo de las claves de SettingsManager de cada pestaña, para "Restablecer".
const TAB_PREFIXES: Array[String] = ["display/", "graphics/", "audio/", "controls/", "game/"]
const CONFIRM_SECONDS := 10.0
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const MAX_FPS_OPTIONS: Array[int] = [0, 30, 60, 90, 120, 144, 165, 240]
const AUDIO_LABELS := {&"Master": "General", &"Music": "Música", &"SFX": "Efectos", &"Ambient": "Ambiente",
	&"UI": "Interfaz", &"Voice": "Voces"}
const PRESET_NAMES: Array[String] = ["Bajo", "Medio", "Alto", "Ultra"]

static var _open_count := 0

var _ui_scale := 1.0
var _snapshot: Dictionary
var _tab_buttons: Array[Button] = []
var _current_tab := 0
var _scroll: ScrollContainer
var _page: VBoxContainer
var _notice: Label
var _preset_button: OptionButton
var _scale_label: Label
## Reasignación en curso: {"action", "slot", "button"}.
var _capture: Dictionary = {}
var _confirm: Control
var _confirm_label: Label
var _confirm_left := 0.0
var _display_before: Dictionary = {}


static func is_open() -> bool:
	return _open_count > 0


func _enter_tree() -> void:
	_open_count += 1


func _exit_tree() -> void:
	_open_count -= 1


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_scale = clampf(get_viewport().get_visible_rect().size.y / 1440.0, 0.5, 2.0)
	_snapshot = Settings.snapshot()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = _build_theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var viewport_size := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(_px(1500), viewport_size.x - _px(64)),
		minf(_px(1200), viewport_size.y - _px(64)))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(_px(18)))
	panel.add_child(column)
	column.add_child(_build_header())
	column.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_notice = Label.new()
	_notice.theme_type_variation = "ValueLabel"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_notice)
	column.add_child(_build_footer())
	_build_confirm(root)

	Settings.changed.connect(_on_setting_changed)
	_show_tab(0)
	_refresh_notice()


func _process(delta: float) -> void:
	if _confirm == null or not _confirm.visible:
		return
	_confirm_left -= delta
	if _confirm_left <= 0.0:
		_revert_display()
	else:
		_confirm_label.text = "¿Mantener esta configuración de pantalla?\nSe deshace en %d s." % ceili(_confirm_left)


func _input(event: InputEvent) -> void:
	if not _capture.is_empty():
		_capture_input(event)
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm.visible:
			_revert_display()
		else:
			_on_accept()


# --- Estructura ---------------------------------------------------------------------------------

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", roundi(_px(12)))
	var title := Label.new()
	title.text = "OPCIONES"
	title.theme_type_variation = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var tab := Button.new()
		tab.text = TABS[i]
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(_px(190), _px(64))
		tab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tab.pressed.connect(_show_tab.bind(i))
		header.add_child(tab)
		_tab_buttons.append(tab)
	return header


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", roundi(_px(20)))
	var reset := Button.new()
	reset.text = "Restablecer pestaña"
	reset.custom_minimum_size = Vector2(_px(300), _px(68))
	reset.pressed.connect(_on_reset_tab)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.custom_minimum_size = Vector2(_px(240), _px(68))
	cancel.pressed.connect(_on_cancel)
	footer.add_child(cancel)
	var accept := Button.new()
	accept.text = "Aceptar"
	accept.theme_type_variation = "AccentButton"
	accept.custom_minimum_size = Vector2(_px(280), _px(68))
	accept.pressed.connect(_on_accept)
	footer.add_child(accept)
	return footer


func _build_confirm(root: Control) -> void:
	_confirm = ColorRect.new()
	(_confirm as ColorRect).color = Color(0, 0, 0, 0.55)
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	root.add_child(_confirm)
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(_px(24)))
	box.add_child(column)
	_confirm_label = Label.new()
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_confirm_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", roundi(_px(20)))
	var revert := Button.new()
	revert.text = "Deshacer"
	revert.custom_minimum_size = Vector2(_px(240), _px(64))
	revert.pressed.connect(_revert_display)
	buttons.add_child(revert)
	var keep := Button.new()
	keep.text = "Mantener"
	keep.theme_type_variation = "AccentButton"
	keep.custom_minimum_size = Vector2(_px(240), _px(64))
	keep.pressed.connect(func() -> void: _confirm.visible = false)
	buttons.add_child(keep)
	column.add_child(buttons)


func _show_tab(index: int) -> void:
	_cancel_capture()
	var scroll_position := _scroll.scroll_vertical if index == _current_tab else 0
	_current_tab = index
	_tab_buttons[index].button_pressed = true
	if _page != null:
		_scroll.remove_child(_page)
		_page.queue_free()
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", roundi(_px(14)))
	_preset_button = null
	_scale_label = null
	match index:
		0: _build_display_page()
		1: _build_graphics_page()
		2: _build_audio_page()
		3: _build_controls_page()
		4: _build_game_page()
	_scroll.add_child(_page)
	# El ScrollContainer recalcula su rango al siguiente frame.
	_scroll.set_deferred("scroll_vertical", scroll_position)


# --- Páginas ------------------------------------------------------------------------------------

func _build_display_page() -> void:
	var mode := _choice_control("display/window_mode", ["Ventana", "Pantalla completa", "Pantalla completa exclusiva"],
		func(i: int) -> void: _change_display("display/window_mode", i))
	_row("Modo de ventana", mode, "La exclusiva puede dar algo más de rendimiento; la otra cambia de ventana más rápido.")

	var resolution := OptionButton.new()
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var current: Vector2i = SettingsManager.value("display/resolution")
	var sizes: Array[Vector2i] = [Vector2i.ZERO]
	resolution.add_item("La del proyecto")
	for size in RESOLUTIONS:
		if size.x <= screen_size.x and size.y <= screen_size.y:
			sizes.append(size)
			resolution.add_item("%d × %d" % [size.x, size.y])
	if not sizes.has(current):
		sizes.append(current)
		resolution.add_item("%d × %d" % [current.x, current.y])
	resolution.select(sizes.find(current))
	resolution.disabled = SettingsManager.level("display/window_mode", 3) != SettingsManager.WindowMode.WINDOWED
	resolution.item_selected.connect(func(i: int) -> void: _change_display("display/resolution", sizes[i]))
	_row("Tamaño de la ventana", resolution, "Solo en modo ventana. En pantalla completa la resolución es la del monitor: para ganar rendimiento baja la escala de render en Gráficos.")

	_row("Sincronización vertical", _choice_control("display/vsync", ["Desactivada", "Activada", "Adaptativa"]),
		"Evita el tearing a cambio de algo de latencia. La adaptativa solo sincroniza cuando el juego va sobrado.")

	var fps := OptionButton.new()
	for limit in MAX_FPS_OPTIONS:
		fps.add_item("Sin límite" if limit == 0 else "%d FPS" % limit)
	var fps_index := MAX_FPS_OPTIONS.find(int(SettingsManager.value("display/max_fps")))
	fps.select(maxi(fps_index, 0))
	fps.item_selected.connect(func(i: int) -> void: Settings.set_value("display/max_fps", MAX_FPS_OPTIONS[i]))
	_row("Límite de FPS", fps, "Limitar los FPS reduce el calor y el ruido del equipo y suaviza los tirones.")


func _build_graphics_page() -> void:
	_preset_button = OptionButton.new()
	for preset_name in PRESET_NAMES:
		_preset_button.add_item(preset_name)
	_preset_button.add_item("Personalizado")
	_preset_button.set_item_disabled(PRESET_NAMES.size(), true)
	_preset_button.item_selected.connect(_on_preset_selected)
	_sync_preset()
	_row("Calidad general", _preset_button, "Ajusta todo lo de abajo de una vez. En un equipo antiguo empieza por Bajo.")

	_section("Imagen")
	var scale_slider := _slider_control("graphics/render_scale", 0.5, 1.0, 0.05)
	_scale_label = scale_slider.get_meta(&"value_label")
	_row("Escala de render", scale_slider, "Resolución a la que se dibuja el mundo 3D; la interfaz no cambia. Es lo que más rendimiento da.")
	_row("Reescalado", _choice_control("graphics/upscaler", ["Bilineal", "AMD FSR 1.0", "AMD FSR 2.2"]),
		"Cómo se amplía la imagen cuando la escala es menor de 100 %. FSR 2.2 se ve mejor pero cuesta más.")
	_row("Antialiasing", _choice_control("graphics/antialiasing", ["Desactivado", "FXAA", "MSAA 2x", "MSAA 4x", "TAA"]),
		"FXAA es casi gratis; MSAA es más nítido y más caro.")

	_section("Sombras")
	_row("Calidad de las sombras", _choice_control("graphics/shadow_quality", ["Desactivadas", "Baja", "Media", "Alta", "Ultra"]))
	_row("Distancia de las sombras", _choice_control("graphics/shadow_distance", ["Corta", "Media", "Larga"]))
	_row("Sombras de la vegetación", _choice_control("graphics/vegetation_shadows", ["Desactivadas", "Solo cercanas", "Todas"]),
		"", true)

	_section("Cielo y efectos")
	_row("Calidad de la atmósfera", _choice_control("graphics/atmosphere_quality", ["Baja", "Media", "Alta"]),
		"Nitidez del cielo y rayos de luz. Las nubes y la niebla conservan su resolución.")
	_row("Nubes", _choice_control("graphics/clouds", ["Desactivadas", "Bajas", "Medias", "Altas"]))
	_row("Rayos de luz", _toggle_control("graphics/god_rays"), "Haces de sol entre nubes y árboles.")
	_row("Resplandor", _toggle_control("graphics/glow"))
	_row("Oclusión ambiental", _toggle_control("graphics/ssao"), "Oscurece rincones y contactos. Cara en equipos antiguos.")
	_row("Partículas del clima", _choice_control("graphics/weather_particles", ["Pocas", "Normales", "Muchas"]))
	_row("Fauna", _choice_control("graphics/fauna", ["Poca", "Normal", "Mucha"]))

	_section("Mundo")
	_row("Detalle del terreno lejano", _choice_control("graphics/terrain_detail", ["Bajo", "Medio", "Alto", "Ultra"]),
		"Hasta dónde llega el terreno detallado. Pesa en CPU y GPU.", true)
	_row("Relieve fino del terreno", _toggle_control("graphics/terrain_normalmaps"),
		"Mapas de normales del terreno lejano. Apagarlo aligera la CPU.", true)
	_row("Material del terreno", _choice_control("graphics/terrain_material", ["Bajo", "Medio", "Alto"]),
		"Detalle de las texturas y profundidad del relieve cercano. Pesa en GPU.", true)
	_row("Densidad de la hierba", _choice_control("graphics/grass_density", ["Baja", "Media", "Alta"]), "", true)
	_row("Distancia de la hierba", _choice_control("graphics/grass_distance", ["Corta", "Media", "Larga"]), "", true)
	_row("Bosque lejano", _choice_control("graphics/forest_distance", ["Cercano", "Medio", "Hasta el horizonte"]), "", true)
	_update_scale_label()


func _build_audio_page() -> void:
	for bus in SettingsManager.AUDIO_BUSES:
		_row(AUDIO_LABELS.get(bus, String(bus)), _slider_control("audio/%s" % bus, 0.0, 1.0, 0.01))


func _build_game_page() -> void:
	_row("Sangre y mutilaciones", _choice_control("game/gore", ["Sin sangre", "Solo sangre", "Completo"]),
		"Completo: un tajo fuerte puede cercenar un brazo o una pierna.")


func _build_controls_page() -> void:
	_row("Sensibilidad del ratón", _slider_control("controls/mouse_sensitivity",
		SettingsManager.MIN_MOUSE_SENSITIVITY, SettingsManager.MAX_MOUSE_SENSITIVITY, 0.05))
	_row("Invertir eje vertical", _toggle_control("controls/invert_y"))
	var hint := Label.new()
	hint.text = "Haz clic en una tecla para cambiarla y pulsa la nueva (Escape cancela). Clic derecho la borra."
	hint.theme_type_variation = "HintLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(hint)
	for group in SettingsManager.REBINDABLE_ACTIONS:
		_section(group[0])
		for entry in group[1]:
			var action: StringName = entry[0]
			if not InputMap.has_action(action):
				continue
			var slots := HBoxContainer.new()
			slots.add_theme_constant_override("separation", roundi(_px(12)))
			for slot in 2:
				slots.add_child(_binding_button(action, slot))
			_row(entry[1], slots)


# --- Controles de fila --------------------------------------------------------------------------

func _section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.theme_type_variation = "SectionLabel"
	var spacer := Control.new()
	spacer.custom_minimum_size.y = _px(10)
	_page.add_child(spacer)
	_page.add_child(label)


## Fila: nombre (con su explicación debajo) a la izquierda y el control a la derecha.
func _row(text: String, control: Control, hint := "", restart := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_px(32)))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", roundi(_px(2)))
	var label := Label.new()
	label.text = text
	texts.add_child(label)
	if hint != "" or restart:
		var detail := Label.new()
		detail.theme_type_variation = "HintLabel"
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = hint if not restart else ("Al reiniciar el juego. " + hint).strip_edges()
		texts.add_child(detail)
	row.add_child(texts)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, _px(560))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_page.add_child(row)


## Desplegable de una opción por niveles. Por defecto guarda el índice elegido en `key`.
func _choice_control(key: String, options: Array, on_selected := Callable()) -> OptionButton:
	var button := OptionButton.new()
	for option in options:
		button.add_item(option)
	button.select(SettingsManager.level(key, options.size()))
	button.custom_minimum_size.y = _px(60)
	if on_selected.is_valid():
		button.item_selected.connect(on_selected)
	else:
		button.item_selected.connect(func(i: int) -> void: Settings.set_value(key, i))
	return button


func _toggle_control(key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(SettingsManager.value(key))
	toggle.text = "Activado" if toggle.button_pressed else "Desactivado"
	toggle.toggled.connect(func(on: bool) -> void:
		toggle.text = "Activado" if on else "Desactivado"
		Settings.set_value(key, on))
	return toggle


## Slider con su valor al lado. Porcentaje salvo la sensibilidad, que es un multiplicador.
func _slider_control(key: String, min_value: float, max_value: float, step: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = float(SettingsManager.value(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.theme_type_variation = "ValueLabel"
	label.custom_minimum_size.x = _px(150)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var multiplier := key == "controls/mouse_sensitivity"
	var display_value := func(v: float) -> void:
		label.text = "x%.2f" % v if multiplier else "%d %%" % roundi(v * 100.0)
	display_value.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		display_value.call(v)
		Settings.set_value(key, v))
	box.add_child(slider)
	box.add_child(label)
	box.set_meta(&"value_label", label)
	return box


func _binding_button(action: StringName, slot: int) -> Button:
	var button := Button.new()
	var events := InputMap.action_get_events(action)
	button.text = SettingsManager.event_label(events[slot]) if slot < events.size() else "—"
	button.custom_minimum_size = Vector2(_px(274), _px(56))
	button.clip_text = true
	button.pressed.connect(func() -> void:
		_cancel_capture()
		_capture = {"action": action, "slot": slot, "button": button}
		button.text = "Pulsa una tecla…")
	button.gui_input.connect(func(event: InputEvent) -> void:
		if _capture.is_empty() and event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			button.accept_event()
			_set_binding(action, slot, null))
	return button


# --- Reasignación -------------------------------------------------------------------------------

func _capture_input(event: InputEvent) -> void:
	var bound: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel_capture()
			return
		bound = SettingsManager.dict_to_event({"key": event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode})
	elif event is InputEventMouseButton and event.pressed:
		bound = SettingsManager.dict_to_event({"mouse": event.button_index})
	else:
		return
	get_viewport().set_input_as_handled()
	var action: StringName = _capture.action
	var slot: int = _capture.slot
	_capture = {}
	_set_binding(action, slot, bound)


## Pone (o con null quita) el evento de una ranura. Si el evento ya lo usaba otra acción, se lo
## quita y lo avisa, para que ninguna tecla haga dos cosas sin que el jugador lo sepa.
func _set_binding(action: StringName, slot: int, event: InputEvent) -> void:
	var stolen: Array[String] = []
	if event != null:
		for group in SettingsManager.REBINDABLE_ACTIONS:
			for entry in group[1]:
				if entry[0] == action or not InputMap.has_action(entry[0]):
					continue
				var others := InputMap.action_get_events(entry[0])
				var kept := others.filter(func(e: InputEvent) -> bool: return not SettingsManager.same_event(e, event))
				if kept.size() != others.size():
					Settings.set_action_events(entry[0], kept)
					stolen.append(entry[1])
	var events: Array = InputMap.action_get_events(action)
	if event == null:
		if slot < events.size():
			events.remove_at(slot)
	else:
		events = events.filter(func(e: InputEvent) -> bool: return not SettingsManager.same_event(e, event))
		if slot < events.size():
			events[slot] = event
		else:
			events.append(event)
	Settings.set_action_events(action, events)
	_show_tab(_current_tab)
	if not stolen.is_empty():
		_notice.text = "%s ya no está asignada a: %s." % [SettingsManager.event_label(event), ", ".join(stolen)]


func _cancel_capture() -> void:
	if _capture.is_empty():
		return
	var button: Button = _capture.button
	var events := InputMap.action_get_events(_capture.action)
	var slot: int = _capture.slot
	button.text = SettingsManager.event_label(events[slot]) if slot < events.size() else "—"
	_capture = {}


# --- Cambios ------------------------------------------------------------------------------------

func _change_display(key: String, new_value: Variant) -> void:
	if SettingsManager.value(key) == new_value:
		return
	if not _confirm.visible:
		_display_before = {
			"display/window_mode": SettingsManager.value("display/window_mode"),
			"display/resolution": SettingsManager.value("display/resolution"),
		}
	Settings.set_value(key, new_value)
	_confirm_left = CONFIRM_SECONDS
	_confirm.visible = true
	_show_tab(_current_tab)


func _revert_display() -> void:
	_confirm.visible = false
	for key in _display_before:
		Settings.set_value(key, _display_before[key])
	_display_before = {}
	_show_tab(_current_tab)


func _on_preset_selected(index: int) -> void:
	if index >= PRESET_NAMES.size():
		return
	Settings.apply_preset(index)
	_show_tab(_current_tab)


func _sync_preset() -> void:
	if _preset_button == null:
		return
	var preset := SettingsManager.current_preset()
	_preset_button.select(PRESET_NAMES.size() if preset == SettingsManager.PRESET_CUSTOM else preset)


func _update_scale_label() -> void:
	if _scale_label == null:
		return
	var size := get_viewport().get_visible_rect().size
	var render_scale := float(SettingsManager.value("graphics/render_scale"))
	_scale_label.text = "%d %%  ·  %d×%d" % [roundi(render_scale * 100.0), roundi(size.x * render_scale),
		roundi(size.y * render_scale)]


func _on_setting_changed(key: String) -> void:
	if key.begins_with("graphics/"):
		_sync_preset()
		if key == "graphics/render_scale":
			_update_scale_label()
	_refresh_notice()


func _refresh_notice() -> void:
	_notice.text = "Algunos cambios del mundo (terreno y vegetación) se aplicarán al reiniciar el juego." \
		if SettingsManager.needs_restart() else ""


func _on_reset_tab() -> void:
	var prefix := TAB_PREFIXES[_current_tab]
	if prefix == "display/":
		_change_display("display/window_mode", SettingsManager.default_value("display/window_mode"))
		_change_display("display/resolution", SettingsManager.default_value("display/resolution"))
		Settings.set_value("display/vsync", SettingsManager.default_value("display/vsync"))
		Settings.set_value("display/max_fps", SettingsManager.default_value("display/max_fps"))
	else:
		Settings.reset_section(prefix)
	_show_tab(_current_tab)


func _on_accept() -> void:
	_cancel_capture()
	Settings.save()
	_close()


func _on_cancel() -> void:
	_cancel_capture()
	Settings.restore(_snapshot)
	_close()


func _close() -> void:
	set_process_input(false)
	closed.emit()
	# Se libera al final del frame: hasta entonces is_open() sigue siendo cierto, y el Escape que
	# la ha cerrado no llega a abrir o cerrar el menú de debajo.
	queue_free()


# --- Aspecto ------------------------------------------------------------------------------------

## El de la creación de personaje, más los desplegables y los interruptores que allí no hay.
func _build_theme() -> Theme:
	var theme := CreationTheme.build(_ui_scale)
	var popup := _box(Color(0.06, 0.065, 0.078, 0.98), 8, _px(10), 1, Color(1, 1, 1, 0.12))
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", _box(CreationTheme.ACCENT_DARK, 6, _px(8), 0, Color.TRANSPARENT))
	theme.set_color("font_color", "PopupMenu", CreationTheme.TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_disabled_color", "PopupMenu", CreationTheme.MUTED)
	theme.set_font_size("font_size", "PopupMenu", roundi(_px(26)))
	theme.set_constant("v_separation", "PopupMenu", roundi(_px(14)))
	theme.set_constant("item_start_padding", "PopupMenu", roundi(_px(14)))
	theme.set_constant("item_end_padding", "PopupMenu", roundi(_px(14)))
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(_px(8))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "CheckButton", bare)
	# El interruptor por defecto mide lo mismo a cualquier escala y a 1440 px apenas se ve.
	var on := _switch_icon(true)
	var off := _switch_icon(false)
	for icon in ["checked", "checked_mirrored"]:
		theme.set_icon(icon, "CheckButton", on)
	for icon in ["unchecked", "unchecked_mirrored"]:
		theme.set_icon(icon, "CheckButton", off)
	return theme


## Pastilla con el botón a la derecha (encendido, color de acento) o a la izquierda.
func _switch_icon(on: bool) -> ImageTexture:
	var height := roundi(_px(34))
	var width := roundi(_px(64))
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var track := CreationTheme.ACCENT_DARK if on else Color(1, 1, 1, 0.16)
	var knob := CreationTheme.ACCENT if on else CreationTheme.MUTED
	var radius := height * 0.5
	var knob_center := Vector2(width - radius if on else radius, radius)
	for y in height:
		for x in width:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var nearest := Vector2(clampf(p.x, radius, width - radius), radius)
			var track_alpha := clampf(radius - p.distance_to(nearest), 0.0, 1.0)
			var knob_alpha := clampf(radius - _px(5) - p.distance_to(knob_center), 0.0, 1.0)
			var color := Color(track, track.a * track_alpha).blend(Color(knob, knob_alpha))
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _box(color: Color, radius: int, margin: float, border: int, border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(roundi(radius * _ui_scale))
	box.set_content_margin_all(margin)
	box.set_border_width_all(border)
	box.border_color = border_color
	return box


func _px(value: float) -> float:
	return value * _ui_scale
