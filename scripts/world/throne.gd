class_name Throne
extends Node3D

## Trono del jefe: E lo usa (ThroneView): el jugador se sienta y, desde la vista de la base, manda a
## los colonos (SettlerWork) cuyas bases están a menos de MANAGE_RADIUS m. Su transformación se guarda
## como la del lecho. Ver docs/villagers.md.
const GROUP := &"throne"
const ITEM_ID := &"throne"
const REACH := 2.6
## Los colonos que se mandan desde aquí: los que tienen su base a menos de esto (m).
const MANAGE_RADIUS := 90.0
## Dónde quedan las caderas de quien se sienta (local: a la altura del asiento, algo detrás del centro).
const SEAT := Vector3(0.0, ThroneVisualScript.SEAT_HEIGHT + 0.08, -0.06)
## Delante del trono, donde se levanta (local).
const STAND := Vector3(0.0, 0.05, 0.85)
const ThroneVisualScript = preload("res://scripts/world/throne_visual.gd")

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
		entity_id = "throne_%d_%d" % [Time.get_unix_time_from_system(), randi()]


static func nearest(tree: SceneTree, position: Vector3) -> Throne:
	var best: Throne
	var distance := REACH
	for node in tree.get_nodes_in_group(GROUP):
		var throne := node as Throne
		if throne != null and throne.is_inside_tree() and not throne.is_queued_for_deletion():
			var d := throne.global_position.distance_to(position)
			if d <= distance:
				best = throne
				distance = d
	return best


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
