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
	# 2) Ahora recopilar datos serializables
	var save_data: Dictionary = {
		"meta": {
			"timestamp": Time.get_datetime_string_from_system(),
			"game_state": current_state,
		},
		"entities": {}
	}
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not entity.has_method("get_save_data") or not entity.get("entity_id"):
			push_warning("SaveSystem: entity missing get_save_data() or entity_id: %s" % entity.name)
			continue
		save_data.entities[entity.entity_id] = {
			"scene_path": entity.scene_file_path,
			"parent_path": str(entity.get_parent().get_path()),
			"data": entity.get_save_data()
		}
	
	var path := SAVE_DIR + slot_name + SAVE_EXTENSION
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveSystem: cannot write to %s" % path)
		return false
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("SaveSystem: game saved to %s (%d entities)" % [path, save_data.entities.size()])
	return true


func load_game(slot_name: String = "default") -> bool:
	var path := SAVE_DIR + slot_name + SAVE_EXTENSION
	if not FileAccess.file_exists(path):
		push_error("SaveSystem: save file not found: %s" % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveSystem: cannot read %s — %s" % [path, FileAccess.get_open_error()])
		return false

	var parse_result = JSON.parse_string(file.get_as_text())
	file.close()

	if parse_result == null:
		push_error("SaveSystem: invalid JSON in %s" % path)
		return false

	var save_data: Dictionary = parse_result

	var saved_state: int = save_data.meta.get("game_state", State.PLAYING)
	_change_state(saved_state as State)

	# Configurar streams de terreno ANTES de restaurar entidades
	#_setup_terrain_streams(slot_name)

	# Fase 1: restaurar entidades existentes
	var restored_ids: Array[String] = []
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not entity.get("entity_id"):
			continue
		var id: String = entity.entity_id
		if save_data.entities.has(id):
			entity.restore_save_data(save_data.entities[id].data)
			restored_ids.append(id)

	# Fase 1b: instanciar entidades que faltan
	for id in save_data.entities:
		if id in restored_ids:
			continue
		var entry: Dictionary = save_data.entities[id]
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

	print("SaveSystem: game loaded from %s" % path)
	return true


## Busca todos los planetas con voxel terrain y les asigna el stream
func _setup_terrain_streams(slot_name: String) -> void:
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.has_method("setup_voxel_stream"):
			entity.setup_voxel_stream()


func has_save(slot_name: String = "default") -> bool:
	return FileAccess.file_exists(SAVE_DIR + slot_name + SAVE_EXTENSION)


func delete_save(slot_name: String = "default") -> bool:
	var path := SAVE_DIR + slot_name + SAVE_EXTENSION
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return true
	return false


func get_save_slots() -> Array[String]:
	var slots: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return slots
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(SAVE_EXTENSION):
			slots.append(file_name.trim_suffix(SAVE_EXTENSION))
		file_name = dir.get_next()
	return slots


## Helper: buscar una entidad registrada por su entity_id
func get_entity(entity_id: String) -> Node:
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.get("entity_id") == entity_id:
			return entity
	return null
