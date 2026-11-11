class_name GroundPath extends RefCounted

## Camino a pie para quien anda en línea recta (Companion) cuando esa línea no avanza: dentro de una
## casa, detrás de una pared, entre rocas. A* sobre una rejilla de CELL m en el plano tangente del sitio
## (a esta escala el planeta es plano), de casilla en casilla y solo por las que explora: cada una mira
## el suelo con un rayo desde la altura de la que viene (escalones de hasta STEP m hacia arriba y de
## hasta DROP m hacia abajo, saltando: de un tejado al que ha subido se baja; una casa de dos plantas
## sigue la planta en la que se está) y si cabe el cuerpo, una cápsula de RADIUS m hasta HEIGHT
## m. El hueco de una puerta cerrada (WoodenDoor) cuenta como paso: quien sigue el camino la abre.
## Busca hasta MAX_NODES casillas a menos de MAX_RANGE m de donde sale; sin camino, devuelve [].
## Después se acorta: de cada punto, al más lejano que se ve en línea recta por la rejilla.

const CELL := 0.5
const MAX_NODES := 1500
const MAX_RANGE := 35.0
const RADIUS := 0.3
const HEIGHT := 1.7
const STEP := 0.55
## El rayo del suelo empieza esto (m) por encima de la casilla de la que viene y baja hasta DROP.
const PROBE_UP := 0.8
const DROP := 4.0
const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []
var _origin := Vector3.ZERO
var _up := Vector3.UP
var _ax := Vector3.RIGHT
var _az := Vector3.BACK
## Casilla -> su suelo (mundo) o null (no se pisa).
var _ground := {}
var _doors: Array[WoodenDoor] = []
## Por qué no se pisan las casillas, de la última búsqueda (para depurar): sin suelo, escalón, choca.
static var last_stats := {}
var _stats := {"expanded": 0, "no_ground": 0, "step": 0, "blocked": 0, "blockers": {}}
var _capsule := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


## El camino (puntos en el suelo, mundo) de [from] hasta llegar a menos de [reach] m (en el plano) de
## [to], para [body] (que no cuenta como obstáculo), con [up] el del planeta. [] si no lo hay.
static func find(body: CollisionObject3D, from: Vector3, to: Vector3, up: Vector3, reach: float) -> PackedVector3Array:
	var path := GroundPath.new()
	return path._search(body, from, to, up, reach)


func _search(body: CollisionObject3D, from: Vector3, to: Vector3, up: Vector3, reach: float) -> PackedVector3Array:
	_space = body.get_world_3d().direct_space_state
	_exclude = [body.get_rid()]
	_origin = from
	_up = up.normalized()
	var toward := (to - from).slide(_up)
	_ax = toward.normalized() if toward.length_squared() > 1e-6 else _up.cross(Vector3.FORWARD).normalized()
	_az = _up.cross(_ax).normalized()
	_capsule.radius = RADIUS
	_capsule.height = HEIGHT - 0.3
	_query.shape = _capsule
	_query.collision_mask = PhysicsLayers.WORLD
	_query.collide_with_areas = false
	_query.exclude = _exclude
	for node in body.get_tree().get_nodes_in_group(WoodenDoor.GROUP):
		var door := node as WoodenDoor
		if door != null and door.global_position.distance_to(from) < MAX_RANGE + 5.0:
			_doors.append(door)
	# Se sale del suelo que tiene debajo (en el aire, saltando o cayendo, no de sus pies), aunque ahí no
	# quepa (rozando una pared): es para salir de ahí.
	var start := Vector2i.ZERO
	var below := _space.intersect_ray(PhysicsRayQueryParameters3D.create(from + _up * 0.3, from - _up * (DROP + 2.0),
		PhysicsLayers.WORLD, _exclude))
	_ground[start] = below.position as Vector3 if not below.is_empty() else from
	var goal_flat := Vector2((to - from).dot(_ax), (to - from).dot(_az))
	var came := {}
	var cost := {start: 0.0}
	var heap: Array = []
	_push(heap, goal_flat.length(), start)
	var expanded := 0
	var found := Vector2i(-99999, 0)
	while not heap.is_empty() and expanded < MAX_NODES:
		var cell: Vector2i = _pop(heap)
		expanded += 1
		_stats.expanded = expanded
		if (Vector2(cell) * CELL).distance_to(goal_flat) <= reach:
			found = cell
			break
		for step in NEIGHBORS:
			var next := cell + step
			if Vector2(next).length() * CELL > MAX_RANGE:
				continue
			if not _walkable(next, cell):
				continue
			# En diagonal, sin cortar esquinas.
			if step.x != 0 and step.y != 0 and (not _walkable(Vector2i(cell.x + step.x, cell.y), cell)
					or not _walkable(Vector2i(cell.x, cell.y + step.y), cell)):
				continue
			var g: float = cost[cell] + (1.4142 if step.x != 0 and step.y != 0 else 1.0)
			if g < float(cost.get(next, INF)):
				cost[next] = g
				came[next] = cell
				_push(heap, g + (Vector2(next) * CELL).distance_to(goal_flat) / CELL, next)
	last_stats = _stats
	if found.x == -99999:
		return PackedVector3Array()
	var cells: Array[Vector2i] = [found]
	while came.has(cells.back()):
		cells.append(came[cells.back()])
	cells.reverse()
	return _shorten(cells)


## Si se pisa [cell] viniendo de [parent] (ya pisable): suelo a un escalón y sitio para el cuerpo.
func _walkable(cell: Vector2i, parent: Vector2i) -> bool:
	if not _ground.has(cell):
		_ground[cell] = _floor_at(cell, _ground[parent])
	return _ground[cell] != null


## El suelo de [cell] buscado desde la altura de [from] (mundo), o null si no hay o no cabe.
func _floor_at(cell: Vector2i, from: Variant) -> Variant:
	if from == null:
		return null
	var base := from as Vector3
	var flat := _origin + _ax * (cell.x * CELL) + _az * (cell.y * CELL)
	var p := flat + _up * (base - flat).dot(_up)
	var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(p + _up * PROBE_UP, p - _up * DROP,
		PhysicsLayers.WORLD, _exclude))
	if hit.is_empty():
		_stats.no_ground += 1
		return null
	var ground: Vector3 = hit.position
	var rise := (ground - base).dot(_up)
	if rise > STEP or rise < -DROP:
		_stats.step += 1
		return null
	if _in_doorway(ground):
		return ground
	var y := _up
	var x := y.cross(_ax).normalized()
	_query.transform = Transform3D(Basis(x, y, x.cross(y)), ground + _up * (0.3 + _capsule.height * 0.5))
	var hits := _space.intersect_shape(_query, 1)
	if hits.is_empty():
		return ground
	_stats.blocked += 1
	var name := str((hits[0].collider as Object).get_class()) + ":" + str((hits[0].collider as Node).name) \
		if hits[0].collider is Node else "?"
	_stats.blockers[name] = int(_stats.blockers.get(name, 0)) + 1
	return null


## Si [point] (mundo) está en el hueco de una puerta cerrada.
func _in_doorway(point: Vector3) -> bool:
	for door in _doors:
		if not is_instance_valid(door) or door.open_side != 0:
			continue
		var local := door.global_transform.affine_inverse() * point
		var size := door_size(door)
		if absf(local.x) < size.x * 0.5 and absf(local.z) < 0.6 and local.y > -0.6 and local.y < size.y:
			return true
	return false


## Ancho y alto (m) del hueco de [door].
static func door_size(door: WoodenDoor) -> Vector2:
	return Vector2(door._cells) * door.cell


## De cada punto, al más lejano que se ve por la rejilla (todas las casillas de en medio pisables).
func _shorten(cells: Array[Vector2i]) -> PackedVector3Array:
	var out := PackedVector3Array()
	var i := 0
	out.append(_ground[cells[0]])
	while i < cells.size() - 1:
		var j := cells.size() - 1
		while j > i + 1 and not _clear(cells[i], cells[j]):
			j -= 1
		i = j
		out.append(_ground[cells[i]])
	return out


func _clear(a: Vector2i, b: Vector2i) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	var previous := a
	for k in range(1, steps + 1):
		var t := float(k) / steps
		var cell := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if cell == previous:
			continue
		if not _walkable(cell, previous):
			return false
		previous = cell
	return true


# --- Montículo (f mínima arriba) ------------------------------------------------------------------

static func _push(heap: Array, f: float, cell: Vector2i) -> void:
	heap.append([f, cell])
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent][0] <= heap[i][0]:
			break
		var swap: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


static func _pop(heap: Array) -> Vector2i:
	var top: Vector2i = heap[0][1]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var smallest := i
		if left < heap.size() and heap[left][0] < heap[smallest][0]:
			smallest = left
		if right < heap.size() and heap[right][0] < heap[smallest][0]:
			smallest = right
		if smallest == i:
			break
		var swap: Array = heap[smallest]
		heap[smallest] = heap[i]
		heap[i] = swap
		i = smallest
	return top
