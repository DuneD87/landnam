extends CanvasLayer
class_name InventoryUI

## El inventario y la pantalla de personaje. Con la I sale el inventario solo, a un lado y sin
## tapar el mundo, para ver dónde cae lo que se tira (y el botín al lado mientras se saquea). Con
## la C, la pantalla de personaje: el inventario a la izquierda, el personaje en 3D con sus huecos
## en el centro (el muñeco de CharacterWindow) y sus atributos a la derecha, con el mundo detrás
## oscurecido y desenfocado. Con el Tabulador (o «Fabricar»), la ventana de fabricar (CraftingPanel)
## en lugar del personaje, con el inventario a su izquierda. La barra rápida sube por encima de todo
## mientras está abierta.
##
## Los objetos se mueven a clics: el izquierdo coge el montón (con Mayús, la mitad) y lo suelta
## donde se pinche; el derecho coge la mitad o suelta de uno en uno. Al pasar el ratón por un
## hueco sale su ficha (ItemCard), comparada con lo que se lleva puesto en su sitio.

## Lo que se lleva en el cursor y se pincha fuera de las ventanas se suelta al suelo: lo hace el
## jugador (DroppedItem).
signal drop_requested(data: ItemData, quantity: int)
## Se ha cerrado (con Escape, la tecla o el aspa): quien la abrió recupera el ratón.
signal closed
## Doble clic sobre algo del inventario: usarlo (comerlo, beber del odre; SurvivalActions.use_item).
signal use_requested(data: ItemData)

## Lo que enseña: el inventario solo, la pantalla de personaje entera o la de fabricar.
enum View {INVENTORY, CHARACTER, CRAFTING}

const BACKDROP_SHADER := preload("res://shaders/ui/backdrop.gdshader")
## Filtros del inventario: «Todo» y las categorías de ItemTaxonomy (-1 = todas), con sus claves.
static var FILTERS: Array = [["INV_FILTER_ALL", -1]] + ItemTaxonomy.CATEGORIES.map(
	func(entry: Array) -> Array: return [entry[1], entry[0]])
## Medidas en la escala base de 1440 px: ancho de las columnas de los lados, ancho del muñeco
## (mínimo y máximo), hueco entre columnas, márgenes y la franja de abajo, que es de la barra.
const SIDE_WIDTH := 660.0
const DOLL_WIDTH := Vector2(560.0, 900.0)
const GAP := 36.0
const MARGIN := Vector2(56.0, 40.0)
const BOTTOM := 170.0

var inventory: Inventory
var character_window: CharacterWindow
var slots: Array[InventorySlot] = []
var hotbar: Hotbar
## Las tres columnas: fuera de ellas (y de la barra rápida) un clic tira lo que va en el cursor.
var panel: Control

var floating_item: InventoryItem = null
var floating_slot_index: int = -1
var floating_inventory: Inventory = null
var view := View.INVENTORY
## Quien fabrica (el jugador): las recetas de una estación de trabajo piden tenerla cerca.
var crafter: Node3D

var _ui_scale := 1.0
var _root: Control
var _backdrop: ColorRect
var _header: Control
var _header_title: Label
var _header_hint: Label
var _frame: VBoxContainer
var _inventory_column: PanelContainer
var _side_column: PanelContainer
var _doll_holder: Control
var _inventory_panel: InventoryPanel
var _count_label: Label
var _filter := 0
var _filter_buttons: Array[Button] = []
var _close_button: Button
## El aspa del inventario solo, que no lleva la cabecera de la pantalla.
var _inventory_close: Button
var _card: ItemCard
## El hueco cuya ficha está a la vista.
var _card_slot: ItemSlotView
var _held: ItemSlotView
var _held_root: Control
var _hotbar_layer := -1

var _stats_box: VBoxContainer
var _health: HealthComponent
var _stamina: StaminaComponent
var _health_bar: ProgressBar
var _health_value: Label
var _stamina_bar: ProgressBar
var _stamina_value: Label
## Protección contra tajo, contundente y perforante de lo puesto.
var _armor_values: Array[Label] = []
var _needs: SurvivalNeeds
## Valor de cada necesidad en la ficha, por su nombre (SurvivalNeeds.NAMES, más "water").
var _need_values := {}
var _hand_boxes := {}

## Columna de la derecha: atributos, botín u hoguera (la manda _update_side).
var _campfire: Campfire = null
var _campfire_box: VBoxContainer
var _campfire_slots: Array[InventorySlot] = []
var _cook_bars: Array[ProgressBar] = []
var _fuel_bar: ProgressBar
var _fire_label: Label
var _fuel_label: Label
var _ignite_button: Button
## «Fabricar», en la cabecera del inventario: abre y cierra la vista de fabricar.
var _craft_toggle: Button
var _crafting_panel: CraftingPanel

var _loot_box: VBoxContainer
var _loot_inventory: Inventory = null
var _loot_slots: Array[InventorySlot] = []
var _loot_panel: InventoryPanel
var _loot_title: Label
var _loot_hint: Label
var _storage: Storage
var _dismantle_storage_button: Button
var _closing_container := false
var _loot_label: Label


func _ready() -> void:
	layer = 13
	visible = false
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BACKDROP_SHADER
	_backdrop.material = material
	_root.add_child(_backdrop)

	_frame = VBoxContainer.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)
	_header = _build_header()
	_frame.add_child(_header)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(body)
	panel = body
	_inventory_column = _build_inventory_column()
	body.add_child(_inventory_column)
	_doll_holder = MarginContainer.new()
	_doll_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_doll_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_doll_holder)
	_side_column = _build_side_column()
	body.add_child(_side_column)
	_crafting_panel = CraftingPanel.new()
	_crafting_panel.ui = self
	_crafting_panel.visible = false
	body.add_child(_crafting_panel)

	_card = ItemCard.new()
	_root.add_child(_card)
	_build_held()
	_apply_scale()
	get_viewport().size_changed.connect(_apply_scale)


func setup(inv: Inventory, char_window: CharacterWindow, hbar: Hotbar) -> void:
	inventory = inv
	character_window = char_window
	hotbar = hbar

	inventory.inventory_changed.connect(_refresh)
	character_window.slot_clicked.connect(_on_equipment_slot_clicked)
	character_window.slot_hovered.connect(_on_slot_hovered.bind(&"equipment"))
	character_window.equipment_changed.connect(func(_slot, _item, _equip) -> void:
		if visible:
			_refresh_stats())
	var doll := character_window.take_doll()
	if doll != null:
		_doll_holder.add_child(doll)
	hotbar.hotbar_slot_clicked.connect(_on_hotbar_slot_clicked)
	for slot in hotbar.slots:
		slot.hover_changed.connect(_on_slot_hovered.bind(&"hotbar"))

	_create_slots()
	_refresh()


## Vida y aguante del personaje, para los atributos.
func set_vitals(health: HealthComponent, stamina: StaminaComponent, needs: SurvivalNeeds = null) -> void:
	_health = health
	_stamina = stamina
	_needs = needs


func _process(_delta: float) -> void:
	if not visible:
		return
	if _held.visible:
		_held_root.position = get_viewport().get_mouse_position() + Vector2(14, 14) * _ui_scale
	_refresh_vitals()


# --- Estructura ---------------------------------------------------------------------------------

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_title = Label.new()
	_header_title.theme_type_variation = &"TitleLabel"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_header_title)
	_header_hint = Label.new()
	_header_hint.theme_type_variation = &"HintLabel"
	_header_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_header_hint)
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.theme_type_variation = &"CloseButton"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.tooltip_text = "UI_CLOSE"
	_close_button.pressed.connect(close)
	header.add_child(_close_button)
	return header


func _build_inventory_column() -> PanelContainer:
	var column := PanelContainer.new()
	column.theme_type_variation = &"WindowPanel"
	var box := VBoxContainer.new()
	column.add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "INV_TITLE"
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_count_label = Label.new()
	_count_label.theme_type_variation = &"ValueLabel"
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count_label)
	var sort := Button.new()
	sort.text = "INV_SORT"
	sort.theme_type_variation = &"TabButton"
	sort.focus_mode = Control.FOCUS_NONE
	sort.tooltip_text = "INV_SORT_TIP"
	sort.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sort.pressed.connect(_sort_inventory)
	header.add_child(sort)
	_craft_toggle = Button.new()
	_craft_toggle.text = "INV_CRAFT"
	_craft_toggle.theme_type_variation = &"TabButton"
	_craft_toggle.toggle_mode = true
	_craft_toggle.focus_mode = Control.FOCUS_NONE
	_craft_toggle.tooltip_text = "INV_CRAFT_TIP"
	_craft_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_craft_toggle.toggled.connect(func(on: bool) -> void: open(View.CRAFTING if on else View.INVENTORY))
	header.add_child(_craft_toggle)
	_inventory_close = Button.new()
	_inventory_close.text = "×"
	_inventory_close.theme_type_variation = &"CloseButton"
	_inventory_close.focus_mode = Control.FOCUS_NONE
	_inventory_close.tooltip_text = "INV_CLOSE_TIP"
	_inventory_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_inventory_close.pressed.connect(close)
	header.add_child(_inventory_close)
	box.add_child(header)
	box.add_child(HSeparator.new())

	var filters := HFlowContainer.new()
	var group := ButtonGroup.new()
	for i in FILTERS.size():
		var button := Button.new()
		button.text = FILTERS[i][0]
		button.theme_type_variation = &"TabButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = i == _filter
		button.pressed.connect(_set_filter.bind(i))
		filters.add_child(button)
		_filter_buttons.append(button)
	box.add_child(filters)

	_inventory_panel = InventoryPanel.new()
	_inventory_panel.slot_clicked.connect(_on_slot_clicked)
	_inventory_panel.slot_double_clicked.connect(_on_slot_double_clicked)
	_inventory_panel.slot_hovered.connect(_on_slot_hovered.bind(&"inventory"))
	box.add_child(_inventory_panel)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	box.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "INV_HINT"
	hint.theme_type_variation = &"HintLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	return column


## Columna de la derecha: los atributos o, mientras se saquea, el botín.
func _build_side_column() -> PanelContainer:
	var column := PanelContainer.new()
	column.theme_type_variation = &"WindowPanel"
	var box := VBoxContainer.new()
	column.add_child(box)
	_stats_box = _build_stats()
	box.add_child(_stats_box)
	_loot_box = _build_loot()
	_loot_box.visible = false
	box.add_child(_loot_box)
	_campfire_box = _build_campfire()
	_campfire_box.visible = false
	box.add_child(_campfire_box)
	return column


## La hoguera abierta: su fuego, el hueco del combustible y los ocho del asador.
func _build_campfire() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	var title := _label("INV_CAMPFIRE", &"HeaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_fire_label = _label("", &"ValueLabel")
	_fire_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_fire_label)
	box.add_child(header)
	box.add_child(HSeparator.new())
	box.add_child(_label("INV_FUEL", &"SectionLabel"))
	var fuel_row := HBoxContainer.new()
	var fuel_slot := InventorySlot.new()
	fuel_slot.slot_index = Campfire.FUEL_SLOT
	fuel_slot.slot_clicked.connect(_on_campfire_slot_clicked)
	fuel_slot.hover_changed.connect(_on_slot_hovered.bind(&"campfire"))
	fuel_row.add_child(fuel_slot)
	_campfire_slots.append(fuel_slot)
	var fuel_info := VBoxContainer.new()
	fuel_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_info.alignment = BoxContainer.ALIGNMENT_CENTER
	_fuel_label = _label("", &"StatValue")
	fuel_info.add_child(_fuel_label)
	_fuel_bar = _bar(&"StaminaBar")
	fuel_info.add_child(_fuel_bar)
	fuel_info.add_child(_label("INV_FUEL_HINT", &"HintLabel"))
	fuel_row.add_child(fuel_info)
	box.add_child(fuel_row)
	box.add_child(HSeparator.new())
	box.add_child(_label("INV_ROAST", &"SectionLabel"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for i in Campfire.COOK_SLOTS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var slot := InventorySlot.new()
		slot.slot_index = 1 + i
		slot.slot_clicked.connect(_on_campfire_slot_clicked)
		slot.hover_changed.connect(_on_slot_hovered.bind(&"campfire"))
		cell.add_child(slot)
		_campfire_slots.append(slot)
		var bar := _bar(&"HealthBar")
		bar.custom_minimum_size.y = 6
		cell.add_child(bar)
		_cook_bars.append(bar)
		grid.add_child(cell)
	box.add_child(grid)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var buttons := HBoxContainer.new()
	_ignite_button = Button.new()
	_ignite_button.theme_type_variation = &"AccentButton"
	_ignite_button.focus_mode = Control.FOCUS_NONE
	_ignite_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ignite_button.pressed.connect(_toggle_fire)
	buttons.add_child(_ignite_button)
	var take := Button.new()
	take.text = "INV_TAKE_COOKED"
	take.focus_mode = Control.FOCUS_NONE
	take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take.pressed.connect(_take_cooked)
	buttons.add_child(take)
	box.add_child(buttons)
	var dismantle := Button.new()
	dismantle.text = "UI_DISMANTLE"
	dismantle.focus_mode = Control.FOCUS_NONE
	dismantle.tooltip_text = "INV_DISMANTLE_FIRE_TIP"
	dismantle.pressed.connect(_dismantle_campfire)
	box.add_child(dismantle)
	var hint := _label("INV_CAMPFIRE_HINT", &"HintLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	return box


func _build_stats() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_label("INV_ATTRIBUTES", &"HeaderLabel"))
	box.add_child(HSeparator.new())
	var vitals := GridContainer.new()
	vitals.columns = 2
	_health_value = _stat_row(vitals, "STAT_HEALTH")
	_health_bar = _bar(&"HealthBar")
	box.add_child(vitals)
	box.add_child(_health_bar)
	var stamina_grid := GridContainer.new()
	stamina_grid.columns = 2
	_stamina_value = _stat_row(stamina_grid, "STAT_STAMINA")
	_stamina_bar = _bar(&"StaminaBar")
	box.add_child(stamina_grid)
	box.add_child(_stamina_bar)
	box.add_child(_label("INV_ARMOR", &"SectionLabel"))
	_armor_values.clear()
	var armor := GridContainer.new()
	armor.columns = 2
	for kind in [ItemData.DamageKind.SLASH, ItemData.DamageKind.BLUNT, ItemData.DamageKind.PIERCE]:
		_armor_values.append(_stat_row(armor, Armor.KIND_NAMES[kind]))
	box.add_child(armor)
	box.add_child(HSeparator.new())
	box.add_child(_label("INV_NEEDS", &"SectionLabel"))
	var needs := GridContainer.new()
	needs.columns = 2
	for need in [["hunger", "NEED_HUNGER"], ["thirst", "NEED_THIRST"], ["rest", "NEED_REST"],
			["sanity", "NEED_SANITY"], ["warmth", "NEED_TEMPERATURE"], ["water", "NEED_WATER"]]:
		_need_values[need[0]] = _stat_row(needs, need[1])
	box.add_child(needs)
	for slot_type in CharacterWindow.RIGHT_SLOTS:
		box.add_child(HSeparator.new())
		box.add_child(_label(CharacterWindow.SLOT_NAMES[slot_type], &"SectionLabel"))
		var hand := VBoxContainer.new()
		hand.add_theme_constant_override("separation", 2)
		box.add_child(hand)
		_hand_boxes[slot_type] = hand
	return box


func _build_loot() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	_loot_title = _label("INV_LOOT", &"HeaderLabel")
	_loot_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_loot_title)
	_loot_label = _label("", &"ValueLabel")
	_loot_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_loot_label)
	box.add_child(header)
	box.add_child(HSeparator.new())
	_loot_panel = InventoryPanel.new()
	_loot_panel.slot_clicked.connect(_on_loot_slot_clicked)
	_loot_panel.slot_hovered.connect(_on_slot_hovered.bind(&"loot"))
	box.add_child(_loot_panel)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var take_all := Button.new()
	take_all.text = "INV_TAKE_ALL"
	take_all.theme_type_variation = &"AccentButton"
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.pressed.connect(_take_all_loot)
	box.add_child(take_all)
	_dismantle_storage_button = Button.new()
	_dismantle_storage_button.text = "UI_DISMANTLE"
	_dismantle_storage_button.focus_mode = Control.FOCUS_NONE
	_dismantle_storage_button.tooltip_text = "INV_STORAGE_DISMANTLE_TIP"
	_dismantle_storage_button.visible = false
	_dismantle_storage_button.pressed.connect(_dismantle_storage)
	box.add_child(_dismantle_storage_button)
	_loot_hint = _label("INV_HINT_TO_INVENTORY", &"HintLabel")
	_loot_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loot_hint)
	return box


## Lo que va pegado al cursor: un hueco suelto en su propia capa, por encima de todo.
func _build_held() -> void:
	var held_layer := CanvasLayer.new()
	held_layer.layer = 100
	add_child(held_layer)
	_held_root = Control.new()
	_held_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_layer.add_child(_held_root)
	_held = ItemSlotView.new()
	_held.size_kind = &"held"
	_held.held = true
	_held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held.visible = false
	_held_root.add_child(_held)


## Tema y medidas a la escala de la ventana. Si las columnas no caben a lo ancho, se encoge todo.
func _apply_scale() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_ui_scale = GameTheme.scale_for(get_viewport())
	var theme := GameTheme.build(_ui_scale)
	_root.theme = theme
	_held_root.theme = theme
	_card.ui_scale = _ui_scale
	var s := _ui_scale
	_inventory_column.custom_minimum_size.x = SIDE_WIDTH * s
	_side_column.custom_minimum_size.x = SIDE_WIDTH * s
	_crafting_panel.ui_scale = s
	panel.add_theme_constant_override("separation", roundi(GAP * s))
	_frame.add_theme_constant_override("separation", roundi(18 * s))

	var sides := (2.0 * SIDE_WIDTH + 2.0 * GAP) * s
	var available := viewport_size.x - 2.0 * MARGIN.x * s
	var doll := clampf(available - sides, DOLL_WIDTH.x * s, DOLL_WIDTH.y * s)
	var width := sides + doll
	var height := viewport_size.y - MARGIN.y * s - BOTTOM * s
	_inventory_panel.max_height = maxf(100.0 * s, height - 220.0 * s)
	_loot_panel.max_height = maxf(100.0 * s, height - 220.0 * s)
	var fit := minf(1.0, available / width) if available > 0.0 else 1.0
	# Anclado y no con size: las etiquetas que parten líneas piden mucho alto mientras aún no
	# tienen ancho, y un tamaño puesto a mano ya no volvería a encoger.
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.offset_left = -width * 0.5
	_frame.offset_right = width * 0.5
	_frame.offset_top = MARGIN.y * s
	_frame.offset_bottom = MARGIN.y * s + height / fit
	_frame.pivot_offset = Vector2(width * 0.5, 0.0)
	_frame.scale = Vector2(fit, fit)


# --- Contenido ----------------------------------------------------------------------------------

func _create_slots() -> void:
	_inventory_panel.bind_inventory(inventory)
	slots = _inventory_panel.slots


func _refresh() -> void:
	if not inventory:
		return

	_inventory_panel.refresh()
	var count := inventory.max_slots - inventory.get_free_slots()
	_count_label.text = "%d / %d" % [count, inventory.max_slots]
	_apply_filter()
	if visible:
		_refresh_stats()
		if view == View.CRAFTING:
			_crafting_panel.refresh()


func _set_filter(index: int) -> void:
	_filter = index
	_filter_buttons[index].button_pressed = true
	_apply_filter()


## Lo que no es del filtro elegido queda en segundo plano (sin moverse: cada cosa sigue en su hueco).
func _apply_filter() -> void:
	var category: int = FILTERS[_filter][1]
	for slot in slots:
		slot.dimmed = category >= 0 and slot.item != null and ItemTaxonomy.category_of(slot.item.data) != category


func _sort_inventory() -> void:
	if floating_item:
		_return_to_origin()
	ItemTaxonomy.sort_inventory(inventory)
	_refresh()


func _refresh_stats() -> void:
	var armor := character_window.get_armor() if character_window != null else Vector3.ZERO
	for i in _armor_values.size():
		_armor_values[i].text = ItemTrait.number(armor[i])
	for slot_type in _hand_boxes:
		var box: VBoxContainer = _hand_boxes[slot_type]
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
		var data := _equipped(slot_type)
		if data == null:
			box.add_child(_label("INV_HAND_EMPTY", &"HintLabel"))
			continue
		box.add_child(_label(data.get_display_name(), &"StatValue"))
		box.add_child(_label(ItemCard.kind_line(data), &"HintLabel"))
		var grid := GridContainer.new()
		grid.columns = 2
		for row in ItemCard.stat_rows(data, null):
			var value := _stat_row(grid, row[0])
			value.text = row[1]
		box.add_child(grid)
	_refresh_vitals()


func _refresh_vitals() -> void:
	var has_health := _health != null and is_instance_valid(_health)
	_health_bar.visible = has_health
	_health_value.text = "%d / %d" % [ceili(_health.health), roundi(_health.max_health)] if has_health else "—"
	if has_health:
		_health_bar.value = _health.health / maxf(_health.max_health, 1.0)
	var has_stamina := _stamina != null and is_instance_valid(_stamina)
	_stamina_bar.visible = has_stamina
	_stamina_value.text = "%d / %d" % [floori(_stamina.stamina), roundi(_stamina.max_stamina)] if has_stamina else "—"
	if has_stamina:
		_stamina_bar.value = _stamina.stamina / maxf(_stamina.max_stamina, 1.0)
	var has_needs := _needs != null and is_instance_valid(_needs)
	for need in _need_values:
		var label: Label = _need_values[need]
		if not has_needs:
			label.text = "—"
		elif need == "warmth":
			label.text = "%s · %d °C" % [_needs.temperature_word(), roundi(_needs.felt_temperature)]
		elif need == "water":
			var room := _needs.water_capacity()
			label.text = tr("INV_SIPS_OF") % [_needs.water, room] if room > 0 else tr("INV_NO_WATERSKIN")
			label.theme_type_variation = &"StatValue"
			continue
		else:
			label.text = "%d %%" % roundi(_needs.get_value(need) * 100.0)
		label.theme_type_variation = &"WorseLabel" if has_needs and _needs.is_critical(need) else &"StatValue"


func _equipped(slot_type: ItemData.ArmorSlot) -> ItemData:
	if character_window == null:
		return null
	var slot: EquipmentSlot = character_window.equipment_slots.get(slot_type)
	return slot.equipped_item.data if slot != null and slot.has_item() else null


## Lo que se lleva puesto donde iría [data] (las armas y herramientas, en la mano derecha).
func _equipped_counterpart(data: ItemData) -> ItemData:
	if data.category == ItemData.Category.WEAPON or data.category == ItemData.Category.TOOL:
		return _equipped(ItemData.ArmorSlot.RIGHT_HAND)
	if data.armor_slot != ItemData.ArmorSlot.NONE:
		return _equipped(data.armor_slot)
	return null


# --- Ficha del objeto ---------------------------------------------------------------------------

func _on_slot_hovered(slot: ItemSlotView, on: bool, context: StringName) -> void:
	if not on:
		if slot == _card_slot:
			_hide_card()
		return
	if not visible or floating_item != null:
		return
	var data: ItemData = null
	var quantity := 1
	var hint := ""
	match context:
		&"inventory":
			var item: InventoryItem = (slot as InventorySlot).item
			if item:
				data = item.data
				quantity = item.quantity
			hint = tr("INV_HINT_TAKE")
			if item and (item.data.get_trait(EdibleTrait) != null or item.data.get_trait(WaterContainerTrait) != null):
				hint += " · " + tr("INV_HINT_DOUBLE_DRINK" if item.data.get_trait(WaterContainerTrait) != null else "INV_HINT_DOUBLE_EAT")
		&"loot":
			var item: InventoryItem = (slot as InventorySlot).item
			if item:
				data = item.data
				quantity = item.quantity
			hint = tr("INV_STORAGE_HINT" if _storage != null else "INV_HINT_TO_INVENTORY")
		&"campfire":
			var item: InventoryItem = (slot as InventorySlot).item
			if item:
				data = item.data
				quantity = item.quantity
				hint = tr("INV_HINT_TO_INVENTORY")
			else:
				var fuel := (slot as InventorySlot).slot_index == Campfire.FUEL_SLOT
				_card.show_empty("INV_FUEL" if fuel else "INV_ROAST",
					"INV_FUEL_EMPTY_HINT" if fuel else "INV_ROAST_EMPTY_HINT")
		&"equipment":
			var equipment := slot as EquipmentSlot
			if equipment.has_item():
				data = equipment.equipped_item.data
				hint = tr("INV_HINT_UNEQUIP")
			else:
				_card.show_empty(CharacterWindow.SLOT_NAMES.get(equipment.slot_type, "SLOT_EMPTY"),
					"INV_EQUIP_EMPTY_HINT")
		&"hotbar":
			data = (slot as HotbarSlot).assigned_data
			hint = tr("INV_HINT_HOTBAR")
			quantity = 0
	if data != null:
		var compare: ItemData = null if context == &"equipment" else _equipped_counterpart(data)
		if context == &"hotbar" and inventory != null:
			quantity = inventory.get_item_count(data)
		_card.show_item(data, quantity, compare, hint)
	elif context != &"equipment" and context != &"campfire":
		return
	_card_slot = slot
	_place_card.call_deferred(slot, context)


## La ficha sale fuera de la columna del hueco, para no tapar sus vecinos: a la derecha del
## inventario, a la izquierda del botín, junto al hueco del muñeco y encima de la barra.
func _place_card(slot: ItemSlotView, context: StringName) -> void:
	if slot != _card_slot or not is_instance_valid(slot):
		return
	var rect := slot.get_global_rect()
	match context:
		&"hotbar":
			# Por encima de la consola entera: la cresta y la media orbe del centro asoman sobre la
			# barra, y la barra va en una capa por encima de esta mientras está abierta.
			if hotbar != null and hotbar.plate != null and hotbar.plate.visible:
				var top := hotbar.plate.get_global_rect().position.y
				rect = Rect2(rect.position.x, top, rect.size.x, rect.end.y - top)
			_card.place_above(rect)
			return
		&"inventory", &"loot", &"campfire":
			var column := (_inventory_column if context == &"inventory" else _side_column).get_global_rect()
			rect = Rect2(column.position.x, rect.position.y, column.size.x, rect.size.y)
	_card.place_beside(rect)


func _hide_card() -> void:
	_card.visible = false
	_card_slot = null


# --- Abrir y cerrar -----------------------------------------------------------------------------

## La tecla de una vista la abre, o la cierra si es la que está a la vista; con la otra
## abierta, cambia a ella.
func toggle(which := View.INVENTORY) -> void:
	if visible and view == which:
		close()
	else:
		open(which)


func open(which := View.INVENTORY) -> void:
	view = which
	_hide_card()
	_apply_view()
	visible = true
	if hotbar != null and _hotbar_layer < 0:
		# La barra va por encima del fondo, para asignarle cosas.
		_hotbar_layer = hotbar.layer
		hotbar.layer = layer + 1
	# El muñeco solo se prepara cuando se ve: el inventario solo no paga su cuerpo.
	if view == View.CHARACTER and character_window != null:
		character_window.refresh()
	_refresh()


## Lo que sale en cada vista. El inventario solo va a la izquierda, centrado en alto y del alto
## de lo que tiene; en la de personaje y en la de fabricar, las columnas llenan la pantalla.
func _apply_view() -> void:
	var full := view == View.CHARACTER
	var crafting := view == View.CRAFTING
	_backdrop.visible = full or crafting
	_header.visible = full or crafting
	_header_title.text = "INV_HEADER_CRAFT" if crafting else "INV_HEADER_EQUIPMENT"
	_header_hint.text = "INV_HEADER_HINT_CRAFT" if crafting else "INV_HEADER_HINT_CHARACTER"
	_doll_holder.visible = full
	_side_column.visible = not crafting and (full or _loot_inventory != null or _campfire != null)
	_crafting_panel.visible = crafting
	_craft_toggle.set_pressed_no_signal(crafting)
	_inventory_close.visible = not full and not crafting
	var vertical := Control.SIZE_FILL if full or crafting else Control.SIZE_SHRINK_CENTER
	_inventory_column.size_flags_vertical = vertical
	_side_column.size_flags_vertical = vertical


func close() -> void:
	var was_open := visible
	if floating_item:
		_cancel_floating_item()
	close_loot()
	close_campfire()
	_hide_card()
	_release_focus()
	visible = false
	if hotbar != null and _hotbar_layer >= 0:
		hotbar.layer = _hotbar_layer
		_hotbar_layer = -1
	if was_open:
		closed.emit()


func open_loot(loot_inv: Inventory) -> void:
	close_loot()
	close_campfire()
	_loot_title.text = "INV_LOOT"
	_loot_hint.text = "INV_HINT_TO_INVENTORY"
	_open_container(loot_inv)


func open_storage(storage: Storage) -> void:
	close_loot()
	close_campfire()
	_storage = storage
	_loot_title.text = ItemCatalog.get_item(storage.item_id).display_name
	_loot_hint.text = "INV_STORAGE_HINT"
	_open_container(storage.inventory)


func open_storage_node() -> Storage:
	return _storage


func _open_container(content: Inventory) -> void:
	_loot_inventory = content
	content.inventory_changed.connect(_refresh_loot)
	content.tree_exiting.connect(_on_container_exiting)
	_create_loot_slots()
	_dismantle_storage_button.visible = _storage != null
	_update_side()
	_refresh_loot()
	open(view if visible and view != View.CRAFTING else View.INVENTORY)


func close_loot() -> void:
	if _closing_container:
		return
	_closing_container = true
	if floating_item != null and floating_inventory == _loot_inventory:
		_return_to_origin()
	if is_instance_valid(_loot_inventory):
		if _loot_inventory.inventory_changed.is_connected(_refresh_loot):
			_loot_inventory.inventory_changed.disconnect(_refresh_loot)
		if _loot_inventory.tree_exiting.is_connected(_on_container_exiting):
			_loot_inventory.tree_exiting.disconnect(_on_container_exiting)
	_loot_inventory = null
	_storage = null
	if _card_slot in _loot_slots:
		_hide_card()
	_loot_panel.bind_inventory(null)
	_dismantle_storage_button.visible = false
	_closing_container = false
	_update_side()


func _on_container_exiting() -> void:
	if floating_item != null and floating_inventory == _loot_inventory:
		_return_to_origin(true)
	close_loot()


func _dismantle_storage() -> void:
	if not is_instance_valid(_storage):
		return
	_cancel_floating_item()
	if _storage.inventory.get_free_slots() != _storage.inventory.max_slots:
		return
	var storage := _storage
	var data := ItemCatalog.get_item(storage.item_id)
	close_loot()
	var left := inventory.add_item(data, 1)
	if left > 0:
		drop_requested.emit(data, left)
	storage.queue_free()


## Qué va en la columna de la derecha: el botín si se saquea, la hoguera si está abierta y, si no,
## los atributos.
func _update_side() -> void:
	var mode := &"stats"
	if _loot_inventory != null:
		mode = &"loot"
	elif _campfire != null:
		mode = &"campfire"
	_stats_box.visible = mode == &"stats"
	_loot_box.visible = mode == &"loot"
	_campfire_box.visible = mode == &"campfire"
	_apply_view()


# --- Hoguera ------------------------------------------------------------------------------------

func open_campfire(fire: Campfire) -> void:
	close_loot()
	close_campfire()
	_campfire = fire
	fire.changed.connect(_refresh_campfire)
	fire.inventory.inventory_changed.connect(_refresh_campfire)
	fire.tree_exiting.connect(close_campfire)
	_update_side()
	_refresh_campfire()
	open(view if visible and view != View.CRAFTING else View.INVENTORY)


func close_campfire() -> void:
	if _campfire != null and is_instance_valid(_campfire):
		if _campfire.changed.is_connected(_refresh_campfire):
			_campfire.changed.disconnect(_refresh_campfire)
		if _campfire.inventory.inventory_changed.is_connected(_refresh_campfire):
			_campfire.inventory.inventory_changed.disconnect(_refresh_campfire)
		if _campfire.tree_exiting.is_connected(close_campfire):
			_campfire.tree_exiting.disconnect(close_campfire)
	if _campfire == null:
		return
	_campfire = null
	if _card_slot in _campfire_slots:
		_hide_card()
	_update_side()


## La hoguera que está abierta (SurvivalActions la cierra si uno se aleja).
func open_campfire_node() -> Campfire:
	return _campfire


func _refresh_campfire() -> void:
	if _campfire == null or not is_instance_valid(_campfire):
		return
	for slot in _campfire_slots:
		var item := _campfire.inventory.items[slot.slot_index]
		if item != null:
			slot.set_item(item)
		else:
			slot.clear()
	for i in _cook_bars.size():
		_cook_bars[i].value = _campfire.cook_ratio(i)
		_cook_bars[i].modulate.a = 1.0 if _campfire.inventory.items[1 + i] != null else 0.25
	var left := _campfire.burn_seconds_left()
	_fuel_label.text = tr("INV_FIRE_LEFT") % [floori(left / 60.0), int(left) % 60] if left > 0.0 else tr("INV_NO_FUEL")
	_fuel_bar.value = _campfire.fuel_left / maxf(_campfire.fuel_total, 1.0) if _campfire.fuel_left > 0.0 else 0.0
	_fire_label.text = "INV_FIRE_LIT" if _campfire.lit else "INV_FIRE_OUT"
	_ignite_button.text = "INV_PUT_OUT" if _campfire.lit else "INV_LIGHT"
	_ignite_button.disabled = not _campfire.lit and not _campfire.has_fuel()


func _on_campfire_slot_clicked(slot: InventorySlot, button_index: int) -> void:
	if _campfire == null:
		return
	var index := slot.slot_index
	var stored := _campfire.inventory.items[index]
	if floating_item != null:
		if not _campfire.accepts(index, floating_item.data):
			if hotbar != null:
				hotbar.notify(tr("INV_NOT_HERE" if index != Campfire.FUEL_SLOT else "INV_DOESNT_BURN"))
			return
		floating_item = _campfire.inventory.put_at(index, floating_item,
			1 if button_index == MOUSE_BUTTON_RIGHT else -1, false)
		if stored == null and _campfire.inventory.items[index] != null and index != Campfire.FUEL_SLOT:
			_campfire.progress[index - 1] = 0.0
		_finish_inventory_transfer(_campfire.inventory)
	elif stored != null and button_index == MOUSE_BUTTON_LEFT:
		_campfire.inventory.transfer_to(inventory, index)
		if index != Campfire.FUEL_SLOT and _campfire.inventory.items[index] == null:
			_campfire.progress[index - 1] = 0.0


func _toggle_fire() -> void:
	if _campfire == null:
		return
	if _campfire.lit:
		_campfire.extinguish()
	elif not _campfire.ignite() and hotbar != null:
		hotbar.notify(tr("INV_ADD_FUEL"))


## Al inventario todo lo que ya está asado (lo que no se asa más).
func _take_cooked() -> void:
	if _campfire == null:
		return
	for i in Campfire.COOK_SLOTS:
		var item := _campfire.inventory.items[1 + i]
		if item != null and item.data.get_trait(CookableTrait) == null:
			_campfire.inventory.transfer_to(inventory, 1 + i)


func _dismantle_campfire() -> void:
	if _campfire == null:
		return
	if _campfire.lit or not _campfire.is_empty():
		if hotbar != null:
			hotbar.notify(tr("INV_PUT_OUT_FIRST"))
		return
	var fire := _campfire
	close_campfire()
	var left := inventory.add_item(ItemCatalog.get_item(Campfire.ITEM_ID), 1)
	if left > 0:
		drop_requested.emit(ItemCatalog.get_item(Campfire.ITEM_ID), left)
	fire.queue_free()


# --- Fabricar -----------------------------------------------------------------------------------

## E junto a una estación de trabajo: la ventana de fabricar, en sus recetas.
func open_station(station: Workstation) -> void:
	_crafting_panel.focus_station(station.item_id)
	open(View.CRAFTING)


## Fuera el foco de los campos (la cantidad): si no, las teclas del juego se quedarían escribiendo.
func _release_focus() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and _root.is_ancestor_of(focus):
		focus.release_focus()


func _create_loot_slots() -> void:
	_loot_panel.bind_inventory(_loot_inventory)
	_loot_slots = _loot_panel.slots


func _refresh_loot() -> void:
	if not is_instance_valid(_loot_inventory):
		return
	_loot_panel.refresh()
	var count := _loot_inventory.max_slots - _loot_inventory.get_free_slots()
	_loot_label.text = "%d / %d" % [count, _loot_inventory.max_slots]
	_dismantle_storage_button.disabled = count > 0 or floating_item != null
	if count == 0 and _storage == null and not _closing_container:
		close_loot()


func _on_loot_slot_clicked(slot: InventorySlot, button_index: int) -> void:
	if not is_instance_valid(_loot_inventory):
		return
	if _storage == null:
		if button_index == MOUSE_BUTTON_LEFT and slot.item != null and floating_item == null:
			_take_loot(slot.slot_index)
		return
	if button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if floating_item != null:
		_drop_to_slot(_loot_inventory, slot.slot_index, button_index == MOUSE_BUTTON_RIGHT)
	elif slot.item != null:
		if button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT):
			_loot_inventory.transfer_to(inventory, slot.slot_index)
		else:
			_pickup_from(_loot_inventory, slot.slot_index, button_index == MOUSE_BUTTON_RIGHT)


func _take_all_loot() -> void:
	if not is_instance_valid(_loot_inventory):
		return
	_cancel_floating_item()
	var loot := _loot_inventory
	for i in loot.max_slots:
		loot.transfer_to(inventory, i)


## Pasa al inventario lo que quepa del hueco [index] del botín.
func _take_loot(index: int) -> void:
	_loot_inventory.transfer_to(inventory, index)


# --- Mover objetos ------------------------------------------------------------------------------

func _on_hotbar_slot_clicked(slot_index: int) -> void:
	if not visible:
		return
	if floating_item:
		var data = floating_item.data
		_return_to_origin()
		hotbar.assign_to_slot(slot_index, data)
	else:
		hotbar.clear_slot(slot_index)


func _on_slot_clicked(slot: InventorySlot, button_index: int) -> void:
	if _storage != null and floating_item == null and button_index == MOUSE_BUTTON_LEFT \
			and Input.is_key_pressed(KEY_SHIFT):
		inventory.transfer_to(_loot_inventory, slot.slot_index)
		return
	if button_index == MOUSE_BUTTON_LEFT:
		_handle_inventory_left_click(slot)
	elif button_index == MOUSE_BUTTON_RIGHT:
		_handle_inventory_right_click(slot)


## El primer clic lo cogió y el segundo lo ha devuelto a su hueco: se usa de ahí.
func _on_slot_double_clicked(slot: ItemSlotView) -> void:
	if floating_item:
		_return_to_origin()
	var item := inventory.items[(slot as InventorySlot).slot_index]
	if item != null and item.data != null:
		use_requested.emit(item.data)


func _handle_inventory_left_click(slot: InventorySlot) -> void:
	if not floating_item:
		if slot.item:
			_pickup_from_inventory(slot)
	else:
		_drop_to_inventory(slot)


func _handle_inventory_right_click(slot: InventorySlot) -> void:
	if not floating_item:
		if slot.item:
			_pickup_half_from_inventory(slot)
	else:
		_drop_single_to_inventory(slot)


func _on_equipment_slot_clicked(slot: EquipmentSlot) -> void:
	if floating_item:
		_drop_to_equipment(slot)
	elif slot.has_item():
		_pickup_from_equipment(slot)


func _pickup_from_inventory(slot: InventorySlot, half: bool = false) -> void:
	_pickup_from(inventory, slot.slot_index, half or Input.is_key_pressed(KEY_SHIFT))


func _pickup_from(source: Inventory, index: int, half: bool = false) -> void:
	var item := source.get_item_at_slot(index)
	if item == null:
		return
	floating_item = source.take_at(index, ceili(item.quantity / 2.0) if half else -1)
	floating_inventory = source
	floating_slot_index = index
	_update_floating_display()
	_refresh()
	# El cursor es una transacción en curso; aquí solo se actualiza la presentación.
	_loot_panel.refresh()
	_dismantle_storage_button.disabled = true


func _pickup_half_from_inventory(slot: InventorySlot) -> void:
	_pickup_from_inventory(slot, true)


func _pickup_from_equipment(slot: EquipmentSlot) -> void:
	floating_item = character_window.unequip_item(slot)
	floating_inventory = null
	floating_slot_index = -1
	_update_floating_display()


func _drop_to_inventory(target_slot: InventorySlot) -> void:
	_drop_to_slot(inventory, target_slot.slot_index)


func _drop_single_to_inventory(target_slot: InventorySlot) -> void:
	_drop_to_slot(inventory, target_slot.slot_index, true)


func _drop_to_slot(target: Inventory, index: int, single: bool = false) -> void:
	if target == floating_inventory and index == floating_slot_index and not single:
		_return_to_origin()
		return
	var stored := target.get_item_at_slot(index)
	var stacking := stored != null and stored.can_stack_with(floating_item)
	floating_item = target.put_at(index, floating_item, 1 if single else -1, not single)
	if not single and floating_item != null and (floating_inventory != null or stacking):
		_return_to_origin()
		# El destino también ha cambiado si se ha intercambiado o apilado parte del montón.
		if target != inventory and is_instance_valid(target):
			target.inventory_changed.emit()
	else:
		_finish_inventory_transfer(target)


func _finish_inventory_transfer(target: Inventory = null) -> void:
	var origin := floating_inventory
	if floating_item == null:
		_clear_floating_item()
	else:
		_update_floating_display()
	if is_instance_valid(origin) and origin != inventory and origin != target:
		origin.inventory_changed.emit()
	if is_instance_valid(target) and target != inventory:
		target.inventory_changed.emit()
	inventory.inventory_changed.emit()


func _drop_to_equipment(slot: EquipmentSlot) -> void:
	var old_item := character_window.equip_item(slot, floating_item)
	if old_item == floating_item:
		return
	floating_item.remove(1)
	if floating_item.is_empty():
		floating_item = null
		_finish_inventory_transfer()
	else:
		_return_to_origin()
	if old_item != null:
		floating_item = old_item
		floating_inventory = null
		floating_slot_index = -1
		_update_floating_display()


func _return_to_origin(origin_unavailable: bool = false) -> void:
	if floating_item == null:
		return
	var origin := floating_inventory
	if not origin_unavailable and is_instance_valid(origin):
		floating_item = origin.put_at(floating_slot_index, floating_item, -1, false)
		if floating_item != null:
			floating_item = origin.insert(floating_item)
	if floating_item != null:
		floating_item = inventory.insert(floating_item)
	if floating_item != null:
		# Puede ocurrir si se llenó el hueco mientras había algo en el cursor.
		drop_requested.emit(floating_item.data, floating_item.quantity)
		floating_item = null
	_finish_inventory_transfer()


func _cancel_floating_item() -> void:
	if floating_item != null:
		_return_to_origin()


func _clear_floating_item() -> void:
	floating_item = null
	floating_inventory = null
	floating_slot_index = -1
	_held.visible = false


## Tira al suelo [amount] de lo que va en el cursor.
func _drop_to_world(amount: int) -> void:
	var n := mini(amount, floating_item.quantity)
	drop_requested.emit(floating_item.data, n)
	floating_item.remove(n)
	if floating_item.is_empty():
		floating_item = null
	_finish_inventory_transfer()


## El ratón está sobre alguna ventana: el inventario, el muñeco, la columna derecha, la cabecera
## o la barra rápida con su consola.
func _over_ui(mp: Vector2) -> bool:
	var areas: Array[Control] = [_inventory_column, _side_column, _crafting_panel, _close_button, _inventory_close]
	if character_window != null and character_window.panel != null:
		areas.append(character_window.panel)
	if hotbar != null and hotbar.visible:
		areas.append(hotbar.get_panel())
		areas.append(hotbar.plate)
	for area in areas:
		if area != null and is_instance_valid(area) and area.is_visible_in_tree() \
				and area.get_global_rect().has_point(mp):
			return true
	return false


func _update_floating_display() -> void:
	if not floating_item:
		return
	_hide_card()
	_held.show_item(floating_item.data.icon, floating_item.quantity)
	_held.visible = true
	_held_root.position = get_viewport().get_mouse_position() + Vector2(14, 14) * _ui_scale


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		close()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event is InputEventMouseButton and floating_item:
		var mb := event as InputEventMouseButton
		# Con algo en el cursor, un clic fuera de las ventanas lo tira entero; el derecho, de uno en
		# uno. Soltar el botón no tira nada: arrastrar y soltar fuera deja el objeto en el cursor.
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
				and not _over_ui(mb.global_position):
			_drop_to_world(1 if mb.button_index == MOUSE_BUTTON_RIGHT else floating_item.quantity)
			get_viewport().set_input_as_handled()
			return


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


## Fila de dos columnas (nombre y valor) en [grid]; devuelve la etiqueta del valor.
func _stat_row(grid: GridContainer, text: String) -> Label:
	var name_label := _label(text, &"StatLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(name_label)
	var value := _label("", &"StatValue")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value)
	return value


func _bar(variation: StringName) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = variation
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.custom_minimum_size.y = 10
	return bar
