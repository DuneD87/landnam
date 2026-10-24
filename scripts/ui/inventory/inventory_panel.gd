class_name InventoryPanel
extends ScrollContainer

## Cuadrícula reutilizable: se enlaza a cualquier Inventory y solo presenta sus huecos.
signal slot_clicked(slot: InventorySlot, button_index: int)
signal slot_double_clicked(slot: InventorySlot)
signal slot_hovered(slot: InventorySlot, hovered: bool)

var inventory: Inventory
var slots: Array[InventorySlot] = []
var max_height := 600.0:
	set(value):
		max_height = value
		_update_height()
var _grid := GridContainer.new()


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_grid)


func bind_inventory(value: Inventory) -> void:
	if is_instance_valid(inventory) and inventory.inventory_changed.is_connected(refresh):
		inventory.inventory_changed.disconnect(refresh)
	inventory = value
	if inventory != null:
		inventory.inventory_changed.connect(refresh)
	scroll_vertical = 0
	refresh()


func refresh() -> void:
	var count := inventory.max_slots if is_instance_valid(inventory) else 0
	if slots.size() != count:
		for slot in slots:
			_grid.remove_child(slot)
			slot.queue_free()
		slots.clear()
		for i in count:
			var slot := InventorySlot.new()
			slot.slot_index = i
			slot.slot_clicked.connect(func(s: InventorySlot, button: int) -> void: slot_clicked.emit(s, button))
			slot.slot_double_clicked.connect(func(s: InventorySlot) -> void: slot_double_clicked.emit(s))
			slot.hover_changed.connect(func(s: InventorySlot, on: bool) -> void: slot_hovered.emit(s, on))
			_grid.add_child(slot)
			slots.append(slot)
	for i in count:
		slots[i].set_item(inventory.get_item_at_slot(i))
	_update_height()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_update_height()


func _update_height() -> void:
	if _grid == null:
		return
	var side := get_theme_constant(&"inventory", &"ItemSlot")
	var rows := ceili(slots.size() / float(_grid.columns))
	var height := rows * side + maxi(0, rows - 1) * _grid.get_theme_constant(&"v_separation")
	custom_minimum_size.y = minf(height, max_height)
