# character_window.gd
class_name CharacterWindow
extends CanvasLayer

signal equipment_changed(slot_type: ItemData.ArmorSlot, item: InventoryItem)
signal slot_clicked(slot: EquipmentSlot)

const EquipmentSlotScene = preload("res://scenes/Player/equipment_slot.tscn")

@onready var panel: PanelContainer = $PanelContainer
@onready var close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/Header/CloseButton
@onready var slots_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/SlotsContainer

## Iconos de fondo para cada slot (configurables desde el inspector)
@export_group("Slot Background Icons")
@export var icon_head: Texture2D
@export var icon_chest: Texture2D
@export var icon_hands: Texture2D
@export var icon_legs: Texture2D
@export var icon_feet: Texture2D
@export var icon_main_hand: Texture2D
@export var icon_off_hand: Texture2D
@export var icon_tool: Texture2D

var equipment_slots: Dictionary = {}


func _ready() -> void:
	_apply_panel_style()
	close_button.pressed.connect(close)
	visible = false
	_create_slots()


func _apply_panel_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.3, 1)
	panel.add_theme_stylebox_override("panel", style)


func _create_slots() -> void:
	# Limpiar contenedor
	for child in slots_container.get_children():
		child.queue_free()
	
	# Row 1: HEAD (centrado)
	var row1 = _create_row()
	_add_spacer(row1)
	_add_slot(row1, ItemData.ArmorSlot.HEAD, icon_head)
	_add_spacer(row1)
	slots_container.add_child(row1)
	
	# Row 2: OFF_HAND - CHEST - MAIN_HAND
	var row2 = _create_row()
	_add_slot(row2, ItemData.ArmorSlot.OFFHAND, icon_off_hand)
	_add_slot(row2, ItemData.ArmorSlot.CHEST, icon_chest)
	_add_slot(row2, ItemData.ArmorSlot.RIGHT_HAND, icon_main_hand)
	slots_container.add_child(row2)
	
	# Row 3: HANDS (centrado)
	var row3 = _create_row()
	_add_spacer(row3)
	_add_slot(row3, ItemData.ArmorSlot.HANDS, icon_hands)
	_add_spacer(row3)
	slots_container.add_child(row3)
	
	# Row 4: LEGS (centrado)
	var row4 = _create_row()
	_add_spacer(row4)
	_add_slot(row4, ItemData.ArmorSlot.LEGS, icon_legs)
	_add_spacer(row4)
	slots_container.add_child(row4)
	
	# Row 5: TOOL - FEET - (spacer)
	var row5 = _create_row()
	_add_slot(row5, ItemData.ArmorSlot.LEFT_HAND, icon_tool)
	_add_slot(row5, ItemData.ArmorSlot.FEET, icon_feet)
	_add_spacer(row5)
	slots_container.add_child(row5)


func _create_row() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	return row


func _add_slot(parent: HBoxContainer, slot_type: ItemData.ArmorSlot, icon: Texture2D) -> void:
	var slot = EquipmentSlotScene.instantiate() as EquipmentSlot
	slot.slot_type = slot_type
	slot.background_icon = icon
	slot.slot_clicked.connect(_on_slot_clicked)
	parent.add_child(slot)
	equipment_slots[slot_type] = slot


func _add_spacer(parent: HBoxContainer) -> void:
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(64, 64)
	parent.add_child(spacer)


func _on_slot_clicked(slot: EquipmentSlot, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(slot)


## Equipa un item en un slot. Devuelve el item que había equipado (o null)
func equip_item(slot: EquipmentSlot, item: InventoryItem) -> InventoryItem:
	if not slot or not item:
		return null
	if slot.slot_type != item.data.armor_slot:
		return item
	var old_item: InventoryItem = null

	if slot.has_item():
		old_item = slot.equipped_item
		equipment_changed.emit(slot.slot_type, old_item, false)
	
	var equip_item = InventoryItem.new(item.data, 1)
	slot.set_item(equip_item)
	equipment_changed.emit(slot.slot_type, equip_item, true)
	
	return old_item


## Desequipa el item de un slot. Devuelve el item desequipado (o null)
func unequip_item(slot: EquipmentSlot) -> InventoryItem:
	if not slot or not slot.has_item():
		return null
	
	var item = slot.equipped_item
	slot.clear()
	equipment_changed.emit(slot.slot_type, item, false)
	
	return item


func get_slot(slot_type: String) -> EquipmentSlot:
	return equipment_slots.get(slot_type)


func get_equipped_item(slot_type: String) -> InventoryItem:
	var slot = get_slot(slot_type)
	if slot:
		return slot.equipped_item
	return null


func toggle() -> void:
	visible = !visible
	if visible:
		open()
	else:
		close()


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
