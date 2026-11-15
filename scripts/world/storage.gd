class_name Storage
extends Node3D

## Contenedor del mundo. Su ItemData aporta StorageTrait y GroundPlaceableTrait; cada instancia
## tiene contenido propio. Las escenas solo eligen el objeto, el aspecto y la colisión.
## Los colonos dejan en él lo que sacan si acepta su oficio (jobs; vacío, todos: SettlerWork). El
## comedero (feeder) es aparte: solo admite comida, de él comen los colonos y solo el cocinero deja
## en él (lo asado).
const GROUP := &"storage"
const REACH := 2.6

@export var item_id: StringName

var inventory := Inventory.new()
## Los oficios de los colonos que dejan aquí lo que sacan (SettlerWork.JOB_IDS); vacío, todos.
var jobs: Array[StringName] = []
## Comedero (StorageTrait.feeder).
var feeder := false
var entity_id := ""
var save_category := "planet"
var discard_on_load := true
## El barco del que colgaba al guardar (GroundPlaceableTrait.restore_ship).
var _ship_id := ""


func _ready() -> void:
	var data := ItemCatalog.get_item(item_id)
	var config := data.get_trait(StorageTrait) as StorageTrait if data != null else null
	if config == null:
		push_error("Storage: '%s' necesita StorageTrait" % item_id)
		return
	inventory.max_slots = config.slots
	inventory.rules = config.rules
	feeder = config.feeder
	add_child(inventory)
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "%s_%d_%d" % [item_id, Time.get_unix_time_from_system(), randi()]


## Si el colono de oficio [id] deja aquí lo que saca. En el comedero, nadie (el cocinero lo deja
## aparte: SettlerTask.feeders).
func accepts_job(id: StringName) -> bool:
	return not feeder and (jobs.is_empty() or jobs.has(id))


## Los comederos a menos de [reach] m de [at] (mundo), del más cercano a [from] al más lejano.
static func feeders(tree: SceneTree, at: Vector3, reach: float, from: Vector3) -> Array[Storage]:
	var out: Array[Storage] = []
	for node in tree.get_nodes_in_group(GROUP):
		var storage := node as Storage
		if storage != null and storage.feeder and storage.is_inside_tree() and not storage.is_queued_for_deletion() \
				and storage.global_position.distance_to(at) <= reach:
			out.append(storage)
	out.sort_custom(func(a: Storage, b: Storage) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return out


## Marca o desmarca el oficio [id].
func set_job(id: StringName, on: bool) -> void:
	if on and not jobs.has(id):
		jobs.append(id)
	elif not on:
		jobs.erase(id)


static func nearest(tree: SceneTree, position: Vector3) -> Storage:
	var best: Storage
	var distance := REACH
	for node in tree.get_nodes_in_group(GROUP):
		var storage := node as Storage
		if storage != null and storage.is_inside_tree() and not storage.is_queued_for_deletion():
			var d := storage.global_position.distance_to(position)
			if d <= distance:
				best = storage
				distance = d
	return best


func get_save_data() -> Dictionary:
	var t := transform
	return {"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y,
		t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z],
		"origin": [t.origin.x, t.origin.y, t.origin.z], "inventory": inventory.get_save_data(),
		"ship": GroundPlaceableTrait.ship_id(self), "jobs": jobs.map(func(id: StringName) -> String: return String(id))}


func restore_save_data(data: Dictionary) -> void:
	_ship_id = String(data.get("ship", ""))
	jobs.clear()
	for id in data.get("jobs", []):
		jobs.append(StringName(id))
	var b: Array = data.get("basis", [])
	var p: Array = data.get("origin", [])
	if b.size() == 9 and p.size() == 3:
		transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]),
			Vector3(b[6], b[7], b[8])), Vector3(p[0], p[1], p[2]))
	if not inventory.restore_save_data(data.get("inventory", {})):
		push_error("Storage: no se pudo restaurar el contenido de '%s'" % entity_id)


func post_restore() -> void:
	GroundPlaceableTrait.restore_ship(self, _ship_id)
