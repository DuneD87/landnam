class_name SavesScreen
extends CanvasLayer

## Pantalla de partidas: las guardadas, la más reciente primero, con su fecha, personaje y nota, para
## cargarlas, protegerlas o borrarlas; en partida, además, guardar con un nombre nuevo o encima de una.
## Se abre desde el menú principal (en partida, el de pausa). Cargar lo hace el menú, con su fundido:
## aquí solo se pide (load_requested). Borrar y sobrescribir piden una segunda pulsación.

signal load_requested(slot: String)
signal closed

static var _open_count := 0

## En partida, abre con el cursor en el nombre (Guardar sin partida en juego, o en una protegida).
var focus_name := false

var _ui_scale := 1.0
var _built_size := Vector2.ZERO
var _root: Control
var _name_field: LineEdit
var _note_field: LineEdit
var _notice: Label
var _save_button: Button
var _busy := false
## Acción pendiente de confirmar: "delete:<slot>" u "overwrite:<slot>".
var _armed := ""


static func is_open() -> bool:
	return _open_count > 0


func _enter_tree() -> void:
	_open_count += 1


func _exit_tree() -> void:
	_open_count -= 1


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _playing() -> bool:
	return GameManager.current_state == GameManager.State.PLAYING


# --- Estructura ---------------------------------------------------------------------------------

func _build() -> void:
	_built_size = get_viewport().get_visible_rect().size
	_ui_scale = clampf(_built_size.y / 1440.0, 0.5, 2.0)
	var typed_name := _name_field.text if _name_field != null else ""
	var typed_note := _note_field.text if _note_field != null else ""
	if _root != null:
		_root.queue_free()
	_name_field = null
	_note_field = null
	_save_button = null
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameTheme.build(_ui_scale)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(_px(1500), _built_size.x - _px(64)),
		minf(_px(1200), _built_size.y - _px(64)))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(_px(18)))
	panel.add_child(column)
	var title := Label.new()
	title.text = "SAVES_TITLE"
	title.theme_type_variation = "TitleLabel"
	column.add_child(title)
	column.add_child(HSeparator.new())
	if _playing():
		column.add_child(_build_save_row(typed_name, typed_note))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", roundi(_px(10)))
	scroll.add_child(list)
	var saves := SaveSlots.list()
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "SAVES_EMPTY"
		empty.theme_type_variation = "HintLabel"
		list.add_child(empty)
	for meta in saves:
		list.add_child(_build_row(meta))

	var previous_notice := _notice.text if _notice != null else ""
	_notice = Label.new()
	_notice.theme_type_variation = "ValueLabel"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.text = previous_notice
	column.add_child(_notice)

	var footer := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var close := Button.new()
	close.text = "UI_CLOSE"
	close.custom_minimum_size = Vector2(_px(240), _px(68))
	close.pressed.connect(_close)
	footer.add_child(close)
	column.add_child(footer)

	if _name_field != null and focus_name:
		focus_name = false
		_name_field.grab_focus.call_deferred()


## Nombre, nota y Guardar. El nombre arranca con el de la partida en juego.
func _build_save_row(typed_name: String, typed_note: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_px(12)))
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "SAVES_NAME_PLACEHOLDER"
	_name_field.max_length = SaveSlots.MAX_NAME
	_name_field.text = typed_name if typed_name != "" else GameManager.current_slot
	_name_field.custom_minimum_size = Vector2(_px(420), _px(64))
	_name_field.text_changed.connect(func(_t: String) -> void: _disarm())
	_name_field.text_submitted.connect(func(_t: String) -> void: _on_save_pressed())
	row.add_child(_name_field)
	_note_field = LineEdit.new()
	_note_field.placeholder_text = "SAVES_NOTE_PLACEHOLDER"
	_note_field.text = typed_note
	_note_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_field.custom_minimum_size.y = _px(64)
	_note_field.text_submitted.connect(func(_t: String) -> void: _on_save_pressed())
	row.add_child(_note_field)
	_save_button = Button.new()
	_save_button.text = "SAVES_CONFIRM" if _armed == "overwrite:" + SaveSlots.sanitize(_name_field.text) else "SAVES_SAVE"
	_save_button.theme_type_variation = "AccentButton"
	_save_button.custom_minimum_size = Vector2(_px(220), _px(64))
	_save_button.disabled = _busy
	_save_button.pressed.connect(_on_save_pressed)
	row.add_child(_save_button)
	return row


## Una partida: nombre, fecha · personaje · estado, su nota y los botones.
func _build_row(meta: Dictionary) -> Control:
	var slot: String = meta.slot
	var protected := bool(meta.get("protected", false))
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_px(10)))
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var name_label := Label.new()
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.text = slot
	name_label.theme_type_variation = "CardTitle"
	info.add_child(name_label)
	var details := PackedStringArray([str(meta.get("timestamp", "")).replace("T", " ").left(16)])
	if str(meta.get("character", "")) != "":
		details.append(str(meta.character))
	if slot == GameManager.current_slot and _playing():
		details.append(tr("SAVES_CURRENT"))
	if protected:
		details.append(tr("SAVES_PROTECTED"))
	var detail_label := Label.new()
	detail_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	detail_label.text = " · ".join(details)
	detail_label.theme_type_variation = "StatLabel"
	info.add_child(detail_label)
	var note := str(meta.get("note", ""))
	if note != "":
		var note_label := Label.new()
		note_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		note_label.text = note
		note_label.theme_type_variation = "HintLabel"
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(note_label)

	var load_button := _row_button("SAVES_LOAD", row, func() -> void: _on_load(slot))
	load_button.theme_type_variation = "AccentButton"
	if _playing():
		var overwrite := _row_button("SAVES_CONFIRM" if _armed == "overwrite:" + slot else "SAVES_OVERWRITE", row,
			func() -> void: _on_overwrite(slot))
		overwrite.disabled = _busy or protected
	_row_button("SAVES_UNPROTECT" if protected else "SAVES_PROTECT", row,
		func() -> void: _on_protect(slot, not protected))
	var delete := _row_button("SAVES_CONFIRM" if _armed == "delete:" + slot else "SAVES_DELETE", row,
		func() -> void: _on_delete(slot))
	delete.disabled = _busy or protected
	return card


func _row_button(text: String, row: HBoxContainer, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(_px(190), _px(60))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = _busy
	button.pressed.connect(action)
	row.add_child(button)
	return button


# --- Acciones -----------------------------------------------------------------------------------

func _on_save_pressed() -> void:
	if _busy or _name_field == null:
		return
	var slot := SaveSlots.sanitize(_name_field.text)
	if slot == "":
		_say(tr("SAVES_BAD_NAME"))
		return
	if SaveSlots.is_protected(slot):
		_say(tr("SAVES_IS_PROTECTED") % slot)
		return
	# Encima de otra partida (que no sea la que está en juego), segunda pulsación.
	if SaveSlots.exists(slot) and slot != GameManager.current_slot and _armed != "overwrite:" + slot:
		_armed = "overwrite:" + slot
		_build()
		return
	_save(slot, _note_field.text.strip_edges())


func _on_overwrite(slot: String) -> void:
	if _armed != "overwrite:" + slot:
		_armed = "overwrite:" + slot
		_build()
		return
	_save(slot, _note_field.text.strip_edges() if _note_field != null else "")


func _save(slot: String, note: String) -> void:
	_armed = ""
	_busy = true
	_say(tr("SAVES_SAVING"))
	_build()
	var ok: bool = await GameManager.save_game(slot, note)
	_busy = false
	if not is_inside_tree():
		return
	if ok and _note_field != null:
		_note_field.text = ""
	_say(tr("SAVES_SAVED") % slot if ok else tr("SAVES_SAVE_FAILED") % slot)
	if _name_field != null:
		_name_field.text = slot
	_build()


func _on_load(slot: String) -> void:
	if _busy:
		return
	load_requested.emit(slot)
	_close()


func _on_protect(slot: String, on: bool) -> void:
	_armed = ""
	SaveSlots.set_protected(slot, on)
	_build()


func _on_delete(slot: String) -> void:
	if _armed != "delete:" + slot:
		_armed = "delete:" + slot
		_build()
		return
	_armed = ""
	if GameManager.delete_save(slot):
		_say(tr("SAVES_DELETED") % slot)
	_build()


## Al cambiar el nombre, la confirmación de sobrescribir pendiente ya no vale.
func _disarm() -> void:
	if _armed.begins_with("overwrite:"):
		_armed = ""
		if _save_button != null:
			_save_button.text = "SAVES_SAVE"


func _say(text: String) -> void:
	if _notice != null:
		_notice.text = text


func _close() -> void:
	if _busy:
		return
	set_process_input(false)
	closed.emit()
	# Al final del frame: hasta entonces is_open() sigue siendo cierto y el Escape que la cierra no
	# llega al menú de debajo.
	queue_free()


# --- Aspecto ------------------------------------------------------------------------------------

func _on_viewport_resized() -> void:
	if get_viewport().get_visible_rect().size != _built_size:
		_build.call_deferred()


func _px(value: float) -> float:
	return value * _ui_scale
