class_name CraftingPanel
extends PanelContainer

## La ventana de fabricar (la vista CRAFTING de InventoryUI, a la derecha del inventario). Enseña las
## recetas de un sitio: las que se hacen a mano (con el Tabulador) o las de una estación (E junto a
## ella, o «Recetas» en la hoguera: show_station), cada una con su menú:
## - arriba, de qué sitio es, si está cerca y, si es una estación de trabajo, el botón de desmontarla;
## - a la izquierda, las pestañas: «Todo» y las categorías de ItemTaxonomy que tienen recetas ahí;
## - en medio, sus recetas por era. Lo que ahora no se puede hacer sale apagado;
## - a la derecha, la receta elegida: su ficha, dónde se hace, lo que pide para las veces que se
##   quieran hacer (la cantidad, con sus flechas, y «Máx») y el botón de fabricar.
## Lo fabricado va al inventario y lo que no cabe, al suelo. Ver docs/items.md y docs/ui.md.

## Ancho de las pestañas, de la ficha de la receta y del campo de la cantidad, en la escala base.
const RAIL_WIDTH := 250.0
const DETAIL_WIDTH := 560.0
const QUANTITY_WIDTH := 150.0
## Veces como mucho de una tirada.
const MAX_TIMES := 99
## Cada cuánto se mira si la estación sigue cerca (s).
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
## De qué sitio son las recetas: Recipes.HAND o el id de la estación (Workstation.CAMPFIRE, la
## hoguera), y la que se ha abierto (null a mano).
var _station: StringName = Recipes.HAND
var _station_node: Node3D
## Si la estación sigue al alcance (y la hoguera, encendida), mirado cada STATION_POLL.
var _near := false
var _poll := 0.0

var _rail: VBoxContainer
var _rail_group := ButtonGroup.new()
var _scroll: ScrollContainer
var _list: VBoxContainer
var _title: Label
var _station_state: Label
var _dismantle_button: Button
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
	_title = _label("", &"HeaderLabel")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_station_state = _label("", &"BetterLabel")
	_station_state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_station_state)
	_dismantle_button = Button.new()
	_dismantle_button.text = "UI_DISMANTLE"
	_dismantle_button.focus_mode = Control.FOCUS_NONE
	_dismantle_button.tooltip_text = "CRAFT_DISMANTLE_TIP"
	_dismantle_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dismantle_button.pressed.connect(func() -> void: _dismantle(_station_node as Workstation))
	header.add_child(_dismantle_button)
	var only := CheckButton.new()
	only.text = "CRAFT_ONLY_CRAFTABLE"
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
	var hint := _label("CRAFT_HINT", &"HintLabel")
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
	detail.add_child(_label("CRAFT_WHERE", &"SectionLabel"))
	var where := HBoxContainer.new()
	_where = _label("", &"StatValue")
	_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.add_child(_where)
	_where_state = _label("", &"BetterLabel")
	where.add_child(_where_state)
	detail.add_child(where)
	detail.add_child(HSeparator.new())
	detail.add_child(_label("CRAFT_MATERIALS", &"SectionLabel"))
	_inputs = VBoxContainer.new()
	_inputs.add_theme_constant_override("separation", 6)
	detail.add_child(_inputs)
	column.add_child(HSeparator.new())

	var amount := HBoxContainer.new()
	var amount_label := _label("CARD_QUANTITY", &"StatLabel")
	amount_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(amount_label)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = MAX_TIMES
	_quantity.step = 1
	_quantity.rounded = true
	_quantity.select_all_on_focus = true
	_quantity.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity.tooltip_text = "CRAFT_QUANTITY_TIP"
	_quantity.value_changed.connect(func(_value: float) -> void: _refresh_detail())
	amount.add_child(_quantity)
	_max_button = Button.new()
	_max_button.text = "CRAFT_MAX"
	_max_button.focus_mode = Control.FOCUS_NONE
	_max_button.tooltip_text = "CRAFT_MAX_TIP"
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
	if _station_near() != _near:
		refresh()


# --- Abrir ----------------------------------------------------------------------------------------

## Lo vuelve a montar todo con lo que se lleva y la estación de al lado.
func refresh() -> void:
	if ui == null or ui.inventory == null:
		return
	if _station != Recipes.HAND and not is_instance_valid(_station_node):
		show_station(null)
		return
	_near = _station_near()
	_refresh_header()
	if _selected == null or _selected.station != _station:
		_selected = _first_recipe()
	_rebuild_list()
	_refresh_detail()


## Las recetas de [station] (una estación de trabajo o una hoguera) o, con null, las de a mano. Vuelve
## a la pestaña «Todo» y a su primera receta.
func show_station(station: Node3D) -> void:
	_station_node = station
	if station is Workstation:
		_station = (station as Workstation).item_id
	elif station is Campfire:
		_station = Workstation.CAMPFIRE
	else:
		_station_node = null
		_station = Recipes.HAND
	_selected = null
	_quantity.set_value_no_signal(1)
	_build_rail()
	_set_tab(-1)


func _apply_scale() -> void:
	if _rail == null:
		return
	_rail.custom_minimum_size.x = roundf(RAIL_WIDTH * ui_scale)
	_detail_box.custom_minimum_size.x = roundf(DETAIL_WIDTH * ui_scale)
	_quantity.custom_minimum_size.x = roundf(QUANTITY_WIDTH * ui_scale)


# --- Pestañas -------------------------------------------------------------------------------------

## «Todo» y las categorías que tienen alguna receta en este sitio, en el orden de ItemTaxonomy.
func _build_rail() -> void:
	for child in _rail.get_children():
		_rail.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	var used := {}
	for recipe in Recipes.of_station(_station):
		var result: ItemData = ItemCatalog.get_item(recipe.result)
		if result != null:
			used[ItemTaxonomy.category_of(result)] = true
	var tabs: Array = [[-1, "INV_FILTER_ALL"]]
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
	var grid: HFlowContainer = null
	for recipe in Recipes.of_station(_station):
		var result: ItemData = ItemCatalog.get_item(recipe.result)
		if result == null or (_tab >= 0 and ItemTaxonomy.category_of(result) != _tab):
			continue
		var can := _station_ready(recipe.station) and Recipes.can_craft(recipe, ui.inventory, 1, _needs())
		if _only_craftable and not can:
			continue
		if int(recipe.era) != era:
			era = int(recipe.era)
			if _list.get_child_count() > 0:
				_list.add_child(HSeparator.new())
			_list.add_child(_label(Eras.name_of(recipe.era).to_upper(), &"SectionLabel"))
			grid = HFlowContainer.new()
			_list.add_child(grid)
		var tile := ItemSlotView.new()
		tile.size_kind = &"recipe"
		tile.show_item(result.icon, recipe.amount)
		tile.tooltip_text = result.get_display_name()
		tile.selected = recipe == _selected
		tile.modulate = Color.WHITE if can else DIM
		tile.slot_clicked.connect(func(_slot: ItemSlotView, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_select(recipe))
		grid.add_child(tile)
		_tiles[recipe] = tile
	if _tiles.is_empty():
		var empty := _label("CRAFT_NOTHING_AFFORDABLE" if _only_craftable else "CRAFT_NOTHING_HERE", &"HintLabel")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)


## Arriba: de qué sitio son las recetas, si está cerca y, en una estación de trabajo, desmontarla.
func _refresh_header() -> void:
	_title.text = tr("CRAFT_BY_HAND_TITLE") if _station == Recipes.HAND else Recipes.station_name(_station).to_upper()
	_station_state.visible = _station != Recipes.HAND
	_station_state.text = _near_text(_station, _near)
	_station_state.theme_type_variation = &"BetterLabel" if _near else &"WorseLabel"
	_dismantle_button.visible = _station_node is Workstation and _near


func _select(recipe: RecipeData) -> void:
	if recipe != _selected:
		_quantity.set_value_no_signal(1)
	_selected = recipe
	for other in _tiles:
		(_tiles[other] as ItemSlotView).selected = other == recipe
	_refresh_detail()


## La primera receta de este sitio, o null.
func _first_recipe() -> RecipeData:
	var here := Recipes.of_station(_station)
	return here[0] if not here.is_empty() else null


# --- La receta elegida ----------------------------------------------------------------------------

func _refresh_detail() -> void:
	var recipe := _selected
	var result: ItemData = ItemCatalog.get_item(recipe.result) if recipe != null else null
	_detail_box.visible = result != null
	if result == null or ui == null:
		return
	var inventory := ui.inventory
	var times := int(_quantity.value)
	_preview.show_item(result.icon, recipe.amount)
	_name.text = result.get_display_name()
	_kind.text = ItemTaxonomy.kind_line(result)
	_yield.text = tr("CRAFT_YIELD") % recipe.amount if recipe.amount > 1 else ""
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
	_description.text = result.get_description().strip_edges()
	_description.visible = _description.text != ""

	var ready := _station_ready(recipe.station)
	_where.text = Recipes.station_name(recipe.station)
	_where_state.visible = recipe.station != Recipes.HAND
	_where_state.text = _near_text(recipe.station, ready)
	_where_state.theme_type_variation = &"BetterLabel" if ready else &"WorseLabel"

	for child in _inputs.get_children():
		_inputs.remove_child(child)
		child.queue_free()
	var missing := Recipes.missing(recipe, inventory, times, _needs())
	if recipe.water > 0:
		_inputs.add_child(_input_row(ItemCatalog.get_item(&"waterskin"), tr("CRAFT_WATER"),
			tr("INV_SIPS_OF") % [_needs().water if _needs() != null else 0, recipe.water * times],
			missing.has(Recipes.WATER)))
	for id: StringName in recipe.inputs:
		var data: ItemData = ItemCatalog.get_item(id)
		var need: int = recipe.inputs[id] * times
		_inputs.add_child(_input_row(data, data.get_display_name() if data != null else String(id),
			"%d / %d" % [inventory.get_item_count(data), need], missing.has(id)))

	var made := recipe.amount * times
	_total.text = tr("CRAFT_TOTAL") % made if made > 1 else ""
	_max_button.disabled = Recipes.max_times(recipe, inventory, _needs()) < 1
	_make_button.text = tr("INV_CRAFT") if times == 1 else tr("CRAFT_MAKE_N") % times
	_make_button.disabled = not ready or not missing.is_empty()
	if not ready and recipe.station == Workstation.CAMPFIRE:
		_reason.text = tr("CRAFT_NEED_FIRE")
	elif not ready:
		_reason.text = tr("CRAFT_NEED_STATION") % Recipes.station_name(recipe.station).to_lower()
	elif missing.size() == 1 and missing.has(Recipes.WATER):
		_reason.text = tr("CRAFT_NEED_WATER")
	elif not missing.is_empty():
		_reason.text = tr("CRAFT_MISSING") if times == 1 else tr("CRAFT_MISSING_N") % times
	else:
		_reason.text = ""
	_reason.visible = _reason.text != ""


func _set_max() -> void:
	if _selected != null:
		_quantity.value = clampi(Recipes.max_times(_selected, ui.inventory, _needs()), 1, MAX_TIMES)


func _craft() -> void:
	var recipe := _selected
	if recipe == null or ui == null:
		return
	if not _station_ready(recipe.station):
		_notify(tr("CRAFT_GO_TO") % Recipes.station_name(recipe.station).to_lower())
		return
	var times := int(_quantity.value)
	var left := Recipes.craft(recipe, ui.inventory, times, _needs())
	if left < 0:
		_notify(tr("CRAFT_MISSING"))
		return
	var result: ItemData = ItemCatalog.get_item(recipe.result)
	var progression := Progression.of(ui.crafter)
	if progression != null:
		progression.reward_craft(recipe, times)
	if left > 0:
		ui.drop_requested.emit(result, left)
	var made := recipe.amount * times
	_notify(tr("CRAFT_CRAFTED") % result.get_display_name() + (" ×%d" % made if made > 1 else "")
		+ (" · " + tr("CRAFT_DROPPED") % left if left > 0 else ""))
	ui.inventory.inventory_changed.emit()


# --- Estaciones -----------------------------------------------------------------------------------

## Las necesidades de quien fabrica (el agua de sus odres), o null.
func _needs() -> SurvivalNeeds:
	if ui == null or ui.crafter == null or not is_instance_valid(ui.crafter):
		return null
	return ui.crafter.get(&"needs") as SurvivalNeeds


## Fila de un ingrediente: su icono, su nombre y lo que hay de lo que hace falta.
func _input_row(data: ItemData, text: String, count_text: String, short: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var icon := ItemSlotView.new()
	icon.size_kind = &"ingredient"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if data != null:
		icon.show_item(data.icon)
	row.add_child(icon)
	var name_label := _label(text, &"StatLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	var count := _label(count_text, &"WorseLabel" if short else &"BetterLabel")
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(count)
	return row


## Si quien fabrica está al alcance de la estación abierta (Workstation.reach, Campfire.REACH) y,
## si es una hoguera, encendida. A mano, siempre.
func _station_near() -> bool:
	if _station == Recipes.HAND:
		return true
	if ui == null or ui.crafter == null or not is_instance_valid(ui.crafter) or not ui.crafter.is_inside_tree() \
			or not is_instance_valid(_station_node) or not _station_node.is_inside_tree():
		return false
	var d := _station_node.global_position.distance_to(ui.crafter.global_position)
	if _station_node is Campfire:
		return (_station_node as Campfire).lit and d <= Campfire.REACH
	return d <= (_station_node as Workstation).reach()


## «Cerca» / «No está cerca»; la hoguera tiene que estar encendida.
func _near_text(station: StringName, near: bool) -> String:
	if station == Workstation.CAMPFIRE:
		return tr("CRAFT_FIRE_NEAR") if near else tr("CRAFT_FIRE_NOT_NEAR")
	return tr("CRAFT_NEAR") if near else tr("CRAFT_NOT_NEAR")


## Se puede hacer aquí lo de [station]: a mano siempre; lo de la estación abierta, con ella cerca.
func _station_ready(station: StringName) -> bool:
	return station == Recipes.HAND or (station == _station and _near)


func _dismantle(station: Workstation) -> void:
	if not is_instance_valid(station) or station.is_queued_for_deletion():
		return
	var data: ItemData = ItemCatalog.get_item(station.item_id)
	# Fuera de los grupos ya: se libera al acabar el cuadro y antes se volvería a contar.
	station.remove_from_group(Workstation.GROUP)
	station.remove_from_group(GroundPlaceableTrait.PLACED_GROUP)
	station.remove_from_group(GameManager.SAVEABLE_GROUP)
	station.queue_free()
	if data != null:
		var left := ui.inventory.add_item(data, 1)
		if left > 0:
			ui.drop_requested.emit(data, left)
		_notify(tr("CRAFT_DISMANTLED") % data.get_display_name().to_lower())
	# Sin la estación, sus recetas ya no se pueden hacer: a las de a mano.
	show_station(null)
	ui.inventory.inventory_changed.emit()


func _notify(text: String) -> void:
	if ui != null and ui.hotbar != null:
		ui.hotbar.notify(text)


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
