class_name SailingHUD
extends Control

## Rosa del viento relativa a la proa (arriba). La flecha azul señala hacia dónde sopla.
var navigation: BoatSailing
var speed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(328, 360)


func _draw() -> void:
	if navigation == null:
		return
	var sail := navigation
	var outline := PackedVector2Array([Vector2(12, 0), Vector2(316, 0), Vector2(328, 12),
		Vector2(328, 348), Vector2(316, 360), Vector2(12, 360), Vector2(0, 348), Vector2(0, 12), Vector2(12, 0)])
	draw_colored_polygon(outline, GameTheme.IRON)
	draw_polyline(outline, GameTheme.BRONZE_LINE, 1.5, true)
	_text(Vector2(0, 34), tr("SAIL_TITLE"), GameTheme.BRONZE, 23, true)
	var center := Vector2(86, 118)
	draw_circle(center, 52, GameTheme.IRON_DEEP)
	draw_arc(center, 52, 0, TAU, 64, GameTheme.BRONZE_DARK, 1.5, true)
	for i in 8:
		var direction := Vector2.from_angle(float(i) * TAU / 8.0)
		draw_line(center + direction * 44, center + direction * 50, GameTheme.BRONZE_DARK, 1.0, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -34), center + Vector2(-7, -14),
		center + Vector2(0, -19), center + Vector2(7, -14)]), GameTheme.BONE)
	if not sail.wind.is_zero_approx():
		var direction := Vector2(sin(sail.wind_angle), -cos(sail.wind_angle))
		var normal := Vector2(-direction.y, direction.x)
		draw_line(center - direction * 29, center + direction * 29, GameTheme.FROST, 3, true)
		draw_colored_polygon(PackedVector2Array([center + direction * 37,
			center + direction * 20 + normal * 7, center + direction * 20 - normal * 7]), GameTheme.FROST)
	_text(Vector2(154, 92), tr("SAIL_WIND") % sail.wind.length(), GameTheme.FROST, 22)
	_text(Vector2(154, 122), tr("SAIL_SPEED") % speed, GameTheme.BONE, 22)
	_text(Vector2(154, 152), tr("SAIL_AREA") % sail.area, GameTheme.MUTED, 20)
	_text(Vector2(22, 205), tr("SAIL_DEPLOYMENT") % roundi(sail.deployment * 100.0), GameTheme.BONE, 23)
	for i in 3:
		var rect := Rect2(22 + i * 96, 219, 88, 7)
		draw_rect(rect, GameTheme.LEATHER_LIGHT)
		var fraction := clampf(sail.deployment * 3.0 - i, 0.0, 1.0)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y)), GameTheme.BRONZE)
	var status := "SAIL_WORKING"
	if sail.sails.is_empty():
		status = "SAIL_MISSING"
	elif sail.deployment < 0.01:
		status = "SAIL_FURLED"
	elif sail.wind.length() < 0.2:
		status = "SAIL_CALM"
	elif sail.efficiency < 0.05:
		status = "SAIL_HEADWIND"
	if sail.rowing:
		status = "SAIL_ROWING"
	_text(Vector2(0, 260), tr(status), GameTheme.MOSS if status in ["SAIL_WORKING", "SAIL_ROWING"] else GameTheme.MUTED, 21, true)
	_text(Vector2(0, 302), tr("SAIL_CONTROLS") % [_key(&"boat_sail_raise"), _key(&"boat_sail_lower"),
		_key(&"boat_steer_left"), _key(&"boat_steer_right")], GameTheme.MUTED, 19, true)
	_text(Vector2(0, 333), tr("SAIL_ROW_HINT") % _key(&"boat_row"), GameTheme.MUTED, 19, true)


func _text(at: Vector2, text: String, color: Color, font_size: int, centered := false) -> void:
	var font := GameTheme.body_font()
	if centered:
		at.x = (328.0 - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) * 0.5
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func _key(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	if not events.is_empty() and events[0] is InputEventKey:
		var code: int = events[0].physical_keycode if events[0].physical_keycode != KEY_NONE else events[0].keycode
		match code:
			KEY_UP: return "↑"
			KEY_DOWN: return "↓"
			KEY_LEFT: return "←"
			KEY_RIGHT: return "→"
		if DisplayServer.get_name() == "headless":
			return OS.get_keycode_string(code)
	return SettingsManager.event_label(events[0]) if not events.is_empty() else "—"
