class_name SaveSlots
extends RefCounted

## Las partidas guardadas en disco: una carpeta por partida, user://saves/<nombre>/, con un JSON por
## categoría (meta.json, player.json, grid.json…) y en terrain/ la copia del terreno de cada planeta
## (la base de datos SQLite del módulo de vóxeles) tal como estaba al guardar.
##
## El terreno con el que se juega está en user://saves/live/: el módulo escribe en él cada vez que
## suelta bloques, no solo al guardar, así que nunca es el de una partida. Al guardar se copia a la
## carpeta de la partida y al cargar se copia de vuelta (GameManager).
##
## Una partida "protegida" solo se carga: guardar encima o borrarla falla hasta desprotegerla. Sirve
## para las partidas de prueba, que deben quedarse como estaban.

const ROOT := "user://saves/"
const LIVE := "user://saves/live/"
const TERRAIN := "terrain/"
const LAST_FILE := "user://saves/last_slot.txt"
## 1: archivos <slot>_<categoría>.json sueltos en saves/ y el terreno compartido en saves/*.sqlite.
## 2: una carpeta por partida, con su terreno.
const FORMAT := 2
const MAX_NAME := 48
## Las copias a mano de saves/ que se hacían antes de las partidas con nombre (saves_aldea_test…).
const LEGACY_PREFIX := "saves_"
## La partida de siempre del menú, antes de que hubiera nombres.
const LEGACY_MAIN := "main_save"


## Un nombre de partida válido como carpeta: espacios a "_", sin separadores ni caracteres que no
## admita un nombre de archivo, sin puntos al principio y como mucho MAX_NAME caracteres. Vacío si no
## queda nada o es el de la carpeta del terreno vivo.
static func sanitize(name: String) -> String:
	var clean := name.strip_edges().replace(" ", "_").validate_filename()
	while clean.begins_with("."):
		clean = clean.substr(1)
	clean = clean.left(MAX_NAME)
	if clean == "live":
		return ""
	return clean


static func dir(slot: String) -> String:
	return ROOT + slot + "/"


static func file(slot: String, category: String) -> String:
	return dir(slot) + category + ".json"


static func terrain_file(slot: String, entity_id: String) -> String:
	return dir(slot) + TERRAIN + entity_id + ".sqlite"


static func exists(slot: String) -> bool:
	return slot != "" and FileAccess.file_exists(file(slot, "meta"))


static func read_meta(slot: String) -> Dictionary:
	var data: Variant = read_json(file(slot, "meta"))
	return data if data is Dictionary else {}


static func write_meta(slot: String, meta: Dictionary) -> bool:
	return write_json(file(slot, "meta"), meta)


static func is_protected(slot: String) -> bool:
	return bool(read_meta(slot).get("protected", false))


static func set_protected(slot: String, on: bool) -> bool:
	if not exists(slot):
		return false
	var meta := read_meta(slot)
	meta["protected"] = on
	return write_meta(slot, meta)


static func set_note(slot: String, note: String) -> bool:
	if not exists(slot):
		return false
	var meta := read_meta(slot)
	meta["note"] = note
	return write_meta(slot, meta)


## Todas las partidas, la más reciente primero: su meta.json con "slot" (el nombre de la carpeta).
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name in DirAccess.get_directories_at(ROOT):
		if name == "live" or not exists(name):
			continue
		var meta := read_meta(name)
		meta["slot"] = name
		out.append(meta)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("timestamp", "")) > str(b.get("timestamp", "")))
	return out


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for meta in list():
		out.append(meta.slot)
	return out


## La que dice last_slot.txt, exista o no. Vacía si no hay archivo.
static func last_recorded() -> String:
	return FileAccess.get_file_as_string(LAST_FILE).strip_edges() if FileAccess.file_exists(LAST_FILE) else ""


## La última partida cargada o guardada, si sigue existiendo; si no, la más reciente. Vacía si no hay.
static func last() -> String:
	var slot := last_recorded()
	if exists(slot):
		return slot
	var all := list()
	return all[0].slot if not all.is_empty() else ""


static func set_last(slot: String) -> void:
	var f := FileAccess.open(LAST_FILE, FileAccess.WRITE)
	if f:
		f.store_string(slot)


static func delete(slot: String) -> bool:
	if not exists(slot):
		return false
	return remove_tree(dir(slot))


# --- Migración ----------------------------------------------------------------------------------

## Una vez por PC: el guardado de antes (los <slot>_<categoría>.json sueltos en saves/ y el terreno en
## saves/*.sqlite) pasa a carpetas, y las copias que se hacían a mano de saves/ (user://saves_*/) se
## importan como partidas protegidas, sin tocar las carpetas originales. Devuelve las importadas.
static func migrate_legacy() -> PackedStringArray:
	var imported := PackedStringArray()
	if _legacy_slots(ROOT).is_empty():
		return imported
	imported.append_array(_import_flat(ROOT, "", true, false))
	# Continuar sigue siendo la partida de siempre, no una copia importada con su misma fecha.
	if LEGACY_MAIN in imported:
		set_last(LEGACY_MAIN)
	elif not imported.is_empty():
		set_last(imported[0])
	for folder in DirAccess.get_directories_at("user://"):
		if folder.begins_with(LEGACY_PREFIX):
			imported.append_array(_import_flat("user://" + folder + "/", folder.substr(LEGACY_PREFIX.length()),
				false, true))
	print("SaveSlots: migradas al formato %d: %s" % [FORMAT, ", ".join(imported)])
	return imported


## Los slots del formato 1 en [path]: los que tienen <slot>_meta.json.
static func _legacy_slots(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(path):
		if f.ends_with("_meta.json"):
			out.append(f.trim_suffix("_meta.json"))
	return out


## Pasa los slots del formato 1 de [src] a carpetas. [label] da el nombre de la partida (la carpeta
## copiada a mano: saves_aldea_test -> aldea_test); si la carpeta tenía más de un slot, se le añade el
## del slot. El terreno de [src] era uno para todos sus slots: va con main_save, o con el único que haya.
## [move] mueve los archivos (el saves/ de siempre); si no, los copia.
static func _import_flat(src: String, label: String, move: bool, protect: bool) -> PackedStringArray:
	var created := PackedStringArray()
	var slots := _legacy_slots(src)
	var files := DirAccess.get_files_at(src)
	var terrain_owner := LEGACY_MAIN if LEGACY_MAIN in slots else (slots[0] if slots.size() == 1 else "")
	for slot in slots:
		var target := slot
		if label != "":
			target = label if slots.size() == 1 or slot == LEGACY_MAIN else label + "_" + slot
		target = sanitize(target)
		if target == "" or exists(target):
			push_warning("SaveSlots: no se importa '%s%s': ya hay una partida '%s'" % [src, slot, target])
			continue
		DirAccess.make_dir_recursive_absolute(dir(target) + TERRAIN)
		for f in files:
			if f.begins_with(slot + "_") and f.ends_with(".json"):
				var category := f.trim_prefix(slot + "_").trim_suffix(".json")
				# Un slot que empieza igual que otro (main_save y main_save_x): solo sus categorías.
				if category.contains("_") and category != "world_items":
					continue
				_transfer(src + f, file(target, category), move)
		if slot == terrain_owner:
			for f in files:
				if f.ends_with(".sqlite"):
					_transfer(src + f, dir(target) + TERRAIN + f, move)
		var meta := read_meta(target)
		meta["format"] = FORMAT
		meta["protected"] = protect
		if label != "":
			meta["note"] = "Importada de user://%s%s" % [LEGACY_PREFIX, label]
		write_meta(target, meta)
		created.append(target)
	return created


static func _transfer(from: String, to: String, move: bool) -> void:
	var err := DirAccess.rename_absolute(from, to) if move else DirAccess.copy_absolute(from, to)
	if err != OK:
		push_error("SaveSlots: no se pudo %s %s -> %s (%s)" % ["mover" if move else "copiar", from, to,
			error_string(err)])


# --- Archivos -----------------------------------------------------------------------------------

static func write_json(path: String, data: Variant) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_error("SaveSystem: cannot write to %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("SaveSystem: cannot read %s — %s" % [path, FileAccess.get_open_error()])
		return null
	var result: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return result


static func remove_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	path = path.trim_suffix("/") + "/"
	for sub in DirAccess.get_directories_at(path):
		remove_tree(path + sub)
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + f)
	return DirAccess.remove_absolute(path) == OK
