class_name GridInspector
extends CanvasLayer

## Visor de grids (comando de consola 'grids'): todas las construcciones del mundo con lo que cuesta
## su física en cada tick, para encontrar las que provocan picos y ver por qué. Una fila por cuerpo
## dinámico (con todas sus grids) o por grupo estático. La elegida enseña el reparto de su tick por
## partes (DynamicGridBody.profile_sections) y se puede marcar en el mundo, ir hasta ella o borrarla.
## No pausa el juego: los costes son los de ahora mismo.

## Cada cuánto (s) se leen los costes y se rehace la lista.
const REFRESH := 0.5
## Ventana (en lecturas) del pico que enseña cada fila: unos 5 s.
const PEAK_SAMPLES := 10
const COLUMNS := ["GRIDS_COL_NAME", "GRIDS_COL_KIND", "GRIDS_COL_BLOCKS", "GRIDS_COL_DIST",
	"GRIDS_COL_AVG", "GRIDS_COL_PEAK", "GRIDS_COL_CONTACTS"]
const MARK_COLOR := Color(1.0, 0.35, 0.1, 0.35)

## {clave de fila: {grids, body, kind, blocks, center, avg_ms, peaks, contacts, sections, forces_ms}}
var _rows: Dictionary = {}
var _selected := ""
var _delete_armed := ""
var _elapsed := 0.0
var _physics_frames := 0
var _process_frames := 0

var _tree: Tree
## Las filas del Tree por clave: se actualizan en su sitio para no perder el scroll ni la selección.
var _items: Dictionary = {}
var _filling := false
var _summary: Label
var _detail: RichTextLabel
var _mark_btn: Button
var _go_btn: Button
var _delete_btn: Button
var _marker: MeshInstance3D
var _player: Node3D
var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _prev_input_enabled := true


func _ready() -> void:
	layer = 120
	_build_ui()
	_player = GameManager.player
	_prev_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if is_instance_valid(_player):
		_prev_input_enabled = _player.input_enabled
		_player.input_enabled = false
	DynamicGridBody.profile_sections = true
	_physics_frames = Engine.get_physics_frames()
	_process_frames = Engine.get_process_frames()
	# La primera lectura descarta lo acumulado antes de abrir.
	for body in get_tree().get_nodes_in_group(DynamicGridBody.GROUP):
		(body as DynamicGridBody).take_cost_sample()
	_refresh()


func close() -> void:
	DynamicGridBody.profile_sections = false
	_clear_marker()
	Input.set_mouse_mode(_prev_mouse_mode)
	if is_instance_valid(_player):
		_player.input_enabled = _prev_input_enabled
	queue_free()


## En _input y no después: el jugador abre la pausa con Escape en su _input. Este nodo es el último
## de la raíz, así que la tecla le llega antes.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH:
		_elapsed = 0.0
		_refresh()


# --------------------------------------------------------------------------------------------
#  Datos
# --------------------------------------------------------------------------------------------

func _refresh() -> void:
	var physics_now := Engine.get_physics_frames()
	var process_now := Engine.get_process_frames()
	var ticks_per_frame := float(physics_now - _physics_frames) / maxf(process_now - _process_frames, 1)
	_physics_frames = physics_now
	_process_frames = process_now

	var seen := {}
	var total_ms := 0.0
	# Cuerpos dinámicos: una fila por cuerpo, aunque no le quede ninguna grid (también se ven).
	for node in get_tree().get_nodes_in_group(DynamicGridBody.GROUP):
		var body := node as DynamicGridBody
		if body == null or body.is_queued_for_deletion():
			continue
		var key := "body_%d" % body.get_instance_id()
		var row: Dictionary = _rows.get(key, {"peaks": []})
		var sample := body.take_cost_sample()
		var ticks := maxi(int(sample.ticks), 1)
		row.body = body
		row.grids = body._grids.map(func(g: GridBase) -> String: return g.grid_id)
		row.kind = "GRIDS_KIND_FROZEN" if body.far_frozen else "GRIDS_KIND_DYNAMIC"
		row.blocks = body.get_block_count()
		row.center = body.get_hull_center_world()
		row.avg_ms = (int(sample.sum) + int(sample.forces)) / 1000.0 / ticks
		row.forces_ms = int(sample.forces) / 1000.0 / ticks
		row.contacts = int(sample.contacts)
		row.sections = sample.sections
		row.ticks = int(sample.ticks)
		row.sleeping = body.sleeping
		row.speed = body.linear_velocity.length()
		row.from_split = body.spawned_from_split
		(row.peaks as Array).append(int(sample.max) / 1000.0)
		if (row.peaks as Array).size() > PEAK_SAMPLES:
			(row.peaks as Array).pop_front()
		total_ms += row.avg_ms
		_rows[key] = row
		seen[key] = true
	# Grupos estáticos: su física es solo colisión en Jolt, sin script por tick.
	var grouped := {}
	for grid: GridBase in GridManager._grids.values():
		if grid is DynamicPlanetGrid or grouped.has(grid.grid_id):
			continue
		var group := GridManager.get_grid_group(grid.grid_id)
		var ids: Array = group.map(func(g: GridBase) -> String: return g.grid_id)
		ids.sort()
		for id in ids:
			grouped[id] = true
		var key := "static_" + String(ids[0])
		var row: Dictionary = _rows.get(key, {"peaks": []})
		var blocks := 0
		var version := 0
		for g: GridBase in group:
			blocks += g.get_block_count()
			version += g.edit_version
		row.body = null
		row.grids = ids
		row.kind = "GRIDS_KIND_STATIC"
		row.blocks = blocks
		# Recorre todos los bloques: solo cuando la construcción cambia, no en cada lectura. Se guarda
		# en el marco del planeta, que sobrevive a los rebases del origen flotante.
		var planet := grid.planet_node
		if row.get("version", -1) != version or not row.has("center_local"):
			var center := _static_center(group)
			row.center_local = planet.to_local(center) if planet != null else center
			row.version = version
		row.center = planet.to_global(row.center_local) if planet != null else row.center_local
		row.avg_ms = -1.0
		row.contacts = -1
		_rows[key] = row
		seen[key] = true
	for key in _rows.keys():
		if not seen.has(key):
			_rows.erase(key)
	if not _rows.has(_selected):
		_selected = ""

	_summary.text = tr("GRIDS_SUMMARY") % [_rows.size(), total_ms, ticks_per_frame, total_ms * ticks_per_frame,
		Engine.get_frames_per_second()]
	_fill_tree()
	_fill_detail()


## Centro de los bloques de un grupo estático (el origen de la grid puede quedar lejos de ellos).
func _static_center(group: Array) -> Vector3:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for grid: GridBase in group:
		for grid_pos: Vector3i in grid.get_all_blocks():
			var p := grid.grid_to_world(grid_pos)
			lo = lo.min(p)
			hi = hi.max(p)
	if lo == Vector3.INF:
		return (group[0] as GridBase).get_origin_world()
	return (lo + hi) * 0.5


func _peak(row: Dictionary) -> float:
	var best := 0.0
	for value: float in row.peaks:
		best = maxf(best, value)
	return best


func _distance(row: Dictionary) -> float:
	return _player.global_position.distance_to(row.center) if is_instance_valid(_player) else 0.0


# --------------------------------------------------------------------------------------------
#  Interfaz
# --------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -1180
	panel.self_modulate = Color(1, 1, 1, 0.94)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = tr("GRIDS_TITLE")
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = tr("GRIDS_CLOSE")
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 22)
	box.add_child(_summary)

	_tree = Tree.new()
	_tree.columns = COLUMNS.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.add_theme_font_size_override("font_size", 20)
	_tree.add_theme_font_size_override("title_button_font_size", 20)
	for i in COLUMNS.size():
		_tree.set_column_title(i, tr(COLUMNS[i]))
		_tree.set_column_expand(i, i == 0)
		if i > 0:
			_tree.set_column_custom_minimum_width(i, 120)
	_tree.item_selected.connect(_on_item_selected)
	box.add_child(_tree)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.custom_minimum_size = Vector2(0, 360)
	_detail.add_theme_font_size_override("normal_font_size", 20)
	box.add_child(_detail)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	_mark_btn = Button.new()
	_mark_btn.pressed.connect(_on_mark)
	actions.add_child(_mark_btn)
	_go_btn = Button.new()
	_go_btn.text = tr("GRIDS_GO")
	_go_btn.pressed.connect(_on_go)
	actions.add_child(_go_btn)
	_delete_btn = Button.new()
	_delete_btn.pressed.connect(_on_delete)
	actions.add_child(_delete_btn)
	_update_buttons()


func _fill_tree() -> void:
	var keys := _rows.keys()
	# Lo más caro arriba; los estáticos (sin coste por tick) al final, por distancia.
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ra: Dictionary = _rows[a]
		var rb: Dictionary = _rows[b]
		if ra.avg_ms != rb.avg_ms:
			return ra.avg_ms > rb.avg_ms
		return _distance(ra) < _distance(rb))
	_filling = true
	var root := _tree.get_root() if _tree.get_root() != null else _tree.create_item()
	for key: String in _items.keys():
		if not _rows.has(key):
			(_items[key] as TreeItem).free()
			_items.erase(key)
	var previous: TreeItem = null
	for key: String in keys:
		var row: Dictionary = _rows[key]
		var item: TreeItem = _items.get(key)
		if item == null:
			item = _tree.create_item(root)
			item.set_metadata(0, key)
			_items[key] = item
		if previous != null:
			item.move_after(previous)
		elif item != root.get_first_child():
			item.move_before(root.get_first_child())
		previous = item
		var name := ", ".join(row.grids) if not (row.grids as Array).is_empty() else tr("GRIDS_NO_GRIDS")
		item.set_text(0, name)
		item.set_text(1, tr(row.kind))
		item.set_text(2, str(row.blocks))
		item.set_text(3, _format_distance(_distance(row)))
		if row.avg_ms >= 0.0:
			item.set_text(4, "%.3f" % row.avg_ms)
			item.set_text(5, "%.2f" % _peak(row))
			item.set_text(6, str(row.contacts))
			var hot: bool = row.avg_ms >= 0.5 or _peak(row) >= 3.0
			for c in COLUMNS.size():
				if hot:
					item.set_custom_color(c, Color(1.0, 0.55, 0.45))
				else:
					item.clear_custom_color(c)
		else:
			for c in [4, 5, 6]:
				item.set_text(c, "—")
		for c in range(2, COLUMNS.size()):
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
	_filling = false


func _format_distance(meters: float) -> String:
	return "%.1f km" % (meters / 1000.0) if meters >= 1000.0 else "%.0f m" % meters


func _fill_detail() -> void:
	_update_buttons()
	if _selected == "":
		_detail.text = "[color=#9aa0a6]%s[/color]" % tr("GRIDS_PICK_HINT")
		return
	var row: Dictionary = _rows[_selected]
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]  ·  %s  ·  %s" % [", ".join(row.grids) if not (row.grids as Array).is_empty()
		else tr("GRIDS_NO_GRIDS"), tr(row.kind), _format_distance(_distance(row))])
	if row.body == null:
		lines.append(tr("GRIDS_STATIC_NOTE") % row.blocks)
		_detail.text = "\n".join(lines)
		return
	lines.append(tr("GRIDS_BODY_STATE") % [row.blocks, row.speed, tr("GRIDS_YES") if row.sleeping else tr("GRIDS_NO"),
		row.contacts, tr("GRIDS_YES") if row.from_split else tr("GRIDS_NO"), row.ticks])
	lines.append(tr("GRIDS_COST_LINE") % [row.avg_ms, _peak(row), row.forces_ms])
	# Reparto del tick: cada parte en ms por tick, de la más cara a la más barata.
	var sections: Dictionary = row.sections
	var ticks := maxi(int(row.ticks), 1)
	var labels := sections.keys()
	labels.sort_custom(func(a, b) -> bool: return sections[a] > sections[b])
	var parts := PackedStringArray()
	var counted := 0
	for label in labels:
		counted += int(sections[label])
		parts.append("%s %.3f" % [label, int(sections[label]) / 1000.0 / ticks])
	var rest: float = row.avg_ms - row.forces_ms - counted / 1000.0 / ticks
	if rest > 0.0005:
		parts.append("%s %.3f" % [tr("GRIDS_OTHER"), rest])
	lines.append(tr("GRIDS_SECTIONS") % (" · ".join(parts) if not parts.is_empty() else "—"))
	_detail.text = "\n".join(lines)


func _update_buttons() -> void:
	var has := _selected != ""
	_mark_btn.disabled = not has
	_go_btn.disabled = not has or not is_instance_valid(_player)
	_delete_btn.disabled = not has
	_mark_btn.text = tr("GRIDS_UNMARK") if is_instance_valid(_marker) else tr("GRIDS_MARK")
	_delete_btn.text = tr("GRIDS_DELETE_CONFIRM") if has and _delete_armed == _selected else tr("GRIDS_DELETE")


func _on_item_selected() -> void:
	if _filling:
		return
	var item := _tree.get_selected()
	_selected = item.get_metadata(0) if item != null else ""
	_delete_armed = ""
	_fill_detail()


# --------------------------------------------------------------------------------------------
#  Acciones
# --------------------------------------------------------------------------------------------

## Una caja translúcida, visible a través del terreno, del tamaño de la construcción. La de un cuerpo
## dinámico va colgada de él y lo sigue.
func _on_mark() -> void:
	if is_instance_valid(_marker):
		_clear_marker()
		_update_buttons()
		return
	if _selected == "":
		return
	var row: Dictionary = _rows[_selected]
	var size := Vector3.ONE * 2.0
	var parent: Node3D = null
	var local := Transform3D.IDENTITY
	if row.body != null and is_instance_valid(row.body):
		var body: DynamicGridBody = row.body
		var bounds := body.get_hull_bounds()
		if bounds.has("half"):
			size = (bounds.half as Vector3) * 2.0 + Vector3.ONE
			local.origin = bounds.pos
		parent = body
	else:
		parent = get_tree().current_scene as Node3D
		size = Vector3.ONE * maxf(4.0, pow(float(row.blocks), 1.0 / 3.0) * 2.0)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = MARK_COLOR
	mesh.material = material
	_marker = MeshInstance3D.new()
	_marker.mesh = mesh
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(_marker)
	if row.body != null:
		_marker.transform = local
	else:
		_marker.global_position = row.center
	_update_buttons()


func _clear_marker() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


## Pone al jugador encima de la construcción, unos metros por fuera de ella hacia el cielo.
func _on_go() -> void:
	if _selected == "" or not is_instance_valid(_player):
		return
	var row: Dictionary = _rows[_selected]
	var planet: Node3D = _player.get("planet")
	var center: Vector3 = planet.global_position if planet != null else Vector3.ZERO
	var up: Vector3 = (row.center - center).normalized()
	_player.global_position = row.center + up * (4.0 + pow(float(row.blocks), 1.0 / 3.0))
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## Pide confirmación con un segundo clic. Borra el grupo entero (todas sus grids y bloques); un
## cuerpo sin grids se libera sin más.
func _on_delete() -> void:
	if _selected == "":
		return
	if _delete_armed != _selected:
		_delete_armed = _selected
		_update_buttons()
		return
	var row: Dictionary = _rows[_selected]
	if is_instance_valid(_marker):
		_clear_marker()
	if not (row.grids as Array).is_empty():
		GridManager.remove_grid_group(row.grids[0])
	if row.body != null and is_instance_valid(row.body) and not row.body.is_queued_for_deletion():
		(row.body as DynamicGridBody).queue_free()
	_rows.erase(_selected)
	_selected = ""
	_delete_armed = ""
	_refresh()
