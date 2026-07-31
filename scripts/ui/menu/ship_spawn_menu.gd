class_name ShipSpawnMenu
extends CanvasLayer

## Panel de depuración para generar el barco de prueba con dimensiones a medida.
## Recoge largo (eslora), ancho (manga) y alto (puntal) en bloques, más el número de camarotes
## y de plantas por camarote, y emite spawn_requested; quien lo escuche decide dónde y cómo
## construir el casco. Recuerda los últimos valores introducidos.

signal spawn_requested(length: int, width: int, height: int, compartments: int, decks: int)

const DEFAULT_LENGTH := 120
const DEFAULT_WIDTH := 30
const DEFAULT_HEIGHT := 26
const DEFAULT_COMPARTMENTS := 10
const DEFAULT_DECKS := 1

var _length_spin: SpinBox
var _width_spin: SpinBox
var _height_spin: SpinBox
var _compartments_spin: SpinBox
var _decks_spin: SpinBox


func _ready() -> void:
	layer = 10
	_build_ui()
	visible = false


func toggle() -> void:
	visible = !visible


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.30, 0.20, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Generar barco"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1.0))
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(toggle)
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	_length_spin = _add_field(grid, "Largo (bloques)", DEFAULT_LENGTH, 6, 400)
	_width_spin = _add_field(grid, "Ancho (bloques)", DEFAULT_WIDTH, 3, 160)
	_height_spin = _add_field(grid, "Alto (bloques)", DEFAULT_HEIGHT, 2, 120)
	_compartments_spin = _add_field(grid, "Camarotes", DEFAULT_COMPARTMENTS, 1, 60)
	_decks_spin = _add_field(grid, "Plantas por camarote", DEFAULT_DECKS, 1, 20)

	vbox.add_child(HSeparator.new())

	var spawn_btn := Button.new()
	spawn_btn.text = "Generar"
	spawn_btn.pressed.connect(_on_spawn_pressed)
	vbox.add_child(spawn_btn)


## Añade una fila etiqueta + SpinBox al grid y devuelve el SpinBox.
func _add_field(grid: GridContainer, text: String, value: int, min_value: int, max_value: int) -> SpinBox:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(120, 0)
	grid.add_child(spin)
	return spin


func _on_spawn_pressed() -> void:
	spawn_requested.emit(int(_length_spin.value), int(_width_spin.value), int(_height_spin.value),
		int(_compartments_spin.value), int(_decks_spin.value))
	visible = false
