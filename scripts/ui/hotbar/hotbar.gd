class_name Hotbar
extends CanvasLayer

signal selection_changed(old_data: ItemData, new_data: ItemData)
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
	# Los iconos de bloque se renderizan uno a uno al arrancar y la tanda dura segundos. assign()
	# copia la textura del item en ese instante y no vuelve a mirarla, así que restaurar una
	# partida a medias dejaba en blanco todo lo que aún no se hubiera renderizado. Repintar solo al
	# final tampoco basta: hay huecos que estrenan icono en mitad de la tanda, así que se repinta
	# con cada uno hasta que están todos.
	if not BlockDatabase.are_materials_ready():
		BlockDatabase.icon_generated.connect(_refresh_slot_icons)
		BlockDatabase.materials_ready.connect(_on_block_icons_ready)


func _on_block_icons_ready() -> void:
	if BlockDatabase.icon_generated.is_connected(_refresh_slot_icons):
		BlockDatabase.icon_generated.disconnect(_refresh_slot_icons)
	_refresh_slot_icons()


func _refresh_slot_icons() -> void:
	for slot in slots:
		slot.refresh_icon()

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


func assign_to_slot(index: int, item_data: ItemData) -> void:
	if index < 0 or index >= HOTBAR_SLOTS:
		return
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


## _unhandled_input (y no _input) para que la GUI tenga prioridad:
## con la consola abierta, su LineEdit consume los números antes de llegar aquí.
func _unhandled_input(event: InputEvent) -> void:
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


func get_save_data() -> Array:
	var result: Array = []
	for slot in slots:
		if not slot.assigned_data:
			result.append(null)
		elif slot.assigned_data.category == ItemData.Category.BLOCK:
			result.append({
				"type": "block",
				"id": str(slot.assigned_data.id),
				"block_id": slot.assigned_data.block_id,
				"build_material_id": slot.assigned_data.build_material_id,
			})
		else:
			result.append({
				"type": "item",
				"id": str(slot.assigned_data.id),
			})
	return result


## Vuelca en la barra los huecos guardados. Cargar puede pasar sobre una partida en curso, así que
## primero se vacía entera: los huecos que el save dejó vacíos tienen que quedar vacíos, y la
## selección se reinicia para que select_slot() no lea el hueco ya elegido como un clic y lo apague.
func restore_save_data(data: Array, config: Object) -> void:
	var previous: ItemData = get_selected_data()
	for i in HOTBAR_SLOTS:
		slots[i].set_selected(false)
		slots[i].clear()
	selected_index = -1
	if previous:
		selection_changed.emit(previous, null)

	for i in mini(data.size(), HOTBAR_SLOTS):
		var value = data[i]
		if value == null:
			continue
		var item_data: ItemData
		if value["type"] == "block":
			var mat_id: String = value.get("build_material_id", "")
			if mat_id != "":
				var items_by_mat := BlockDatabase.get_block_items_by_material()
				if items_by_mat.has(mat_id):
					for item in items_by_mat[mat_id]["items"]:
						if item.block_id == value["block_id"]:
							item_data = item
							break
			if not item_data:
				push_warning("[Hotbar] Sin item para bloque %s de material '%s'; se restaura el bloque genérico." % [value["block_id"], mat_id])
				item_data = BlockDatabase.get_block_item(value["block_id"])
		else:
			item_data = config.get_item(StringName(value["id"]))
		if item_data:
			slots[i].assign(item_data)
		
