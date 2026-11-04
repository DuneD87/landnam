class_name VillagerChat
extends CanvasLayer

## Hablar con un aldeano (Villager): E delante de uno abre abajo su ficha (nombre, oficio, poblado y la
## confianza del poblado, SettlementRelations) con lo que dice (VillagerTalk) y qué hacer: hablar otra vez,
## regalarle algo del inventario o despedirse. Mientras, él se para y mira al jugador, y el jugador no se
## mueve (el ratón va suelto). Se cierra con E, Escape, alejándose o si él se va (una fiera). Ver
## docs/villagers.md.

## Más lejos de esto (m) se acaba la charla.
const REACH := 4.0
## Lo que se ve la subida de confianza (s).
const GAIN_TIME := 2.5
const GIFT_COLUMNS := 8

var _player: PlayerController
var _villager: Villager
var _rng := RandomNumberGenerator.new()
var _last_line := ""
var _gifting := false
var _gain_left := 0.0
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _root: Control
var _panel: PanelContainer
var _margin: MarginContainer
var _box: VBoxContainer
var _name: Label
var _subtitle: Label
var _trust_label: Label
var _trust_bar: ProgressBar
var _gain: Label
var _line: Label
var _gift_scroll: ScrollContainer
var _gift_grid: GridContainer
var _gift_hint: Label
var _talk_button: Button
var _gift_button: Button
var _back_button: Button
var _bye_button: Button


func _ready() -> void:
	layer = 14
	_rng.randomize()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func setup(player: PlayerController) -> void:
	_player = player
	_player.health_component.died.connect(close)
	_player.inventory.inventory_changed.connect(func() -> void:
		if visible and _gifting:
			_fill_gifts())
	GameManager.state_changed.connect(func(state: GameManager.State) -> void:
		if state != GameManager.State.PLAYING:
			close(false))


func is_open() -> bool:
	return visible


## Habla con el aldeano que tiene delante, si hay alguno a mano. Falso si no hay ninguno.
func try_open() -> bool:
	var camera := _player.camera
	var look := -camera.global_basis.z
	var villager := Villager.find(get_tree(), _player.global_position, look)
	if villager == null:
		return false
	if not villager.can_chat():
		_player.hotbar.notify(tr("VILLAGER_ASLEEP") % villager.resident.name)
		return true
	open(villager)
	return true


func open(villager: Villager) -> void:
	if villager == null or not villager.begin_chat():
		return
	_villager = villager
	_gifting = false
	_last_line = ""
	_previous_mouse_mode = Input.get_mouse_mode()
	_layout()
	visible = true
	_player.capture_mouse(false)
	_speak()
	var gain := villager.village.relations.talk(villager.village.index, String(villager.resident.id))
	_show_gain(gain)
	_refresh()


func close(capture_mouse := true) -> void:
	var was_open := visible
	visible = false
	_gifting = false
	if _villager != null and is_instance_valid(_villager):
		_villager.end_chat()
	_villager = null
	if was_open and capture_mouse and is_instance_valid(_player):
		_player.capture_mouse(_previous_mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _exit_tree() -> void:
	close(false)


func _process(delta: float) -> void:
	if not visible:
		return
	if _villager == null or not is_instance_valid(_villager) or not _villager.is_chatting() \
			or _player.global_position.distance_to(_villager.global_position) > REACH \
			or _player.health_component.is_dead:
		close()
		return
	if _gain_left > 0.0:
		_gain_left -= delta
		_gain.modulate.a = clampf(_gain_left / 0.6, 0.0, 1.0)
		if _gain_left <= 0.0:
			_gain.text = ""


func _speak() -> void:
	var said := VillagerTalk.line(_villager, _player, _rng, _last_line)
	_say(said)


func _say(said: Dictionary) -> void:
	_last_line = said.key
	_line.text = tr("VILLAGER_QUOTE") % said.text
	_villager.say()


func _show_gain(gain: float) -> void:
	if gain <= 0.0:
		return
	_gain.text = "+%d" % maxi(1, roundi(gain))
	_gain.modulate.a = 1.0
	_gain_left = GAIN_TIME


func _refresh() -> void:
	if _villager == null:
		return
	var village := _villager.village
	var who := _villager.resident
	_name.text = who.name
	_subtitle.text = "%s · %s" % [tr(VillagerTalk.job_title(who)), village.name]
	var trust := village.relations.trust(village.index)
	_trust_label.text = tr("VILLAGE_TRUST") % [tr(SettlementRelations.tier_name(SettlementRelations.tier_of(trust))),
		floori(trust)]
	_trust_bar.value = trust
	_gift_scroll.visible = _gifting
	_gift_hint.visible = _gifting
	_talk_button.visible = not _gifting
	_gift_button.visible = not _gifting
	_back_button.visible = _gifting
	_gift_button.disabled = village.danger


func _on_talk() -> void:
	_speak()
	_refresh()


func _on_gift() -> void:
	_gifting = true
	_fill_gifts()
	_refresh()


func _on_back() -> void:
	_gifting = false
	_refresh()


## Los montones del inventario, uno por objeto, con lo que hay de cada uno.
func _fill_gifts() -> void:
	for child in _gift_grid.get_children():
		child.queue_free()
	var counts := {}
	var order: Array[ItemData] = []
	for item in _player.inventory.get_all_items():
		if item == null or item.data == null:
			continue
		if not counts.has(item.data.id):
			counts[item.data.id] = 0
			order.append(item.data)
		counts[item.data.id] += item.quantity
	order.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		return ItemTaxonomy._less(ItemTaxonomy.sort_key(a), ItemTaxonomy.sort_key(b)))
	for data in order:
		var slot := ItemSlotView.new()
		slot.size_kind = &"hotbar"
		slot.show_item(data.icon, counts[data.id])
		slot.tooltip_text = data.get_display_name()
		slot.slot_clicked.connect(func(_s: ItemSlotView, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_give(data))
		_gift_grid.add_child(slot)
	if order.is_empty():
		_gift_hint.text = tr("VILLAGER_GIFT_EMPTY")
	else:
		_gift_hint.text = tr("VILLAGER_GIFT_HINT")


## Le da una unidad de [data].
func _give(data: ItemData) -> void:
	if _villager == null or _player.inventory.remove_item(data, 1) < 1:
		return
	var village := _villager.village
	var value := ItemValue.of(data)
	var taste := VillagerTalk.taste(StringName(_villager.resident.get("job", {}).get("kind", "")), data)
	var gain := village.relations.gift(village.index, value, taste)
	_say(VillagerTalk.gift_line(gain, taste, value * taste, _rng, _last_line))
	_show_gain(gain)
	AudioManager.play_ui(&"item_pickup")
	_refresh()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"WindowPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	_box = VBoxContainer.new()
	_margin.add_child(_box)

	var header := HBoxContainer.new()
	_box.add_child(header)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(who)
	_name = Label.new()
	_name.theme_type_variation = &"HeaderLabel"
	who.add_child(_name)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"HintLabel"
	who.add_child(_subtitle)
	var trust := VBoxContainer.new()
	trust.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(trust)
	var trust_row := HBoxContainer.new()
	trust_row.alignment = BoxContainer.ALIGNMENT_END
	trust.add_child(trust_row)
	_gain = Label.new()
	_gain.theme_type_variation = &"BetterLabel"
	trust_row.add_child(_gain)
	_trust_label = Label.new()
	_trust_label.theme_type_variation = &"ValueLabel"
	_trust_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trust_row.add_child(_trust_label)
	_trust_bar = ProgressBar.new()
	_trust_bar.max_value = SettlementRelations.MAX_TRUST
	_trust_bar.show_percentage = false
	trust.add_child(_trust_bar)

	_box.add_child(HSeparator.new())
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_override("font", load("res://fonts/AlegreyaSans-Italic.ttf"))
	_box.add_child(_line)

	_gift_hint = Label.new()
	_gift_hint.theme_type_variation = &"HintLabel"
	_gift_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_gift_hint)
	_gift_scroll = ScrollContainer.new()
	_gift_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_gift_scroll)
	_gift_grid = GridContainer.new()
	_gift_grid.columns = GIFT_COLUMNS
	_gift_scroll.add_child(_gift_grid)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(buttons)
	_talk_button = Button.new()
	_talk_button.text = "VILLAGER_TALK"
	_talk_button.theme_type_variation = &"AccentButton"
	_talk_button.pressed.connect(_on_talk)
	buttons.add_child(_talk_button)
	_gift_button = Button.new()
	_gift_button.text = "VILLAGER_GIFT"
	_gift_button.pressed.connect(_on_gift)
	buttons.add_child(_gift_button)
	_back_button = Button.new()
	_back_button.text = "VILLAGER_GIFT_DONE"
	_back_button.pressed.connect(_on_back)
	buttons.add_child(_back_button)
	_bye_button = Button.new()
	_bye_button.text = "VILLAGER_BYE"
	_bye_button.pressed.connect(close)
	buttons.add_child(_bye_button)


func _layout() -> void:
	var ui_scale := GameTheme.scale_for(get_viewport())
	_root.theme = GameTheme.build(ui_scale)
	_panel.custom_minimum_size.x = 900.0 * ui_scale
	_panel.offset_top = -200.0 * ui_scale
	_panel.offset_bottom = -200.0 * ui_scale
	_line.custom_minimum_size = Vector2(840, 80) * ui_scale
	_trust_bar.custom_minimum_size = Vector2(260, 14) * ui_scale
	# Tres filas enteras de huecos.
	var slot_side := float(_root.theme.get_constant(&"hotbar", &"ItemSlot"))
	var gap := roundi(6.0 * ui_scale)
	_gift_grid.add_theme_constant_override("h_separation", gap)
	_gift_grid.add_theme_constant_override("v_separation", gap)
	_gift_scroll.custom_minimum_size.y = slot_side * 3.0 + gap * 2.0
	_box.add_theme_constant_override("separation", roundi(14.0 * ui_scale))
	for side in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, roundi(24.0 * ui_scale))
	for button: Button in [_talk_button, _gift_button, _back_button, _bye_button]:
		button.custom_minimum_size.x = 170.0 * ui_scale
