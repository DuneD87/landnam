class_name ItemCatalog
extends RefCounted

## Catálogo de ItemData: todos los .tres de res://data/items/ por su id. Se carga entero la
## primera vez que se pide un objeto.

const ITEMS_DIR := "res://data/items/"

static var items: Dictionary = {}


static func get_item(id: StringName) -> ItemData:
	if items.is_empty():
		_load_items_from_folder(ITEMS_DIR)
	return items.get(id)


static func _load_items_from_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		push_error("No se pudo abrir el directorio: " + path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_load_items_from_folder(full_path)
		elif file_name.ends_with(".tres"):
			var item := load(full_path) as ItemData
			if item:
				items[item.id] = item
			else:
				push_warning("No se pudo cargar como ItemData: " + full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
