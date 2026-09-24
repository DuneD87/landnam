class_name CharacterCreationScreen
extends CanvasLayer

## New-character flow shown after "Start Game": a shared 3D preview behind a
## sequence of steps (CreationStep), with the step list on top and Back/Next
## at the bottom. To add a page (skills, attributes...) write a CreationStep
## and append it to STEPS; navigation and validation adapt. Emits `finished`
## with the filled CharacterData, or `cancelled` when backing out of the
## first step.

signal finished(character: CharacterData)
signal cancelled

const STEPS: Array[GDScript] = [
	preload("res://scripts/ui/character_creation/appearance_step.gd"),
]

var character := CharacterData.new()
var preview: CharacterPreview

var _ui_scale := 1.0
var _root: Control
var _steps: Array[CreationStep] = []
var _current := -1
var _crumbs: HBoxContainer
var _back_button: Button
var _next_button: Button
var _reason: Label


func _ready() -> void:
	layer = 20
	_ui_scale = clampf(get_viewport().get_visible_rect().size.y / 1440.0, 0.5, 2.0)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = CreationTheme.build(_ui_scale)
	add_child(_root)

	preview = CharacterPreview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(preview)
	_root.add_child(_vignette())

	for script in STEPS:
		var step: CreationStep = script.new()
		step.character = character
		step.preview = preview
		step.ui_scale = _ui_scale
		step.visible = false
		step.validity_changed.connect(_refresh_navigation)
		_root.add_child(step)
		_steps.append(step)
	_build_header()
	_build_footer()
	_show_step(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


func _show_step(index: int) -> void:
	if _current >= 0:
		_steps[_current].leave()
		_steps[_current].visible = false
	_current = index
	_steps[_current].visible = true
	_steps[_current].enter()
	for i in _crumbs.get_child_count():
		var crumb := _crumbs.get_child(i) as Label
		crumb.theme_type_variation = "ValueLabel" if i == _current else "HintLabel"
	_refresh_navigation()


func _on_back() -> void:
	if _current == 0:
		cancelled.emit()
	else:
		_show_step(_current - 1)


func _on_next() -> void:
	if not _steps[_current].can_continue():
		return
	if _current == _steps.size() - 1:
		finished.emit(character)
	else:
		_show_step(_current + 1)


func _refresh_navigation() -> void:
	var step := _steps[_current]
	var last := _current == _steps.size() - 1
	_back_button.text = "Volver al menú" if _current == 0 else "Atrás"
	_next_button.text = "Comenzar partida" if last else "Siguiente"
	_next_button.disabled = not step.can_continue()
	_reason.text = step.blocking_reason()


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = _px(48)
	header.offset_right = -_px(48)
	header.offset_top = _px(44)
	header.add_theme_constant_override("separation", roundi(_px(36)))
	var title := Label.new()
	title.text = "CREACIÓN DE PERSONAJE"
	title.theme_type_variation = "TitleLabel"
	header.add_child(title)
	_crumbs = HBoxContainer.new()
	_crumbs.add_theme_constant_override("separation", roundi(_px(28)))
	_crumbs.alignment = BoxContainer.ALIGNMENT_END
	_crumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumbs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in _steps.size():
		var crumb := Label.new()
		crumb.text = "%d · %s" % [i + 1, _steps[i].get_title()]
		_crumbs.add_child(crumb)
	header.add_child(_crumbs)
	_root.add_child(header)


func _build_footer() -> void:
	var footer := VBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_right = -_px(48)
	footer.offset_bottom = -_px(48)
	_reason = Label.new()
	_reason.theme_type_variation = "HintLabel"
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_reason)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", roundi(_px(20)))
	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(_px(260), _px(72))
	_back_button.pressed.connect(_on_back)
	buttons.add_child(_back_button)
	_next_button = Button.new()
	_next_button.theme_type_variation = "AccentButton"
	_next_button.custom_minimum_size = Vector2(_px(340), _px(72))
	_next_button.pressed.connect(_on_next)
	buttons.add_child(_next_button)
	footer.add_child(buttons)
	_root.add_child(footer)

	# Camera controls, bottom left of the space the side panel leaves free.
	var view := HBoxContainer.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	view.grow_vertical = Control.GROW_DIRECTION_BEGIN
	view.offset_left = _px(876)
	view.offset_bottom = -_px(52)
	var hint := Label.new()
	hint.text = "Clic izquierdo: girar · Clic derecho: subir y bajar · Rueda: acercar"
	hint.theme_type_variation = "HintLabel"
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	view.add_child(hint)
	for framing in [[&"body", "Cuerpo"], [&"face", "Rostro"]]:
		var button := Button.new()
		button.text = framing[1]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(preview.focus.bind(framing[0]))
		view.add_child(button)
	_root.add_child(view)


## Darkens the corners so panels and text read over the preview.
func _vignette() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.65))
	gradient.set_offset(0, 0.45)
	var texture := GradientTexture2D.new()
	# The default 64 px texture bands visibly once stretched over the screen.
	texture.width = 1024
	texture.height = 512
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.55, 0.5)
	texture.fill_to = Vector2(1.15, 1.0)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _px(value: float) -> float:
	return value * _ui_scale
