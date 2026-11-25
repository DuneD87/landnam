extends Node

## GameManager (autoload singleton): máquina de estados del juego y orquestador de guardado/carga.
## Emite señales para que cada sistema reaccione. Registrar en Project > Autoload como "GameManager".

signal state_changed(new_state: State)

enum State {
	MENU,
	CINEMATIC,
	PLAYING,
	## Pantalla de creación de personaje, entre "Start Game" y la cinemática. Va al final
	## para no cambiar el valor de los estados que ya hay guardados.
	CHARACTER_CREATION,
}

const SAVEABLE_GROUP: String = "saveable"
const SAVE_DIR: String = SaveSlots.ROOT
const SAVE_CATEGORIES: Array[String] = ["player", "grid", "planet", "npc", "remains", "world_items"]
## Objetos de sesión que no tienen estado persistente (proyectiles, trozos de tala y minería).
const RESET_ON_LOAD_GROUP := &"reset_on_load"
## La partida de siempre del menú, de antes de las partidas con nombre.
const MAIN_SLOT: String = SaveSlots.LEGACY_MAIN
const PLAYER_ENTITY_ID: String = "player"

var current_state: State = State.MENU
var player: CharacterBody3D
## Personaje de la partida: lo rellena la creación de personaje y lo restaura el jugador al
## cargar. Null en partidas anteriores a la creación de personaje.
var character: CharacterData
## La partida en juego: la última cargada o guardada. Vacía en una partida nueva aún sin guardar.
var current_slot := ""
## La que carga "Continuar" y hacia la que se adelanta el SpawnPoint al arrancar: la de --load=<nombre>
## o la última usada.
var continue_slot := ""
## La que se carga sola al arrancar: `godot -- --load=<nombre>`.
var autoload_slot := ""
## Cada cambio de terreno (cargar, partida nueva) abre una base de datos viva nueva: el stream de
## antes puede tener aún tareas en marcha contra la suya. Las viejas se borran al arrancar.
var _terrain_generation := 0
## La partida cuyo terreno está tal cual en la copia viva: la que se preparó al arrancar, mientras no
## se juegue. Cargarla desde el menú no necesita recargar el terreno.
var _pristine_terrain_slot := ""
## La última partida usada según el disco al arrancar: si se borra la que se haya guardado después
## (los tests guardan en una partida suya y la borran), Continuar vuelve a ella.
var _boot_last_slot := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	SaveSlots.migrate_legacy()
	_boot_last_slot = SaveSlots.last()
	autoload_slot = _cmdline_slot()
	continue_slot = autoload_slot if autoload_slot != "" else SaveSlots.last()
	# Antes que nada del mundo: el planeta abre su terreno de LIVE en su _ready.
	_prepare_live_terrain(continue_slot)
	# Antes de que cargue el planeta: el shader de la vegetación las necesita para compilar.
	BloodFoliage.register_globals()
	SettlementStreets.register_globals()
	CrowdShader.register_globals()


func register_player(p: CharacterBody3D) -> void:
	player = p


func begin_character_creation() -> void:
	if current_state != State.MENU:
		return
	_change_state(State.CHARACTER_CREATION)


func cancel_character_creation() -> void:
	if current_state != State.CHARACTER_CREATION:
		return
	_change_state(State.MENU)


## Arranca la partida desde el menú o desde la creación, con el personaje creado si lo hay.
func start_game(new_character: CharacterData = null) -> void:
	if current_state != State.MENU and current_state != State.CHARACTER_CREATION:
		return
	if new_character != null:
		character = new_character
	# El terreno de la partida que había preparada para Continuar no es el de una partida nueva.
	if _pristine_terrain_slot != "":
		_swap_terrain("")
	current_slot = ""
	_change_state(State.CINEMATIC)


## Lo llama el jugador cuando termina el tween de la cinemática.
func cinematic_completed() -> void:
	if current_state != State.CINEMATIC:
		return
	_change_state(State.PLAYING)


func _change_state(new_state: State) -> void:
	# Jugando, el terreno vivo ya no es el de la partida preparada al arrancar.
	if new_state == State.PLAYING or new_state == State.CINEMATIC:
		_pristine_terrain_slot = ""
	current_state = new_state
	state_changed.emit(new_state)


func _find_spawn_point() -> Node3D:
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.find_child("SpawnPoint", true, false) as Node3D


func _move_spawn_point_to_player() -> void:
	if not player or not is_instance_valid(player):
		push_warning("SaveSystem: cannot move SpawnPoint because player is not registered")
		return

	var spawn_point := _find_spawn_point()
	if not spawn_point:
		push_warning("SaveSystem: SpawnPoint not found in current scene")
		return

	spawn_point.global_position = player.global_position


## Lee del disco los datos guardados del jugador (posición canónica, orientación, cámara…)
## sin cargar la partida. Diccionario vacío si no hay save o no es legible.
func peek_player_data(slot_name: String = "") -> Dictionary:
	if slot_name == "":
		slot_name = continue_slot
	var data: Variant = _read_json(_save_file_path(slot_name, "player"))
	if not (data is Dictionary):
		return {}

	var entry: Variant = data.get(PLAYER_ENTITY_ID)
	if entry == null:
		for id in data:
			entry = data[id]
			break
	if not (entry is Dictionary):
		return {}

	var entry_data: Variant = entry.get("data")
	return entry_data if entry_data is Dictionary else {}


## Lee del disco solo la posición canónica del jugador, sin cargar la partida.
## Devuelve un Vector3, o null si no hay save o no es legible.
func peek_player_position(slot_name: String = "") -> Variant:
	var entry_data := peek_player_data(slot_name)
	if entry_data.is_empty():
		return null
	var pos: Variant = entry_data.get("position")
	if not (pos is Dictionary):
		return null
	return Vector3(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0)))


## Adelanta el SpawnPoint a la posición guardada del jugador antes de cargar la partida, para que
## el VoxelViewer que cuelga de él empiece a streamear el terreno donde el jugador va a aparecer.
## 'spawn_point' se puede pasar explícito si la escena aún no es current_scene (p.ej. desde _ready).
func apply_saved_spawn_point(slot_name: String = "", spawn_point: Node3D = null) -> bool:
	var canonical: Variant = peek_player_position(slot_name)
	if canonical == null:
		return false

	if not spawn_point:
		spawn_point = _find_spawn_point()
	if not spawn_point:
		push_warning("SaveSystem: SpawnPoint not found, cannot preload saved position")
		return false

	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	spawn_point.global_position = fo.from_canonical(canonical) if fo != null else canonical
	print("SaveSystem: SpawnPoint moved to saved player position %s" % str(spawn_point.global_position))
	return true


func _save_file_path(slot_name: String, category: String) -> String:
	return SaveSlots.file(slot_name, category)


func _write_json(path: String, data: Variant) -> bool:
	return SaveSlots.write_json(path, data)


func _read_json(path: String) -> Variant:
	return SaveSlots.read_json(path)


## `godot -- --load=<nombre>`: la partida que se carga sola al arrancar. Vacío si no se pide o no existe.
func _cmdline_slot() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--load="):
			var slot := SaveSlots.sanitize(arg.substr(7))
			if SaveSlots.exists(slot):
				return slot
			push_error("SaveSystem: --load: no existe la partida '%s'" % slot)
	return ""


## Guarda la partida en la carpeta [slot_name] (se crea si no existe). Una partida protegida no se
## sobrescribe: devuelve false. [note], si no está vacía, sustituye la nota de la partida.
func save_game(slot_name: String = "default", note: String = "") -> bool:
	var slot := SaveSlots.sanitize(slot_name)
	if slot == "":
		push_error("SaveSystem: nombre de partida no válido: '%s'" % slot_name)
		return false
	if SaveSlots.is_protected(slot):
		push_warning("SaveSystem: la partida '%s' está protegida, no se guarda encima" % slot)
		return false
	DirAccess.make_dir_recursive_absolute(SaveSlots.dir(slot) + SaveSlots.TERRAIN)
	_move_spawn_point_to_player()

	var voxel_entities := get_tree().get_nodes_in_group(SAVEABLE_GROUP).filter(
		func(e): return not e.is_queued_for_deletion() and e.has_method("save_voxel_data")
	)
	for entity in voxel_entities:
		var tracker: VoxelSaveCompletionTracker = entity.save_voxel_data()
		if tracker:
			while not tracker.is_complete():
				await get_tree().process_frame
			print("SaveSystem: voxel save complete for %s" % entity.entity_id)
		# Con los bloques ya escritos, la copia del terreno vivo pasa a ser el de la partida.
		if is_instance_valid(entity) and entity.has_method("snapshot_voxel_data"):
			if not entity.snapshot_voxel_data(SaveSlots.terrain_file(slot, entity.entity_id)):
				push_warning("SaveSystem: no se pudo copiar el terreno de %s" % entity.entity_id)

	# Después de las esperas del terreno: desde aquí hasta capturar todas las entidades no se
	# cede otro fotograma en el que el jugador pueda volver a coger un montón con el cursor.
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not entity.is_queued_for_deletion() and entity.has_method("prepare_save"):
			entity.prepare_save()
	var by_category: Dictionary = {}
	for cat in SAVE_CATEGORIES:
		by_category[cat] = {}

	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.is_queued_for_deletion():
			continue
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
	by_category["world_items"] = DroppedItem.capture_all(get_tree())

	# La nota y la protección de la partida se conservan al guardar encima.
	var meta := SaveSlots.read_meta(slot)
	meta.merge({
		"format": SaveSlots.FORMAT,
		"timestamp": Time.get_datetime_string_from_system(),
		"game_state": current_state,
		"character": character.display_name if character != null else "",
	}, true)
	if note != "":
		meta["note"] = note
	SaveSlots.write_meta(slot, meta)
	var total := 0
	for cat in SAVE_CATEGORIES:
		_write_json(_save_file_path(slot, cat), by_category[cat])
		total += by_category[cat].size()

	_set_current_slot(slot)
	print("SaveSystem: game saved to slot '%s' (%d entities)" % [slot, total])
	return true


func load_game(slot_name: String = "default") -> bool:
	var slot := SaveSlots.sanitize(slot_name)
	var meta_path := _save_file_path(slot, "meta")
	if slot == "" or not FileAccess.file_exists(meta_path):
		push_error("SaveSystem: save not found: %s" % meta_path)
		return false

	var meta: Variant = _read_json(meta_path)
	if meta == null:
		push_error("SaveSystem: invalid JSON in meta file")
		return false

	var all_entities: Dictionary = {}
	for cat in SAVE_CATEGORIES:
		if cat == "world_items":
			continue
		var cat_data: Variant = _read_json(_save_file_path(slot, cat))
		if cat_data is Dictionary:
			for id in cat_data:
				all_entities[id] = cat_data[id]

	# El terreno de la partida, antes de colocar nada encima: el jugador espera a que su suelo tenga
	# colisión, y la del terreno de antes ya no vale. Desde el menú, si es la partida que se preparó
	# al arrancar, ya está.
	if not (current_state == State.MENU and _pristine_terrain_slot == slot):
		_swap_terrain(slot)

	# Devuelve los objetos del cursor antes de restaurar cualquier contenedor, sin depender del
	# orden de las entidades. Así no se reinsertan objetos antiguos sobre contenido ya restaurado.
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not entity.is_queued_for_deletion() and entity.has_method("prepare_restore"):
			entity.prepare_restore()
	DroppedItem.clear_all(get_tree())
	for node in get_tree().get_nodes_in_group(RESET_ON_LOAD_GROUP):
		if is_instance_valid(node) and node.is_inside_tree():
			node.get_parent().remove_child(node)
			node.queue_free()
	var saved_state: int = meta.get("game_state", State.PLAYING)
	WorldTime.reset()
	_set_current_slot(slot)
	_change_state(saved_state as State)

	var restored_ids: Array[String] = []
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.is_queued_for_deletion() or not entity.get("entity_id"):
			continue
		# Lo que nace en partida (los restos del jugador) y no estaba al guardar, fuera.
		if entity.get("discard_on_load") and not all_entities.has(entity.entity_id):
			entity.remove_from_group(SAVEABLE_GROUP)
			entity.get_parent().remove_child(entity)
			entity.queue_free()
			continue
		var id: String = entity.entity_id
		if all_entities.has(id):
			entity.restore_save_data(all_entities[id].data)
			restored_ids.append(id)

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

	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.has_method("post_restore"):
			entity.post_restore()
	var world_items: Variant = _read_json(_save_file_path(slot, "world_items"))
	DroppedItem.restore_all(get_tree(), world_items if world_items is Dictionary else {})

	print("SaveSystem: game loaded from slot '%s' (%d entities)" % [slot, all_entities.size()])
	return true


func has_save(slot_name: String = "default") -> bool:
	return SaveSlots.exists(SaveSlots.sanitize(slot_name))


## Borra la partida con su terreno. Una protegida no se borra: devuelve false.
func delete_save(slot_name: String = "default") -> bool:
	var slot := SaveSlots.sanitize(slot_name)
	if SaveSlots.is_protected(slot):
		push_warning("SaveSystem: la partida '%s' está protegida, no se borra" % slot)
		return false
	if not SaveSlots.delete(slot):
		return false
	if current_slot == slot:
		current_slot = ""
	if SaveSlots.last_recorded() == slot:
		SaveSlots.set_last(_boot_last_slot if SaveSlots.exists(_boot_last_slot) else "")
	if continue_slot == slot:
		continue_slot = SaveSlots.last()
	return true


func _set_current_slot(slot: String) -> void:
	current_slot = slot
	continue_slot = slot
	SaveSlots.set_last(slot)


# --- Terreno de la partida ----------------------------------------------------------------------

## La base de datos del terreno con la que se juega en el planeta [entity_id] (la abre el planeta en
## su _ready y al cambiar de terreno).
func live_terrain_path(entity_id: String) -> String:
	return _live_dir() + "%s_%d.sqlite" % [entity_id, _terrain_generation]


## Una carpeta por proceso: un test headless que arranca mientras se juega no toca el terreno vivo
## de la partida abierta.
func _live_dir() -> String:
	return SaveSlots.LIVE + str(OS.get_process_id()) + "/"


## Al arrancar, con nada abierto todavía: borra los terrenos vivos de procesos que ya no existen y
## copia a la carpeta de este el terreno de [slot], para que el planeta arranque ya con él y
## Continuar no tenga que recargarlo.
func _prepare_live_terrain(slot: String) -> void:
	for f in DirAccess.get_files_at(SaveSlots.LIVE):
		DirAccess.remove_absolute(SaveSlots.LIVE + f)
	for sub in DirAccess.get_directories_at(SaveSlots.LIVE):
		if not sub.is_valid_int() or not OS.is_process_running(sub.to_int()) or sub.to_int() == OS.get_process_id():
			SaveSlots.remove_tree(SaveSlots.LIVE + sub)
	DirAccess.make_dir_recursive_absolute(_live_dir())
	_terrain_generation = 0
	_pristine_terrain_slot = slot
	if slot == "":
		return
	var terrain_dir := SaveSlots.dir(slot) + SaveSlots.TERRAIN
	for f in DirAccess.get_files_at(terrain_dir):
		if f.ends_with(".sqlite"):
			DirAccess.copy_absolute(terrain_dir + f, live_terrain_path(f.get_basename()))


## Cambia el terreno de todos los planetas por el guardado en [slot] (vacío: el de una partida nueva,
## sin modificar). Lo que se hubiera cavado o construido desde el último guardado se descarta.
func _swap_terrain(slot: String) -> void:
	_terrain_generation += 1
	for entity in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if entity.is_queued_for_deletion() or not entity.has_method("swap_voxel_stream"):
			continue
		var live := live_terrain_path(entity.entity_id)
		var saved := SaveSlots.terrain_file(slot, entity.entity_id) if slot != "" else ""
		if saved != "" and FileAccess.file_exists(saved):
			var err := DirAccess.copy_absolute(saved, live)
			if err != OK:
				push_error("SaveSystem: no se pudo copiar el terreno %s (%s)" % [saved, error_string(err)])
		entity.swap_voxel_stream(live)
	_pristine_terrain_slot = slot
