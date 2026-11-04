class_name DoorDesign
extends RefCounted

## Medidas de una puerta o una trampilla de madera hecha en el menú de bloques (DoorBuildPanel): el
## hueco que cierra, en bloques de la grid en la que se pone ({"width": de las bisagras al canto de
## abrir, "height": a lo largo de las bisagras}). Lo que cuesta sale de lo que mide en metros, así que
## depende también del tamaño de celda: madera por m² y una piel para las bisagras de cada tanto.

const DOOR := &"wooden_door"
const TRAPDOOR := &"wooden_trapdoor"
const KINDS: Array[StringName] = [DOOR, TRAPDOOR]
const MIN_SIZE := Vector2i(1, 1)
const MAX_SIZE := Vector2i(4, 6)
## Madera por m² de hoja, y m² de hoja por cada piel de las bisagras.
const WOOD_PER_M2 := 2.0
const M2_PER_HIDE := 3.0


## La de [item_id] si no se dice otra cosa (DoorTrait.cells): 1 × 3 la puerta, 1 × 1 la trampilla.
static func default_cells(item_id: StringName) -> Vector2i:
	var door := WoodenDoor.door_of(item_id)
	return door.cells if door != null else Vector2i(1, 3)


static func normalize(config: Dictionary, item_id: StringName) -> Dictionary:
	var fallback := default_cells(item_id)
	return {
		"width": clampi(int(config.get("width", fallback.x)), MIN_SIZE.x, MAX_SIZE.x),
		"height": clampi(int(config.get("height", fallback.y)), MIN_SIZE.y, MAX_SIZE.y),
	}


static func cells(design: Dictionary) -> Vector2i:
	return Vector2i(int(design.get("width", 1)), int(design.get("height", 1)))


## Lo que cuesta con bloques de [cell_size] m.
static func cost(design: Dictionary, cell_size: float) -> Dictionary:
	var size := cells(design)
	var area := size.x * size.y * cell_size * cell_size
	return {
		&"wood_01": maxi(1, ceili(area * WOOD_PER_M2)),
		&"raw_hide": maxi(1, ceili(area / M2_PER_HIDE)),
	}


## Lo que cuesta la puesta con [state] (el de su colocable, con su tamaño de celda).
static func cost_of_state(item_id: StringName, state: Dictionary) -> Dictionary:
	return cost(normalize(state, item_id), float(state.get("cell", 1.0)))
