extends CanvasLayer
class_name InventoryUI

const SlotScene = preload("res://scenes/ui/inventory_slot.tscn")

@onready var panel: PanelContainer = $CenterContainer/PanelContainer
@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Header/TitleLabel
@onready var close_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Header/CloseButton
@onready var slot_grid: GridContainer = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SlotGrid

var inventory: Inventory
var character_window: CharacterWindow
var slots: Array[InventorySlot] = []
var hotbar: Hotbar

var _loot_inventory: Inventory = null
var _loot_slots: Array[InventorySlot] = []
var _loot_container: Control = null
var _loot_panel_node: PanelContainer = null
var _loot_grid: GridContainer = null
var _loot_label: Label = null

var _drag_active: bool = false
var _drag_target: Control = null
var _drag_offset: Vector2 = Vector2.ZERO
var _player_panel_header: Control = null
var _loot_panel_header: Control = null

var floating_item: InventoryItem = null
var floating_slot_index: int = -1
var floating_display: Control = null
var floating_icon: TextureRect = null
var floating_label: Label = null


func _ready() -> void:
	_apply_panel_style()
	close_button.pressed.connect(close)
	slot_grid.columns = 5
	visible = false
	_create_floating_display()
	_player_panel_header = title_label.get_parent() as Control
	call_deferred("_setup_player_panel_drag")


func _on_hotbar_slot_clicked(slot_index: int) -> void:
	if not visible:
		return
	if floating_item:
		var data = floating_item.data
		_return_to_origin()
		hotbar.assign_to_slot(slot_index, data)
	else:
		hotbar.clear_slot(slot_index)


func setup(inv: Inventory, char_window: CharacterWindow, hbar: Hotbar) -> void:
	inventory = inv
	character_window = char_window
	
	inventory.inventory_changed.connect(_refresh)
	character_window.slot_clicked.connect(_on_equipment_slot_clicked)
	
	_create_slots()
	_refresh()
	hotbar = hbar
	hotbar.hotbar_slot_clicked.connect(_on_hotbar_slot_clicked)

func _setup_player_panel_drag() -> void:
	var center := panel.get_parent()
	if not center:
		return
	center.remove_child(panel)
	add_child(panel)
	await get_tree().process_frame
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	var vp := get_viewport().get_visible_rect().size
	panel.set_position(vp * 0.5 - panel.size * 0.5)


func _apply_panel_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.3, 1)
	panel.add_theme_stylebox_override("panel", style)


func _create_floating_display() -> void:
	var floating_layer = CanvasLayer.new()
	floating_layer.layer = 100
	add_child(floating_layer)
	
	floating_display = Control.new()
	floating_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floating_display.visible = false
	floating_layer.add_child(floating_display)
	
	var panel_container = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.border_color = Color(0.7, 0.7, 0.7, 1)
	panel_container.add_theme_stylebox_override("panel", style)
	floating_display.add_child(panel_container)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel_container.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	floating_icon = TextureRect.new()
	floating_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	floating_icon.custom_minimum_size = Vector2(64, 64)
	floating_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(floating_icon)
	
	floating_label = Label.new()
	floating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(floating_label)


func _process(_delta: float) -> void:
	if floating_display and floating_display.visible:
		floating_display.global_position = get_viewport().get_mouse_position() + Vector2(10, 10)


func _create_slots() -> void:
	for slot in slots:
		slot.queue_free()
	slots.clear()
	
	for i in range(inventory.max_slots):
		var slot = SlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot_grid.add_child(slot)
		slots.append(slot)


func _refresh() -> void:
	if not inventory:
		return
	
	var items = inventory.get_all_items()
	var count = 0
	for item in items:
		if item != null:
			count += 1
	
	title_label.text = "Inventario (%d/%d)" % [count, inventory.max_slots]
	
	for i in range(slots.size()):
		if i < items.size():
			slots[i].set_item(items[i])
		else:
			slots[i].clear()
	
	if floating_item and floating_slot_index >= 0 and floating_slot_index < slots.size():
		slots[floating_slot_index].clear()


func toggle() -> void:
	visible = !visible
	if visible:
		open()
	else:
		close()


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	if floating_item:
		_cancel_floating_item()
	close_loot()
	visible = false


func open_loot(loot_inv: Inventory) -> void:
	if _loot_inventory:
		close_loot()
	_loot_inventory = loot_inv
	_loot_inventory.inventory_changed.connect(_refresh_loot)
	_build_loot_panel()
	_refresh_loot()
	open()


func close_loot() -> void:
	if _loot_inventory and _loot_inventory.inventory_changed.is_connected(_refresh_loot):
		_loot_inventory.inventory_changed.disconnect(_refresh_loot)
	_loot_inventory = null
	_loot_slots.clear()
	if _loot_container:
		_loot_container.queue_free()
		_loot_container = null
	_loot_panel_node = null
	_loot_grid = null
	_loot_label = null
	_loot_panel_header = null


func _build_loot_panel() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_loot_container = root

	var loot_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.6, 0.4, 0.1, 1)
	loot_panel.add_theme_stylebox_override("panel", style)
	loot_panel.custom_minimum_size = Vector2(280, 0)
	var vp := get_viewport().get_visible_rect().size
	loot_panel.position = Vector2(vp.x * 0.1, vp.y * 0.5 - 160.0)
	root.add_child(loot_panel)
	_loot_panel_node = loot_panel

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	loot_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(header)

	_loot_label = Label.new()
	_loot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_loot_label)

	_loot_panel_header = header

	vbox.add_child(HSeparator.new())

	_loot_grid = GridContainer.new()
	_loot_grid.columns = 5
	vbox.add_child(_loot_grid)

	_create_loot_slots()


func _create_loot_slots() -> void:
	for slot in _loot_slots:
		slot.queue_free()
	_loot_slots.clear()
	for i in range(_loot_inventory.max_slots):
		var slot = SlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.slot_clicked.connect(_on_loot_slot_clicked)
		_loot_grid.add_child(slot)
		_loot_slots.append(slot)


func _refresh_loot() -> void:
	if not _loot_inventory or not _loot_grid:
		return
	var items = _loot_inventory.get_all_items()
	var count := 0
	for item in items:
		if item != null:
			count += 1
	if _loot_label:
		_loot_label.text = "Botín (%d)" % count
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
	var item := slot.item
	var remaining := inventory.add_item(item.data, item.quantity)
	_loot_inventory.items[slot.slot_index] = null
	if remaining > 0:
		_loot_inventory.items[slot.slot_index] = InventoryItem.new(item.data, remaining)
	_loot_inventory.inventory_changed.emit()
	inventory.inventory_changed.emit()



func _on_slot_clicked(slot: InventorySlot, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_LEFT:
		_handle_inventory_left_click(slot)
	elif button_index == MOUSE_BUTTON_RIGHT:
		_handle_inventory_right_click(slot)


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
	if floating_display:
		floating_display.visible = false


func _update_floating_display() -> void:
	if not floating_item or not floating_icon or not floating_label:
		return
	
	floating_icon.texture = floating_item.data.icon
	floating_label.text = str(floating_item.quantity) if floating_item.quantity > 1 else ""
	
	if floating_display:
		floating_display.visible = true


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		close()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mp := (event as InputEventMouseButton).global_position
			if _player_panel_header and _player_panel_header.is_visible_in_tree() \
					and _player_panel_header.get_global_rect().has_point(mp) \
					and not close_button.get_global_rect().has_point(mp):
				_drag_active = true
				_drag_target = panel
				_drag_offset = panel.global_position - mp
				get_viewport().set_input_as_handled()
			elif _loot_panel_header and is_instance_valid(_loot_panel_node) \
					and _loot_panel_header.is_visible_in_tree() \
					and _loot_panel_header.get_global_rect().has_point(mp):
				_drag_active = true
				_drag_target = _loot_panel_node
				_drag_offset = _loot_panel_node.global_position - mp
				get_viewport().set_input_as_handled()
		else:
			if _drag_active:
				_drag_active = false
				_drag_target = null

	elif event is InputEventMouseMotion and _drag_active and is_instance_valid(_drag_target):
		_drag_target.global_position = (event as InputEventMouseMotion).global_position + _drag_offset
		get_viewport().set_input_as_handled()
