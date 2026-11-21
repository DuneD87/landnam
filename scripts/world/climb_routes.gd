class_name ClimbRoutes extends RefCounted

## Lo que ha trepado el jugador (ClimbController), para que el grupo suba detrás por el mismo sitio
## (Companion: _to_route, _climb_step): los puntos por los que ha pasado su cuerpo agarrado a la pared o
## a una escala, cada SAMPLE m (marco del terreno), la normal de la pared en cada uno y dónde ha acabado
## de pie al coronar, con hacia dónde mira. Mientras trepa la ruta está abierta (done = false): el grupo
## va al pie y espera. Si se suelta sin coronar, baja (a una escala desde arriba) o trepa por un barco (se
## mueve), se tira; también si no sube al menos MIN_RISE m (lo que se sube de un salto no hace falta
## trepar). Duran LIFE s y se guardan las KEEP últimas.
## Suben de uno en uno: el siguiente empieza GAP s después del anterior (next).

const SAMPLE := 0.25
const MIN_RISE := 1.5
const LIFE := 180.0
const KEEP := 4
const GAP := 1.6
## Quien la busca (find_for): su pie a menos de REACH m en el plano, él por debajo de donde acaba (o
## del jugador, si aún trepa) al menos BELOW m, y el jugador a menos de REACH m de donde acaba (arriba:
## si ha vuelto a bajar por otro sitio, no se sube).
const REACH := 30.0
const BELOW := 1.5

## {"points", "normals": PackedVector3Array, "stand": Vector3 (INF hasta coronar), "facing": Vector3,
## "done": bool, "time": s, "next": s}.
var routes: Array[Dictionary] = []
var _open := {}
var _topped := false
## Lo que trepa ahora no vale (barco, bajada): hasta que suelte.
var _spoiled := false
## El reloj de las rutas (s de física: va con Engine.time_scale y se para con el juego).
var clock := 0.0


## Cada paso de física: lo que hace [player] (su "climb", ClimbController) sobre [terrain].
func update(player: Node3D, terrain: Node3D, delta: float) -> void:
	clock += delta
	var t := clock
	for i in range(routes.size() - 1, -1, -1):
		if routes[i].done and t - float(routes[i].time) > LIFE:
			routes.remove_at(i)
	var climb: Object = player.get("climb")
	if climb == null or not climb.is_active():
		_close()
		return
	if _spoiled:
		return
	if climb.on_ship() or climb.descending():
		_discard()
		_spoiled = true
		return
	var to_local := terrain.global_transform.affine_inverse()
	if _open.is_empty():
		_open = {"points": PackedVector3Array(), "normals": PackedVector3Array(), "stand": Vector3.INF,
			"facing": Vector3.ZERO, "done": false, "time": t, "next": 0.0}
		routes.append(_open)
		while routes.size() > KEEP:
			routes.remove_at(0)
		_topped = false
	var here := to_local * player.global_position
	var normal := (to_local.basis * (climb.wall_normal() as Vector3)).normalized()
	if climb.topping_up():
		if not _topped:
			_topped = true
			_add(here, normal)
			var frame: Transform3D = climb.top_frame()
			_open.stand = to_local * frame.origin
			_open.facing = (to_local.basis * frame.basis.z).normalized()
		return
	var points: PackedVector3Array = _open.points
	if points.is_empty() or points[points.size() - 1].distance_to(here) >= SAMPLE:
		_add(here, normal)


## La ruta por la que puede subir [c] hacia el jugador, o {} (la más reciente que valga).
func find_for(c: Companion, terrain: Node3D, player: Node3D) -> Dictionary:
	var up := c.up_direction
	for i in range(routes.size() - 1, -1, -1):
		var r: Dictionary = routes[i]
		var points: PackedVector3Array = r.points
		if points.is_empty():
			continue
		var foot := terrain.global_transform * points[0]
		if (foot - c.global_position).slide(up).length() > REACH:
			continue
		var top: Vector3 = terrain.global_transform * (r.stand as Vector3) if r.done else player.global_position
		if (top - c.global_position).dot(up) < BELOW or player.global_position.distance_to(top) > REACH:
			continue
		return r
	return {}


## Si [r] sigue siendo una ruta (no se ha tirado ni caducado).
func has(r: Dictionary) -> bool:
	for route in routes:
		if is_same(route, r):
			return true
	return false


## Los Packed*Array salen copiados del diccionario: se añade a la copia y se vuelve a guardar.
func _add(point: Vector3, normal: Vector3) -> void:
	var points: PackedVector3Array = _open.points
	var normals: PackedVector3Array = _open.normals
	points.append(point)
	normals.append(normal)
	_open.points = points
	_open.normals = normals


## Ha soltado: si coronó hacia arriba, la ruta queda hecha; si no, se tira.
func _close() -> void:
	_spoiled = false
	if _open.is_empty():
		return
	var points: PackedVector3Array = _open.points
	var stand: Vector3 = _open.stand
	if _topped and stand.is_finite() and not points.is_empty() \
			and (stand - points[0]).dot(stand.normalized()) >= MIN_RISE:
		_open.done = true
		_open.time = clock
		_open = {}
	else:
		_discard()
	_topped = false


func _discard() -> void:
	for i in range(routes.size() - 1, -1, -1):
		if is_same(routes[i], _open):
			routes.remove_at(i)
	_open = {}
	_topped = false
