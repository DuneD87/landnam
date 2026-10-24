class_name Workstation
extends Node3D

## Estación de trabajo plantada en el suelo (el banco de trabajo de la Edad de piedra...). Quien
## esté cerca puede fabricar sus recetas (RecipeData.station = [item_id]), y E junto a ella abre la
## ventana de fabricar en ellas (InventoryUI.open_station). La planta SurvivalActions desde su
## objeto, que lleva CraftingStationTrait (era y alcance) y GroundPlaceableTrait. Se desmonta desde
## la ventana de fabricar y se guarda con la partida. Ver docs/items.md.

const GROUP := &"workstation"
## La hoguera encendida también es una estación (bebedizos, lo que se cuece): sus recetas llevan
## este id en RecipeData.station, y se hacen a su alcance (Campfire.REACH).
const CAMPFIRE := &"campfire"
## Desde dónde se abre con E (m, desde los pies).
const REACH := 2.6

## Id de su objeto: el que se planta, el que vuelve al desmontarla y el de sus recetas.
@export var item_id: StringName
## Lo que se ve (la misma escena que la vista previa al plantarla).
@export var visual: PackedScene
## Caja de colisión, apoyada en el suelo (m).
@export var collision_size := Vector3(1.2, 0.75, 0.5)

var entity_id := ""
var save_category := "planet"
var discard_on_load := true


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "%s_%d_%d" % [item_id, Time.get_unix_time_from_system(), randi()]
	if visual != null:
		add_child(visual.instantiate())
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y * 0.5
	body.add_child(shape)
	add_child(body)


func display_name() -> String:
	return Recipes.station_name(item_id)


## Hasta dónde se pueden usar sus recetas (CraftingStationTrait.reach).
func reach() -> float:
	var data: ItemData = ItemCatalog.get_item(item_id)
	var station := data.get_trait(CraftingStationTrait) as CraftingStationTrait if data != null else null
	return station.reach if station != null else REACH


## La más cercana a [world_pos] a menos de [max_distance] (m), o null.
static func nearest(tree: SceneTree, world_pos: Vector3, max_distance: float = REACH) -> Workstation:
	var best: Workstation = null
	var best_d := max_distance
	for node in tree.get_nodes_in_group(GROUP):
		var station := node as Workstation
		if station == null or not is_instance_valid(station):
			continue
		var d := station.global_position.distance_to(world_pos)
		if d <= best_d:
			best = station
			best_d = d
	return best


## Las estaciones a cuyo alcance está [world_pos]: id de su objeto → la más cercana de ese tipo.
## Una hoguera encendida cuenta como CAMPFIRE.
static func in_reach(tree: SceneTree, world_pos: Vector3) -> Dictionary:
	var out := {}
	for node in tree.get_nodes_in_group(Campfire.GROUP):
		var fire := node as Campfire
		if fire == null or not is_instance_valid(fire) or not fire.is_inside_tree() or not fire.lit:
			continue
		var d := fire.global_position.distance_to(world_pos)
		if d <= Campfire.REACH and (not out.has(CAMPFIRE) or d < (out[CAMPFIRE] as Node3D).global_position.distance_to(world_pos)):
			out[CAMPFIRE] = fire
	for node in tree.get_nodes_in_group(GROUP):
		var station := node as Workstation
		if station == null or not is_instance_valid(station) or not station.is_inside_tree():
			continue
		var d := station.global_position.distance_to(world_pos)
		if d > station.reach():
			continue
		var other: Workstation = out.get(station.item_id)
		if other == null or d < other.global_position.distance_to(world_pos):
			out[station.item_id] = station
	return out


func get_save_data() -> Dictionary:
	var t := transform
	return {
		"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z],
		"origin": [t.origin.x, t.origin.y, t.origin.z],
	}


func restore_save_data(data: Dictionary) -> void:
	var b: Array = data.get("basis", [])
	var o: Array = data.get("origin", [])
	if b.size() == 9 and o.size() == 3:
		transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])),
			Vector3(o[0], o[1], o[2]))
