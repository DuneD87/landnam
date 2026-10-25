class_name BlueprintSitePanel
extends CanvasLayer

## Lo que se ve al apuntar a una obra (BlueprintSite), en Saga, arriba como el panel de colocar: el
## nombre, cuánto lleva hecho, cada material con lo que tiene frente a lo que pide (y lo que se lleva
## encima), qué hacer ahora y los controles.

var _root: Control
var _title: Label
var _bar: ProgressBar
var _percent: Label
var _costs: VBoxContainer
var _state: Label
var _hint: Label
var _signature := ""


func _ready() -> void:
	layer = 9
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 24.0
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	var progress_row := HBoxContainer.new()
	progress_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(progress_row)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_row.add_child(_bar)
	_percent = Label.new()
	_percent.theme_type_variation = &"ValueLabel"
	progress_row.add_child(_percent)
	_costs = VBoxContainer.new()
	_costs.add_theme_constant_override("separation", 4)
	column.add_child(_costs)
	_state = Label.new()
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_state)
	_hint = Label.new()
	_hint.theme_type_variation = &"HintLabel"
	_hint.text = "SITE_HINT"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)


## Enseña la obra [site] frente a [inventory]. [state] es lo que hay que hacer ahora (ya traducido) y
## [ok], si se puede hacer.
func show_site(site: BlueprintSite, inventory: Inventory, state: String, ok: bool) -> void:
	if not visible:
		var ui_scale := GameTheme.scale_for(get_viewport())
		_root.theme = GameTheme.build(ui_scale)
		_hint.custom_minimum_size.x = 640.0 * ui_scale
		_bar.custom_minimum_size.y = 18.0 * ui_scale
		_signature = ""
		visible = true
	var cost := site.get_cost()
	var supplied := site.get_supplied()
	var rows := BuildCost.rows(cost, inventory)
	# Solo se rehace si ha cambiado algo: lo hecho, lo aportado, lo que se lleva o el estado.
	var signature := "%s|%.4f|%s|%s|%s|%s" % [site.get_instance_id(), site.progress(), str(supplied),
		str(rows.map(func(row: Array) -> int: return row[2])), state, BuildingSystem.free_build]
	if signature == _signature:
		return
	_signature = signature
	_title.text = site.blueprint_name if site.blueprint_name != "" else tr("SITE_TITLE")
	_bar.value = site.progress()
	_percent.text = "%d %%" % floori(site.progress() * 100.0)
	for child in _costs.get_children():
		_costs.remove_child(child)
		child.queue_free()
	if BuildingSystem.free_build:
		var free := Label.new()
		free.theme_type_variation = &"StatLabel"
		free.text = "SITE_FREE"
		free.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_costs.add_child(free)
	else:
		for row: Array in rows:
			var data := row[0] as ItemData
			var have := int(supplied.get(data.id, 0))
			var line := HBoxContainer.new()
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			var icon := TextureRect.new()
			icon.texture = data.icon
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(36, 36)
			line.add_child(icon)
			var item_name := Label.new()
			item_name.theme_type_variation = &"StatLabel"
			item_name.text = data.get_display_name()
			line.add_child(item_name)
			var count := Label.new()
			count.theme_type_variation = &"BetterLabel" if have >= row[1] else &"WorseLabel"
			count.text = "%d / %d" % [have, row[1]]
			line.add_child(count)
			if have < row[1]:
				var carried := Label.new()
				carried.theme_type_variation = &"HintLabel"
				carried.text = tr("SITE_CARRIED") % row[2]
				line.add_child(carried)
			_costs.add_child(line)
	_state.text = state
	_state.theme_type_variation = &"BetterLabel" if ok else &"WorseLabel"


func hide_site() -> void:
	visible = false
