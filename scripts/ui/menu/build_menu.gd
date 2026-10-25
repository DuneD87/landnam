class_name BuildMenu
extends CanvasLayer

## Menú de bloques del martillo, en Saga:
## - a la izquierda, los materiales, con lo que se lleva de cada uno, y los bloques elegidos hace
##   poco (de cualquier material);
## - en medio, los bloques del material, apagados los que no alcanza para poner ni uno;
## - a la derecha, la ficha del que está bajo el ratón (o del elegido): lo que cuesta al tamaño de
##   celda de ahora, lo que se lleva, para cuántos alcanza y si se gira;
## - arriba, el tamaño de celda.
## Un clic en un bloque (o «Construir con este bloque») lo deja como el que pone el martillo, en
## modo poner, y cierra el menú. Se abre desde la rueda del martillo o con su tecla, y se cierra con
## Esc, la tecla, el aspa o un clic fuera de la ventana.

signal block_picked(item_data: ItemData)
signal closed()

const BACKDROP_SHADER := preload("res://shaders/ui/backdrop.gdshader")
## Medidas en la escala base de 1440 px de alto.
const WINDOW_SIZE := Vector2(1640.0, 960.0)
const RAIL_WIDTH := 300.0
const DETAIL_WIDTH := 540.0
const TILE := Vector2(176.0, 214.0)
const MATERIAL_ICON := 40.0
const DIM := Color(1, 1, 1, 0.45)
const NAVAL_CATEGORY := "naval"

var building_system: BuildingSystem
var inventory: Inventory

var _ui_scale := 1.0
var _root: Control
var _window: PanelContainer
var _rail: VBoxContainer
var _rail_detail: VBoxContainer
var _rail_group := ButtonGroup.new()
var _material_buttons := {}
var _recent_box: VBoxContainer
var _recent_flow: HFlowContainer
var _grid_title: Label
var _tiles: HFlowContainer
var _tile_group := ButtonGroup.new()
var _tile_buttons := {}
var _cell_group := ButtonGroup.new()
var _cell_buttons: Array[Button] = []
var _detail_box: PanelContainer
var _preview: ItemSlotView
var _name: Label
var _kind: Label
var _description: Label
var _stats: GridContainer
var _reason: Label
var _use_button: Button
## Material de la pestaña y bloque de la ficha.
var _material_id := ""
var _shown: ItemData = null
var _center: VBoxContainer
var _naval_panel: NavalBuildPanel


func _ready() -> void:
	layer = 10
	_build_ui()
	visible = false
	get_viewport().size_changed.connect(_apply_scale)


func setup(bsys: BuildingSystem, inv: Inventory = null) -> void:
	building_system = bsys
	inventory = inv
	building_system.cell_size_changed.connect(func(_size: float) -> void: _refresh_if_open())
	building_system.recent_blocks_changed.connect(_refresh_if_open)
	if inventory:
		inventory.inventory_changed.connect(_refresh_if_open)
	# Al arrancar los items ya existen pero sus iconos aún se están renderizando: se repinta con
	# cada uno para no enseñar una rejilla de huecos vacíos.
	if not BlockDatabase.are_materials_ready():
		BlockDatabase.icon_generated.connect(_refresh_if_open)
		BlockDatabase.materials_ready.connect(_refresh_if_open)


func open() -> void:
	if not building_system:
		return
	var mat := building_system.get_current_material()
	_material_id = NAVAL_CATEGORY if building_system.is_naval_mode() else (mat.material_id if mat else "")
	if _material_id == NAVAL_CATEGORY:
		_naval_panel.configure(building_system, inventory)
	_apply_scale()
	visible = true
	_refresh()
	_show(_selected_item())


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _refresh_if_open() -> void:
	if visible:
		_refresh()
		_show(_shown if _shown else _selected_item())


func _refresh() -> void:
	_rebuild_rail()
	_rebuild_recent()
	_rebuild_tiles()
	_refresh_cell_buttons()
	var naval := _material_id == NAVAL_CATEGORY
	_center.visible = not naval
	_detail_box.visible = not naval
	_naval_panel.visible = naval
	if naval:
		if _naval_panel.building_system == null:
			_naval_panel.configure(building_system, inventory)
		else:
			_naval_panel.refresh()


# --- Montaje --------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# El mundo detrás, desenfocado y algo oscurecido. Un clic en él cierra el menú.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = BACKDROP_SHADER
	backdrop_material.set_shader_parameter(&"darken", 0.45)
	backdrop.material = backdrop_material
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	_root.add_child(backdrop)

	_window = PanelContainer.new()
	_window.theme_type_variation = &"WindowPanel"
	_window.anchor_left = 0.5
	_window.anchor_right = 0.5
	_window.anchor_top = 0.5
	_window.anchor_bottom = 0.5
	_root.add_child(_window)
	var column := VBoxContainer.new()
	_window.add_child(column)

	var header := HBoxContainer.new()
	var title := _label("BUILD_MENU_TITLE", &"HeaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var cell_label := _label("BUILD_MENU_CELL", &"StatLabel")
	cell_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(cell_label)
	for i in BuildingSystem.CELL_SIZES.size():
		var button := Button.new()
		button.theme_type_variation = &"TabButton"
		button.toggle_mode = true
		button.button_group = _cell_group
		button.focus_mode = Control.FOCUS_NONE
		button.text = _meters(BuildingSystem.CELL_SIZES[i])
		button.tooltip_text = "BUILD_MENU_CELL_TIP"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void: building_system.set_cell_size_index(i))
		header.add_child(button)
		_cell_buttons.append(button)
	var close_button := Button.new()
	close_button.theme_type_variation = &"CloseButton"
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)
	column.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_rail = VBoxContainer.new()
	body.add_child(_rail)
	_rail.add_child(_label("BUILD_MENU_MATERIALS", &"SectionLabel"))
	_rail_detail = VBoxContainer.new()
	_rail_detail.add_theme_constant_override("separation", 2)
	_rail.add_child(_rail_detail)
	_recent_box = VBoxContainer.new()
	_recent_box.add_child(HSeparator.new())
	_recent_box.add_child(_label("BUILD_MENU_RECENT", &"SectionLabel"))
	_recent_flow = HFlowContainer.new()
	_recent_box.add_child(_recent_flow)
	_rail.add_child(_recent_box)

	var center := VBoxContainer.new()
	_center = center
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_grid_title = _label("", &"SectionLabel")
	center.add_child(_grid_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(scroll)
	_tiles = HFlowContainer.new()
	_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tiles)

	_detail_box = PanelContainer.new()
	_detail_box.theme_type_variation = &"Inset"
	body.add_child(_detail_box)
	_build_detail()
	_naval_panel = NavalBuildPanel.new()
	body.add_child(_naval_panel)
	_naval_panel.visible = false
	_naval_panel.piece_picked.connect(close)

	column.add_child(HSeparator.new())
	var hint := _label("BUILD_MENU_HINT", &"HintLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)


func _build_detail() -> void:
	var detail := VBoxContainer.new()
	_detail_box.add_child(detail)
	var top := HBoxContainer.new()
	_preview = ItemSlotView.new()
	_preview.size_kind = &"preview"
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_preview)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 4)
	_name = _label("", &"CardTitle")
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_name)
	_kind = _label("", &"HintLabel")
	_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_kind)
	top.add_child(names)
	detail.add_child(top)
	_description = _label("", &"StatLabel")
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_description)
	detail.add_child(HSeparator.new())
	_stats = GridContainer.new()
	_stats.columns = 2
	detail.add_child(_stats)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	_reason = _label("", &"WorseLabel")
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_reason)
	_use_button = Button.new()
	_use_button.theme_type_variation = &"AccentButton"
	_use_button.text = "BUILD_MENU_USE"
	_use_button.focus_mode = Control.FOCUS_NONE
	_use_button.pressed.connect(func() -> void:
		if _shown:
			_pick(_shown))
	detail.add_child(_use_button)


func _apply_scale() -> void:
	_ui_scale = GameTheme.scale_for(get_viewport())
	var s := _ui_scale
	_root.theme = GameTheme.build(s)
	var viewport := get_viewport().get_visible_rect().size
	var size := Vector2(minf(WINDOW_SIZE.x * s, viewport.x - 48.0 * s), minf(WINDOW_SIZE.y * s, viewport.y - 220.0 * s))
	_window.offset_left = -size.x * 0.5
	_window.offset_right = size.x * 0.5
	# Algo por encima del centro: abajo queda la barra rápida.
	_window.offset_top = -size.y * 0.5 - 60.0 * s
	_window.offset_bottom = size.y * 0.5 - 60.0 * s
	_rail.custom_minimum_size.x = RAIL_WIDTH * s
	_detail_box.custom_minimum_size.x = DETAIL_WIDTH * s
	_naval_panel.apply_scale(s)
	for button: Button in _tile_buttons.values():
		button.custom_minimum_size = TILE * s


# --- Materiales y recientes -----------------------------------------------------------------------

func _rebuild_rail() -> void:
	_clear(_rail_detail)
	_material_buttons.clear()
	for mat in BlockDatabase.build_materials:
		var button := Button.new()
		button.theme_type_variation = &"RailButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = _rail_group
		button.focus_mode = Control.FOCUS_NONE
		button.text = "%s   %s" % [tr(mat.display_name), _have_text(mat.item)]
		if mat.item and mat.item.icon:
			button.icon = mat.item.icon
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", roundi(MATERIAL_ICON * _ui_scale))
		button.set_pressed_no_signal(mat.material_id == _material_id)
		button.pressed.connect(_set_material.bind(mat.material_id))
		_rail_detail.add_child(button)
		_material_buttons[mat.material_id] = button
	var naval := Button.new()
	naval.theme_type_variation = &"RailButton"
	naval.alignment = HORIZONTAL_ALIGNMENT_LEFT
	naval.toggle_mode = true
	naval.button_group = _rail_group
	naval.focus_mode = Control.FOCUS_NONE
	naval.text = "NAVAL_TITLE"
	naval.set_pressed_no_signal(_material_id == NAVAL_CATEGORY)
	naval.pressed.connect(_set_material.bind(NAVAL_CATEGORY))
	_rail_detail.add_child(naval)
	_material_buttons[NAVAL_CATEGORY] = naval


func _rebuild_recent() -> void:
	_clear(_recent_flow)
	var recent := building_system.recent_blocks
	_recent_box.visible = not recent.is_empty()
	for item in recent:
		var slot := ItemSlotView.new()
		slot.size_kind = &"ingredient"
		slot.show_item(item.icon)
		slot.tooltip_text = item.get_display_name()
		slot.selected = item == _selected_item()
		slot.slot_clicked.connect(func(_slot: ItemSlotView, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_pick(item))
		slot.hover_changed.connect(func(_slot: ItemSlotView, on: bool) -> void:
			_show(item if on else _selected_item()))
		_recent_flow.add_child(slot)


func _set_material(mat_id: String) -> void:
	_material_id = mat_id
	if mat_id == NAVAL_CATEGORY:
		_naval_panel.configure(building_system, inventory)
	_refresh()
	for id: String in _material_buttons:
		(_material_buttons[id] as Button).set_pressed_no_signal(id == mat_id)
	_rebuild_tiles()
	var current := _selected_item()
	_show(current if current and current.build_material_id == mat_id else _first_tile())


# --- Bloques --------------------------------------------------------------------------------------

func _rebuild_tiles() -> void:
	_clear(_tiles)
	_tile_buttons.clear()
	var mat := BlockDatabase.get_material_by_id(_material_id)
	_grid_title.text = tr(mat.display_name) if mat else ""
	var grouped := BlockDatabase.get_block_items_by_material()
	if not grouped.has(_material_id):
		return
	var selected := _selected_item()
	for item: ItemData in grouped[_material_id]["items"]:
		var button := Button.new()
		button.theme_type_variation = &"Tile"
		button.toggle_mode = true
		button.button_group = _tile_group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = TILE * _ui_scale
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.icon = item.icon
		button.text = _block_name(item)
		button.tooltip_text = item.get_display_name()
		button.set_pressed_no_signal(item == selected)
		button.modulate = Color.WHITE if _affordable(item) >= 1 else DIM
		button.pressed.connect(_pick.bind(item))
		button.mouse_entered.connect(_show.bind(item))
		button.mouse_exited.connect(func() -> void: _show(_selected_item()))
		_tiles.add_child(button)
		_tile_buttons[item] = button


func _first_tile() -> ItemData:
	for item: ItemData in _tile_buttons:
		return item
	return null


func _refresh_cell_buttons() -> void:
	for i in _cell_buttons.size():
		_cell_buttons[i].set_pressed_no_signal(i == building_system.cell_size_index)


## Lo deja como el bloque del martillo y cierra.
func _pick(item: ItemData) -> void:
	if item == null:
		return
	building_system.pick_block(item)
	block_picked.emit(item)
	close()


# --- Ficha ----------------------------------------------------------------------------------------

func _show(item: ItemData) -> void:
	if _material_id == NAVAL_CATEGORY:
		_detail_box.visible = false
		return
	_shown = item
	_detail_box.visible = item != null
	if item == null:
		return
	var mat := BlockDatabase.get_material_by_id(item.build_material_id)
	var block := BlockDatabase.get_block(item.block_id)
	_preview.show_item(item.icon)
	_name.text = item.get_display_name()
	_kind.text = ItemTaxonomy.kind_line(item) + (" · " + tr(mat.display_name) if mat else "")
	_description.text = item.get_description()
	_description.visible = _description.text != ""

	_clear(_stats)
	var cell := building_system.cell_size
	var cost := mat.get_cost_for_size(cell) if mat and mat.item else 0
	var have := inventory.get_item_count(mat.item) if inventory and mat and mat.item else 0
	var free := BuildingSystem.free_build or cost == 0
	_stat("BUILD_MENU_CELL_SIZE", _meters(cell))
	if free:
		_stat("BUILD_MENU_COST", tr("BUILD_MENU_FREE"))
	else:
		_stat("BUILD_MENU_COST", "%d %s" % [cost, mat.item.get_display_name().to_lower()])
		_stat("BUILD_MENU_HAVE", str(have), &"BetterLabel" if have >= cost else &"WorseLabel")
		var count := _affordable(item)
		_stat("BUILD_MENU_ENOUGH_FOR", tr("BUILD_MENU_BLOCKS_N") % count if count > 0 else tr("BUILD_MENU_NONE"),
			&"BetterLabel" if count > 0 else &"WorseLabel")
	_stat("BUILD_MENU_ROTATES", tr("BUILD_MENU_ROTATES_YES") if block and block.can_rotate else tr("UI_NO").capitalize())
	if item == _selected_item():
		_stat("BUILD_MENU_STATE", tr("BUILD_MENU_IN_HAMMER"), &"ValueLabel")

	_reason.text = "" if free or have >= cost else tr("BUILD_MENU_MISSING") % mat.item.get_display_name().to_lower()
	_reason.visible = _reason.text != ""


func _stat(key: String, value: String, variation: StringName = &"StatValue") -> void:
	var name_label := _label(key, &"StatLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.add_child(name_label)
	var value_label := _label(value, variation)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.add_child(value_label)


# --- Cuentas --------------------------------------------------------------------------------------

## El bloque+material que pone ahora el martillo.
func _selected_item() -> ItemData:
	return building_system.get_selected_block_item() if building_system else null


## Bloques de [item] que alcanza a poner lo que se lleva, al tamaño de celda de ahora (99999 si no
## cuesta nada).
func _affordable(item: ItemData) -> int:
	var mat := BlockDatabase.get_material_by_id(item.build_material_id)
	if BuildingSystem.free_build or mat == null or mat.item == null or inventory == null:
		return 99999
	return inventory.get_item_count(mat.item) / maxi(1, mat.get_cost_for_size(building_system.cell_size))


func _have_text(data: ItemData) -> String:
	if data == null or inventory == null:
		return ""
	return str(inventory.get_item_count(data))


## El nombre del bloque sin el material, que ya dice la pestaña («Rampa»).
func _block_name(item: ItemData) -> String:
	var generic := BlockDatabase.get_block_item(item.block_id)
	return generic.get_display_name() if generic else item.get_display_name()


static func _meters(value: float) -> String:
	return ItemTrait.number(value) + " m"


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
