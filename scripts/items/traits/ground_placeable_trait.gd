class_name GroundPlaceableTrait
extends ItemTrait

## Se planta en el suelo (no en un bloque): la escena que deja y cuánta pendiente aguanta.
## Seleccionado en la barra, SurvivalActions enseña dónde iría y lo planta con el clic.

## Grupo de lo que ya está plantado (hogueras, estaciones de trabajo), para no plantar una cosa
## encima de otra.
const PLACED_GROUP := &"ground_placed"

@export_file("*.tscn") var scene_path := ""
## Lo que se enseña, translúcido, donde iría (solo lo que se ve, sin la lógica).
@export var preview_scene: PackedScene
## Radio con el que se asienta en el suelo (GroundFit), pendiente máxima en grados (más allá no
## se planta) y desnivel máximo que puede quedar bajo él (m).
@export var radius := 0.55
@export var max_slope := 28.0
@export var max_rough := 0.3
## Distancia mínima a otra cosa plantada (m).
@export var spacing := 1.5
## Cuánto se inclina con la pendiente (grados): lo bajo, como una hoguera, sigue al suelo; lo que va
## sobre patas va casi derecho.
@export var max_tilt := 20.0
## Cuánto se hunde para que el lado más bajo no flote: la parte del desnivel (0-1) y el tope (m).
## Sobre patas se apoya en lo más bajo y las del lado alto se clavan en el suelo.
@export var settle := 0.6
@export var max_settle := 0.1


func describe() -> Array:
	return [["TRAIT_PLACED", tr("TRAIT_ON_GROUND")]]


## Sobre la cubierta de un barco, lo plantado cuelga de él (se mueve con el casco) y su colisión no
## choca con el propio casco: hundida unos centímetros en la cubierta, lo empujaría sin parar.
static func attach_to_ship(node: Node3D, ship: DynamicGridBody) -> void:
	for body in node.find_children("*", "PhysicsBody3D", true, false):
		(body as PhysicsBody3D).add_collision_exception_with(ship)


## Lo que se guarda para volver a colgarlo del barco: su id de grid, o "" en tierra.
static func ship_id(node: Node) -> String:
	var ship := DynamicGridBody.holding(node.get_parent())
	return String(ship.get_meta("grid_id", "")) if ship != null else ""


## En post_restore: los barcos se recrean al cargar y el viejo sigue en el árbol hasta liberarse, así
## que la ruta guardada del padre no vale. Lo cuelga del nuevo por su id, con su transform local.
static func restore_ship(node: Node3D, id: String) -> void:
	if id == "":
		return
	var grid := GridManager.get_grid(id) as DynamicPlanetGrid
	var ship := grid._body if grid != null else null
	if not is_instance_valid(ship) or not ship.is_inside_tree() or ship.is_queued_for_deletion():
		push_warning("%s: no está el barco '%s' del que colgaba" % [node.name, id])
		return
	if node.get_parent() != ship:
		var old := DynamicGridBody.holding(node.get_parent())
		if old != null:
			for body in node.find_children("*", "PhysicsBody3D", true, false):
				(body as PhysicsBody3D).remove_collision_exception_with(old)
		var local := node.transform
		node.reparent(ship, false)
		node.transform = local
	attach_to_ship(node, ship)
