class_name GridManipulatorMenu
extends CanvasLayer

## Menú de blueprints («Blueprints» en la rueda del martillo, o la G), en Saga. Dos pestañas:
## - Construcción: la que se apuntaba al abrirlo (se congela al abrir: con el ratón suelto el
##   raycast del jugador ya no apunta a donde mirabas). Su miniatura, sus datos, lo que vale en
##   materiales (lo que devuelve al desmontarla), guardarla como blueprint (avisa antes de sustituir
##   uno), convertirla en dinámica y desmontarla (como quitar bloque a bloque con el martillo).
## - Biblioteca: los blueprints guardados, con miniatura, búsqueda y orden. La ficha del elegido:
##   medidas, bloques, lo que cuesta frente a lo que se lleva, colocarlo (queda una obra, BlueprintSite,
##   que se levanta con el martillo; construyendo gratis, entero), renombrarlo y borrarlo.
## Sin construcción apuntada abre en la biblioteca. Los blueprints de antes sin miniatura se pintan
## la primera vez que se ven (BlueprintThumbnail).

## Colocar el blueprint (el jugador cierra el menú y entra en modo colocación).
signal load_requested(blueprint_name: String, as_static: bool)
## Aviso corto para la barra (al desmontar, que cierra el menú).
signal notice(text: String)
signal closed()

enum Tab { CONSTRUCTION, LIBRARY }

const BACKDROP_SHADER := preload("res://shaders/ui/backdrop.gdshader")
## Medidas en la escala base de 1440 px de alto.
const WINDOW_SIZE := Vector2(1720.0, 980.0)
const LIST_WIDTH := 660.0
const PREVIEW_WIDTH := 600.0
const CARD_THUMB := 116.0
const CONSTRUCTION_THUMB := 380.0
const LIBRARY_THUMB := 240.0

## Grupo de grids sobre el que opera la pestaña de construcción; null si no se apuntaba a ninguna.
var target_grid: GridBase = null
var building_system: BuildingSystem
var inventory: Inventory

var _ui_scale := 1.0
var _tab := Tab.LIBRARY
var _root: Control
var _window: PanelContainer
var _tab_buttons := {}
var _tab_group := ButtonGroup.new()
var _construction: Control
var _library: Control
var _status: Label
var _thumbnails: BlueprintThumbnail

# Construcción
var _grid_thumb: TextureRect
var _grid_title: Label
var _grid_kind: Label
var _grid_stats: GridContainer
var _grid_value: VBoxContainer
var _name_edit: LineEdit
var _save_btn: Button
var _overwrite_hint: Label
var _convert_btn: Button
var _dismantle_btn: Button
var _no_target: Label
var _grid_body: Control
var _overwrite_armed := ""
var _dismantle_armed := false

# Biblioteca
var _search: LineEdit
var _sort_group := ButtonGroup.new()
var _sort_by_date := false
var _cards: VBoxContainer
var _card_group := ButtonGroup.new()
var _card_thumbs := {}
var _infos: Array = []
var _selected := ""
var _detail: Control
var _detail_thumb: TextureRect
var _detail_name: Label
var _detail_kind: Label
var _detail_stats: GridContainer
var _detail_unknown: Label
var _detail_costs: VBoxContainer
var _as_static_check: CheckButton
var _reason: Label
var _place_btn: Button
var _rename_btn: Button
var _delete_btn: Button
var _rename_row: HBoxContainer
var _rename_edit: LineEdit
var _delete_armed := false
## Miniaturas ya leídas o pintadas, por nombre (null = no tiene, o se está pintando).
var _thumb_cache := {}
var _thumb_queue: Array[String] = []
var _thumb_running := false


func _ready() -> void:
	layer = 10
	_thumbnails = BlueprintThumbnail.new()
	add_child(_thumbnails)
	_build_ui()
	visible = false
	get_viewport().size_changed.connect(_apply_scale)


func setup(bsys: BuildingSystem, inv: Inventory) -> void:
	building_system = bsys
	inventory = inv
	if inventory:
		inventory.inventory_changed.connect(func() -> void:
			if visible:
				_refresh_tab())


## Abre el menú sobre una grid (pestaña de construcción) o sin ella (biblioteca).
func open(grid: GridBase) -> void:
	target_grid = grid
	_overwrite_armed = ""
	_dismantle_armed = false
	_delete_armed = false
	set_status("")
	_apply_scale()
	visible = true
	_set_tab(Tab.CONSTRUCTION if grid != null else Tab.LIBRARY)


func close() -> void:
	if not visible:
		return
	visible = false
	target_grid = null
	# Lo que quedaba por pintar se vuelve a pedir la próxima vez.
	for bp_name in _thumb_queue:
		_thumb_cache.erase(bp_name)
	_thumb_queue.clear()
	closed.emit()


func toggle(grid: GridBase) -> void:
	if visible:
		close()
	else:
		open(grid)


## Aviso al pie del menú; [ok] = en verde, si no en rojo.
func set_status(text: String, ok: bool = true) -> void:
	_status.text = text
	_status.theme_type_variation = &"BetterLabel" if ok else &"WorseLabel"


func _set_tab(tab: Tab) -> void:
	_tab = tab
	(_tab_buttons[tab] as Button).set_pressed_no_signal(true)
	_construction.visible = tab == Tab.CONSTRUCTION
	_library.visible = tab == Tab.LIBRARY
	_refresh_tab()


func _refresh_tab() -> void:
	if _tab == Tab.CONSTRUCTION:
		_refresh_construction()
	else:
		_refresh_library()


# --- Montaje --------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = BACKDROP_SHADER
	backdrop_material.set_shader_parameter(&"darken", 0.5)
	backdrop.material = backdrop_material
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
	var title := _label("GRID_MENU_TITLE", &"HeaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for entry in [[Tab.CONSTRUCTION, "GRID_TAB_CONSTRUCTION"], [Tab.LIBRARY, "GRID_TAB_LIBRARY"]]:
		var button := Button.new()
		button.theme_type_variation = &"TabButton"
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = _tab_group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_set_tab.bind(entry[0]))
		header.add_child(button)
		_tab_buttons[entry[0]] = button
	var close_button := Button.new()
	close_button.theme_type_variation = &"CloseButton"
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)
	column.add_child(HSeparator.new())

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stack)
	_construction = _build_construction()
	_library = _build_library()
	for view in [_construction, _library]:
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(view)

	column.add_child(HSeparator.new())
	_status = _label("", &"BetterLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


func _apply_scale() -> void:
	_ui_scale = GameTheme.scale_for(get_viewport())
	var s := _ui_scale
	_root.theme = GameTheme.build(s)
	var viewport := get_viewport().get_visible_rect().size
	var size := Vector2(minf(WINDOW_SIZE.x * s, viewport.x - 48.0 * s), minf(WINDOW_SIZE.y * s, viewport.y - 200.0 * s))
	_window.offset_left = -size.x * 0.5
	_window.offset_right = size.x * 0.5
	_window.offset_top = -size.y * 0.5 - 50.0 * s
	_window.offset_bottom = size.y * 0.5 - 50.0 * s
	(_grid_thumb.get_parent().get_parent() as Control).custom_minimum_size.x = PREVIEW_WIDTH * s
	_grid_thumb.custom_minimum_size = Vector2(0, CONSTRUCTION_THUMB * s)
	(_cards.get_parent().get_parent() as Control).custom_minimum_size.x = LIST_WIDTH * s
	_detail_thumb.custom_minimum_size = Vector2(LIBRARY_THUMB, LIBRARY_THUMB) * s


# --- Construcción ---------------------------------------------------------------------------------

func _build_construction() -> Control:
	var view := VBoxContainer.new()
	_no_target = _label("GRID_NO_TARGET", &"HintLabel")
	_no_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(_no_target)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(body)
	_grid_body = body

	var preview := PanelContainer.new()
	preview.theme_type_variation = &"Inset"
	body.add_child(preview)
	var preview_column := VBoxContainer.new()
	preview.add_child(preview_column)
	_grid_thumb = _thumb_rect()
	preview_column.add_child(_grid_thumb)
	_grid_title = _label("", &"CardTitle")
	_grid_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview_column.add_child(_grid_title)
	_grid_kind = _label("", &"HintLabel")
	_grid_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_column.add_child(_grid_kind)
	preview_column.add_child(HSeparator.new())
	_grid_stats = GridContainer.new()
	_grid_stats.columns = 2
	preview_column.add_child(_grid_stats)

	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)

	right.add_child(_label("GRID_SECTION_VALUE", &"SectionLabel"))
	_grid_value = VBoxContainer.new()
	_grid_value.add_theme_constant_override("separation", 6)
	right.add_child(_grid_value)
	var value_hint := _label("GRID_VALUE_HINT", &"HintLabel")
	value_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(value_hint)
	right.add_child(HSeparator.new())

	right.add_child(_label("GRID_SECTION_SAVE", &"SectionLabel"))
	var save_row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "GRID_NAME_PLACEHOLDER"
	# El nombre lo pone el jugador: no se busca en las traducciones.
	_name_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(_text: String) -> void: _refresh_save_state())
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_save_pressed())
	save_row.add_child(_name_edit)
	_save_btn = Button.new()
	_save_btn.theme_type_variation = &"AccentButton"
	_save_btn.text = "GRID_SAVE"
	_save_btn.focus_mode = Control.FOCUS_NONE
	_save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(_save_btn)
	right.add_child(save_row)
	_overwrite_hint = _label("", &"HintLabel")
	_overwrite_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_overwrite_hint)
	right.add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	_convert_btn = Button.new()
	_convert_btn.text = "GRID_CONVERT"
	_convert_btn.focus_mode = Control.FOCUS_NONE
	_convert_btn.pressed.connect(_on_convert_pressed)
	actions.add_child(_convert_btn)
	_dismantle_btn = Button.new()
	_dismantle_btn.text = "GRID_DISMANTLE"
	_dismantle_btn.tooltip_text = "GRID_DISMANTLE_TIP"
	_dismantle_btn.focus_mode = Control.FOCUS_NONE
	_dismantle_btn.add_theme_color_override("font_color", GameTheme.BLOOD.lightened(0.25))
	_dismantle_btn.pressed.connect(_on_dismantle_pressed)
	actions.add_child(_dismantle_btn)
	right.add_child(actions)
	return view


func _target_alive() -> bool:
	return target_grid != null and is_instance_valid(target_grid) \
		and GridManager.get_grid(target_grid.grid_id) == target_grid


func _refresh_construction() -> void:
	var alive := _target_alive()
	_no_target.visible = not alive
	_grid_body.visible = alive
	if not alive:
		return
	var stats := GridManager.get_group_stats(target_grid.grid_id)
	if stats.is_empty():
		_no_target.text = "GRID_GONE"
		_no_target.visible = true
		_grid_body.visible = false
		return
	_grid_title.text = tr("GRID_TITLE_ID") % stats["grid_id"]
	_grid_kind.text = "%s · %s" % [tr("GRID_DYNAMIC" if stats["dynamic"] else "GRID_STATIC").capitalize(),
		str(stats["planet"])]
	_clear(_grid_stats)
	var size: Vector3 = stats["size"]
	_stat(_grid_stats, "GRID_STAT_SIZE", _dims(size))
	_stat(_grid_stats, "GRID_STAT_BLOCKS", str(stats["blocks"]))
	_stat(_grid_stats, "GRID_STAT_PROPS", str(stats["props"]))
	_stat(_grid_stats, "GRID_STAT_VOLUME", "%s m³" % ItemTrait.number(stats["volume"]))
	_stat(_grid_stats, "GRID_STAT_CELLS", _cells(stats["cell_sizes"]))
	if int(stats["grids"]) > 1:
		_stat(_grid_stats, "GRID_STAT_GRIDS", str(stats["grids"]))
	if stats.has("mass"):
		_stat(_grid_stats, "GRID_STAT_MASS", "%d kg" % roundi(stats["mass"]))
	if stats.has("flood"):
		var flood: Dictionary = stats["flood"]
		_stat(_grid_stats, "GRID_STAT_COMPARTMENTS", tr("GRID_COMPARTMENTS_VALUE") % [
			flood["compartments"], flood["flooded"], flood["breached"]])

	var group := GridManager.get_grid_group(target_grid.grid_id)
	_fill_costs(_grid_value, BuildCost.of_grids(group, true), false)
	_convert_btn.visible = not stats["dynamic"]
	_dismantle_btn.text = "GRID_DELETE_CONFIRM" if _dismantle_armed else "GRID_DISMANTLE"
	if _name_edit.text == "":
		_name_edit.text = str(stats["grid_id"])
	_refresh_save_state()
	_grid_thumb.texture = null
	_render_target_thumb()


func _render_target_thumb() -> void:
	var grid := target_grid
	var texture := await _thumbnails.render_grids(GridManager.get_grid_group(grid.grid_id))
	if visible and grid == target_grid:
		_grid_thumb.texture = texture


func _refresh_save_state() -> void:
	var bp_name := GridBlueprint.sanitize_name(_name_edit.text)
	if bp_name != _overwrite_armed:
		_overwrite_armed = ""
	var taken := bp_name != "" and GridBlueprint.exists(bp_name)
	_overwrite_hint.text = tr("GRID_OVERWRITE_WARN") % bp_name if taken else ""
	_overwrite_hint.visible = taken
	_save_btn.text = "GRID_REPLACE" if _overwrite_armed != "" else "GRID_SAVE"
	_save_btn.disabled = bp_name == ""


func _on_save_pressed() -> void:
	if not _target_alive():
		return
	var bp_name := GridBlueprint.sanitize_name(_name_edit.text)
	if bp_name == "":
		set_status(tr("GRID_NAME_NEEDED"), false)
		return
	# Sustituir uno que ya existe pide pulsar dos veces.
	if GridBlueprint.exists(bp_name) and _overwrite_armed != bp_name:
		_overwrite_armed = bp_name
		_refresh_save_state()
		return
	_overwrite_armed = ""
	var blocks := building_system.save_grid_blueprint(target_grid.grid_id, bp_name)
	if blocks < 0:
		set_status(tr("GRID_CANT_SAVE") % bp_name, false)
		return
	_thumb_cache.erase(bp_name)
	set_status(tr("GRID_SAVED") % [bp_name, blocks])
	_refresh_save_state()
	if not _target_alive():
		return
	var texture := await _thumbnails.render_grids(GridManager.get_grid_group(target_grid.grid_id), bp_name)
	if texture:
		_thumb_cache[bp_name] = texture


func _on_convert_pressed() -> void:
	if not _target_alive():
		return
	var converted := GridManager.convert_to_dynamic(target_grid.grid_id)
	if converted.is_empty():
		set_status(tr("GRID_CANT_CONVERT"), false)
		return
	# La conversión sustituye las PlanetGrid por DynamicPlanetGrid nuevas: se reapunta a la grid
	# resultante o el menú seguiría mostrando (y desmontando) las estáticas ya vaciadas.
	target_grid = converted[0]
	set_status(tr("GRID_CONVERTED") % converted.size())
	_refresh_construction()


func _on_dismantle_pressed() -> void:
	if not _target_alive():
		return
	if not _dismantle_armed:
		_dismantle_armed = true
		_dismantle_btn.text = "GRID_DELETE_CONFIRM"
		return
	var refund := building_system.dismantle_group(target_grid.grid_id)
	var text := tr("GRID_DISMANTLED_FREE") if BuildingSystem.free_build else \
		tr("GRID_DISMANTLED") % (BuildCost.describe(refund) if not refund.is_empty() else tr("GRID_VALUE_NONE").to_lower())
	close()
	notice.emit(text)


# --- Biblioteca -----------------------------------------------------------------------------------

func _build_library() -> Control:
	var view := HBoxContainer.new()

	var list_column := VBoxContainer.new()
	view.add_child(list_column)
	var tools := HBoxContainer.new()
	_search = LineEdit.new()
	_search.placeholder_text = "GRID_SEARCH"
	_search.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _rebuild_cards())
	tools.add_child(_search)
	for entry in [[false, "GRID_SORT_NAME"], [true, "GRID_SORT_DATE"]]:
		var button := Button.new()
		button.theme_type_variation = &"TabButton"
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = _sort_group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.set_pressed_no_signal(entry[0] == _sort_by_date)
		button.pressed.connect(func() -> void:
			_sort_by_date = entry[0]
			_rebuild_cards())
		tools.add_child(button)
	list_column.add_child(tools)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_column.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 8)
	scroll.add_child(_cards)

	var detail_box := PanelContainer.new()
	detail_box.theme_type_variation = &"Inset"
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(detail_box)
	var detail := VBoxContainer.new()
	detail_box.add_child(detail)
	_detail = detail
	# Arriba, la miniatura y a su lado el nombre y los datos; debajo, lo que cuesta y los botones.
	var top := HBoxContainer.new()
	detail.add_child(top)
	_detail_thumb = _thumb_rect()
	_detail_thumb.size_flags_horizontal = Control.SIZE_FILL
	top.add_child(_detail_thumb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	_detail_name = _label("", &"CardTitle")
	_detail_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_detail_name)
	_detail_kind = _label("", &"HintLabel")
	_detail_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_detail_kind)
	info.add_child(HSeparator.new())
	_detail_stats = GridContainer.new()
	_detail_stats.columns = 2
	info.add_child(_detail_stats)
	_detail_unknown = _label("", &"WorseLabel")
	_detail_unknown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_detail_unknown)
	detail.add_child(HSeparator.new())
	detail.add_child(_label("GRID_MATERIALS", &"SectionLabel"))
	var costs_scroll := ScrollContainer.new()
	costs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	costs_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(costs_scroll)
	_detail_costs = VBoxContainer.new()
	_detail_costs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_costs.add_theme_constant_override("separation", 6)
	costs_scroll.add_child(_detail_costs)
	detail.add_child(HSeparator.new())

	_as_static_check = CheckButton.new()
	_as_static_check.text = "GRID_PLACE_STATIC"
	_as_static_check.tooltip_text = "GRID_PLACE_STATIC_TIP"
	_as_static_check.focus_mode = Control.FOCUS_NONE
	detail.add_child(_as_static_check)
	_reason = _label("", &"WorseLabel")
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_reason)
	_rename_row = HBoxContainer.new()
	_rename_edit = LineEdit.new()
	_rename_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_edit.text_submitted.connect(func(_text: String) -> void: _on_rename_confirmed())
	_rename_row.add_child(_rename_edit)
	var accept := Button.new()
	accept.text = "UI_ACCEPT"
	accept.focus_mode = Control.FOCUS_NONE
	accept.pressed.connect(_on_rename_confirmed)
	_rename_row.add_child(accept)
	var cancel := Button.new()
	cancel.text = "UI_CANCEL"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void: _rename_row.visible = false)
	_rename_row.add_child(cancel)
	_rename_row.visible = false
	detail.add_child(_rename_row)
	var buttons := HBoxContainer.new()
	_place_btn = Button.new()
	_place_btn.theme_type_variation = &"AccentButton"
	_place_btn.text = "GRID_PLACE"
	# Los controles de colocar salen también en el panel mientras se coloca.
	_place_btn.tooltip_text = "GRID_PLACE_HINT"
	_place_btn.focus_mode = Control.FOCUS_NONE
	_place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_btn.pressed.connect(_on_place_pressed)
	buttons.add_child(_place_btn)
	_rename_btn = Button.new()
	_rename_btn.text = "GRID_RENAME"
	_rename_btn.focus_mode = Control.FOCUS_NONE
	_rename_btn.pressed.connect(_on_rename_pressed)
	buttons.add_child(_rename_btn)
	_delete_btn = Button.new()
	_delete_btn.text = "GRID_DELETE_BLUEPRINT"
	_delete_btn.focus_mode = Control.FOCUS_NONE
	_delete_btn.add_theme_color_override("font_color", GameTheme.BLOOD.lightened(0.25))
	_delete_btn.pressed.connect(_on_delete_pressed)
	buttons.add_child(_delete_btn)
	detail.add_child(buttons)
	return view


func _refresh_library() -> void:
	_infos = GridBlueprint.list_infos()
	_rebuild_cards()


## Las fichas que pasan la búsqueda, en el orden elegido.
func _visible_infos() -> Array:
	var query := _search.text.strip_edges().to_lower()
	var out := _infos.filter(func(info: Dictionary) -> bool:
		return query == "" or String(info["name"]).to_lower().contains(query))
	if _sort_by_date:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("created", "")) > str(b.get("created", "")))
	return out


func _rebuild_cards() -> void:
	_clear(_cards)
	_card_thumbs.clear()
	var shown := _visible_infos()
	if shown.is_empty():
		var empty := _label(tr("GRID_NO_MATCH") % _search.text.strip_edges() if not _infos.is_empty()
			else tr("GRID_NO_BLUEPRINTS_HINT"), &"HintLabel")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cards.add_child(empty)
		_show_detail({})
		return
	var keep := ""
	for info: Dictionary in shown:
		if info["name"] == _selected:
			keep = _selected
		_cards.add_child(_card(info))
	_select(keep if keep != "" else String(shown[0]["name"]))


func _card(info: Dictionary) -> Button:
	var bp_name: String = info["name"]
	var s := _ui_scale
	var button := Button.new()
	button.theme_type_variation = &"Tile"
	button.toggle_mode = true
	button.button_group = _card_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, (CARD_THUMB + 20.0) * s)
	button.set_meta(&"bp_name", bp_name)
	button.pressed.connect(_select.bind(bp_name))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, roundi(10 * s))
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(CARD_THUMB, CARD_THUMB) * s
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumb)
	_card_thumbs[bp_name] = thumb
	_set_thumb(thumb, bp_name, info)

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", roundi(2 * s))
	row.add_child(texts)
	var title := _label(bp_name, &"StatValue")
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var line := _label(tr("GRID_CARD_LINE") % [_dims(info["size"]), int(info.get("blocks", 0))], &"StatLabel")
	texts.add_child(line)
	var affordable := _affordable(info)
	var state := _label("GRID_CAN_BUILD" if affordable else "GRID_CANT_BUILD",
		&"BetterLabel" if affordable else &"WorseLabel")
	texts.add_child(state)
	for label: Label in [title, line, state]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button


func _select(bp_name: String) -> void:
	_selected = bp_name
	_delete_armed = false
	_rename_row.visible = false
	for card in _cards.get_children():
		if card is Button:
			(card as Button).set_pressed_no_signal(card.get_meta(&"bp_name", "") == bp_name)
	for info: Dictionary in _infos:
		if info["name"] == bp_name:
			_show_detail(info)
			return
	_show_detail({})


func _show_detail(info: Dictionary) -> void:
	_detail.visible = not info.is_empty()
	if info.is_empty():
		return
	var bp_name: String = info["name"]
	_detail_name.text = bp_name
	var created := str(info.get("created", "")).replace("T", " ")
	_detail_kind.text = tr("GRID_SAVED_ON_TYPE") % [created,
		tr("GRID_DYNAMIC" if info.get("dynamic", false) else "GRID_STATIC")]
	_set_thumb(_detail_thumb, bp_name, info)
	_clear(_detail_stats)
	_stat(_detail_stats, "GRID_STAT_SIZE", _dims(info["size"]))
	_stat(_detail_stats, "GRID_STAT_BLOCKS", str(int(info.get("blocks", 0))))
	_stat(_detail_stats, "GRID_STAT_PROPS", str(int(info.get("props", 0))))
	_stat(_detail_stats, "GRID_STAT_CELLS", _cells(info.get("cell_sizes", [])))
	if int(info.get("grids", 1)) > 1:
		_stat(_detail_stats, "GRID_STAT_GRIDS", str(int(info["grids"])))
	var unknown := int(info.get("unknown_blocks", 0))
	_detail_unknown.text = tr("GRID_UNKNOWN_BLOCKS") % unknown if unknown > 0 else ""
	_detail_unknown.visible = unknown > 0

	var cost := BuildCost.of_counts(info.get("counts", {}))
	_fill_costs(_detail_costs, cost, true)
	_as_static_check.visible = info.get("dynamic", false)
	# Se coloca siempre: queda una obra, y los materiales se le aportan después.
	_place_btn.disabled = false
	if BuildingSystem.free_build:
		_reason.text = tr("GRID_FREE_BUILD")
		_reason.theme_type_variation = &"BetterLabel"
	else:
		_reason.text = tr("GRID_PLACE_AS_SITE")
		_reason.theme_type_variation = &"HintLabel"
	_reason.visible = _reason.text != ""
	_delete_btn.text = "GRID_DELETE_CONFIRM" if _delete_armed else "GRID_DELETE_BLUEPRINT"


func _affordable(info: Dictionary) -> bool:
	if BuildingSystem.free_build:
		return true
	return BuildCost.missing(BuildCost.of_counts(info.get("counts", {})), inventory).is_empty()


func _on_place_pressed() -> void:
	if _selected == "":
		return
	var as_static := _as_static_check.visible and _as_static_check.button_pressed
	load_requested.emit(_selected, as_static)


func _on_rename_pressed() -> void:
	if _selected == "":
		return
	_rename_edit.text = _selected
	_rename_row.visible = true
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _on_rename_confirmed() -> void:
	var new_name := GridBlueprint.sanitize_name(_rename_edit.text)
	if new_name == "" or new_name == _selected:
		_rename_row.visible = false
		return
	if not GridBlueprint.rename_on_disk(_selected, new_name):
		set_status(tr("GRID_CANT_RENAME") % new_name, false)
		return
	_thumb_cache[new_name] = _thumb_cache.get(_selected)
	_thumb_cache.erase(_selected)
	_rename_row.visible = false
	_rename_edit.release_focus()
	_selected = new_name
	set_status(tr("GRID_RENAMED") % new_name)
	_refresh_library()


func _on_delete_pressed() -> void:
	if _selected == "":
		return
	if not _delete_armed:
		_delete_armed = true
		_delete_btn.text = "GRID_DELETE_CONFIRM"
		return
	var bp_name := _selected
	if GridBlueprint.delete_from_disk(bp_name):
		set_status(tr("GRID_BLUEPRINT_DELETED") % bp_name)
	else:
		set_status(tr("GRID_CANT_DELETE") % bp_name, false)
	_thumb_cache.erase(bp_name)
	_selected = ""
	_refresh_library()


# --- Miniaturas -----------------------------------------------------------------------------------

## Pone en [rect] la miniatura de [bp_name]: la guardada o, si no tiene, la pide (una vez).
func _set_thumb(rect: TextureRect, bp_name: String, info: Dictionary) -> void:
	if not _thumb_cache.has(bp_name):
		var texture := GridBlueprint.load_thumbnail(bp_name)
		# Hueco en la caché mientras se pinta: así no se pide dos veces.
		_thumb_cache[bp_name] = texture
		if texture == null and int(info.get("blocks", 0)) <= BlueprintThumbnail.DATA_BLOCK_LIMIT \
				and BlueprintThumbnail.can_render():
			_thumb_queue.append(bp_name)
			_run_thumb_queue()
	rect.texture = _thumb_cache.get(bp_name)


func _run_thumb_queue() -> void:
	if _thumb_running:
		return
	_thumb_running = true
	while not _thumb_queue.is_empty() and visible:
		var bp_name: String = _thumb_queue.pop_front()
		var data := GridBlueprint.load_from_disk(bp_name)
		var texture: Texture2D = null
		if not data.is_empty():
			texture = await _thumbnails.render_data(data, bp_name)
		_thumb_cache[bp_name] = texture
		if _card_thumbs.has(bp_name) and is_instance_valid(_card_thumbs[bp_name]):
			(_card_thumbs[bp_name] as TextureRect).texture = texture
		if bp_name == _selected:
			_detail_thumb.texture = texture
	_thumb_running = false


# --- Piezas ---------------------------------------------------------------------------------------

## Filas de un coste: el icono, el nombre y la cantidad (con [against_inventory], «lo que llevas /
## lo que pide», en verde o en rojo).
func _fill_costs(box: VBoxContainer, cost: Dictionary, against_inventory: bool) -> void:
	_clear(box)
	var rows := BuildCost.rows(cost, inventory)
	if rows.is_empty():
		box.add_child(_label("GRID_VALUE_NONE", &"StatLabel"))
		return
	for row: Array in rows:
		var data: ItemData = row[0]
		var line := HBoxContainer.new()
		var icon := ItemSlotView.new()
		icon.size_kind = &"ingredient"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.show_item(data.icon)
		line.add_child(icon)
		var item_name := _label(data.get_display_name(), &"StatLabel")
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(item_name)
		var count: Label
		if against_inventory and not BuildingSystem.free_build:
			var enough: bool = row[2] >= row[1]
			count = _label("%d / %d" % [row[2], row[1]], &"BetterLabel" if enough else &"WorseLabel")
		else:
			count = _label(str(row[1]), &"StatValue")
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(count)
		box.add_child(line)


func _stat(grid: GridContainer, key: String, value: String) -> void:
	var name_label := _label(key, &"StatLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(name_label)
	var value_label := _label(value, &"StatValue")
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	grid.add_child(value_label)


func _thumb_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func _dims(size: Vector3) -> String:
	return "%s × %s × %s m" % [ItemTrait.number(size.x), ItemTrait.number(size.y), ItemTrait.number(size.z)]


static func _cells(cells: Array) -> String:
	var parts: Array[String] = []
	for cell in cells:
		parts.append(ItemTrait.number(float(cell)) + " m")
	return ", ".join(parts)


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
