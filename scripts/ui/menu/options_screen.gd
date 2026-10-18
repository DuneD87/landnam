class_name OptionsScreen
extends CanvasLayer

## Pantalla de opciones (pantalla, gráficos, audio y controles). Se abre desde el menú principal,
## que en partida hace de menú de pausa. Los cambios se aplican al momento para poder verlos;
## "Aceptar" (o Escape) los guarda y "Cancelar" deja todo como estaba al abrir. Los cambios de
## ventana piden confirmación y se deshacen solos si no llega, por si la dejan inservible.
## Los textos son claves de localization/translations.csv: los fijos se ponen tal cual en el control,
## que los traduce y los cambia solo al cambiar de idioma; los que llevan valores pasan por tr() y la
## página se rehace al cambiar de idioma.

signal closed

const TABS: Array[String] = ["OPT_TAB_DISPLAY", "OPT_TAB_GRAPHICS", "OPT_TAB_AUDIO", "OPT_TAB_CONTROLS", "OPT_TAB_GAME"]
## Prefijo de las claves de SettingsManager de cada pestaña, para "Restablecer".
const TAB_PREFIXES: Array[String] = ["display/", "graphics/", "audio/", "controls/", "game/"]
const CONFIRM_SECONDS := 10.0
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const MAX_FPS_OPTIONS: Array[int] = [0, 30, 60, 90, 120, 144, 165, 240]
const AUDIO_LABELS := {&"Master": "OPT_AUDIO_MASTER", &"Music": "OPT_AUDIO_MUSIC", &"SFX": "OPT_AUDIO_SFX",
	&"Ambient": "OPT_AUDIO_AMBIENT", &"UI": "OPT_AUDIO_UI", &"Voice": "OPT_AUDIO_VOICE"}
const PRESET_NAMES: Array[String] = ["OPT_LOW", "OPT_MEDIUM", "OPT_HIGH", "OPT_ULTRA"]

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
		_confirm_label.text = tr("OPT_CONFIRM_DISPLAY") % ceili(_confirm_left)


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
	title.text = "OPT_TITLE"
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
	reset.text = "OPT_RESET_TAB"
	reset.custom_minimum_size = Vector2(_px(300), _px(68))
	reset.pressed.connect(_on_reset_tab)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "UI_CANCEL"
	cancel.custom_minimum_size = Vector2(_px(240), _px(68))
	cancel.pressed.connect(_on_cancel)
	footer.add_child(cancel)
	var accept := Button.new()
	accept.text = "UI_ACCEPT"
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
	revert.text = "OPT_REVERT"
	revert.custom_minimum_size = Vector2(_px(240), _px(64))
	revert.pressed.connect(_revert_display)
	buttons.add_child(revert)
	var keep := Button.new()
	keep.text = "OPT_KEEP"
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
	var mode := _choice_control("display/window_mode", ["OPT_WINDOWED", "OPT_FULLSCREEN", "OPT_EXCLUSIVE_FULLSCREEN"],
		func(i: int) -> void: _change_display("display/window_mode", i))
	_row("OPT_WINDOW_MODE", mode, "OPT_WINDOW_MODE_HINT")

	var resolution := OptionButton.new()
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var current: Vector2i = SettingsManager.value("display/resolution")
	var sizes: Array[Vector2i] = [Vector2i.ZERO]
	resolution.add_item("OPT_RESOLUTION_PROJECT")
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
	_row("OPT_WINDOW_SIZE", resolution, "OPT_WINDOW_SIZE_HINT")

	_row("OPT_VSYNC", _choice_control("display/vsync", ["OPT_VSYNC_OFF", "OPT_VSYNC_ON", "OPT_VSYNC_ADAPTIVE"]),
		"OPT_VSYNC_HINT")

	var fps := OptionButton.new()
	for limit in MAX_FPS_OPTIONS:
		fps.add_item("OPT_FPS_UNLIMITED" if limit == 0 else "%d FPS" % limit)
	var fps_index := MAX_FPS_OPTIONS.find(int(SettingsManager.value("display/max_fps")))
	fps.select(maxi(fps_index, 0))
	fps.item_selected.connect(func(i: int) -> void: Settings.set_value("display/max_fps", MAX_FPS_OPTIONS[i]))
	_row("OPT_MAX_FPS", fps, "OPT_MAX_FPS_HINT")


func _build_graphics_page() -> void:
	_preset_button = OptionButton.new()
	for preset_name in PRESET_NAMES:
		_preset_button.add_item(preset_name)
	_preset_button.add_item("OPT_CUSTOM")
	_preset_button.set_item_disabled(PRESET_NAMES.size(), true)
	_preset_button.item_selected.connect(_on_preset_selected)
	_sync_preset()
	_row("OPT_PRESET", _preset_button, "OPT_PRESET_HINT")

	_section("OPT_SECTION_IMAGE")
	var scale_slider := _slider_control("graphics/render_scale", 0.5, 1.0, 0.05)
	_scale_label = scale_slider.get_meta(&"value_label")
	_row("OPT_RENDER_SCALE", scale_slider, "OPT_RENDER_SCALE_HINT")
	_row("OPT_UPSCALER", _choice_control("graphics/upscaler", ["OPT_BILINEAR", "AMD FSR 1.0", "AMD FSR 2.2"]),
		"OPT_UPSCALER_HINT")
	_row("OPT_ANTIALIASING", _choice_control("graphics/antialiasing", ["OPT_OFF_M", "FXAA", "MSAA 2x", "MSAA 4x", "TAA"]),
		"OPT_ANTIALIASING_HINT")

	_section("OPT_SECTION_SHADOWS")
	_row("OPT_SHADOW_QUALITY", _choice_control("graphics/shadow_quality", ["OPT_OFF_F_PL", "OPT_LOW_F", "OPT_MEDIUM_F", "OPT_HIGH_F", "OPT_ULTRA"]))
	_row("OPT_SHADOW_DISTANCE", _choice_control("graphics/shadow_distance", ["OPT_SHORT_F", "OPT_MEDIUM_F", "OPT_LONG_F"]))
	_row("OPT_VEGETATION_SHADOWS", _choice_control("graphics/vegetation_shadows", ["OPT_OFF_F_PL", "OPT_NEAR_ONLY", "OPT_ALL_F_PL"]),
		"", true)

	_section("OPT_SECTION_SKY")
	_row("OPT_ATMOSPHERE_QUALITY", _choice_control("graphics/atmosphere_quality", ["OPT_LOW_F", "OPT_MEDIUM_F", "OPT_HIGH_F"]),
		"OPT_ATMOSPHERE_QUALITY_HINT")
	_row("OPT_CLOUDS", _choice_control("graphics/clouds", ["OPT_OFF_F_PL", "OPT_LOW_F_PL", "OPT_MEDIUM_F_PL", "OPT_HIGH_F_PL"]))
	_row("OPT_GOD_RAYS", _toggle_control("graphics/god_rays"), "OPT_GOD_RAYS_HINT")
	_row("OPT_GLOW", _toggle_control("graphics/glow"))
	_row("OPT_SSAO", _toggle_control("graphics/ssao"), "OPT_SSAO_HINT")
	_row("OPT_WEATHER_PARTICLES", _choice_control("graphics/weather_particles", ["OPT_FEW_F_PL", "OPT_NORMAL_F_PL", "OPT_MANY_F_PL"]))
	_row("OPT_FAUNA", _choice_control("graphics/fauna", ["OPT_FEW_F", "OPT_NORMAL_F", "OPT_MANY_F"]))

	_section("OPT_SECTION_WORLD")
	_row("OPT_TERRAIN_DETAIL", _choice_control("graphics/terrain_detail", ["OPT_LOW", "OPT_MEDIUM", "OPT_HIGH", "OPT_ULTRA"]),
		"OPT_TERRAIN_DETAIL_HINT", true)
	_row("OPT_TERRAIN_NORMALMAPS", _toggle_control("graphics/terrain_normalmaps"),
		"OPT_TERRAIN_NORMALMAPS_HINT", true)
	_row("OPT_TERRAIN_MATERIAL", _choice_control("graphics/terrain_material", ["OPT_LOW", "OPT_MEDIUM", "OPT_HIGH"]),
		"OPT_TERRAIN_MATERIAL_HINT", true)
	_row("OPT_GRASS_DENSITY", _choice_control("graphics/grass_density", ["OPT_LOW_F", "OPT_MEDIUM_F", "OPT_HIGH_F"]), "", true)
	_row("OPT_GRASS_DISTANCE", _choice_control("graphics/grass_distance", ["OPT_SHORT_F", "OPT_MEDIUM_F", "OPT_LONG_F"]), "", true)
	_row("OPT_FOREST_DISTANCE", _choice_control("graphics/forest_distance", ["OPT_NEAR", "OPT_MEDIUM", "OPT_TO_HORIZON"]), "", true)
	_update_scale_label()


func _build_audio_page() -> void:
	for bus in SettingsManager.AUDIO_BUSES:
		_row(AUDIO_LABELS.get(bus, String(bus)), _slider_control("audio/%s" % bus, 0.0, 1.0, 0.01))


func _build_game_page() -> void:
	_row("OPT_LANGUAGE", _language_control(), "OPT_LANGUAGE_HINT")
	_row("OPT_GORE", _choice_control("game/gore", ["OPT_GORE_OFF", "OPT_GORE_BLOOD", "OPT_GORE_FULL"]),
		"OPT_GORE_HINT")
	_row("OPT_HOTBAR_SCALE", _slider_control("game/hotbar_scale", SettingsManager.MIN_HOTBAR_SCALE,
		SettingsManager.MAX_HOTBAR_SCALE, 0.05),
		"OPT_HOTBAR_SCALE_HINT")


func _build_controls_page() -> void:
	_row("OPT_MOUSE_SENSITIVITY", _slider_control("controls/mouse_sensitivity",
		SettingsManager.MIN_MOUSE_SENSITIVITY, SettingsManager.MAX_MOUSE_SENSITIVITY, 0.05))
	_row("OPT_INVERT_Y", _toggle_control("controls/invert_y"))
	var hint := Label.new()
	hint.text = "OPT_BINDINGS_HINT"
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


## Fila: nombre (con su explicación debajo) a la izquierda y el control a la derecha. [text] y [hint]
## son claves.
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
		detail.text = hint if not restart else ("%s %s" % [tr("OPT_ON_RESTART"), tr(hint)]).strip_edges()
		texts.add_child(detail)
	row.add_child(texts)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, _px(560))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_page.add_child(row)


## Desplegable de una opción por niveles (claves o textos sin traducir, como "FXAA"). Por defecto
## guarda el índice elegido en `key`.
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
	toggle.text = "OPT_ON" if toggle.button_pressed else "OPT_OFF"
	toggle.toggled.connect(func(on: bool) -> void:
		toggle.text = "OPT_ON" if on else "OPT_OFF"
		Settings.set_value(key, on))
	return toggle


## Idioma: el del sistema o una de las columnas de la tabla de traducciones, cada una por su nombre.
func _language_control() -> OptionButton:
	var button := OptionButton.new()
	var locales: Array[String] = [""]
	button.add_item("OPT_LANGUAGE_SYSTEM")
	for locale in SettingsManager.languages():
		locales.append(locale)
		button.add_item(SettingsManager.language_name(locale))
	button.select(maxi(locales.find(String(SettingsManager.value("game/language"))), 0))
	button.custom_minimum_size.y = _px(60)
	button.item_selected.connect(func(i: int) -> void: Settings.set_value("game/language", locales[i]))
	return button


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
		button.text = "OPT_PRESS_KEY")
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
					stolen.append(tr(entry[1]))
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
		_notice.text = tr("OPT_KEY_STOLEN") % [SettingsManager.event_label(event), ", ".join(stolen)]


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
	if key == "game/language":
		# Lo fijo cambia solo; las filas con valores y las pistas compuestas se rehacen.
		_show_tab(_current_tab)
	if key.begins_with("graphics/"):
		_sync_preset()
		if key == "graphics/render_scale":
			_update_scale_label()
	_refresh_notice()


func _refresh_notice() -> void:
	_notice.text = tr("OPT_RESTART_NOTICE") if SettingsManager.needs_restart() else ""


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

func _build_theme() -> Theme:
	return GameTheme.build(_ui_scale)


func _px(value: float) -> float:
	return value * _ui_scale
