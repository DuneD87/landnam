# config.gd
extends Node

enum ANIMATION {IDLE, RUN, JUMP_START, JUMP_IDLE, JUMP_LAND, ATTACK_1, SPRINT, FALLING, SWIM, SWIM_IDLE}

static var items: Dictionary = {}

static func _load_items_from_folder(path: String) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		push_error("No se pudo abrir el directorio: " + path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path.path_join(file_name)
		
		if dir.current_is_dir():
			# Recursión para subcarpetas (ignora . y ..)
			if not file_name.begins_with("."):
				_load_items_from_folder(full_path)
		elif file_name.ends_with(".tres"):
			var item = load(full_path) as ItemData
			if item:
				items[item.id] = item
				print("Item cargado: ", item.id)
			else:
				push_warning("No se pudo cargar como ItemData: " + full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

static func get_item(id: StringName) -> ItemData:
	if items.size() == 0:
		_load_items_from_folder("res://data/items/")
	return items.get(id)
