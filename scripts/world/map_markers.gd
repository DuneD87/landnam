class_name MapMarkers extends RefCounted

## Marcadores personales. Las UV y el id del planeta sobreviven al origen flotante y al
## rehorneado del mapa. El jugador los incluye en su guardado, separados del caché del terreno.

const ICONS := ["home", "resources", "cave", "camp", "danger", "flag", "tombstone"]
const LAST_DEATH := "last_death"
const ICON_LABELS := {
	"home": "MAP_MARKER_HOME",
	"resources": "MAP_MARKER_RESOURCES",
	"cave": "MAP_MARKER_CAVE",
	"camp": "MAP_MARKER_CAMP",
	"danger": "MAP_MARKER_DANGER",
	"flag": "MAP_MARKER_FLAG",
	"tombstone": "MAP_MARKER_TOMBSTONE",
}
const MAX_NAME_LENGTH := 48

var _entries: Array[Dictionary] = []
var _next_id := 1


func add(planet_id: String, uv: Vector2, icon: String, marker_name: String = "") -> int:
	if planet_id.is_empty() or not is_valid_uv(uv) or icon not in ICONS:
		return 0
	var id := _next_id
	_next_id += 1
	_entries.append({"id": id, "planet_id": planet_id, "uv": uv,
		"icon": icon, "name": _clean_name(marker_name)})
	return id


## Una única última muerte entre todos los planetas. Las tumbas puestas a mano son independientes.
func record_death(planet_id: String, uv: Vector2) -> int:
	if planet_id.is_empty() or not is_valid_uv(uv):
		return 0
	for entry in _entries:
		if entry.get("kind", "") == LAST_DEATH:
			entry.planet_id = planet_id
			entry.uv = uv
			entry.icon = "tombstone"
			entry.name = ""
			return entry.id
	var id := add(planet_id, uv, "tombstone")
	_entries[-1]["kind"] = LAST_DEATH
	return id


func update(id: int, icon: String, marker_name: String) -> bool:
	if icon not in ICONS:
		return false
	for entry in _entries:
		if entry.id == id:
			entry.icon = icon
			entry.name = _clean_name(marker_name)
			return true
	return false


func remove(id: int) -> bool:
	for i in _entries.size():
		if _entries[i].id == id:
			_entries.remove_at(i)
			return true
	return false


func for_planet(planet_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _entries:
		if entry.planet_id == planet_id:
			out.append(entry.duplicate())
	return out


func get_marker(id: int) -> Dictionary:
	for entry in _entries:
		if entry.id == id:
			return entry.duplicate()
	return {}


func save_data() -> Array:
	var out: Array = []
	for entry in _entries:
		out.append({"id": entry.id, "planet_id": entry.planet_id,
			"uv": {"u": entry.uv.x, "v": entry.uv.y},
			"icon": entry.icon, "name": entry.name})
		if entry.get("kind", "") == LAST_DEATH:
			out[-1]["kind"] = LAST_DEATH
	return out


## Una partida anterior a los marcadores carga una lista vacía. Restaurar sustituye la lista:
## cargar varias veces o cambiar de slot nunca mezcla ni duplica marcadores.
func load_data(data: Variant) -> void:
	_entries.clear()
	_next_id = 1
	if not data is Array:
		return
	var seen := {}
	var last_death_id := 0
	for value in data:
		if not value is Dictionary:
			continue
		var id_value: Variant = value.get("id")
		if not (id_value is int or id_value is float):
			continue
		if not is_finite(float(id_value)) or float(id_value) != floor(float(id_value)):
			continue
		var id := int(id_value)
		var planet_id: Variant = value.get("planet_id")
		var coords: Variant = value.get("uv")
		if id <= 0 or seen.has(id) or not planet_id is String or planet_id.is_empty():
			continue
		if not coords is Dictionary:
			continue
		var u: Variant = coords.get("u")
		var v: Variant = coords.get("v")
		if not (u is float or u is int) or not (v is float or v is int):
			continue
		var uv := Vector2(float(u), float(v))
		if not is_valid_uv(uv):
			continue
		var icon: Variant = value.get("icon", "flag")
		if not icon is String or icon not in ICONS:
			icon = "flag"
		var marker_name: Variant = value.get("name", "")
		_entries.append({"id": id, "planet_id": planet_id, "uv": uv, "icon": icon,
			"name": _clean_name(marker_name if marker_name is String else "")})
		if value.get("kind", "") == LAST_DEATH:
			# Incluso con datos duplicados solo se conserva la última entrada válida.
			if last_death_id != 0:
				remove(last_death_id)
			_entries[-1]["kind"] = LAST_DEATH
			last_death_id = id
		seen[id] = true
		_next_id = maxi(_next_id, id + 1)


static func display_name(marker: Dictionary) -> String:
	if not marker.name.is_empty():
		return marker.name
	if marker.get("kind", "") == LAST_DEATH:
		return TranslationServer.translate("MAP_LAST_DEATH")
	return TranslationServer.translate(ICON_LABELS[marker.icon])


static func is_valid_uv(uv: Vector2) -> bool:
	return uv.is_finite() and uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0


static func _clean_name(marker_name: String) -> String:
	return marker_name.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(MAX_NAME_LENGTH)
