class_name Bedroll
extends Node3D

## Lecho de fibras y pieles: E abre el descanso. Su transformación se guarda como la del banco.
const GROUP := &"bedroll"
const ITEM_ID := &"bedroll"
const REACH := 2.6

var entity_id := ""
var save_category := "planet"
var discard_on_load := true
## El barco del que colgaba al guardar (GroundPlaceableTrait.restore_ship).
var _ship_id := ""


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "bedroll_%d_%d" % [Time.get_unix_time_from_system(), randi()]


static func nearest(tree: SceneTree, position: Vector3) -> Bedroll:
	var best: Bedroll
	var distance := REACH
	for node in tree.get_nodes_in_group(GROUP):
		var bed := node as Bedroll
		if bed != null and bed.is_inside_tree() and not bed.is_queued_for_deletion():
			var d := bed.global_position.distance_to(position)
			if d <= distance:
				best = bed
				distance = d
	return best


static func find_by_id(tree: SceneTree, id: String) -> Bedroll:
	for node in tree.get_nodes_in_group(GROUP):
		var bed := node as Bedroll
		if bed != null and bed.entity_id == id and not bed.is_queued_for_deletion():
			return bed
	return null


func respawn_transform() -> Transform3D:
	var frame := global_transform.orthonormalized()
	# Los pies por encima de la colisión del lecho, también en superficies planetarias inclinadas.
	frame.origin += frame.basis.y * 0.25
	return frame


func get_save_data() -> Dictionary:
	var t := transform
	return {"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y,
		t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z], "origin": [t.origin.x, t.origin.y, t.origin.z],
		"ship": GroundPlaceableTrait.ship_id(self)}


func restore_save_data(data: Dictionary) -> void:
	_ship_id = String(data.get("ship", ""))
	var b: Array = data.get("basis", [])
	var p: Array = data.get("origin", [])
	if b.size() == 9 and p.size() == 3:
		transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]),
			Vector3(b[6], b[7], b[8])), Vector3(p[0], p[1], p[2]))


func post_restore() -> void:
	GroundPlaceableTrait.restore_ship(self, _ship_id)
