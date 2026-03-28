# hotbar.gd
class_name Hotbar
extends CanvasLayer

## Emitted when the selected slot changes. Provides old and new InventoryItem (either can be null).
signal selection_changed(old_item: InventoryItem, new_item: InventoryItem)

const HOTBAR_SLOTS := 10
const HotbarSlotScene = preload("res://scenes/inventory/hotbar_slot.tscn")

@onready var slot_container: HBoxContainer = $BottomAnchor/PanelContainer/MarginContainer/HBoxContainer

var inventory: Inventory
var slots: Array[HotbarSlot] = []
var selected_index: int = 0

# Key actions mapped to hotbar indices 0-9
# Keys 1-9 → indices 0-8, Key 0 → index 9
var _key_actions: Array[StringName] = [
	&"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4", &"hotbar_5",
	&"hotbar_6", &"hotbar_7", &"hotbar_8", &"hotbar_9", &"hotbar_0",
]


func _ready() -> void:
	_ensure_input_actions()
	_create_slots()
	# Select first slot visually
	if slots.size() > 0:
		slots[0].set_selected(true)


func setup(inv: Inventory) -> void:
	inventory = inv
	inventory.inventory_changed.connect(_refresh)
	_refresh()


func _create_slots() -> void:
	for child in slot_container.get_children():
		child.queue_free()
	slots.clear()

	for i in HOTBAR_SLOTS:
		var slot := HotbarSlotScene.instantiate() as HotbarSlot
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot_container.add_child(slot)
		slots.append(slot)


func _refresh() -> void:
	if not inventory:
		return
	for i in HOTBAR_SLOTS:
		if i < inventory.items.size():
			slots[i].set_item(inventory.items[i])
		else:
			slots[i].clear()


func select_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SLOTS:
		return
	if index == selected_index:
		return

	var old_item := get_selected_item()

	slots[selected_index].set_selected(false)
	selected_index = index
	slots[selected_index].set_selected(true)

	var new_item := get_selected_item()
	selection_changed.emit(old_item, new_item)


func get_selected_item() -> InventoryItem:
	if not inventory or selected_index >= inventory.items.size():
		return null
	return inventory.items[selected_index]


func get_selected_index() -> int:
	return selected_index


func _on_slot_clicked(slot: HotbarSlot, _button_index: int) -> void:
	select_slot(slot.slot_index)


func _input(event: InputEvent) -> void:
	for i in HOTBAR_SLOTS:
		if event.is_action_pressed(_key_actions[i]):
			select_slot(i)
			get_viewport().set_input_as_handled()
			return

	# Mouse wheel slot cycling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot(posmod(selected_index - 1, HOTBAR_SLOTS))
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot(posmod(selected_index + 1, HOTBAR_SLOTS))
			get_viewport().set_input_as_handled()


## Auto-create input actions if they don't exist yet (keys 1-9, 0)
func _ensure_input_actions() -> void:
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	for i in HOTBAR_SLOTS:
		var action := _key_actions[i]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.keycode = keys[i]
			InputMap.action_add_event(action, ev)
