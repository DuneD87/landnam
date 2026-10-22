class_name RestController
extends CanvasLayer

## Descanso en un lecho: ocho horas del mundo a ritmo acelerado, interrumpibles por el jugador,
## daño, muerte, agua, alejarse, abrir otro modo o retirar el lecho. El sueño no se guarda.
const SLEEP_SPEED := 60.0

var _player: PlayerController
var _bed: Bedroll
var _sleeping := false
var _hours := 0.0
var _model_transform := Transform3D.IDENTITY
var _animation_active := false
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _root: Control
var _margin: MarginContainer
var _box: VBoxContainer
var _panel: PanelContainer
var _title: Label
var _detail: Label
var _progress: ProgressBar
var _sleep_button: Button
var _pickup_button: Button
var _close_button: Button


func _ready() -> void:
	layer = 14
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func setup(player: PlayerController) -> void:
	_player = player
	_player.health_component.damaged.connect(_on_damaged)
	_player.health_component.died.connect(close)
	GameManager.state_changed.connect(_on_state_changed)


func is_sleeping() -> bool:
	return _sleeping


func is_open() -> bool:
	return visible


func open(bed: Bedroll) -> void:
	if bed == null or not is_instance_valid(bed):
		return
	_bed = bed
	_previous_mouse_mode = Input.get_mouse_mode()
	_layout()
	visible = true
	_player.capture_mouse(false)
	_refresh()


func start_sleep() -> bool:
	if _sleeping:
		return true
	var reason := _cannot_sleep()
	if reason != "":
		_detail.text = tr(reason)
		return false
	_sleeping = true
	_hours = 0.0
	_player.needs.sleeping = true
	_player.velocity = Vector3.ZERO
	_player.movement.velocity = Vector3.ZERO
	if _player.player_model != null:
		_model_transform = _player.player_model.transform
		_player.player_model.global_transform = _bed.global_transform * Transform3D(
			Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.2, -0.85))
	if _player.animator_tree != null:
		_animation_active = _player.animator_tree.active
		_player.animator_tree.active = false
	WorldTime.request_speed(self, SLEEP_SPEED)
	_refresh()
	return true


func close(capture_mouse := true) -> void:
	var was_open := visible
	if _sleeping:
		_sleeping = false
		if is_instance_valid(_player):
			if is_instance_valid(_player.needs):
				_player.needs.sleeping = false
			if is_instance_valid(_player.player_model):
				_player.player_model.transform = _model_transform
			if is_instance_valid(_player.animator_tree):
				_player.animator_tree.active = _animation_active
	WorldTime.release_speed(self)
	visible = false
	_bed = null
	if was_open and capture_mouse and is_instance_valid(_player):
		_player.capture_mouse(_previous_mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _exit_tree() -> void:
	close(false)


func _physics_process(delta: float) -> void:
	if not visible or _player == null:
		return
	if not is_instance_valid(_bed) or _bed.is_queued_for_deletion() \
			or _player.global_position.distance_to(_bed.global_position) > Bedroll.REACH \
			or _player.health_component.is_dead or _player.free_flight_enabled or not _player.visible:
		close()
		return
	if _sleeping:
		if _player.movement.is_swimming or _player.needs.paused or not _player.input_enabled \
				or not WorldTime.is_clock_running():
			close()
			return
		_hours += WorldTime.hours_elapsed(delta)
		if _hours >= SurvivalNeeds.SLEEP_HOURS:
			close()
			return
	_refresh()


func _cannot_sleep() -> String:
	if not is_instance_valid(_bed) or _bed.is_queued_for_deletion() \
			or _player.global_position.distance_to(_bed.global_position) > Bedroll.REACH:
		return "SLEEP_TOO_FAR"
	if not WorldTime.is_clock_running():
		return "SLEEP_CLOCK_STOPPED"
	if _player.health_component.is_dead or _player.free_flight_enabled or _player.needs.paused \
			or _player.movement.is_swimming or not _player.is_on_floor() \
			or (_player.combat != null and _player.combat.is_busy()) \
			or (_player.climb != null and _player.climb.is_active()):
		return "SLEEP_UNAVAILABLE"
	return ""


func _pickup() -> void:
	if _sleeping or not is_instance_valid(_bed):
		return
	var data: ItemData = ItemCatalog.get_item(Bedroll.ITEM_ID)
	if _player.inventory.add_item(data, 1) > 0:
		_detail.text = tr("SLEEP_INVENTORY_FULL")
		return
	_bed.remove_from_group(GameManager.SAVEABLE_GROUP)
	_bed.queue_free()
	close()


func _on_damaged(_amount: float, _source: Node) -> void:
	if _sleeping:
		close()
		if _player.hotbar != null:
			_player.hotbar.notify(tr("SLEEP_INTERRUPTED"))


func _on_state_changed(state: GameManager.State) -> void:
	if state != GameManager.State.PLAYING:
		close(false)


func _refresh() -> void:
	_title.text = tr("SLEEP_SLEEPING" if _sleeping else "ITEM_BEDROLL")
	_progress.value = _player.needs.rest * 100.0
	_sleep_button.visible = not _sleeping
	_pickup_button.visible = not _sleeping
	_close_button.text = tr("SLEEP_WAKE" if _sleeping else "UI_CLOSE")
	if _sleeping:
		_detail.text = tr("SLEEP_PROGRESS") % [_hours, SurvivalNeeds.SLEEP_HOURS, WorldTime.speed]
	else:
		var reason := _cannot_sleep()
		_sleep_button.disabled = reason != ""
		_detail.text = tr(reason if reason != "" else "SLEEP_DESCRIPTION")


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.02, 0.015, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"WindowPanel"
	center.add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	_box = VBoxContainer.new()
	_margin.add_child(_box)
	_title = Label.new()
	_title.theme_type_variation = &"SectionLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_title)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_detail)
	var rest_label := Label.new()
	rest_label.text = "NEED_REST"
	_box.add_child(rest_label)
	_progress = ProgressBar.new()
	_box.add_child(_progress)
	_sleep_button = Button.new()
	_sleep_button.text = "SLEEP_START"
	_sleep_button.theme_type_variation = &"AccentButton"
	_sleep_button.pressed.connect(start_sleep)
	_box.add_child(_sleep_button)
	_pickup_button = Button.new()
	_pickup_button.text = "SLEEP_PICKUP"
	_pickup_button.pressed.connect(_pickup)
	_box.add_child(_pickup_button)
	_close_button = Button.new()
	_close_button.pressed.connect(close)
	_box.add_child(_close_button)


func _layout() -> void:
	var ui_scale := GameTheme.scale_for(get_viewport())
	_root.theme = GameTheme.build(ui_scale)
	_panel.custom_minimum_size.x = 480.0 * ui_scale
	_detail.custom_minimum_size = Vector2(420, 90) * ui_scale
	_progress.custom_minimum_size.y = 24.0 * ui_scale
	_box.add_theme_constant_override("separation", roundi(16.0 * ui_scale))
	for side in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, roundi(24.0 * ui_scale))
