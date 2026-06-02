## GameManager - Autoload Singleton
## Pure state machine + save/load orchestrator.
## Emits signals, lets each system react.
##
## Setup: Project > Project Settings > Autoload > Add as "GameManager"
extends Node

signal state_changed(new_state: State)

enum State {
	MENU,
	CINEMATIC,
	PLAYING,
}

const SAVEABLE_GROUP: String = "saveable"
const SAVE_DIR: String = "user://saves/"
const SAVE_EXTENSION: String = ".json"
const SAVE_CATEGORIES: Array[String] = ["player", "grid", "planet", "npc"]

var current_state: State = State.MENU
var player: CharacterBody3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func register_player(p: CharacterBody3D) -> void:
	player = p


func start_game() -> void:
	if current_state != State.MENU:
		return
	_change_state(State.CINEMATIC)


## Called by the player when the cinematic tween finishes
func cinematic_completed() -> void:
	if current_state != State.CINEMATIC:
		return
	_change_state(State.PLAYING)


func _change_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(new_state)


# ── Save / Load ──────────────────────────────────────────────────────────────

func _move_spawn_point_to_player() -> void:
	if not player or not is_instance_valid(player):
		push_warning("SaveSystem: cannot move SpawnPoint because player is not registered")
		return

	var spawn_point := get_tree().current_scene.find_child("SpawnPoint", true, false) as Node3D
	if not spawn_point:
		push_warning("SaveSystem: SpawnPoint not found in current scene")
		return

	spawn_point.global_position = player.global_position


func _save_file_path(slot_name: String, category: String) -> String:
	return SAVE_DIR + slot_name + "_" + category + SAVE_EXTENSION


func _write_json(path: String, data: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveSystem: cannot write to %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveSystem: cannot read %s — %s" % [path, FileAccess.get_open_error()])
		return null
	var result: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return result


func save_game(slot_name: String = "default") -> bool:
	_move_spawn_point_to_player()

	var voxel_entities := get_tree().get_nodes_in_group(SAVEABLE_GROUP).filter(
		func(e): return e.has_method("save_voxel_data")
	)
	for entity in voxel_entities:
		var tracker: VoxelSaveCompletionTracker = entity.save_voxel_data()
		if tracker:
			while not tracker.is_complete():
				await get_tree().process_frame
			print("SaveSystem: voxel save complete for %s" % entity.entity_id)

	var by_category: Dictionary = {}
	for cat in SAVE_CATEGORIES:
		by_category[cat] = {}

	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not entity.has_method("get_save_data") or not entity.get("entity_id"):
			push_warning("SaveSystem: entity missing get_save_data() or entity_id: %s" % entity.name)
			continue
		var cat: Variant = entity.get("save_category")
		if not by_category.has(cat):
			push_warning("SaveSystem: unknown save_category '%s' for entity '%s'" % [str(cat), entity.entity_id])
			continue
		by_category[cat][entity.entity_id] = {
			"scene_path": entity.scene_file_path,
			"parent_path": str(entity.get_parent().get_path()),
			"data": entity.get_save_data()
		}

	_write_json(_save_file_path(slot_name, "meta"), {
		"timestamp": Time.get_datetime_string_from_system(),
		"game_state": current_state,
	})
	var total := 0
	for cat in SAVE_CATEGORIES:
		_write_json(_save_file_path(slot_name, cat), by_category[cat])
		total += by_category[cat].size()

	print("SaveSystem: game saved to slot '%s' (%d entities)" % [slot_name, total])
	return true


func load_game(slot_name: String = "default") -> bool:
	var meta_path := _save_file_path(slot_name, "meta")
	if not FileAccess.file_exists(meta_path):
		push_error("SaveSystem: save not found: %s" % meta_path)
		return false

	var meta: Variant = _read_json(meta_path)
	if meta == null:
		push_error("SaveSystem: invalid JSON in meta file")
		return false

	var all_entities: Dictionary = {}
	for cat in SAVE_CATEGORIES:
		var cat_data: Variant = _read_json(_save_file_path(slot_name, cat))
		if cat_data is Dictionary:
			for id in cat_data:
				all_entities[id] = cat_data[id]

	var saved_state: int = meta.get("game_state", State.PLAYING)
	_change_state(saved_state as State)

	# Fase 1: restaurar entidades existentes
	var restored_ids: Array[String] = []
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not entity.get("entity_id"):
			continue
		var id: String = entity.entity_id
		if all_entities.has(id):
			entity.restore_save_data(all_entities[id].data)
			restored_ids.append(id)

	# Fase 1b: instanciar entidades que faltan
	for id in all_entities:
		if id in restored_ids:
			continue
		var entry: Dictionary = all_entities[id]
		var scene := load(entry.scene_path) as PackedScene
		if not scene:
			push_warning("SaveSystem: cannot load scene '%s' for entity '%s'" % [entry.scene_path, id])
			continue
		var entity := scene.instantiate()
		entity.entity_id = id
		var parent := get_tree().root.get_node_or_null(entry.parent_path)
		if parent:
			parent.add_child(entity)
		else:
			get_tree().current_scene.add_child(entity)
		entity.restore_save_data(entry.data)

	# Fase 2: post_restore
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.has_method("post_restore"):
			entity.post_restore()

	print("SaveSystem: game loaded from slot '%s' (%d entities)" % [slot_name, all_entities.size()])
	return true


## Busca todos los planetas con voxel terrain y les asigna el stream
func _setup_terrain_streams(_slot_name: String) -> void:
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.has_method("setup_voxel_stream"):
			entity.setup_voxel_stream()


func has_save(slot_name: String = "default") -> bool:
	return FileAccess.file_exists(_save_file_path(slot_name, "meta"))


func delete_save(slot_name: String = "default") -> bool:
	var meta_path := _save_file_path(slot_name, "meta")
	if not FileAccess.file_exists(meta_path):
		return false
	DirAccess.remove_absolute(meta_path)
	for cat in SAVE_CATEGORIES:
		var path := _save_file_path(slot_name, cat)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	return true


func get_save_slots() -> Array[String]:
	var slots: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return slots
	var suffix := "_meta" + SAVE_EXTENSION
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(suffix):
			slots.append(file_name.trim_suffix(suffix))
		file_name = dir.get_next()
	return slots


## Helper: buscar una entidad registrada por su entity_id
func get_entity(entity_id: String) -> Node:
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.get("entity_id") == entity_id:
			return entity
	return null
