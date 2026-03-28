# hotbar.gd
class_name Hotbar
extends CanvasLayer

## Emitido al cambiar de slot. Proporciona el ItemData anterior y el nuevo (pueden ser null).
signal selection_changed(old_data: ItemData, new_data: ItemData)
## Emitido cuando se hace click en un slot (para que InventoryUI pueda asignar el floating item)
signal hotbar_slot_clicked(slot_index: int)

const HOTBAR_SLOTS := 10
const HotbarSlotScene = preload("res://scenes/ui/hotbar_slot.tscn")

@onready var slot_container: HBoxContainer = $BottomAnchor/PanelContainer/MarginContainer/HBoxContainer

var slots: Array[HotbarSlot] = []
var selected_index: int = -1
var is_ctrl_hold: bool = false

var _key_actions: Array[StringName] = [
	&"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4", &"hotbar_5",
	&"hotbar_6", &"hotbar_7", &"hotbar_8", &"hotbar_9", &"hotbar_0",
]


func _ready() -> void:
	_ensure_input_actions()
	_create_slots()

func _process(delta: float) -> void:
	if Input.is_action_pressed("left_ctrl"):
		is_ctrl_hold = true
	else:
		is_ctrl_hold = false
		
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


## Asigna un ItemData a un slot del hotbar (solo referencia)
func assign_to_slot(index: int, item_data: ItemData) -> void:
	if index < 0 or index >= HOTBAR_SLOTS:
		return
	# Si ya estaba asignado en otro slot, limpiar el anterior
	for i in HOTBAR_SLOTS:
		if slots[i].assigned_data and item_data and slots[i].assigned_data.id == item_data.id:
			slots[i].clear()
			
	var old_data: ItemData = slots[selected_index].assigned_data if index == selected_index else null
	slots[index].assign(item_data)
	
	if index == selected_index:
		selection_changed.emit(old_data, item_data)
		
func clear_slot(index: int) -> void:
	if index >= 0 and index < HOTBAR_SLOTS:
		if index == selected_index:
			slots[index].set_selected(false)
			selection_changed.emit(slots[index].assigned_data, null)
			selected_index = -1
		slots[index].clear()


func get_selected_data() -> ItemData:
	if selected_index < 0:
		return null
	return slots[selected_index].assigned_data


func select_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SLOTS:
		return
	if not slots[index].assigned_data:
		return

	var old_data: ItemData = slots[selected_index].assigned_data if selected_index >= 0 else null

	if index == selected_index:
		slots[selected_index].set_selected(false)
		selected_index = -1
		selection_changed.emit(old_data, null)
		return

	if selected_index >= 0:
		slots[selected_index].set_selected(false)
	selected_index = index
	slots[selected_index].set_selected(true)
	selection_changed.emit(old_data, slots[selected_index].assigned_data)


func _on_slot_clicked(slot: HotbarSlot, _button_index: int) -> void:
	hotbar_slot_clicked.emit(slot.slot_index)


func _input(event: InputEvent) -> void:
	for i in HOTBAR_SLOTS:
		if event.is_action_pressed(_key_actions[i]):
			select_slot(i)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed and is_ctrl_hold:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot(posmod(selected_index - 1, HOTBAR_SLOTS))
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot(posmod(selected_index + 1, HOTBAR_SLOTS))
			get_viewport().set_input_as_handled()


func _ensure_input_actions() -> void:
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	for i in HOTBAR_SLOTS:
		var action := _key_actions[i]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.keycode = keys[i]
			InputMap.action_add_event(action, ev)


## Para save/load: devuelve array de item IDs (o "" si vacío)
func get_save_data() -> Array:
	var result: Array = []
	for slot in slots:
		result.append(str(slot.assigned_data.id) if slot.assigned_data else "")
	return result


## Para save/load: restaura asignaciones desde array de IDs
func restore_save_data(data: Array, config: Object) -> void:
	for i in mini(data.size(), HOTBAR_SLOTS):
		if data[i] != "":
			var item_data: ItemData = config.get_item(StringName(data[i]))
			if item_data:
				slots[i].assign(item_data)
		else:
			slots[i].clear()
