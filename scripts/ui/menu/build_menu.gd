class_name BuildMenu
extends CanvasLayer

signal block_picked(item_data: ItemData)

const COLUMNS := 5

@onready var panel: PanelContainer
@onready var scroll: ScrollContainer
@onready var content_vbox: VBoxContainer
@onready var title_label: Label

var hotbar: Hotbar
var building_system: BuildingSystem
var _floating_data: ItemData = null
var _floating_display: Control = null
var _floating_icon: TextureRect = null
var _floating_label: Label = null


func _ready() -> void:
	layer = 10
	_build_ui()
	_create_floating_display()
	visible = false


func setup(hbar: Hotbar, bsys: BuildingSystem) -> void:
	hotbar = hbar
	building_system = bsys
	hotbar.hotbar_slot_clicked.connect(_on_hotbar_slot_clicked)
	_populate_blocks()
	# Al arrancar los items ya existen pero sus iconos aún se están renderizando: se repuebla
	# cuando terminen para no enseñar una rejilla de huecos vacíos.
	if not BlockDatabase.are_materials_ready():
		BlockDatabase.materials_ready.connect(_populate_blocks)


func toggle() -> void:
	visible = !visible
	if visible:
		_populate_blocks()
	else:
		_cancel_floating()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.30, 0.20, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(760, 600)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	margin.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	title_label = Label.new()
	title_label.text = "Build Menu"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(toggle)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	outer_vbox.add_child(sep)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 500)
	outer_vbox.add_child(scroll)

	content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_vbox)


func _populate_blocks() -> void:
	for child in content_vbox.get_children():
		child.queue_free()

	if not building_system:
		return

	var grouped := BlockDatabase.get_block_items_by_material()

	for mat_id in grouped:
		var group: Dictionary = grouped[mat_id]
		var items: Array = group["items"]
		if items.is_empty():
			continue

		var mat_label := Label.new()
		mat_label.text = group["display_name"]
		mat_label.add_theme_font_size_override("font_size", 28)
		mat_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1.0))
		mat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_vbox.add_child(mat_label)

		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_vbox.add_child(grid)

		for item_data in items:
			grid.add_child(_create_block_slot(item_data))

		var sep := HSeparator.new()
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_vbox.add_child(sep)


func _create_block_slot(item_data: ItemData) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(128, 128)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.4, 0.9)
	slot.add_theme_stylebox_override("panel", style)

	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_%s" % side, 8)
	slot.add_child(m)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(vb)

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.custom_minimum_size = Vector2(96, 96)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item_data.icon:
		icon.texture = item_data.icon
	vb.add_child(icon)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = item_data.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	vb.add_child(label)

	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_block_slot_input.bind(item_data))
	slot.tooltip_text = "%s\n%s" % [item_data.display_name, item_data.description]
	return slot


func _on_block_slot_input(event: InputEvent, item_data: ItemData) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_floating_data = item_data
		_update_floating_display()
		block_picked.emit(item_data)


func _on_hotbar_slot_clicked(slot_index: int) -> void:
	if not visible or not _floating_data:
		return
	hotbar.assign_to_slot(slot_index, _floating_data)
	_cancel_floating()



func _create_floating_display() -> void:
	var fl := CanvasLayer.new()
	fl.layer = 101
	add_child(fl)

	_floating_display = Control.new()
	_floating_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floating_display.visible = false
	fl.add_child(_floating_display)

	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.22, 0.15, 0.9)
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.border_color = Color(0.8, 0.65, 0.2, 1.0)
	pc.add_theme_stylebox_override("panel", style)
	_floating_display.add_child(pc)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_%s" % side, 8)
	pc.add_child(m)

	var vb := VBoxContainer.new()
	m.add_child(vb)

	_floating_icon = TextureRect.new()
	_floating_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_floating_icon.custom_minimum_size = Vector2(96, 96)
	_floating_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vb.add_child(_floating_icon)

	_floating_label = Label.new()
	_floating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_label.add_theme_font_size_override("font_size", 14)
	vb.add_child(_floating_label)


func _update_floating_display() -> void:
	if not _floating_data:
		return
	_floating_icon.texture = _floating_data.icon
	_floating_label.text = _floating_data.display_name
	_floating_display.visible = true


func _cancel_floating() -> void:
	_floating_data = null
	if _floating_display:
		_floating_display.visible = false


func _process(_delta: float) -> void:
	if _floating_display and _floating_display.visible:
		_floating_display.global_position = get_viewport().get_mouse_position() + Vector2(10, 10)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()
