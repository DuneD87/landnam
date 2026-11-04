class_name DoorBuildPanel
extends HBoxContainer

## Puertas y trampillas de madera del menú de bloques, a medida como la vela: el ancho y el alto del
## hueco que cierran, en bloques (DoorDesign), con su vista (DoorMesh, que se gira arrastrando) y lo
## que cuestan al tamaño de celda de ahora. «Construir» la deja en el martillo
## (BuildingSystem.pick_door).
signal piece_picked()

var building_system: BuildingSystem
var inventory: Inventory
var _kind := DoorDesign.DOOR
## Las medidas de cada una, para no perderlas al cambiar de pestaña.
var _designs := {}
var _syncing := false
var _types: Array[Button] = []
var _fields: Array[SpinBox] = []
var _field_labels: Array[Label] = []
var _description: Label
var _summary: Label
var _cost: Label
var _reason: Label
var _use: Button
var _viewport: SubViewport
var _view: SubViewportContainer
var _holder: Node3D
var _mesh: MeshInstance3D
var _camera: Camera3D
var _controls: VBoxContainer
var _yaw := 0.5
var _pitch := 0.25
var _zoom := 1.0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_build_stage()
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_render())


func configure(bsys: BuildingSystem, inv: Inventory) -> void:
	building_system = bsys
	inventory = inv
	for kind in DoorDesign.KINDS:
		if not _designs.has(kind):
			_designs[kind] = DoorDesign.normalize({}, kind)
	if bsys.is_door_mode():
		_kind = bsys.selected_placeable.id
		_designs[_kind] = DoorDesign.normalize(bsys.door_design, _kind)
	_refresh()


func refresh() -> void:
	if building_system:
		_refresh()


func apply_scale(scale_factor: float) -> void:
	_controls.custom_minimum_size.x = 440.0 * scale_factor
	_view.custom_minimum_size = Vector2(300, 280) * scale_factor
	for field in _fields:
		field.custom_minimum_size.x = 180.0 * scale_factor


func _build_ui() -> void:
	var visual := VBoxContainer.new()
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(visual)
	visual.add_child(_label("DOOR_PREVIEW", &"SectionLabel"))
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.gui_input.connect(_view_input)
	_view.resized.connect(func() -> void:
		if building_system:
			_update_camera())
	visual.add_child(_view)
	var orbit_hint := _label("NAVAL_ORBIT_HINT", &"HintLabel")
	orbit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visual.add_child(orbit_hint)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	add_child(panel)
	_controls = VBoxContainer.new()
	panel.add_child(_controls)
	_controls.add_child(_label("DOOR_BUILD_TITLE", &"CardTitle"))
	var types := HBoxContainer.new()
	var group := ButtonGroup.new()
	for kind in DoorDesign.KINDS:
		var button := Button.new()
		button.text = ItemCatalog.get_item(kind).display_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"TabButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_kind = kind
			_refresh())
		types.add_child(button)
		_types.append(button)
	_controls.add_child(types)
	_description = _label("", &"StatLabel")
	_controls.add_child(_description)
	_controls.add_child(HSeparator.new())
	var fields := GridContainer.new()
	fields.columns = 2
	for axis in 2:
		var label := _label("", &"StatLabel")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fields.add_child(label)
		_field_labels.append(label)
		var field := SpinBox.new()
		field.step = 1.0
		field.rounded = true
		field.min_value = DoorDesign.MIN_SIZE[axis]
		field.max_value = DoorDesign.MAX_SIZE[axis]
		field.suffix = tr("DOOR_BLOCKS")
		field.value_changed.connect(func(value: float) -> void:
			if not _syncing:
				_designs[_kind][["width", "height"][axis]] = roundi(value)
				_refresh())
		fields.add_child(field)
		_fields.append(field)
	_controls.add_child(fields)
	_summary = _label("", &"StatLabel")
	_controls.add_child(_summary)
	_cost = _label("", &"ValueLabel")
	_controls.add_child(_cost)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls.add_child(spacer)
	_controls.add_child(_label("DOOR_BUILD_HINT", &"HintLabel"))
	_reason = _label("", &"WorseLabel")
	_controls.add_child(_reason)
	_use = Button.new()
	_use.theme_type_variation = &"AccentButton"
	_use.pressed.connect(_pick)
	_controls.add_child(_use)


func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(640, 640)
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.add_child(_viewport)
	var stage := Node3D.new()
	_viewport.add_child(stage)
	IconStudio.light(stage, IconStudio.BLOCK_EXPOSURE, IconStudio.BLOCK_FILL)
	_holder = Node3D.new()
	stage.add_child(_holder)
	_mesh = MeshInstance3D.new()
	_holder.add_child(_mesh)
	_camera = IconStudio.make_camera(4.0)
	stage.add_child(_camera)
	_camera.current = true


func _refresh() -> void:
	_syncing = true
	var door := _kind == DoorDesign.DOOR
	var design: Dictionary = DoorDesign.normalize(_designs.get(_kind, {}), _kind)
	_designs[_kind] = design
	var size := DoorDesign.cells(design)
	for kind in _types.size():
		_types[kind].set_pressed_no_signal(DoorDesign.KINDS[kind] == _kind)
	_field_labels[0].text = "DOOR_WIDTH"
	_field_labels[1].text = "DOOR_HEIGHT" if door else "DOOR_LENGTH"
	_fields[0].value = size.x
	_fields[1].value = size.y
	_description.text = "DOOR_DESCRIPTION" if door else "TRAPDOOR_DESCRIPTION"
	_use.text = "DOOR_BUILD_USE" if door else "TRAPDOOR_BUILD_USE"
	_syncing = false

	var cell := building_system.cell_size
	_mesh.mesh = DoorMesh.make(size)
	_mesh.scale = Vector3.ONE * cell
	_mesh.position = Vector3(0.0, -size.y * cell * 0.5, 0.0)
	_summary.text = tr("DOOR_SUMMARY") % [ItemTrait.number(size.x * cell), ItemTrait.number(size.y * cell),
		ItemTrait.number(cell)]
	var cost := DoorDesign.cost(design, cell)
	var lines: Array[String] = []
	for row: Array in BuildCost.rows(cost, inventory):
		lines.append(tr("SAIL_MATERIAL_LINE") % [row[0].get_display_name(), row[1], row[2]])
	_cost.text = tr("BUILD_MENU_FREE") if BuildingSystem.free_build else "\n".join(lines)
	var missing := BuildCost.missing(cost, inventory)
	_reason.text = tr("BUILD_MENU_MISSING") % BuildCost.describe(missing)
	_reason.visible = inventory != null and not BuildingSystem.free_build and not missing.is_empty()
	_update_camera()


func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.008, -1.45, 1.45)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(0.5, _zoom - 0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(2.0, _zoom + 0.1)
		_update_camera()


func _update_camera() -> void:
	_holder.basis = Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.UP, _yaw)
	var size := DoorDesign.cells(_designs.get(_kind, {}))
	var dimensions := Vector3(size.x, size.y, 0.2) * building_system.cell_size
	var bounds: AABB = Transform3D(_holder.basis, Vector3.ZERO) * AABB(-dimensions * 0.5, dimensions)
	var aspect := maxf(0.1, _view.size.x / maxf(1.0, _view.size.y))
	_camera.size = maxf(bounds.size.y, bounds.size.x / aspect) * 1.25 * _zoom
	_camera.position.z = maxf(4.0, bounds.size.length() * 1.5)
	_camera.far = maxf(100.0, _camera.position.z * 3.0)
	_render()


func _render() -> void:
	if _viewport and DisplayServer.get_name() != "headless":
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _pick() -> void:
	building_system.pick_door(_kind, _designs[_kind])
	piece_picked.emit()


func _label(key: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = key
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
