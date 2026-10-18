extends CreationStep

## Name, sex and looks. The option rows are generated from AppearanceCatalog:
## one entry of the category rail per category, a slider, swatch row or tile
## grid per option, so new traits show up here without touching this script.
## Choices (hair, beard, eyebrows, faces, skins) are tiles with a portrait of
## the character wearing each one (ChoiceThumbnails). Edits go straight to the
## live preview.

## Panel width, its margin to the screen edges, the rail's width and the size
## of a tile, at the 1440 px base scale.
const PANEL_WIDTH := 1000.0
const MARGIN := 48.0
const TOP := 150.0
const BOTTOM := 150.0
const RAIL_WIDTH := 230.0
const TILE := Vector2(152, 190)
## Seconds an edit waits before the portraits are taken again.
const THUMBNAIL_DELAY := 0.35

var _name_edit: LineEdit
var _sex_buttons := {}
var _category_buttons := {}
var _category_title: Label
var _options_box: VBoxContainer
var _scroll: ScrollContainer
var _category: Dictionary
var _rng := RandomNumberGenerator.new()
var _apply_queued := false
var _thumbnails: ChoiceThumbnails
## "option/choice" -> portrait, and the tile showing it now.
var _thumbs := {}
var _tiles := {}
var _thumbnail_timer: Timer


func get_title() -> String:
	return "CREATE_STEP_APPEARANCE"


func can_continue() -> bool:
	return not character.display_name.strip_edges().is_empty()


func blocking_reason() -> String:
	return "" if can_continue() else "CREATE_NEED_NAME"


func enter() -> void:
	preview.focus(_category.focus)
	_apply()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_thumbnails = ChoiceThumbnails.new()
	_thumbnails.thumbnail_ready.connect(_on_thumbnail_ready)
	add_child(_thumbnails)
	_thumbnail_timer = Timer.new()
	_thumbnail_timer.one_shot = true
	_thumbnail_timer.wait_time = THUMBNAIL_DELAY
	_thumbnail_timer.timeout.connect(_request_thumbnails)
	add_child(_thumbnail_timer)
	_build_panel()
	character.appearance.changed.connect(_queue_apply)
	character.appearance.changed.connect(_thumbnail_timer.start)
	_select_category(AppearanceCatalog.categories()[0])


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = px(MARGIN)
	panel.offset_right = px(MARGIN + PANEL_WIDTH)
	panel.offset_top = px(TOP)
	panel.offset_bottom = -px(BOTTOM)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)

	# Identity: name and sex side by side.
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", roundi(px(28)))
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(_label("CREATE_NAME", "SectionLabel"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "CREATE_NAME_PLACEHOLDER"
	_name_edit.max_length = 24
	_name_edit.text = character.display_name
	_name_edit.text_changed.connect(func(text: String) -> void:
		character.display_name = text
		validity_changed.emit())
	name_box.add_child(_name_edit)
	identity.add_child(name_box)
	var sex_box := VBoxContainer.new()
	sex_box.add_child(_label("APP_SEX", "SectionLabel"))
	var sex_option := AppearanceCatalog.find(AppearanceCatalog.SEX)
	var sex_row := HBoxContainer.new()
	sex_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sex_group := ButtonGroup.new()
	for choice in sex_option.choices:
		var button := _toggle(choice.label, sex_group)
		button.custom_minimum_size.x = px(170)
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_sex_selected.bind(choice.id))
		_sex_buttons[choice.id] = button
		sex_row.add_child(button)
	sex_box.add_child(sex_row)
	identity.add_child(sex_box)
	column.add_child(identity)
	column.add_child(HSeparator.new())

	# The category rail and the options of the chosen one.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", roundi(px(24)))
	var rail := VBoxContainer.new()
	rail.custom_minimum_size.x = px(RAIL_WIDTH)
	rail.add_theme_constant_override("separation", roundi(px(4)))
	var rail_group := ButtonGroup.new()
	for category in AppearanceCatalog.categories():
		var button := _toggle(category.label, rail_group)
		button.theme_type_variation = "RailButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_category.bind(category))
		_category_buttons[category.id] = button
		rail.add_child(button)
	body.add_child(rail)
	var line := ColorRect.new()
	line.color = GameTheme.BRONZE_FAINT
	line.custom_minimum_size.x = maxf(1.0, roundf(ui_scale))
	body.add_child(line)

	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_title = _label("", "HeaderLabel")
	options.add_child(_category_title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options.add_child(_scroll)
	_options_box = VBoxContainer.new()
	_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_box.add_theme_constant_override("separation", roundi(px(22)))
	_scroll.add_child(_options_box)
	body.add_child(options)
	column.add_child(body)

	column.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	var randomize_button := Button.new()
	randomize_button.text = "CREATE_RANDOMIZE"
	randomize_button.tooltip_text = "CREATE_RANDOMIZE_TIP"
	randomize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	randomize_button.pressed.connect(func() -> void:
		character.appearance.randomize_values(_rng)
		_rebuild_options())
	actions.add_child(randomize_button)
	var vary_button := Button.new()
	vary_button.text = "CREATE_VARY"
	vary_button.tooltip_text = "CREATE_VARY_TIP"
	vary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vary_button.pressed.connect(func() -> void:
		character.appearance.randomize_values(_rng, _category.options)
		_rebuild_options())
	actions.add_child(vary_button)
	var reset_button := Button.new()
	reset_button.text = "CREATE_RESET"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.pressed.connect(func() -> void:
		character.appearance.reset()
		_rebuild_options())
	actions.add_child(reset_button)
	column.add_child(actions)


func _select_category(category: Dictionary) -> void:
	_category = category
	for id in _category_buttons:
		_category_buttons[id].set_pressed_no_signal(id == category.id)
	_category_title.text = tr(category.label).to_upper()
	_rebuild_options()
	if preview and is_visible_in_tree():
		preview.focus(category.focus, true, true)


func _on_sex_selected(sex: StringName) -> void:
	character.appearance.set_sex(sex)
	_rebuild_options()


func _rebuild_options() -> void:
	var sex := character.appearance.get_sex()
	for id in _sex_buttons:
		_sex_buttons[id].set_pressed_no_signal(id == sex)
	for child in _options_box.get_children():
		child.queue_free()
	_tiles.clear()
	for option in _category.options:
		if not option.is_available(sex):
			continue
		match option.kind:
			AppearanceOption.Kind.SLIDER:
				_options_box.add_child(_slider_row(option))
			AppearanceOption.Kind.COLOR:
				_options_box.add_child(_color_row(option))
			AppearanceOption.Kind.CHOICE, AppearanceOption.Kind.PRESET:
				_options_box.add_child(_tile_row(option))
	_scroll.scroll_vertical = 0
	_request_thumbnails()


func _slider_row(option: AppearanceOption) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(px(4)))
	var header := HBoxContainer.new()
	var label := _label(option.label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := _label("", "ValueLabel")
	header.add_child(value_label)
	row.add_child(header)
	var slider := HSlider.new()
	slider.min_value = option.min_value
	slider.max_value = option.max_value
	slider.step = 0.01
	slider.value = character.appearance.get_value(option.id)
	slider.custom_minimum_size.y = px(34)
	slider.tooltip_text = "CREATE_SLIDER_TIP"
	value_label.text = _format(option, slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		character.appearance.set_value(option.id, value)
		value_label.text = _format(option, value))
	slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			slider.value = option.default_for(character.appearance.get_sex()))
	row.add_child(slider)
	return row


func _color_row(option: AppearanceOption) -> Control:
	var row := VBoxContainer.new()
	row.add_child(_label(option.label, "SectionLabel"))
	var swatches := HFlowContainer.new()
	var group := ButtonGroup.new()
	group.allow_unpress = true
	var current: Color = character.appearance.get_value(option.id)
	var picker := ColorPickerButton.new()
	for color in option.palette:
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.custom_minimum_size = Vector2(px(62), px(62))
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.add_theme_stylebox_override("normal", GameTheme.swatch(color, false, ui_scale))
		swatch.add_theme_stylebox_override("hover", GameTheme.swatch(color.lightened(0.12), false, ui_scale))
		swatch.add_theme_stylebox_override("pressed", GameTheme.swatch(color, true, ui_scale))
		swatch.add_theme_stylebox_override("hover_pressed", GameTheme.swatch(color, true, ui_scale))
		swatch.set_pressed_no_signal(color.is_equal_approx(current))
		swatch.pressed.connect(func() -> void:
			character.appearance.set_value(option.id, color)
			picker.color = color)
		swatches.add_child(swatch)
	picker.color = current
	picker.edit_alpha = false
	picker.text = "+"
	picker.tooltip_text = "CREATE_CUSTOM_COLOR"
	picker.custom_minimum_size = Vector2(px(62), px(62))
	picker.color_changed.connect(func(color: Color) -> void:
		var pressed := group.get_pressed_button()
		if pressed:
			pressed.set_pressed_no_signal(false)
		character.appearance.set_value(option.id, color))
	swatches.add_child(picker)
	row.add_child(swatches)
	return row


## A tile per choice, with its portrait once ChoiceThumbnails has taken it.
## Presets (faces) set several options at once.
func _tile_row(option: AppearanceOption) -> Control:
	var row := VBoxContainer.new()
	row.add_child(_label(option.label, "SectionLabel"))
	var tiles := HFlowContainer.new()
	var group := ButtonGroup.new()
	var current: StringName = character.appearance.get_value(option.id)
	for choice in option.choices_for(character.appearance.get_sex()):
		var key := _thumb_key(option.id, choice.id)
		var button := _toggle(choice.label, group)
		button.theme_type_variation = "Tile"
		button.custom_minimum_size = TILE * ui_scale
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.icon = _thumbs.get(key)
		button.set_pressed_no_signal(choice.id == current)
		if option.kind == AppearanceOption.Kind.PRESET:
			button.pressed.connect(func() -> void:
				character.appearance.apply_preset(option, choice.id)
				_rebuild_options.call_deferred())
		else:
			button.pressed.connect(character.appearance.set_value.bind(option.id, choice.id))
		_tiles[key] = button
		tiles.add_child(button)
	row.add_child(tiles)
	return row


func _request_thumbnails() -> void:
	if _category.is_empty():
		return
	_thumbnails.request(_category.options, character.appearance)


func _on_thumbnail_ready(option_id: StringName, choice_id: StringName, texture: Texture2D) -> void:
	var key := _thumb_key(option_id, choice_id)
	_thumbs[key] = texture
	if _tiles.has(key) and is_instance_valid(_tiles[key]):
		_tiles[key].icon = texture


func _thumb_key(option_id: StringName, choice_id: StringName) -> String:
	return "%s/%s" % [option_id, choice_id]


## Signed percentage for centred sliders, plain percentage otherwise.
func _format(option: AppearanceOption, value: float) -> String:
	var percent := roundi(value * 100.0)
	if option.min_value < 0.0:
		return "%+d" % percent if percent != 0 else "0"
	return "%d%%" % percent


func _label(text: String, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


func _toggle(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	return button


## Edits arrive in bursts (a dragged slider); apply once per frame.
func _queue_apply() -> void:
	if not _apply_queued:
		_apply_queued = true
		_apply.call_deferred()


func _apply() -> void:
	_apply_queued = false
	if preview and preview.rig:
		preview.rig.apply(character.appearance)
