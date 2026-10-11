class_name CraftingPanel
extends PanelContainer

## La ventana de fabricar (la vista CRAFTING de InventoryUI, a la derecha del inventario):
## - a la izquierda, las pestañas: «Todo» y las categorías de ItemTaxonomy que tienen recetas;
## - en medio, las recetas de la pestaña por era y, dentro de cada era, por dónde se hacen: a mano
##   y en cada estación de trabajo, con si hay una cerca (Workstation.in_reach) y, si la hay, su
##   botón de desmontarla. Lo que ahora no se puede hacer sale apagado;
## - a la derecha, la receta elegida: su ficha, dónde se hace, lo que pide para las veces que se
##   quieran hacer (la cantidad, con sus flechas, y «Máx») y el botón de fabricar.
## Lo fabricado va al inventario y lo que no cabe, al suelo. Ver docs/items.md y docs/ui.md.

const Config = preload("res://scripts/config.gd")
## Ancho de las pestañas, de la ficha de la receta y del campo de la cantidad, en la escala base.
const RAIL_WIDTH := 250.0
const DETAIL_WIDTH := 560.0
const QUANTITY_WIDTH := 150.0
## Veces como mucho de una tirada.
const MAX_TIMES := 99
## Cada cuánto se mira qué estaciones hay cerca (s).
const STATION_POLL := 0.4
const DIM := Color(1, 1, 1, 0.42)

var ui: InventoryUI
var ui_scale := 1.0:
	set(value):
		ui_scale = value
		_apply_scale()

## Categoría de la pestaña elegida (-1 = todas).
var _tab := -1
var _tab_buttons := {}
var _only_craftable := false
var _selected: RecipeData
var _tiles := {}
## Estaciones al alcance: id de su objeto → la más cercana (Workstation.in_reach).
var _stations := {}
var _poll := 0.0
## Al abrirla en una estación (E junto a ella): se va a sus recetas en cuanto se ven.
var _focus_station: StringName = &""

var _rail: VBoxContainer
var _rail_group := ButtonGroup.new()
var _scroll: ScrollContainer
var _list: VBoxContainer
var _stations_label: Label
var _detail_box: PanelContainer
var _preview: ItemSlotView
var _name: Label
var _kind: Label
var _yield: Label
var _stats: GridContainer
var _description: Label
var _where: Label
var _where_state: Label
var _inputs: VBoxContainer
var _quantity: SpinBox
var _max_button: Button
var _total: Label
var _make_button: Button
var _reason: Label


func _init() -> void:
	theme_type_variation = &"WindowPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	add_child(box)

	var header := HBoxContainer.new()
	var title := _label("FABRICAR", &"HeaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_stations_label = _label("", &"ValueLabel")
	_stations_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_stations_label)
	var only := CheckButton.new()
	only.text = "Solo lo que puedo hacer"
	only.focus_mode = Control.FOCUS_NONE
	only.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	only.toggled.connect(_set_only_craftable)
	header.add_child(only)
	box.add_child(header)
	box.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 2)
	body.add_child(_rail)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_detail_box = PanelContainer.new()
	_detail_box.theme_type_variation = &"Inset"
	body.add_child(_detail_box)
	_build_detail()

	box.add_child(HSeparator.new())
	var hint := _label("Clic en una receta: elegirla · Lo fabricado va al inventario; si no cabe, al suelo · Las estaciones de trabajo se plantan como las hogueras", &"HintLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)


## La ficha de la receta elegida: lo que es, dónde se hace y lo que pide, que se desplaza si no cabe,
## y al pie, siempre a la vista, la cantidad y el botón.
func _build_detail() -> void:
	var column := VBoxContainer.new()
	_detail_box.add_child(column)
	var info_scroll := ScrollContainer.new()
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(info_scroll)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(detail)
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
	_yield = _label("", &"ValueLabel")
	names.add_child(_yield)
	top.add_child(names)
	detail.add_child(top)
	_stats = GridContainer.new()
	_stats.columns = 2
	detail.add_child(_stats)
	_description = _label("", &"StatLabel")
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_description)
	detail.add_child(HSeparator.new())
	detail.add_child(_label("Dónde", &"SectionLabel"))
	var where := HBoxContainer.new()
	_where = _label("", &"StatValue")
	_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.add_child(_where)
	_where_state = _label("", &"BetterLabel")
	where.add_child(_where_state)
	detail.add_child(where)
	detail.add_child(HSeparator.new())
	detail.add_child(_label("Materiales", &"SectionLabel"))
	_inputs = VBoxContainer.new()
	_inputs.add_theme_constant_override("separation", 6)
	detail.add_child(_inputs)
	column.add_child(HSeparator.new())

	var amount := HBoxContainer.new()
	var amount_label := _label("Cantidad", &"StatLabel")
	amount_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(amount_label)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = MAX_TIMES
	_quantity.step = 1
	_quantity.rounded = true
	_quantity.select_all_on_focus = true
	_quantity.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity.tooltip_text = "Cuántas veces: flechas, rueda del ratón o escribiendo"
	_quantity.value_changed.connect(func(_value: float) -> void: _refresh_detail())
	amount.add_child(_quantity)
	_max_button = Button.new()
	_max_button.text = "Máx"
	_max_button.focus_mode = Control.FOCUS_NONE
	_max_button.tooltip_text = "Todas las que te alcanzan"
	_max_button.pressed.connect(_set_max)
	amount.add_child(_max_button)
	_total = _label("", &"ValueLabel")
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(_total)
	column.add_child(amount)
	_make_button = Button.new()
	_make_button.theme_type_variation = &"AccentButton"
	_make_button.focus_mode = Control.FOCUS_NONE
	_make_button.pressed.connect(_craft)
	column.add_child(_make_button)
	_reason = _label("", &"WorseLabel")
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_reason)


func _ready() -> void:
	_build_rail()
	_apply_scale()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = STATION_POLL
	if _signature(_stations_in_reach()) != _signature(_stations):
		refresh()


# --- Abrir ----------------------------------------------------------------------------------------

## Lo vuelve a montar todo con lo que se lleva y las estaciones de al lado.
func refresh() -> void:
	if ui == null or ui.inventory == null:
		return
	_stations = _stations_in_reach()
	_refresh_stations_label()
	if _selected == null:
		_selected = _first_recipe(_focus_station)
	_rebuild_list()
	_refresh_detail()


## Al abrirla con E junto a una estación: todas las pestañas y sus recetas a la vista.
func focus_station(station: StringName) -> void:
	_focus_station = station
	_set_tab(-1)
	var first := _first_recipe(station)
	if first != null:
		_select(first)


func _apply_scale() -> void:
	if _rail == null:
		return
	_rail.custom_minimum_size.x = roundf(RAIL_WIDTH * ui_scale)
	_detail_box.custom_minimum_size.x = roundf(DETAIL_WIDTH * ui_scale)
	_quantity.custom_minimum_size.x = roundf(QUANTITY_WIDTH * ui_scale)


# --- Pestañas -------------------------------------------------------------------------------------

## «Todo» y las categorías que tienen alguna receta, en el orden de ItemTaxonomy.
func _build_rail() -> void:
	var used := {}
	for recipe in Recipes.all():
		var result: ItemData = Config.get_item(recipe.result)
		if result != null:
			used[ItemTaxonomy.category_of(result)] = true
	var tabs: Array = [[-1, "Todo"]]
	for entry in ItemTaxonomy.CATEGORIES:
		if used.has(entry[0]):
			tabs.append([int(entry[0]), entry[1]])
	for tab in tabs:
		var button := Button.new()
		button.text = tab[1]
		button.theme_type_variation = &"RailButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = _rail_group
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = tab[0] == _tab
		button.pressed.connect(_set_tab.bind(tab[0]))
		_rail.add_child(button)
		_tab_buttons[tab[0]] = button


func _set_tab(category: int) -> void:
	_tab = category
	if _tab_buttons.has(category):
		(_tab_buttons[category] as Button).set_pressed_no_signal(true)
	_scroll.scroll_vertical = 0
	refresh()


func _set_only_craftable(on: bool) -> void:
	_only_craftable = on
	refresh()


# --- Recetas --------------------------------------------------------------------------------------

func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_tiles.clear()
	var era := -1
	var station: StringName = &"-"
	var grid: HFlowContainer = null
	var focus: Control = null
	for recipe in Recipes.all():
		var result: ItemData = Config.get_item(recipe.result)
		if result == null or (_tab >= 0 and ItemTaxonomy.category_of(result) != _tab):
			continue
		var can := _station_ready(recipe.station) and Recipes.can_craft(recipe, ui.inventory)
		if _only_craftable and not can:
			continue
		if int(recipe.era) != era:
			era = int(recipe.era)
			station = &"-"
			if _list.get_child_count() > 0:
				_list.add_child(HSeparator.new())
			_list.add_child(_label(Eras.name_of(recipe.era).to_upper(), &"SectionLabel"))
		if recipe.station != station:
			station = recipe.station
			var heading := _station_heading(station)
			_list.add_child(heading)
			if station == _focus_station and station != Recipes.HAND:
				focus = heading
			grid = HFlowContainer.new()
			_list.add_child(grid)
		var tile := ItemSlotView.new()
		tile.size_kind = &"recipe"
		tile.show_item(result.icon, recipe.amount)
		tile.tooltip_text = result.display_name
		tile.selected = recipe == _selected
		tile.modulate = Color.WHITE if can else DIM
		tile.slot_clicked.connect(func(_slot: ItemSlotView, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_select(recipe))
		grid.add_child(tile)
		_tiles[recipe] = tile
	if _tiles.is_empty():
		var empty := _label("No te alcanza para nada de esto: busca más material o acércate a una estación de trabajo." if _only_craftable else "Aquí no hay nada que fabricar.", &"HintLabel")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	if focus != null:
		_focus_station = &""
		_scroll_to.call_deferred(focus)


## «A mano» o el nombre de la estación, si hay una cerca y, si la hay, el botón de desmontarla.
func _station_heading(station: StringName) -> Control:
	var row := HBoxContainer.new()
	var title := _label(Recipes.station_name(station), &"StatValue")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	if station == Recipes.HAND:
		return row
	var near: Workstation = _stations.get(station)
	var state := _label("Cerca" if near != null else "No está cerca", &"BetterLabel" if near != null else &"WorseLabel")
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(state)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if near != null:
		var dismantle := Button.new()
		dismantle.text = "Desmontar"
		dismantle.focus_mode = Control.FOCUS_NONE
		dismantle.tooltip_text = "Vuelve al inventario"
		dismantle.pressed.connect(_dismantle.bind(near))
		row.add_child(dismantle)
	else:
		var made := _made_at(station)
		if made != "":
			var hint := _label("Se fabrica: %s" % made.to_lower(), &"HintLabel")
			hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(hint)
	return row


func _scroll_to(control: Control) -> void:
	if is_instance_valid(control):
		_scroll.ensure_control_visible(control)


func _select(recipe: RecipeData) -> void:
	if recipe != _selected:
		_quantity.set_value_no_signal(1)
	_selected = recipe
	for other in _tiles:
		(_tiles[other] as ItemSlotView).selected = other == recipe
	_refresh_detail()


## La primera receta de [station] o, si no hay, la primera de todas.
func _first_recipe(station: StringName) -> RecipeData:
	var all := Recipes.all()
	for recipe in all:
		if recipe.station == station:
			return recipe
	return all[0] if not all.is_empty() else null


# --- La receta elegida ----------------------------------------------------------------------------

func _refresh_detail() -> void:
	var recipe := _selected
	var result: ItemData = Config.get_item(recipe.result) if recipe != null else null
	_detail_box.visible = result != null
	if result == null or ui == null:
		return
	var inventory := ui.inventory
	var times := int(_quantity.value)
	_preview.show_item(result.icon, recipe.amount)
	_name.text = result.display_name
	_kind.text = ItemTaxonomy.kind_line(result)
	_yield.text = "Salen %d cada vez" % recipe.amount if recipe.amount > 1 else ""
	_yield.visible = recipe.amount > 1
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for row in ItemCard.stat_rows(result, null):
		var name_label := _label(row[0], &"StatLabel")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats.add_child(name_label)
		var value := _label(row[1], &"StatValue")
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats.add_child(value)
	_description.text = result.description.strip_edges()
	_description.visible = _description.text != ""

	var ready := _station_ready(recipe.station)
	_where.text = Recipes.station_name(recipe.station)
	_where_state.visible = recipe.station != Recipes.HAND
	_where_state.text = "Cerca" if ready else "No está cerca"
	_where_state.theme_type_variation = &"BetterLabel" if ready else &"WorseLabel"

	for child in _inputs.get_children():
		_inputs.remove_child(child)
		child.queue_free()
	var missing := Recipes.missing(recipe, inventory, times)
	for id: StringName in recipe.inputs:
		var data: ItemData = Config.get_item(id)
		var need: int = recipe.inputs[id] * times
		var row := HBoxContainer.new()
		var icon := ItemSlotView.new()
		icon.size_kind = &"ingredient"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if data != null:
			icon.show_item(data.icon)
		row.add_child(icon)
		var name_label := _label(data.display_name if data != null else String(id), &"StatLabel")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_label)
		var count := _label("%d / %d" % [inventory.get_item_count(data), need],
			&"WorseLabel" if missing.has(id) else &"BetterLabel")
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(count)
		_inputs.add_child(row)

	var made := recipe.amount * times
	_total.text = "Salen %d" % made if made > 1 else ""
	_max_button.disabled = Recipes.max_times(recipe, inventory) < 1
	_make_button.text = "Fabricar" if times == 1 else "Fabricar ×%d" % times
	_make_button.disabled = not ready or not missing.is_empty()
	if not ready:
		_reason.text = "Hay que estar junto a: %s" % Recipes.station_name(recipe.station).to_lower()
	elif not missing.is_empty():
		_reason.text = "Te falta material" if times == 1 else "Te falta material para %d" % times
	else:
		_reason.text = ""
	_reason.visible = _reason.text != ""


func _set_max() -> void:
	if _selected != null:
		_quantity.value = clampi(Recipes.max_times(_selected, ui.inventory), 1, MAX_TIMES)


func _craft() -> void:
	var recipe := _selected
	if recipe == null or ui == null:
		return
	if not _station_ready(recipe.station):
		_notify("Acércate a: %s" % Recipes.station_name(recipe.station).to_lower())
		return
	var times := int(_quantity.value)
	var left := Recipes.craft(recipe, ui.inventory, times)
	if left < 0:
		_notify("Te falta material")
		return
	var result: ItemData = Config.get_item(recipe.result)
	if left > 0:
		ui.drop_requested.emit(result, left)
	var made := recipe.amount * times
	_notify("Fabricas: %s" % result.display_name + (" ×%d" % made if made > 1 else "")
		+ (" · %d al suelo, no caben" % left if left > 0 else ""))
	ui.inventory.inventory_changed.emit()


# --- Estaciones -----------------------------------------------------------------------------------

func _stations_in_reach() -> Dictionary:
	if ui == null or ui.crafter == null or not is_instance_valid(ui.crafter) or not ui.crafter.is_inside_tree():
		return {}
	return Workstation.in_reach(get_tree(), ui.crafter.global_position)


## Se puede hacer aquí lo de [station]: a mano siempre; lo de una estación, con una cerca.
func _station_ready(station: StringName) -> bool:
	return station == Recipes.HAND or _stations.has(station)


## Dónde se fabrica la estación [station] («A mano», otra estación) o "" si no hay receta.
func _made_at(station: StringName) -> String:
	for recipe in Recipes.all():
		if recipe.result == station:
			return Recipes.station_name(recipe.station)
	return ""


func _refresh_stations_label() -> void:
	var names: Array[String] = []
	for id: StringName in _stations:
		names.append(Recipes.station_name(id))
	names.sort()
	_stations_label.text = "Cerca: " + ", ".join(names) if not names.is_empty() else "Sin estaciones de trabajo cerca"


func _dismantle(station: Workstation) -> void:
	if not is_instance_valid(station):
		return
	var data: ItemData = Config.get_item(station.item_id)
	# Fuera de los grupos ya: se libera al acabar el cuadro y antes se volvería a contar.
	station.remove_from_group(Workstation.GROUP)
	station.remove_from_group(GroundPlaceableTrait.PLACED_GROUP)
	station.remove_from_group(GameManager.SAVEABLE_GROUP)
	station.queue_free()
	if data != null:
		var left := ui.inventory.add_item(data, 1)
		if left > 0:
			ui.drop_requested.emit(data, left)
		_notify("Desmontas: %s" % data.display_name.to_lower())
	ui.inventory.inventory_changed.emit()


## Las estaciones que hay, para ver si han cambiado.
func _signature(stations: Dictionary) -> String:
	var parts: Array[String] = []
	for id: StringName in stations:
		parts.append("%s:%d" % [id, (stations[id] as Object).get_instance_id()])
	parts.sort()
	return ",".join(parts)


func _notify(text: String) -> void:
	if ui != null and ui.hotbar != null:
		ui.hotbar.notify(text)


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
