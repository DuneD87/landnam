class_name CreationTheme
extends RefCounted

## Look of the character creation screens: dark translucent panels over the
## 3D preview with a bronze accent. Sizes are authored for 1440 px of height
## and scaled by `ui_scale`, since the project renders UI unstretched.

const ACCENT := Color("c9a46a")
const ACCENT_DARK := Color("6e5a38")
const TEXT := Color("ece6da")
const MUTED := Color("9c968c")
const PANEL := Color(0.045, 0.05, 0.062, 0.88)
const CONTROL := Color(0.13, 0.135, 0.15, 0.95)
const CONTROL_HOVER := Color(0.19, 0.19, 0.2, 0.98)


static func build(ui_scale: float) -> Theme:
	var theme := Theme.new()
	var px := func(value: float) -> int: return maxi(1, roundi(value * ui_scale))
	theme.default_font_size = px.call(26)

	theme.set_color("font_color", "Label", TEXT)
	for variation in [["TitleLabel", 44, ACCENT], ["SectionLabel", 30, TEXT], ["HintLabel", 22, MUTED],
			["ValueLabel", 22, ACCENT]]:
		theme.set_type_variation(variation[0], "Label")
		theme.set_font_size("font_size", variation[0], px.call(variation[1]))
		theme.set_color("font_color", variation[0], variation[2])

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, 12, px.call(28), 0, Color.TRANSPARENT, ui_scale))

	var margin: int = px.call(14)
	theme.set_stylebox("normal", "Button", _box(CONTROL, 8, margin, px.call(1), Color(1, 1, 1, 0.08), ui_scale))
	theme.set_stylebox("hover", "Button", _box(CONTROL_HOVER, 8, margin, px.call(1), ACCENT_DARK, ui_scale))
	theme.set_stylebox("pressed", "Button", _box(ACCENT_DARK, 8, margin, px.call(2), ACCENT, ui_scale))
	theme.set_stylebox("hover_pressed", "Button", _box(ACCENT_DARK, 8, margin, px.call(2), ACCENT, ui_scale))
	theme.set_stylebox("disabled", "Button", _box(Color(0.1, 0.1, 0.11, 0.6), 8, margin, 0, Color.TRANSPARENT, ui_scale))
	theme.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, 8, margin, px.call(2), ACCENT, ui_scale))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", MUTED * Color(1, 1, 1, 0.6))
	theme.set_type_variation("AccentButton", "Button")
	theme.set_stylebox("normal", "AccentButton", _box(ACCENT_DARK, 8, px.call(18), px.call(2), ACCENT, ui_scale))
	theme.set_stylebox("hover", "AccentButton", _box(ACCENT, 8, px.call(18), px.call(2), ACCENT, ui_scale))
	theme.set_color("font_hover_color", "AccentButton", Color(0.08, 0.07, 0.05))
	theme.set_font_size("font_size", "AccentButton", px.call(30))

	var field := _box(Color(0.02, 0.022, 0.03, 0.9), 8, px.call(14), px.call(1), Color(1, 1, 1, 0.12), ui_scale)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, 8, px.call(14), px.call(2), ACCENT, ui_scale))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED * Color(1, 1, 1, 0.7))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_font_size("font_size", "LineEdit", px.call(30))

	var track := _box(Color(1, 1, 1, 0.12), 4, 0, 0, Color.TRANSPARENT, ui_scale)
	track.content_margin_top = px.call(3)
	track.content_margin_bottom = px.call(3)
	var filled := _box(ACCENT_DARK, 4, 0, 0, Color.TRANSPARENT, ui_scale)
	filled.content_margin_top = px.call(3)
	filled.content_margin_bottom = px.call(3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", _dot(px.call(26), TEXT))
	theme.set_icon("grabber_highlight", "HSlider", _dot(px.call(28), ACCENT))

	theme.set_stylebox("scroll", "VScrollBar", _box(Color(1, 1, 1, 0.04), 4, 0, 0, Color.TRANSPARENT, ui_scale))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grabber := _box(ACCENT_DARK if state == "grabber" else ACCENT, 4, 0, 0, Color.TRANSPARENT, ui_scale)
		grabber.content_margin_left = px.call(5)
		grabber.content_margin_right = px.call(5)
		theme.set_stylebox(state, "VScrollBar", grabber)

	theme.set_stylebox("separator", "HSeparator", _line(ui_scale))
	theme.set_constant("separation", "HSeparator", px.call(20))
	theme.set_constant("separation", "VBoxContainer", px.call(12))
	theme.set_constant("separation", "HBoxContainer", px.call(12))
	theme.set_constant("h_separation", "HFlowContainer", px.call(10))
	theme.set_constant("v_separation", "HFlowContainer", px.call(10))
	return theme


## Swatch style: the colour itself, with an accent ring when selected.
static func swatch(color: Color, selected: bool, ui_scale: float) -> StyleBoxFlat:
	var border := ACCENT if selected else Color(1, 1, 1, 0.15)
	return _box(color, 8, 0, roundi((4.0 if selected else 1.0) * ui_scale), border, ui_scale)


static func _box(color: Color, radius: int, margin: int, border: int, border_color: Color, ui_scale: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(roundi(radius * ui_scale))
	box.set_content_margin_all(margin)
	box.set_border_width_all(border)
	box.border_color = border_color
	box.anti_aliasing = true
	return box


static func _line(ui_scale: float) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.1)
	line.thickness = maxi(1, roundi(ui_scale))
	return line


static func _dot(size: int, color: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center)
			var alpha := clampf(size * 0.5 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(color, alpha))
	return ImageTexture.create_from_image(image)
