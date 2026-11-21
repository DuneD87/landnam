class_name QuestJournal
extends CanvasLayer

## El diario de encargos (L, acción "journal"): un panel a la derecha, sin soltar el ratón, con cada
## encargo abierto (SettlementQuests): quién lo pidió y de dónde, qué hay que hacer y cómo va, lo que le
## queda de plazo y hacia dónde y a cuánto queda lo siguiente (SettlementQuests.target_of). Se rehace cada
## REFRESH s mientras se ve. Además pone esos sitios en el mapa y el minimapa (markers, como
## MapMarkers.provider), en ámbar: el poblado de destino, la zona donde buscar al perdido o a la fiera,
## o el poblado de quien lo pidió para cobrar. Ver docs/villagers.md (Encargos).

const ACTION := &"journal"
const REFRESH := 0.5

var _player: PlayerController
var _root: Control
var _panel: PanelContainer
var _margin: MarginContainer
var _box: VBoxContainer
var _title: Label
var _list: VBoxContainer
var _empty: Label
var _refresh_left := 0.0


func _ready() -> void:
	layer = 6
	_build_ui()
	visible = false


func setup(player: PlayerController) -> void:
	_player = player
	get_viewport().size_changed.connect(_layout)
	_layout()
	# El mapa se crea después: sus marcas, en diferido.
	_hook_markers.call_deferred()


func _hook_markers() -> void:
	if _player != null and is_instance_valid(_player) and _player.world_map_ui != null:
		_player.world_map_ui.markers.provider = markers


func toggle() -> void:
	visible = not visible
	_refresh_left = 0.0
	if visible:
		_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		_refresh()


func _manager() -> SettlementManager:
	var companions := get_tree().get_first_node_in_group(SettlementCompanions.GROUP) as SettlementCompanions
	return companions._manager if companions != null else null


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var manager := _manager()
	var quests: Array = manager.quests.open_list() if manager != null else []
	_empty.visible = quests.is_empty()
	if manager == null:
		return
	var terrain := manager._terrain
	for quest: Dictionary in quests:
		var entry := VBoxContainer.new()
		_list.add_child(entry)
		var head := Label.new()
		head.theme_type_variation = &"SectionLabel"
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.text = tr("JOURNAL_ENTRY") % [tr("JOURNAL_KIND_" + String(quest.kind).to_upper()), quest.name,
			quest.village_name]
		entry.add_child(head)
		var parts := PackedStringArray([VillagerTalk.quest_status(quest, _player.inventory)])
		if not SettlementQuests.is_settled(quest):
			var left := VillagerTalk.time_left(manager.quests.hours_left(quest))
			if left != "":
				parts.append(left)
		if manager.quests.is_ready(quest, _player.inventory):
			parts.append(tr("JOURNAL_READY") % quest.name)
		var target := manager.quests.target_of(quest)
		var at := SettlementQuests.vec(target.get("at", Vector3.INF))
		if at.is_finite() and terrain != null and is_instance_valid(terrain):
			var here := terrain.global_transform.affine_inverse() * _player.global_position
			var up := here.normalized()
			var to := (at - here).slide(up)
			var meters := to.length()
			var where := tr(VillagerTalk.heading_key(up, to)) if meters > 15.0 else tr("JOURNAL_HERE")
			var dist := tr("JOURNAL_KM") % (meters / 1000.0) if meters >= 1000.0 else tr("JOURNAL_M") % (roundi(meters / 10.0) * 10)
			parts.append(tr("JOURNAL_AREA" if target.get("area", false) else "JOURNAL_WAY") % [where, dist])
		var body := Label.new()
		body.theme_type_variation = &"HintLabel"
		body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.text = " · ".join(parts)
		entry.add_child(body)


## Las marcas de los encargos en [planet_id] (MapMarkers.provider): {"uv", "icon", "name"}.
func markers(planet_id: String) -> Array:
	var out: Array = []
	var manager := _manager()
	if manager == null or _player == null or not is_instance_valid(_player):
		return out
	var loader = _player.get("planet")
	if loader == null or str(loader.get("entity_id")) != planet_id:
		return out
	var map: PlanetWorldMap = loader.get("world_map")
	var terrain := manager._terrain
	if map == null or terrain == null or not is_instance_valid(terrain):
		return out
	for quest: Dictionary in manager.quests.open_list():
		var target := manager.quests.target_of(quest)
		var at := SettlementQuests.vec(target.get("at", Vector3.INF))
		if not at.is_finite():
			continue
		out.append({"uv": map.get_uv(terrain.global_transform * at), "icon": String(target.icon),
			"name": tr("JOURNAL_MARKER") % VillagerTalk.quest_status(quest)})
	return out


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"WindowPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_panel)
	_margin = MarginContainer.new()
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_margin)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_box)
	_title = Label.new()
	_title.text = "JOURNAL_TITLE"
	_title.theme_type_variation = &"HeaderLabel"
	_box.add_child(_title)
	_box.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_box.add_child(_list)
	_empty = Label.new()
	_empty.text = "JOURNAL_EMPTY"
	_empty.theme_type_variation = &"HintLabel"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_empty)
	var keys := Label.new()
	keys.text = "JOURNAL_KEYS"
	keys.theme_type_variation = &"HintLabel"
	_box.add_child(keys)


func _layout() -> void:
	var ui_scale := GameTheme.scale_for(get_viewport())
	_root.theme = GameTheme.build(ui_scale)
	_panel.custom_minimum_size.x = 460.0 * ui_scale
	_panel.offset_right = -24.0 * ui_scale
	_box.add_theme_constant_override("separation", roundi(12.0 * ui_scale))
	_list.add_theme_constant_override("separation", roundi(14.0 * ui_scale))
	for side in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, roundi(20.0 * ui_scale))
