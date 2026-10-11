extends CanvasLayer
class_name InventoryUI

## El inventario y la pantalla de personaje. Con la I sale el inventario solo, a un lado y sin
## tapar el mundo, para ver dónde cae lo que se tira (y el botín al lado mientras se saquea). Con
## la C, la pantalla de personaje: el inventario a la izquierda, el personaje en 3D con sus huecos
## en el centro (el muñeco de CharacterWindow) y sus atributos a la derecha, con el mundo detrás
## oscurecido y desenfocado. La barra rápida sube por encima de todo mientras está abierta.
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

## Lo que enseña: el inventario solo o la pantalla de personaje entera.
enum View {INVENTORY, CHARACTER}

const Config = preload("res://scripts/config.gd")
const BACKDROP_SHADER := preload("res://shaders/ui/backdrop.gdshader")
const COLUMNS := 5
## Filtros del inventario: «Todo» y las categorías de ItemTaxonomy (-1 = todas).
static var FILTERS: Array = [["Todo", -1]] + ItemTaxonomy.CATEGORIES.map(
	func(entry: Array) -> Array: return [entry[1], entry[0]])
## Medidas en la escala base de 1440 px: ancho de las columnas de los lados, ancho del muñeco
## (mínimo y máximo), hueco entre columnas, márgenes y la franja de abajo, que es de la barra.
const SIDE_WIDTH := 660.0
const DOLL_WIDTH := Vector2(560.0, 900.0)
const GAP := 36.0
const MARGIN := Vector2(56.0, 40.0)
const BOTTOM := 170.0
const INVENTORY_HINT := "Clic: coger o soltar · Clic derecho: la mitad, o de uno en uno\nClic fuera de las ventanas: tirar al suelo · Sobre la barra rápida: asignar\nDoble clic: comer, beber del odre · Hogueras: selecciónalas en la barra y clic para plantarlas"

var inventory: Inventory
var character_window: CharacterWindow
var slots: Array[InventorySlot] = []
var hotbar: Hotbar
## Las tres columnas: fuera de ellas (y de la barra rápida) un clic tira lo que va en el cursor.
var panel: Control

var floating_item: InventoryItem = null
var floating_slot_index: int = -1
var view := View.INVENTORY

var _ui_scale := 1.0
var _root: Control
var _backdrop: ColorRect
var _header: Control
var _frame: VBoxContainer
var _inventory_column: PanelContainer
var _side_column: PanelContainer
var _doll_holder: Control
var _slot_grid: GridContainer
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
var _armor_value: Label
var _needs: SurvivalNeeds
## Valor de cada necesidad en la ficha, por su nombre de consola (SurvivalNeeds.NAMES).
var _need_values := {}
var _hand_boxes := {}

## Columna de la derecha: atributos, botín, hoguera o fabricar (la manda _update_side).
var _campfire: Campfire = null
var _campfire_box: VBoxContainer
var _campfire_slots: Array[InventorySlot] = []
var _cook_bars: Array[ProgressBar] = []
var _fuel_bar: ProgressBar
var _fire_label: Label
var _fuel_label: Label
var _ignite_button: Button
var _crafting := false
var _craft_box: VBoxContainer
var _craft_list: VBoxContainer
var _craft_toggle: Button

var _loot_box: VBoxContainer
var _loot_inventory: Inventory = null
var _loot_slots: Array[InventorySlot] = []
var _loot_grid: GridContainer
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
	var title := Label.new()
	title.text = "EQUIPO"
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var hint := Label.new()
	hint.text = "C · Esc: cerrar · I: solo el inventario"
	hint.theme_type_variation = &"HintLabel"
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(hint)
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.theme_type_variation = &"CloseButton"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.tooltip_text = "Cerrar"
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
	title.text = "INVENTARIO"
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_count_label = Label.new()
	_count_label.theme_type_variation = &"ValueLabel"
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count_label)
	var sort := Button.new()
	sort.text = "Ordenar"
	sort.theme_type_variation = &"TabButton"
	sort.focus_mode = Control.FOCUS_NONE
	sort.tooltip_text = "Junta lo que se apila y lo ordena por tipo"
	sort.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sort.pressed.connect(_sort_inventory)
	header.add_child(sort)
	_craft_toggle = Button.new()
	_craft_toggle.text = "Fabricar"
	_craft_toggle.theme_type_variation = &"TabButton"
	_craft_toggle.toggle_mode = true
	_craft_toggle.focus_mode = Control.FOCUS_NONE
	_craft_toggle.tooltip_text = "Lo que puedes hacer con lo que llevas"
	_craft_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_craft_toggle.toggled.connect(_set_crafting)
	header.add_child(_craft_toggle)
	_inventory_close = Button.new()
	_inventory_close.text = "×"
	_inventory_close.theme_type_variation = &"CloseButton"
	_inventory_close.focus_mode = Control.FOCUS_NONE
	_inventory_close.tooltip_text = "Cerrar (I, Esc)"
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

	_slot_grid = GridContainer.new()
	_slot_grid.columns = COLUMNS
	_slot_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_slot_grid)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	box.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = INVENTORY_HINT
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
	_craft_box = _build_crafting()
	_craft_box.visible = false
	box.add_child(_craft_box)
	return column


## La hoguera abierta: su fuego, el hueco del combustible y los ocho del asador.
func _build_campfire() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	var title := _label("HOGUERA", &"HeaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_fire_label = _label("", &"ValueLabel")
	_fire_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_fire_label)
	box.add_child(header)
	box.add_child(HSeparator.new())
	box.add_child(_label("Combustible", &"SectionLabel"))
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
	fuel_info.add_child(_label("Madera, ramas: lo que arda", &"HintLabel"))
	fuel_row.add_child(fuel_info)
	box.add_child(fuel_row)
	box.add_child(HSeparator.new())
	box.add_child(_label("Asador", &"SectionLabel"))
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
	take.text = "Recoger lo asado"
	take.focus_mode = Control.FOCUS_NONE
	take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take.pressed.connect(_take_cooked)
	buttons.add_child(take)
	box.add_child(buttons)
	var dismantle := Button.new()
	dismantle.text = "Desmontar"
	dismantle.focus_mode = Control.FOCUS_NONE
	dismantle.tooltip_text = "Apagada y vacía, vuelve al inventario"
	dismantle.pressed.connect(_dismantle_campfire)
	box.add_child(dismantle)
	var hint := _label("Con algo en el cursor, clic en un hueco: dejarlo (una pieza en el asador)\nClic: al inventario", &"HintLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	return box


## Lo que se puede fabricar con lo que se lleva (Recipes).
func _build_crafting() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_label("FABRICAR", &"HeaderLabel"))
	box.add_child(HSeparator.new())
	_craft_list = VBoxContainer.new()
	box.add_child(_craft_list)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var hint := _label("Lo fabricado va al inventario; si no cabe, al suelo", &"HintLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	return box


func _build_stats() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_label("ATRIBUTOS", &"HeaderLabel"))
	box.add_child(HSeparator.new())
	var vitals := GridContainer.new()
	vitals.columns = 2
	_health_value = _stat_row(vitals, "Vida")
	_health_bar = _bar(&"HealthBar")
	box.add_child(vitals)
	box.add_child(_health_bar)
	var stamina_grid := GridContainer.new()
	stamina_grid.columns = 2
	_stamina_value = _stat_row(stamina_grid, "Aguante")
	_stamina_bar = _bar(&"StaminaBar")
	box.add_child(stamina_grid)
	box.add_child(_stamina_bar)
	var armor := GridContainer.new()
	armor.columns = 2
	_armor_value = _stat_row(armor, "Armadura")
	box.add_child(armor)
	box.add_child(HSeparator.new())
	box.add_child(_label("Necesidades", &"SectionLabel"))
	var needs := GridContainer.new()
	needs.columns = 2
	for need in [["hambre", "Hambre"], ["sed", "Sed"], ["descanso", "Descanso"], ["cordura", "Cordura"],
			["temperatura", "Temperatura"], ["agua", "Agua en odres"]]:
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
	var title := _label("BOTÍN", &"HeaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_loot_label = _label("", &"ValueLabel")
	_loot_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_loot_label)
	box.add_child(header)
	box.add_child(HSeparator.new())
	_loot_grid = GridContainer.new()
	_loot_grid.columns = COLUMNS
	_loot_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_loot_grid)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var take_all := Button.new()
	take_all.text = "Cogerlo todo"
	take_all.theme_type_variation = &"AccentButton"
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.pressed.connect(_take_all_loot)
	box.add_child(take_all)
	var hint := _label("Clic: al inventario", &"HintLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
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
	panel.add_theme_constant_override("separation", roundi(GAP * s))
	_frame.add_theme_constant_override("separation", roundi(18 * s))

	var sides := (2.0 * SIDE_WIDTH + 2.0 * GAP) * s
	var available := viewport_size.x - 2.0 * MARGIN.x * s
	var doll := clampf(available - sides, DOLL_WIDTH.x * s, DOLL_WIDTH.y * s)
	var width := sides + doll
	var height := viewport_size.y - MARGIN.y * s - BOTTOM * s
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
	for slot in slots:
		slot.queue_free()
	slots.clear()

	for i in range(inventory.max_slots):
		var slot := InventorySlot.new()
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_double_clicked.connect(_on_slot_double_clicked)
		slot.hover_changed.connect(_on_slot_hovered.bind(&"inventory"))
		_slot_grid.add_child(slot)
		slots.append(slot)


func _refresh() -> void:
	if not inventory:
		return

	var items = inventory.get_all_items()
	var count = 0
	for item in items:
		if item != null:
			count += 1

	_count_label.text = "%d / %d" % [count, inventory.max_slots]

	for i in range(slots.size()):
		if i < items.size():
			slots[i].set_item(items[i])
		else:
			slots[i].clear()

	if floating_item and floating_slot_index >= 0 and floating_slot_index < slots.size():
		slots[floating_slot_index].clear()
	_apply_filter()
	if visible:
		_refresh_stats()
		if _crafting:
			_refresh_crafting()


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
	var armor := 0
	for slot_type in CharacterWindow.LEFT_SLOTS:
		var item := _equipped(slot_type)
		if item != null:
			armor += item.defense
	_armor_value.text = str(armor)
	for slot_type in _hand_boxes:
		var box: VBoxContainer = _hand_boxes[slot_type]
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
		var data := _equipped(slot_type)
		if data == null:
			box.add_child(_label("Vacía", &"HintLabel"))
			continue
		box.add_child(_label(data.display_name, &"StatValue"))
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
		elif need == "temperatura":
			label.text = "%s · %d °C" % [_needs.temperature_word(), roundi(_needs.felt_temperature)]
		elif need == "agua":
			var room := _needs.water_capacity()
			label.text = "%d / %d tragos" % [_needs.water, room] if room > 0 else "Sin odre"
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
			hint = "Clic: coger · Clic derecho: la mitad"
			if item and (item.data.get_trait(EdibleTrait) != null or item.data.get_trait(WaterContainerTrait) != null):
				hint += " · Doble clic: " + ("beber" if item.data.get_trait(WaterContainerTrait) != null else "comer")
		&"loot":
			var item: InventoryItem = (slot as InventorySlot).item
			if item:
				data = item.data
				quantity = item.quantity
			hint = "Clic: al inventario"
		&"campfire":
			var item: InventoryItem = (slot as InventorySlot).item
			if item:
				data = item.data
				quantity = item.quantity
				hint = "Clic: al inventario"
			else:
				var fuel := (slot as InventorySlot).slot_index == Campfire.FUEL_SLOT
				_card.show_empty("Combustible" if fuel else "Asador",
					"Suelta aquí algo que arda" if fuel else "Suelta aquí una pieza para asarla")
		&"craft":
			var item: InventoryItem = (slot as InventorySlot).item
			if item:
				data = item.data
				quantity = 0
			hint = ""
		&"equipment":
			var equipment := slot as EquipmentSlot
			if equipment.has_item():
				data = equipment.equipped_item.data
				hint = "Clic: quitárselo"
			else:
				_card.show_empty(CharacterWindow.SLOT_NAMES.get(equipment.slot_type, "Hueco"),
					"Suelta aquí lo que lleves en el cursor para ponértelo")
		&"hotbar":
			data = (slot as HotbarSlot).assigned_data
			hint = "Clic: vaciar el hueco · Con algo en el cursor: asignarlo"
			quantity = 0
	if data != null:
		var compare: ItemData = null if context in [&"equipment", &"craft"] else _equipped_counterpart(data)
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
		&"inventory", &"loot", &"campfire", &"craft":
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
## de lo que tiene; en la de personaje, las columnas llenan la pantalla.
func _apply_view() -> void:
	var full := view == View.CHARACTER
	_backdrop.visible = full
	_header.visible = full
	_doll_holder.visible = full
	_side_column.visible = full or _loot_inventory != null or _campfire != null or _crafting
	_inventory_close.visible = not full
	var vertical := Control.SIZE_FILL if full else Control.SIZE_SHRINK_CENTER
	_inventory_column.size_flags_vertical = vertical
	_side_column.size_flags_vertical = vertical


func close() -> void:
	var was_open := visible
	if floating_item:
		_cancel_floating_item()
	close_loot()
	close_campfire()
	if _crafting:
		_craft_toggle.button_pressed = false
	_hide_card()
	visible = false
	if hotbar != null and _hotbar_layer >= 0:
		hotbar.layer = _hotbar_layer
		_hotbar_layer = -1
	if was_open:
		closed.emit()


func open_loot(loot_inv: Inventory) -> void:
	if _loot_inventory:
		close_loot()
	_loot_inventory = loot_inv
	_loot_inventory.inventory_changed.connect(_refresh_loot)
	_create_loot_slots()
	_update_side()
	_refresh_loot()
	open(view if visible else View.INVENTORY)


func close_loot() -> void:
	if _loot_inventory and _loot_inventory.inventory_changed.is_connected(_refresh_loot):
		_loot_inventory.inventory_changed.disconnect(_refresh_loot)
	_loot_inventory = null
	for slot in _loot_slots:
		if slot == _card_slot:
			_hide_card()
		slot.queue_free()
	_loot_slots.clear()
	_update_side()


## Qué va en la columna de la derecha: el botín si se saquea, la hoguera si está abierta, lo que
## se fabrica si se ha pedido y, si no, los atributos.
func _update_side() -> void:
	var mode := &"stats"
	if _loot_inventory != null:
		mode = &"loot"
	elif _campfire != null:
		mode = &"campfire"
	elif _crafting:
		mode = &"craft"
	_stats_box.visible = mode == &"stats"
	_loot_box.visible = mode == &"loot"
	_campfire_box.visible = mode == &"campfire"
	_craft_box.visible = mode == &"craft"
	_apply_view()


# --- Hoguera ------------------------------------------------------------------------------------

func open_campfire(fire: Campfire) -> void:
	close_campfire()
	_campfire = fire
	fire.changed.connect(_refresh_campfire)
	fire.inventory.inventory_changed.connect(_refresh_campfire)
	fire.tree_exiting.connect(close_campfire)
	_update_side()
	_refresh_campfire()
	open(view if visible else View.INVENTORY)


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
	_fuel_label.text = "Para %d:%02d" % [floori(left / 60.0), int(left) % 60] if left > 0.0 else "Sin combustible"
	_fuel_bar.value = _campfire.fuel_left / maxf(_campfire.fuel_total, 1.0) if _campfire.fuel_left > 0.0 else 0.0
	_fire_label.text = "Encendida" if _campfire.lit else "Apagada"
	_ignite_button.text = "Apagar" if _campfire.lit else "Encender"
	_ignite_button.disabled = not _campfire.lit and not _campfire.has_fuel()


func _on_campfire_slot_clicked(slot: InventorySlot, button_index: int) -> void:
	if _campfire == null:
		return
	var index := slot.slot_index
	var stored := _campfire.inventory.items[index]
	if floating_item != null:
		if not _campfire.accepts(index, floating_item.data):
			if hotbar != null:
				hotbar.notify("Eso no va ahí" if index != Campfire.FUEL_SLOT else "Eso no arde")
			return
		var room := _campfire.capacity(index, floating_item.data)
		if stored != null and (stored.data.id != floating_item.data.id or not stored.data.stackable):
			return
		var have := stored.quantity if stored != null else 0
		var amount := mini(room - have, 1 if button_index == MOUSE_BUTTON_RIGHT else floating_item.quantity)
		if amount <= 0:
			return
		if stored != null:
			stored.add(amount)
		else:
			_campfire.inventory.items[index] = InventoryItem.new(floating_item.data, amount)
			if index != Campfire.FUEL_SLOT:
				_campfire.progress[index - 1] = 0.0
		floating_item.remove(amount)
		if floating_item.quantity <= 0:
			_clear_floating_item()
		else:
			_update_floating_display()
	elif stored != null and button_index == MOUSE_BUTTON_LEFT:
		var remaining := inventory.add_item(stored.data, stored.quantity)
		_campfire.inventory.items[index] = InventoryItem.new(stored.data, remaining) if remaining > 0 else null
		if index != Campfire.FUEL_SLOT and remaining <= 0:
			_campfire.progress[index - 1] = 0.0
	else:
		return
	_campfire.inventory.inventory_changed.emit()
	inventory.inventory_changed.emit()


func _toggle_fire() -> void:
	if _campfire == null:
		return
	if _campfire.lit:
		_campfire.extinguish()
	elif not _campfire.ignite() and hotbar != null:
		hotbar.notify("Échale algo que arda")


## Al inventario todo lo que ya está asado (lo que no se asa más).
func _take_cooked() -> void:
	if _campfire == null:
		return
	for i in Campfire.COOK_SLOTS:
		var item := _campfire.inventory.items[1 + i]
		if item != null and item.data.get_trait(CookableTrait) == null:
			var remaining := inventory.add_item(item.data, item.quantity)
			_campfire.inventory.items[1 + i] = InventoryItem.new(item.data, remaining) if remaining > 0 else null
	_campfire.inventory.inventory_changed.emit()
	inventory.inventory_changed.emit()


func _dismantle_campfire() -> void:
	if _campfire == null:
		return
	if _campfire.lit or not _campfire.is_empty():
		if hotbar != null:
			hotbar.notify("Apágala y vacíala antes de desmontarla")
		return
	var fire := _campfire
	close_campfire()
	var left := inventory.add_item(Config.get_item(Campfire.ITEM_ID), 1)
	if left > 0:
		drop_requested.emit(Config.get_item(Campfire.ITEM_ID), left)
	fire.queue_free()


# --- Fabricar -----------------------------------------------------------------------------------

func _set_crafting(on: bool) -> void:
	_crafting = on
	if on:
		_refresh_crafting()
	_update_side()


func _refresh_crafting() -> void:
	if _craft_list == null:
		return
	for child in _craft_list.get_children():
		_craft_list.remove_child(child)
		child.queue_free()
	for i in Recipes.LIST.size():
		var recipe: Dictionary = Recipes.LIST[i]
		var result: ItemData = Config.get_item(recipe.result)
		if result == null:
			continue
		var row := HBoxContainer.new()
		var icon := InventorySlot.new()
		icon.set_item(InventoryItem.new(result, int(recipe.amount)))
		icon.hover_changed.connect(_on_slot_hovered.bind(&"craft"))
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_child(_label(result.display_name, &"StatValue"))
		var missing := Recipes.missing(recipe, inventory)
		for id: StringName in recipe.inputs:
			var data: ItemData = Config.get_item(id)
			var need := int(recipe.inputs[id])
			var have := inventory.get_item_count(data)
			var line := _label("%s  %d / %d" % [data.display_name if data else String(id), mini(have, need), need],
				&"WorseLabel" if missing.has(id) else &"BetterLabel")
			info.add_child(line)
		row.add_child(info)
		var make := Button.new()
		make.text = "Fabricar"
		make.theme_type_variation = &"AccentButton"
		make.focus_mode = Control.FOCUS_NONE
		make.disabled = not missing.is_empty()
		make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		make.pressed.connect(_craft.bind(i))
		row.add_child(make)
		_craft_list.add_child(row)
		_craft_list.add_child(HSeparator.new())


func _craft(index: int) -> void:
	var recipe: Dictionary = Recipes.LIST[index]
	var left := Recipes.craft(recipe, inventory)
	if left < 0:
		return
	var result: ItemData = Config.get_item(recipe.result)
	if left > 0:
		drop_requested.emit(result, left)
	if hotbar != null:
		hotbar.notify("Fabricas: %s" % result.display_name)
	inventory.inventory_changed.emit()


func _create_loot_slots() -> void:
	for slot in _loot_slots:
		slot.queue_free()
	_loot_slots.clear()
	for i in range(_loot_inventory.max_slots):
		var slot := InventorySlot.new()
		slot.slot_index = i
		slot.slot_clicked.connect(_on_loot_slot_clicked)
		slot.hover_changed.connect(_on_slot_hovered.bind(&"loot"))
		_loot_grid.add_child(slot)
		_loot_slots.append(slot)


func _refresh_loot() -> void:
	if not _loot_inventory:
		return
	var items = _loot_inventory.get_all_items()
	var count := 0
	for item in items:
		if item != null:
			count += 1
	_loot_label.text = str(count)
	for i in range(_loot_slots.size()):
		if i < items.size():
			_loot_slots[i].set_item(items[i])
		else:
			_loot_slots[i].clear()
	if count == 0:
		close_loot()


func _on_loot_slot_clicked(slot: InventorySlot, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_LEFT or not slot.item:
		return
	_take_loot(slot.slot_index)
	_loot_inventory.inventory_changed.emit()
	inventory.inventory_changed.emit()


func _take_all_loot() -> void:
	if not _loot_inventory:
		return
	var loot := _loot_inventory
	for i in loot.items.size():
		if loot.items[i] != null:
			_take_loot(i)
	inventory.inventory_changed.emit()
	loot.inventory_changed.emit()


## Pasa al inventario lo que quepa del hueco [index] del botín.
func _take_loot(index: int) -> void:
	var item := _loot_inventory.items[index]
	var remaining := inventory.add_item(item.data, item.quantity)
	_loot_inventory.items[index] = null
	if remaining > 0:
		_loot_inventory.items[index] = InventoryItem.new(item.data, remaining)


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
		if slot.item and slot.item.quantity > 1:
			_pickup_half_from_inventory(slot)
	else:
		_drop_single_to_inventory(slot)


func _on_equipment_slot_clicked(slot: EquipmentSlot) -> void:
	if floating_item:
		_drop_to_equipment(slot)
	elif slot.has_item():
		_pickup_from_equipment(slot)


func _pickup_from_inventory(slot: InventorySlot) -> void:
	if Input.is_key_pressed(KEY_SHIFT) and slot.item.quantity > 1:
		_pickup_half_from_inventory(slot)
		return

	floating_item = InventoryItem.new(slot.item.data, slot.item.quantity)
	floating_slot_index = slot.slot_index
	inventory.items[floating_slot_index] = null

	_update_floating_display()
	_refresh()


func _pickup_half_from_inventory(slot: InventorySlot) -> void:
	var half = int(ceil(slot.item.quantity / 2.0))

	floating_item = InventoryItem.new(slot.item.data, half)
	floating_slot_index = slot.slot_index
	inventory.items[slot.slot_index].remove(half)

	_update_floating_display()
	_refresh()


func _pickup_from_equipment(slot: EquipmentSlot) -> void:
	floating_item = character_window.unequip_item(slot)
	floating_slot_index = -1
	_update_floating_display()


func _drop_to_inventory(target_slot: InventorySlot) -> void:
	var target_index = target_slot.slot_index

	if target_index == floating_slot_index:
		_return_to_origin()
		return

	if target_slot.item:
		var target_item = inventory.items[target_index]

		if target_item.data.id == floating_item.data.id and floating_item.data.stackable:
			var space = target_item.data.max_stack - target_item.quantity
			var to_add = min(floating_item.quantity, space)

			target_item.add(to_add)
			floating_item.remove(to_add)

			if floating_item.quantity > 0:
				_return_to_origin()
			else:
				_clear_floating_item()
		else:
			var swapped = target_item
			inventory.items[target_index] = floating_item

			if floating_slot_index >= 0:
				inventory.items[floating_slot_index] = swapped
			else:
				floating_item = swapped
				_update_floating_display()
				inventory.inventory_changed.emit()
				_refresh()
				return

			_clear_floating_item()
	else:
		inventory.items[target_index] = floating_item
		_clear_floating_item()

	inventory.inventory_changed.emit()
	_refresh()


func _drop_single_to_inventory(target_slot: InventorySlot) -> void:
	var target_index = target_slot.slot_index

	if target_slot.item:
		var target_item = inventory.items[target_index]
		if target_item.data.id == floating_item.data.id and floating_item.data.stackable:
			var space = target_item.data.max_stack - target_item.quantity
			if space > 0:
				target_item.add(1)
				floating_item.remove(1)
	else:
		var new_item = InventoryItem.new(floating_item.data, 1)
		inventory.items[target_index] = new_item
		floating_item.remove(1)

	if floating_item.quantity <= 0:
		_clear_floating_item()
	else:
		_update_floating_display()

	inventory.inventory_changed.emit()
	_refresh()


func _drop_to_equipment(slot: EquipmentSlot) -> void:
	var old_item = character_window.equip_item(slot, floating_item)
	# No va en ese hueco: sigue en el cursor.
	if old_item == floating_item:
		return
	floating_item.remove(1)

	if floating_item.quantity > 0:
		if floating_slot_index >= 0:
			inventory.items[floating_slot_index] = floating_item
		else:
			inventory.add_item(floating_item.data, floating_item.quantity)

	if old_item:
		floating_item = old_item
		floating_slot_index = -1
		_update_floating_display()
	else:
		_clear_floating_item()

	inventory.inventory_changed.emit()
	_refresh()


func _return_to_origin() -> void:
	if floating_slot_index >= 0:
		if inventory.items[floating_slot_index] != null:
			inventory.items[floating_slot_index].add(floating_item.quantity)
		else:
			inventory.items[floating_slot_index] = floating_item
	else:
		inventory.add_item(floating_item.data, floating_item.quantity)

	_clear_floating_item()
	inventory.inventory_changed.emit()
	_refresh()


func _cancel_floating_item() -> void:
	if floating_item:
		_return_to_origin()


func _clear_floating_item() -> void:
	floating_item = null
	floating_slot_index = -1
	_held.visible = false


## Tira al suelo [amount] de lo que va en el cursor.
func _drop_to_world(amount: int) -> void:
	var n := mini(amount, floating_item.quantity)
	drop_requested.emit(floating_item.data, n)
	floating_item.remove(n)
	if floating_item.quantity <= 0:
		_clear_floating_item()
	else:
		_update_floating_display()
	inventory.inventory_changed.emit()
	_refresh()


## El ratón está sobre alguna ventana: el inventario, el muñeco, la columna derecha, la cabecera
## o la barra rápida con su consola.
func _over_ui(mp: Vector2) -> bool:
	var areas: Array[Control] = [_inventory_column, _side_column, _close_button, _inventory_close]
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
