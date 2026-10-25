class_name MapMarkerEditor extends PanelContainer

## Ficha sobre el mapa: solo emite cambios al aceptar. Cancelar no modifica el marcador.

signal submitted(icon: String, marker_name: String)
signal deleted()
signal cancelled()

const ICON_TEXTURES := {
	"home": preload("res://textures/icons/map/home.svg"),
	"resources": preload("res://textures/icons/map/resources.svg"),
	"cave": preload("res://textures/icons/map/cave.svg"),
	"camp": preload("res://textures/icons/map/camp.svg"),
	"danger": preload("res://textures/icons/map/danger.svg"),
	"flag": preload("res://textures/icons/map/flag.svg"),
	"tombstone": preload("res://textures/icons/map/tombstone.svg"),
}

var _title: Label
var _coordinates: Label
var _name_edit: LineEdit
var _icon_choice: OptionButton
var _delete_button: Button
var _column: VBoxContainer
var _buttons: HBoxContainer
var _panel_style: StyleBoxFlat


func _ready() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.07, 0.08, 0.10, 0.98)
	_panel_style.border_color = Color(0.58, 0.49, 0.31)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", _panel_style)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_column = VBoxContainer.new()
	add_child(_column)
	_title = Label.new()
	_column.add_child(_title)
	_coordinates = Label.new()
	_coordinates.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
	_column.add_child(_coordinates)
	_icon_choice = OptionButton.new()
	for icon in MapMarkers.ICONS:
		_icon_choice.add_icon_item(ICON_TEXTURES[icon], tr(MapMarkers.ICON_LABELS[icon]))
	_column.add_child(_icon_choice)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "MAP_MARKER_NAME"
	_name_edit.max_length = MapMarkers.MAX_NAME_LENGTH
	_name_edit.text_submitted.connect(func(_text: String) -> void: _submit())
	_column.add_child(_name_edit)
	_buttons = HBoxContainer.new()
	_column.add_child(_buttons)
	var save_button := Button.new()
	save_button.text = "MAP_MARKER_APPLY"
	save_button.pressed.connect(_submit)
	_buttons.add_child(save_button)
	var cancel_button := Button.new()
	cancel_button.text = "UI_CANCEL"
	cancel_button.pressed.connect(func() -> void: cancelled.emit())
	_buttons.add_child(cancel_button)
	_delete_button = Button.new()
	_delete_button.text = "MAP_MARKER_DELETE"
	_delete_button.pressed.connect(func() -> void: deleted.emit())
	_buttons.add_child(_delete_button)
	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale()
	hide()


## Mantiene un mínimo cómodo en 720p y amplía controles e iconos en pantallas mayores.
static func ui_scale_for(viewport: Viewport) -> float:
	return clampf(viewport.get_visible_rect().size.y / 1080.0, 1.0, 1.75)


func _apply_scale() -> void:
	var ui_scale := ui_scale_for(get_viewport())
	var scaled_theme := Theme.new()
	for control_type in ["Label", "Button", "LineEdit", "OptionButton", "PopupMenu"]:
		scaled_theme.set_font_size("font_size", control_type, roundi(22.0 * ui_scale))
	for control_type in ["OptionButton", "PopupMenu"]:
		scaled_theme.set_constant("icon_max_width", control_type, roundi(40.0 * ui_scale))
	scaled_theme.set_constant("h_separation", "OptionButton", roundi(12.0 * ui_scale))
	scaled_theme.set_constant("v_separation", "PopupMenu", roundi(12.0 * ui_scale))
	theme = scaled_theme
	_icon_choice.get_popup().theme = scaled_theme
	custom_minimum_size.x = 460.0 * ui_scale
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		_panel_style.set_content_margin(side, 20.0 * ui_scale)
	_column.add_theme_constant_override("separation", roundi(14.0 * ui_scale))
	_buttons.add_theme_constant_override("separation", roundi(12.0 * ui_scale))
	_title.add_theme_font_size_override("font_size", roundi(28.0 * ui_scale))
	_coordinates.add_theme_font_size_override("font_size", roundi(20.0 * ui_scale))
	_icon_choice.custom_minimum_size.y = 60.0 * ui_scale
	_name_edit.custom_minimum_size.y = 52.0 * ui_scale
	for button: Button in _buttons.get_children():
		button.custom_minimum_size.y = 52.0 * ui_scale
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Al reducir la resolución hay que soltar también el tamaño anterior del contenedor.
	size = get_combined_minimum_size()


func edit(marker: Dictionary, uv: Vector2) -> void:
	_title.text = "MAP_MARKER_NEW" if marker.is_empty() else "MAP_MARKER_EDIT"
	_coordinates.text = WorldMapData.format_latlon(WorldMapData.dir_to_latlon(WorldMapData.uv_to_dir(uv)))
	_name_edit.text = marker.get("name", "")
	_icon_choice.select(MapMarkers.ICONS.find(marker.get("icon", "flag")))
	_delete_button.visible = not marker.is_empty()
	show()
	_name_edit.grab_focus()
	_name_edit.select_all()


func close() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	hide()


func _submit() -> void:
	submitted.emit(MapMarkers.ICONS[_icon_choice.selected], _name_edit.text)
