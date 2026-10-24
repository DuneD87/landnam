class_name Storage
extends Node3D

## Contenedor del mundo. Su ItemData aporta StorageTrait y GroundPlaceableTrait; cada instancia
## tiene contenido propio. Las escenas solo eligen el objeto, el aspecto y la colisión.
const GROUP := &"storage"
const REACH := 2.6

@export var item_id: StringName

var inventory := Inventory.new()
var entity_id := ""
var save_category := "planet"
var discard_on_load := true


func _ready() -> void:
	var data := ItemCatalog.get_item(item_id)
	var config := data.get_trait(StorageTrait) as StorageTrait if data != null else null
	if config == null:
		push_error("Storage: '%s' necesita StorageTrait" % item_id)
		return
	inventory.max_slots = config.slots
	inventory.rules = config.rules
	add_child(inventory)
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "%s_%d_%d" % [item_id, Time.get_unix_time_from_system(), randi()]


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
		"origin": [t.origin.x, t.origin.y, t.origin.z], "inventory": inventory.get_save_data()}


func restore_save_data(data: Dictionary) -> void:
	var b: Array = data.get("basis", [])
	var p: Array = data.get("origin", [])
	if b.size() == 9 and p.size() == 3:
		transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]),
			Vector3(b[6], b[7], b[8])), Vector3(p[0], p[1], p[2]))
	if not inventory.restore_save_data(data.get("inventory", {})):
		push_error("Storage: no se pudo restaurar el contenido de '%s'" % entity_id)
