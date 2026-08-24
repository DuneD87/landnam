class_name GridManipulatorMenu
extends CanvasLayer

## Menú de manipulación de grids (tecla G). Si al abrirlo apuntabas a una grid, muestra las
## estadísticas de su grupo y deja guardarla como blueprint, convertirla a dinámica o eliminarla;
## si no apuntabas a nada, lista los blueprints guardados para cargar uno. El objetivo se congela
## al abrir: con el ratón liberado el raycast del jugador ya no apunta a donde mirabas.

signal save_requested(blueprint_name: String)
signal delete_requested()
signal convert_requested()
signal load_requested(blueprint_name: String)
signal closed()

## Grupo de grids sobre el que opera el menú; null en modo biblioteca.
var target_grid: GridBase = null

var _grid_section: VBoxContainer
var _library_section: VBoxContainer
var _title: Label
var _status: Label
var _grid_stats: Label
var _name_edit: LineEdit
var _convert_btn: Button
var _delete_btn: Button
var _blueprint_list: ItemList
var _blueprint_stats: Label
var _load_btn: Button
var _delete_bp_btn: Button
var _delete_armed: bool = false


func _ready() -> void:
	layer = 10
	_build_ui()
	visible = false


## Abre el menú sobre una grid (modo grid) o sin ella (modo biblioteca).
func open(grid: GridBase) -> void:
	target_grid = grid
	_delete_armed = false
	_status.text = ""
	visible = true

	var grid_mode := grid != null
	_grid_section.visible = grid_mode
	_library_section.visible = not grid_mode

	if grid_mode:
		_refresh_grid_stats()
	else:
		_refresh_blueprint_list()


func close() -> void:
	if not visible:
		return
	visible = false
	target_grid = null
	closed.emit()


func toggle(grid: GridBase) -> void:
	if visible:
		close()
	else:
		open(grid)


func set_status(text: String) -> void:
	_status.text = text


## Relee las estadísticas del grupo apuntado (tras convertir a dinámica, por ejemplo).
func _refresh_grid_stats() -> void:
	if not target_grid:
		return

	var stats := GridManager.get_group_stats(target_grid.grid_id)
	if stats.is_empty():
		_title.text = "Grid"
		_grid_stats.text = "La grid ya no existe."
		return

	_title.text = "Grid %s" % stats["grid_id"]
	_grid_stats.text = _format_group_stats(stats)
	_convert_btn.visible = not stats["dynamic"]
	_delete_btn.text = "Eliminar"
	_delete_armed = false
	_name_edit.text = str(stats["grid_id"])


func _format_group_stats(stats: Dictionary) -> String:
	var size: Vector3 = stats["size"]
	var lines: Array[String] = [
		"Tipo: %s" % ("dinámica" if stats["dynamic"] else "estática"),
		"Planeta: %s" % stats["planet"],
		"Grids del grupo: %d" % stats["grids"],
		"Bloques: %d      Props: %d" % [stats["blocks"], stats["props"]],
		"Dimensiones: %.1f x %.1f x %.1f m" % [size.x, size.y, size.z],
		"Volumen: %.1f m³" % stats["volume"],
		"Tamaños de celda: %s" % _format_cells(stats["cell_sizes"]),
	]

	if stats.has("mass"):
		lines.append("Masa: %.0f kg" % stats["mass"])
	if stats.has("flood"):
		var flood: Dictionary = stats["flood"]
		lines.append("Compartimentos: %d (%d inundados, %d con vía de agua)" % [
			flood["compartments"], flood["flooded"], flood["breached"]])
		if flood.get("heel_assist", 1.0) < 1.0:
			lines.append("Estabilidad: %.0f%%" % (flood["heel_assist"] * 100.0))

	return "\n".join(lines)


func _format_cells(cells: Array) -> String:
	var parts: Array[String] = []
	for cell: float in cells:
		parts.append("%.2f" % cell)
	return ", ".join(parts)


func _refresh_blueprint_list() -> void:
	_title.text = "Cargar blueprint"
	_blueprint_list.clear()
	for bp_name: String in GridBlueprint.list_names():
		_blueprint_list.add_item(bp_name)

	var empty := _blueprint_list.item_count == 0
	_blueprint_stats.text = "No hay blueprints guardados." if empty else "Selecciona un blueprint."
	_load_btn.disabled = true
	_delete_bp_btn.disabled = true


func _on_blueprint_selected(index: int) -> void:
	var bp_name: String = _blueprint_list.get_item_text(index)
	var data := GridBlueprint.load_from_disk(bp_name)
	_load_btn.disabled = data.is_empty()
	_delete_bp_btn.disabled = false

	if data.is_empty():
		_blueprint_stats.text = "No se ha podido leer '%s'." % bp_name
		return

	var stats := GridBlueprint.get_stats(data)
	var size: Vector3 = stats["size"]
	_blueprint_stats.text = "\n".join([
		"Tipo: %s" % ("dinámica" if stats["dynamic"] else "estática"),
		"Grids: %d      Bloques: %d      Props: %d" % [stats["grids"], stats["blocks"], stats["props"]],
		"Dimensiones: %.1f x %.1f x %.1f m" % [size.x, size.y, size.z],
		"Tamaños de celda: %s" % _format_cells(stats["cell_sizes"]),
		"Guardado: %s" % stats["created"],
	])


func _on_save_pressed() -> void:
	var bp_name := GridBlueprint.sanitize_name(_name_edit.text)
	if bp_name == "":
		_status.text = "Pon un nombre al blueprint."
		return
	save_requested.emit(bp_name)


func _on_delete_pressed() -> void:
	if not _delete_armed:
		_delete_armed = true
		_delete_btn.text = "¿Seguro? Pulsa otra vez"
		return
	delete_requested.emit()


func _on_load_pressed() -> void:
	var selected := _blueprint_list.get_selected_items()
	if selected.is_empty():
		return
	load_requested.emit(_blueprint_list.get_item_text(selected[0]))


func _on_delete_blueprint_pressed() -> void:
	var selected := _blueprint_list.get_selected_items()
	if selected.is_empty():
		return
	var bp_name: String = _blueprint_list.get_item_text(selected[0])
	if GridBlueprint.delete_from_disk(bp_name):
		_status.text = "Blueprint '%s' borrado." % bp_name
	else:
		_status.text = "No se ha podido borrar '%s'." % bp_name
	_refresh_blueprint_list()


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
	panel.custom_minimum_size = Vector2(420, 0)
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

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1.0))
	header.add_child(_title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	_build_grid_section(vbox)
	_build_library_section(vbox)

	vbox.add_child(HSeparator.new())

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.7, 0.85, 0.6, 1.0))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)


func _build_grid_section(parent: VBoxContainer) -> void:
	_grid_section = VBoxContainer.new()
	_grid_section.add_theme_constant_override("separation", 10)
	parent.add_child(_grid_section)

	_grid_stats = Label.new()
	_grid_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_grid_section.add_child(_grid_stats)

	_grid_section.add_child(HSeparator.new())

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	_grid_section.add_child(save_row)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nombre del blueprint"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_edit)

	var save_btn := Button.new()
	save_btn.text = "Guardar"
	save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(save_btn)

	_convert_btn = Button.new()
	_convert_btn.text = "Convertir a dinámica"
	_convert_btn.pressed.connect(func() -> void: convert_requested.emit())
	_grid_section.add_child(_convert_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Eliminar"
	_delete_btn.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4, 1.0))
	_delete_btn.pressed.connect(_on_delete_pressed)
	_grid_section.add_child(_delete_btn)


func _build_library_section(parent: VBoxContainer) -> void:
	_library_section = VBoxContainer.new()
	_library_section.add_theme_constant_override("separation", 10)
	parent.add_child(_library_section)

	_blueprint_list = ItemList.new()
	_blueprint_list.custom_minimum_size = Vector2(0, 200)
	_blueprint_list.item_selected.connect(_on_blueprint_selected)
	_library_section.add_child(_blueprint_list)

	_blueprint_stats = Label.new()
	_blueprint_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_library_section.add_child(_blueprint_stats)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_library_section.add_child(buttons)

	_load_btn = Button.new()
	_load_btn.text = "Colocar"
	_load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_btn.pressed.connect(_on_load_pressed)
	buttons.add_child(_load_btn)

	_delete_bp_btn = Button.new()
	_delete_bp_btn.text = "Borrar blueprint"
	_delete_bp_btn.pressed.connect(_on_delete_blueprint_pressed)
	buttons.add_child(_delete_bp_btn)

	var hint := Label.new()
	hint.text = "Al colocar: clic izq. confirma · clic der. o Esc cancela · rueda gira 15° · ctrl+rueda aleja/acerca · shift+rueda sube/baja"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7, 1.0))
	_library_section.add_child(hint)
