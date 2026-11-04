class_name WoodenDoor
extends Node3D

## Hoja de madera que cierra un hueco de una construcción (DoorTrait): la puerta, de pie, y la
## trampilla, para techos, suelos y ventanas, con las medidas que se le dieron en el menú de bloques
## (DoorDesign, en celdas de su grid). Es un colocable (BuildingSystem): su marco
## es el del colocable, con el origen en el centro del canto de abajo de la hoja (en medio de su grueso;
## la hoja va a ras de la cara del hueco del lado de quien la puso), +Y a lo largo de ella, +Z hacia
## delante (hacia quien la puso; los travesaños van detrás) y las bisagras en el canto de +X o de -X. La malla (DoorMesh) es la de una celda de 1 m, escalada a la de su grid. USAR la abre
## hacia el lado contrario de quien la empuja y la vuelve a cerrar. Gira con ella su ancla
## (GridBase.pose_prop), así que abierta choca donde está y se apunta donde se ve.

## Las puestas (no los fantasmas del martillo).
const GROUP := &"doors"
## Lo que gira abierta y lo que tarda en abrirse o cerrarse.
const OPEN_ANGLE := deg_to_rad(90.0)
const SWING_TIME := 0.45
## Desde dónde se abre (m, del pecho a lo apuntado).
const REACH := 3.0
## Lo más que baja por el hueco una puerta puesta apuntando a una jamba (celdas).
const MAX_DROP := 16

@export var item_id := &"wooden_door"

var cell := 1.0
var hinge := 1
## Hacia dónde está abierta: +1 hacia delante (+Z), -1 hacia atrás y 0 cerrada.
var open_side := 0
var _cells := Vector2i(1, 3)
## Lo abierta que se ve, de 0 a 1, y hacia qué lado giró la última vez (para cerrar por el mismo).
var _amount := 0.0
var _swing_side := 1
var _mesh: MeshInstance3D


func _ready() -> void:
	_cells = DoorDesign.default_cells(item_id)
	_mesh = MeshInstance3D.new()
	add_child(_mesh)
	_rebuild()
	# El fantasma del martillo no cuelga de un colocable: no se abre.
	if _key() != "":
		add_to_group(GROUP)
	set_process(false)


## {"cell": lado de la celda de su grid, "width" y "height": sus medidas en celdas (DoorDesign),
## "hinge": ±1, "open": -1, 0 o +1}. Lo de un colocable guardado sale ya en su sitio, sin el giro.
func restore_prop_state(state: Dictionary) -> void:
	var new_cell := float(state.get("cell", cell))
	var new_hinge := -1 if int(state.get("hinge", hinge)) < 0 else 1
	var new_cells := DoorDesign.cells(DoorDesign.normalize(state, item_id))
	if not is_equal_approx(new_cell, cell) or new_hinge != hinge or new_cells != _cells:
		cell = new_cell
		hinge = new_hinge
		_cells = new_cells
		_rebuild()
	open_side = signi(int(state.get("open", 0)))
	if open_side != 0:
		_swing_side = open_side
	_amount = absf(open_side)
	if open_side != 0 and _key() != "":
		# Recién puesta, la grid aún no la tiene apuntada.
		_pose.call_deferred()


## Abierta, la cierra; cerrada, la abre hacia el lado contrario de [from] (en mundo: quien la empuja).
func toggle(from: Vector3) -> void:
	var grid := _grid()
	var info: Dictionary = grid.get_all_props().get(_key(), {}) if grid != null else {}
	if info.is_empty():
		return
	var frame: Transform3D = grid.get_grid_world_transform() * info["local_transform"]
	var center := frame * (Vector3(0.0, _cells.y * 0.5, 0.0) * cell)
	if open_side != 0:
		open_side = 0
	else:
		open_side = -1 if (from - center).dot(frame.basis.z) > 0.0 else 1
		_swing_side = open_side
	var state: Dictionary = info.get("state", {}).duplicate(true)
	state["open"] = open_side
	grid.set_prop_state(_key(), state)
	AudioManager.play_3d(&"door_open" if open_side != 0 else &"door_close", center)
	set_process(true)


func _process(delta: float) -> void:
	var target := absf(open_side)
	_amount = move_toward(_amount, target, delta / SWING_TIME)
	_pose()
	if is_equal_approx(_amount, target):
		set_process(false)


func _pose() -> void:
	var grid := _grid()
	if grid != null:
		grid.pose_prop(_key(), swing(_amount))


## Lo que gira la hoja abierta [amount] (0 cerrada, 1 abierta del todo), en el marco del colocable:
## alrededor del canto de las bisagras, por la cara de las tablas del lado al que se abre. Hacia
## delante sale entera del muro; hacia atrás gira por dentro del hueco pegada a la jamba, con los
## travesaños metidos en ella. De las dos maneras deja libre 0,95 del ancho de una celda.
func swing(amount: float) -> Transform3D:
	if amount <= 0.0:
		return Transform3D.IDENTITY
	var pivot := Vector3(hinge * _cells.x * 0.5, 0.0, DoorMesh.THICKNESS * 0.5 * _swing_side) * cell
	var angle := OPEN_ANGLE * smoothstep(0.0, 1.0, amount) * _swing_side * hinge
	return Transform3D(Basis(Vector3.UP, angle), pivot) * Transform3D(Basis.IDENTITY, -pivot)


func _rebuild() -> void:
	_mesh.mesh = DoorMesh.make(_cells, hinge)
	_mesh.scale = Vector3.ONE * cell


func _key() -> String:
	var anchor := get_parent()
	return str(anchor.get_meta(&"prop_key", "")) if anchor != null else ""


func _grid() -> GridBase:
	var anchor := get_parent()
	if anchor == null or not anchor.has_meta(&"grid_id"):
		return null
	return GridManager.get_grid(anchor.get_meta(&"grid_id"))


static func door_of(id: StringName) -> DoorTrait:
	var item := ItemCatalog.get_item(id)
	return item.get_trait(DoorTrait) as DoorTrait if item != null else null


## La caja con la que choca cerrada una hoja de [cells] (las tablas, sin los travesaños), en el marco
## del colocable.
static func collider_size(cells: Vector2i, cell_size: float) -> Vector3:
	return Vector3(cells.x, cells.y, DoorMesh.THICKNESS) * cell_size


## La hoja que se apunta con [ray_hit] (un intersect_ray), o null.
static func aimed(ray_hit: Dictionary) -> WoodenDoor:
	var body := ray_hit.get("collider") as CollisionObject3D
	if body == null:
		return null
	var anchor: Node = body
	# En un barco el ancla es una forma del casco.
	if not body.has_meta(&"prop_key") and ray_hit.has("shape"):
		anchor = body.shape_owner_get_owner(body.shape_find_owner(int(ray_hit["shape"])))
	if anchor == null:
		return null
	for child in anchor.get_children():
		if child is WoodenDoor:
			return child
	return null


## Cómo cierra una hoja de [cells] el hueco de delante de la cara [face] del bloque [block] de [grid],
## apuntada en [aim] y mirando hacia [view] (los dos en el espacio de la grid): {"transform": el marco
## del colocable en la grid, "hinge": ±1, "cells": las medidas con que va, "ok": si cabe}, o {} si
## delante de la cara hay un bloque.
## - El plano: de frente al eje por el que se atraviesa el hueco (libre a los dos lados); si no está
##   claro, el que más de cara se mira. Lo de delante, hacia quien la pone, y a ras de la cara del
##   hueco de ese lado: por fuera del muro, si se pone desde fuera. Con [flip], como puesta desde el
##   otro lado: a ras de la otra cara, mirando hacia allá y con las bisagras en el mismo sitio.
## - Tumbada (con [lying], o una trampilla en el agujero de un forjado): a ras de arriba, para
##   pisarla, con las tablas hacia arriba; con [flip], a ras de abajo. Una trampilla, o una hoja con
##   [lying], apuntada por abajo o por arriba a un forjado junto al borde de un agujero cierra el
##   agujero (_hole_beside); una trampilla no, si delante de la cara hay un hueco de muro (una
##   ventana, apuntando al alféizar o al dintel).
## - [upright] (una puerta): de pie, con el alto (cells.y) en vertical. Si no (una trampilla), en el
##   plano del hueco, y si no cabe como es, girada un cuarto de vuelta.
## - Las bisagras, en el bloque apuntado. En una puerta apuntando al suelo o al dintel, en el lado de
##   la celda que se apunta; si así no cabe (una puerta ancha), en el otro.
## - Una puerta apuntando a una jamba baja por el hueco mientras siga la jamba: hasta el suelo, o hasta
##   el pie del muro si está sobre el terreno. Apuntando al dintel, cuelga de él.
## - Cabe si las celdas que cierra están vacías y no hay otra hoja en ellas.
static func fit(grid: GridBase, block: Vector3i, face: Vector3i, aim: Vector3, view: Vector3,
		cells: Vector2i, upright: bool, flip: bool = false, lying: bool = false) -> Dictionary:
	var flat := lying
	if (lying or not upright) and face.y != 0:
		var edge := _hole_beside(grid, block, aim)
		if edge != Vector3i.ZERO and (lying or not _walled(grid, block + face)):
			face = edge
			flat = true
		elif lying:
			return {}
	if flat:
		upright = false
	var first := block + face
	if grid.has_block(first):
		return {}
	var candidates: Array[Vector3] = []
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		if is_zero_approx(axis.dot(Vector3(face))) and not (upright and axis == Vector3.UP):
			candidates.append(axis)
	var through: Array[Vector3] = []
	for axis in candidates:
		if not grid.has_block(first + Vector3i(axis)) and not grid.has_block(first - Vector3i(axis)):
			through.append(axis)
	var pool := through if through.size() > 0 else candidates
	var normal: Vector3 = pool[0]
	for axis in pool:
		if absf(axis.dot(view)) > absf(normal.dot(view)):
			normal = axis
	if normal == Vector3.UP or flat:
		normal = Vector3.DOWN if flip else Vector3.UP
	elif (normal.dot(view) > 0.0) != flip:
		normal = -normal

	# Lo que se prueba, por orden: como se apunta y, si no cabe, la otra manera.
	var tries: Array = []
	if upright and face.y != 0:
		var across := Vector3.UP.cross(normal)
		var middle := (Vector3(first) + Vector3.ONE * 0.5) * grid.cell_size
		var side := across if (aim - middle).dot(across) >= 0.0 else -across
		tries = [[side, cells, false], [-side, cells, false]]
	elif upright:
		tries = [[-Vector3(face), cells, false]]
	else:
		# Tumbada o en el plano del hueco, a lo largo de las bisagras puede crecer hacia los dos lados.
		for size: Vector2i in ([cells] if cells.x == cells.y else [cells, Vector2i(cells.y, cells.x)]):
			tries.append([-Vector3(face), size, false])
			if size.y > 1:
				tries.append([-Vector3(face), size, true])
	var best := {}
	for attempt: Array in tries:
		var result := _frame(grid, block, face, normal, attempt[0], attempt[1], upright, attempt[2])
		if best.is_empty():
			best = result
		if result["ok"]:
			return result
	return best


## Hacia dónde está el agujero del forjado junto al que se apunta [block] por abajo o por arriba (en
## [aim]): la celda de al lado vacía, por el borde más cercano a lo apuntado, con nada encima ni debajo
## y con forjado por otro lado más (si no, es el aire de fuera del borde). Vector3i.ZERO si no hay.
static func _hole_beside(grid: GridBase, block: Vector3i, aim: Vector3) -> Vector3i:
	var off := aim / grid.cell_size - (Vector3(block) + Vector3.ONE * 0.5)
	var sides: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]
	sides.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return off.dot(Vector3(a)) > off.dot(Vector3(b)))
	for side in sides:
		var hole := block + side
		if off.dot(Vector3(side)) <= 0.0 or grid.has_block(hole) or grid.has_block(hole + Vector3i.UP) \
				or grid.has_block(hole + Vector3i.DOWN):
			continue
		var rim := 0
		for around in sides:
			rim += 1 if grid.has_block(hole + around) else 0
		if rim >= 2:
			return side
	return Vector3i.ZERO


## Si [cell] es un hueco de muro: con bloques a los dos lados en X o en Z (una ventana, una puerta).
static func _walled(grid: GridBase, cell: Vector3i) -> bool:
	for axis in [Vector3i.RIGHT, Vector3i.BACK]:
		if grid.has_block(cell + axis) and grid.has_block(cell - axis):
			return true
	return false


## El marco de una hoja de [cells] de frente a [normal] y con las bisagras hacia [side], que cierra el
## hueco de delante de la cara [face] del bloque [block]: a lo largo de las bisagras crece hacia su +Y
## o, con [back], hacia el otro lado. Ver fit.
static func _frame(grid: GridBase, block: Vector3i, face: Vector3i, normal: Vector3, side: Vector3,
		cells: Vector2i, upright: bool, back: bool = false) -> Dictionary:
	var first := block + face
	var length := normal.cross(side)
	if length.y < -0.5:
		length = -length
	var width := length.cross(normal)
	var hinge_sign := 1 if width.dot(side) > 0.0 else -1

	var base := first
	if upright and cells.y > 1:
		if face == Vector3i.DOWN:
			base = first - Vector3i.UP * (cells.y - 1)
		elif face.y == 0:
			for k in MAX_DROP:
				if grid.has_block(base + Vector3i.DOWN) or not grid.has_block(block + base - first + Vector3i.DOWN):
					break
				base += Vector3i.DOWN
	if back:
		base -= Vector3i(length) * (cells.y - 1)
	var cs := grid.cell_size
	var center := (Vector3(base) + Vector3.ONE * 0.5 - side * (cells.x - 1) * 0.5
		+ length * (cells.y - 1) * 0.5) * cs
	var flush := normal * (1.0 - DoorMesh.THICKNESS) * 0.5 * cs
	var xform := Transform3D(Basis(width, length, normal), center + flush - length * cells.y * cs * 0.5)

	var slots := {}
	var ok := true
	for slot in slot_cells(xform, cells, cs):
		slots[slot] = true
		ok = ok and not grid.has_block(slot)
	for info: Dictionary in grid.get_all_props().values():
		if not ok or door_of(info["item_id"]) == null:
			continue
		var other := DoorDesign.cells(DoorDesign.normalize(info.get("state", {}), info["item_id"]))
		for slot in slot_cells(info["local_transform"], other, cs):
			ok = ok and not slots.has(slot)
	return {"transform": xform, "hinge": hinge_sign, "cells": cells, "ok": ok}


## Las celdas que cierra una hoja de [cells] con el marco [xform] (en la grid): las de detrás de ella,
## que va a ras de su cara.
static func slot_cells(xform: Transform3D, cells: Vector2i, cell_size: float) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var depth := -(1.0 - DoorMesh.THICKNESS) * 0.5
	for i in cells.x:
		for j in cells.y:
			var p := xform * (Vector3(i + 0.5 - cells.x * 0.5, j + 0.5, depth) * cell_size)
			out.append(Vector3i((p / cell_size).floor()))
	return out
