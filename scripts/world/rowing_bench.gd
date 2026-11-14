class_name RowingBench
extends Node3D

## Bancada: un asiento que se planta (como el trono), en tierra o en la cubierta de un barco, del que
## cuelga entonces. Los compañeros se sientan en ella con la orden «A los bancos» (GroupCommand). En un
## barco y junto a la borda (a menos de BoatOars.ROW_REACH m) quien se sienta lleva un remo y rema con
## la marcha de remo (DynamicGridBody._update_oars, BoatSailing.rowers); lejos de la borda o en tierra
## solo se sienta. Su transformación se guarda como la del lecho; quién se sienta lo guarda el compañero
## (por el entity_id de la bancada). Ver docs/villagers.md y docs/sailing.md.
const GROUP := &"rowing_bench"
const ITEM_ID := &"rowing_bench"
## Dónde quedan las caderas de quien se sienta (local: a la altura del asiento, en el centro).
const SEAT := Vector3(0.0, RowingBenchVisualScript.SEAT_HEIGHT + 0.06, 0.02)
## Delante de la bancada, donde se levanta (local).
const STAND := Vector3(0.0, 0.05, -0.7)
const RowingBenchVisualScript = preload("res://scripts/world/rowing_bench_visual.gd")

var entity_id := ""
var save_category := "planet"
var discard_on_load := true
## Quién se sienta (o va hacia ella a sentarse) y si ya está sentado.
var occupant: Node3D
var seated := false
## El barco del que colgaba al guardar (GroundPlaceableTrait.restore_ship).
var _ship_id := ""
## El remo calculado (BoatOars.station_at), mientras no cambien el casco ni la bancada.
var _station := {}
var _station_version := -1
var _station_at := Transform3D()


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "rowing_bench_%d_%d" % [Time.get_unix_time_from_system(), randi()]


## Si está libre para [who] (nadie, o él mismo).
func is_free_for(who: Node3D) -> bool:
	return not is_instance_valid(occupant) or occupant == who


## El barco del que cuelga, o null en tierra.
func ship() -> DynamicGridBody:
	return get_parent() as DynamicGridBody


## Si lleva remo: en un barco y junto a la borda.
func has_oar() -> bool:
	return not oar_station().is_empty()


## Si ahora hay alguien sentado a su remo.
func is_rowing() -> bool:
	return seated and is_instance_valid(occupant) and has_oar()


## El remo de quien se siente aquí ({} sin remo), en el marco del barco (BoatOars.station_at).
func oar_station() -> Dictionary:
	var body := ship()
	if body == null:
		return {}
	var version := body.hull_version()
	if version != _station_version or not transform.is_equal_approx(_station_at):
		_station_at = transform
		_station = body.oar_station_at(transform * SEAT, -basis.z)
		_station_version = body.hull_version()
	return _station.duplicate()


## Las bancadas libres para [who] a menos de [radius] m de [at]; si [on_ship], solo las de ese barco.
## Primero las de remo y, de cada clase, las más cercanas.
static func free_near(tree: SceneTree, at: Vector3, radius: float, on_ship: DynamicGridBody,
		who: Node3D = null) -> Array[RowingBench]:
	var found: Array[RowingBench] = []
	for node in tree.get_nodes_in_group(GROUP):
		var bench := node as RowingBench
		if bench == null or not bench.is_inside_tree() or bench.is_queued_for_deletion() or not bench.is_free_for(who):
			continue
		if on_ship != null and bench.ship() != on_ship:
			continue
		if on_ship == null and bench.global_position.distance_to(at) > radius:
			continue
		found.append(bench)
	found.sort_custom(func(a: RowingBench, b: RowingBench) -> bool:
		var oar_a := a.has_oar()
		if oar_a != b.has_oar():
			return oar_a
		return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	return found


static func find(tree: SceneTree, id: String) -> RowingBench:
	for node in tree.get_nodes_in_group(GROUP):
		var bench := node as RowingBench
		if bench != null and bench.entity_id == id and not bench.is_queued_for_deletion():
			return bench
	return null


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
