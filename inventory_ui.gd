extends CanvasLayer
class_name InventoryUI

const SlotScene = preload("res://scenes/inventory/inventory_slot.tscn")

@onready var panel: PanelContainer = $CenterContainer/PanelContainer
@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Header/TitleLabel
@onready var close_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Header/CloseButton
@onready var slot_grid: GridContainer = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SlotGrid

var inventory: Inventory
var slots: Array[InventorySlot] = []

func _ready() -> void:
	_apply_panel_style()
	close_button.pressed.connect(close)
	slot_grid.columns = 5
	visible = false

func _apply_panel_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.3, 1)
	panel.add_theme_stylebox_override("panel", style)

func setup(inv: Inventory) -> void:
	inventory = inv
	inventory.inventory_changed.connect(_refresh)
	_create_slots()
	_refresh()

func _create_slots() -> void:
	# Limpiar slots existentes
	for slot in slots:
		slot.queue_free()
	slots.clear()
	
	# Crear nuevos slots
	for i in range(inventory.max_slots):
		var slot = SlotScene.instantiate()
		slot_grid.add_child(slot)
		slots.append(slot)

func _refresh() -> void:
	if not inventory:
		return
	
	var items = inventory.get_all_items()
	title_label.text = "Inventario (%d/%d)" % [items.size(), inventory.max_slots]
	
	for i in range(slots.size()):
		if i < items.size():
			slots[i].set_item(items[i])
		else:
			slots[i].clear()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
	elif event.is_action_pressed("ui_cancel") and visible:
		close()

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
	visible = false
