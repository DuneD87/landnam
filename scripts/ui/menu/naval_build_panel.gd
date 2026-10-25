class_name NavalBuildPanel
extends HBoxContainer

## Editor del catálogo naval del martillo. La vista usa el mismo mallador que la partida.
signal piece_picked()

var building_system: BuildingSystem
var inventory: Inventory
var _kind := NavalPiece.Kind.BOW
var _size := NavalPiece.DEFAULT_SIZE
var _profile := NavalPiece.Profile.ROUND
var _syncing := false
var _blocks: Dictionary = {}
var _dimensions: Array[SpinBox] = []
var _types: Array[Button] = []
var _profile_option: OptionButton
var _profile_label: Label
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
var _yaw := 0.65
var _pitch := 0.55
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
	_kind = bsys.naval_kind if bsys.is_naval_mode() else NavalPiece.Kind.BOW
	_size = bsys.naval_size
	_profile = bsys.naval_profile
	_refresh()


func refresh() -> void:
	if building_system:
		_refresh()


func apply_scale(scale_factor: float) -> void:
	_controls.custom_minimum_size.x = 440.0 * scale_factor
	_view.custom_minimum_size = Vector2(300, 280) * scale_factor
	for field in _dimensions:
		field.custom_minimum_size.x = 180.0 * scale_factor


func _build_ui() -> void:
	var visual := VBoxContainer.new()
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(visual)
	var title := _label("NAVAL_PREVIEW", &"SectionLabel")
	visual.add_child(title)
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
	_controls.add_child(_label("NAVAL_TITLE", &"CardTitle"))
	var types := HBoxContainer.new()
	var group := ButtonGroup.new()
	for kind in NavalPiece.NAME_KEYS.size():
		var button := Button.new()
		button.text = NavalPiece.NAME_KEYS[kind]
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
	_controls.add_child(_label("NAVAL_DESCRIPTION", &"StatLabel"))
	_controls.add_child(HSeparator.new())
	var fields := GridContainer.new()
	fields.columns = 2
	for axis in 3:
		var label := _label(["NAVAL_WIDTH", "NAVAL_HEIGHT", "NAVAL_LENGTH"][axis], &"StatLabel")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fields.add_child(label)
		var field := SpinBox.new()
		field.suffix = "m"
		field.value_changed.connect(func(value: float) -> void:
			if not _syncing:
				_size[axis] = roundi(value / building_system.cell_size)
				_refresh())
		fields.add_child(field)
		_dimensions.append(field)
	_profile_label = _label("NAVAL_PROFILE", &"StatLabel")
	fields.add_child(_profile_label)
	_profile_option = OptionButton.new()
	_profile_option.add_item(tr("NAVAL_PROFILE_STRAIGHT"))
	_profile_option.add_item(tr("NAVAL_PROFILE_ROUND"))
	_profile_option.item_selected.connect(func(index: int) -> void:
		_profile = index
		_refresh())
	fields.add_child(_profile_option)
	_controls.add_child(fields)
	_summary = _label("", &"StatLabel")
	_controls.add_child(_summary)
	_cost = _label("", &"ValueLabel")
	_controls.add_child(_cost)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls.add_child(spacer)
	var hint := _label("NAVAL_JOIN_HINT", &"HintLabel")
	_controls.add_child(hint)
	_reason = _label("", &"WorseLabel")
	_controls.add_child(_reason)
	_use = Button.new()
	_use.text = "NAVAL_USE"
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
	_camera = IconStudio.make_camera(10.0)
	stage.add_child(_camera)
	_camera.current = true


func _refresh() -> void:
	_syncing = true
	var cell := building_system.cell_size
	for axis in 3:
		_dimensions[axis].min_value = NavalPiece.MIN_SIZE[axis] * cell
		_dimensions[axis].max_value = NavalPiece.MAX_SIZE[axis] * cell
		_dimensions[axis].step = cell
		_dimensions[axis].value = _size[axis] * cell
	for kind in _types.size():
		_types[kind].set_pressed_no_signal(kind == _kind)
	_profile_option.select(_profile)
	_profile_label.visible = _kind == NavalPiece.Kind.BOW
	_profile_option.visible = _kind == NavalPiece.Kind.BOW
	_syncing = false
	_blocks = NavalPiece.generate(_kind, _size, _profile)
	var mat := BlockDatabase.get_material_by_id("wood")
	var mesh := ChunkMeshBuilder.build_mesh(_blocks, cell, Transform3D.IDENTITY, {"wood": mat.surface_material})
	_mesh.mesh = mesh
	_mesh.position = -Vector3(_size) * cell * 0.5
	_summary.text = tr("NAVAL_SUMMARY") % [ItemTrait.number(cell), _blocks.size()]
	var cost := mat.get_cost_for_size(cell) * _blocks.size()
	var have := inventory.get_item_count(mat.item) if inventory else 0
	_cost.text = tr("BUILD_MENU_FREE") if BuildingSystem.free_build else tr("NAVAL_COST") % [cost, have]
	_reason.text = tr("BUILD_MENU_MISSING") % mat.item.get_display_name().to_lower()
	_reason.visible = inventory != null and not BuildingSystem.free_build and have < cost
	_update_camera()


func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.008, -0.8, 1.45)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(0.5, _zoom - 0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(2.0, _zoom + 0.1)
		_update_camera()


func _update_camera() -> void:
	_holder.basis = Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.UP, _yaw)
	var bounds: AABB = Transform3D(_holder.basis, Vector3.ZERO) * AABB(-Vector3(_size) * building_system.cell_size * 0.5, Vector3(_size) * building_system.cell_size)
	var aspect := maxf(0.1, _view.size.x / maxf(1.0, _view.size.y))
	_camera.size = maxf(bounds.size.y, bounds.size.x / aspect) * 1.25 * _zoom
	_camera.position.z = maxf(4.0, bounds.size.length() * 1.5)
	_camera.far = maxf(100.0, _camera.position.z * 3.0)
	_render()


func _render() -> void:
	if _viewport and DisplayServer.get_name() != "headless":
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _pick() -> void:
	var icon: Texture2D
	if DisplayServer.get_name() != "headless":
		var image := _viewport.get_texture().get_image()
		if image and not image.is_empty():
			icon = ImageTexture.create_from_image(image)
	building_system.pick_naval_piece(_kind, _size, _profile, icon)
	piece_picked.emit()


func _label(key: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = key
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
