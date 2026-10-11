class_name FracturedRock
extends Node3D

## Roca que se está picando: en el primer golpe RockMining la cambia por sus trozos de Voronoi
## (RockFracture) colocados tal cual, así que se ve igual. Cada vez que el trabajo llega a un
## trozo, se suelta el más cercano al golpe y cae al suelo como un RockFragment. Lo que se queda
## sin apoyo (sin camino de vecinos hasta un trozo que toca el suelo) cae también.
##
## Los trozos enterrados (con terreno encima de su centro) no se sueltan ni llevan piedras: cuando
## no queda nada fuera, se van con la roca.
##
## Cuelga de RockMining (bajo el terreno): sigue al planeta y al origen flotante. Lleva la escala
## de la roca: los trozos y sus colisiones van en unidades de la malla.

const GROUP := &"fractured_rock"
const DESPAWN_DISTANCE := 170.0
## Holgura bajo un trozo para darlo por apoyado en el suelo (m).
const GROUND_GAP := 0.35

## Los trozos que se pueden soltar: índice -> {body: StaticBody3D, piece, stones: int, grounded}
var _pieces: Dictionary = {}
## Los enterrados: índice -> {body, piece}
var _buried: Dictionary = {}
var _item: ItemData
var _up := Vector3.UP
var _work_per_piece := 10.0
var _work := 0.0
var _despawn_check := 1.0


## Los [pieces] de la roca con la malla en [mesh_xf] (mundo, con su escala), [stones] de [item]
## repartidas entre ellos por volumen y [work] para soltarlos todos. [up]: el del planeta.
## [ignore]: las colisiones de la roca entera, que aún no se ha ido.
func setup(pieces: Array, mesh_xf: Transform3D, item: ItemData, stones: int, work: float, up: Vector3,
		ignore: Array[RID]) -> void:
	name = "FracturedRock"
	_item = item
	_up = up
	global_transform = mesh_xf
	reset_physics_interpolation()
	var exclude: Array[RID] = ignore.duplicate()
	var bodies: Array[StaticBody3D] = []
	for piece in pieces:
		var body := StaticBody3D.new()
		body.collision_layer = TreeFelling.WORLD_LAYER
		body.collision_mask = 0
		body.position = piece.offset
		var visual := MeshInstance3D.new()
		visual.mesh = piece.mesh
		body.add_child(visual)
		var shape := CollisionShape3D.new()
		var convex := ConvexPolygonShape3D.new()
		convex.points = piece.points
		shape.shape = convex
		body.add_child(shape)
		add_child(body)
		bodies.append(body)
		exclude.append(body.get_rid())
	# Alturas (sobre el origen de la roca) del punto más bajo de cada trozo y lo más alto de la roca.
	var lows := PackedFloat32Array()
	var top := -INF
	for i in pieces.size():
		var low := INF
		for point in pieces[i].points:
			var height := (bodies[i].global_transform * (point as Vector3) - global_position).dot(up)
			low = minf(low, height)
			top = maxf(top, height)
		lows.append(low)
	# Qué está enterrado y qué toca el suelo: un rayo desde encima de la roca que baja por el centro
	# de cada trozo hasta un poco por debajo de su punto más bajo.
	var space := get_world_3d().direct_space_state
	for i in pieces.size():
		var center := bodies[i].global_position
		var height := (center - global_position).dot(up)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center + up * (top - height + 1.0),
			center + up * (lows[i] - height - GROUND_GAP), TreeFelling.WORLD_LAYER, exclude))
		if not hit.is_empty() and ((hit.position as Vector3) - center).dot(up) > 0.0:
			_buried[i] = {"body": bodies[i], "piece": pieces[i]}
		else:
			_pieces[i] = {"body": bodies[i], "piece": pieces[i], "stones": 0, "grounded": not hit.is_empty()}
	# Toda enterrada: lo que se ve está en el terreno.
	if _pieces.is_empty():
		for i in _buried:
			_pieces[i] = {"body": _buried[i].body, "piece": _buried[i].piece, "stones": 0, "grounded": true}
		_buried.clear()
	# Sin suelo bajo ningún trozo (la colisión del terreno sin cargar): apoya lo de abajo.
	if _buried.is_empty() and not _pieces.values().any(func(entry: Dictionary) -> bool: return entry.grounded):
		var floor_height := INF
		for i in _pieces:
			floor_height = minf(floor_height, lows[i])
		for i in _pieces:
			_pieces[i].grounded = lows[i] < floor_height + GROUND_GAP
	var keys := _pieces.keys()
	var shares := RockMining.share(stones, keys.map(func(i: int) -> float: return pieces[i].volume))
	for k in keys.size():
		_pieces[keys[k]].stones = shares[k]
	_work_per_piece = work / float(maxi(_pieces.size(), 1))
	add_to_group(GROUP)


## Golpe de [power] por [point] (mundo), dado desde [miner].
func hit(point: Vector3, power: float, miner: Node3D) -> bool:
	if _pieces.is_empty() or power <= 0.0:
		return false
	var toward := (miner.global_position - point) if miner != null else _up
	toward = toward - _up * toward.dot(_up)
	toward = toward.normalized() if toward.length_squared() > 1e-6 else _up
	BlockDebris.burst(self, point + toward * 0.2, (toward + _up).normalized(), 2, 0.2)
	AudioManager.play_material(&"block_impact", &"rock", point,
		{"volume_offset_db": -4.0, "pitch": randf_range(1.05, 1.25)})
	CombatFx.play(&"hit_world", point, {"pitch": randf_range(1.1, 1.3)})
	_work += power
	var loose := 0
	while _work >= _work_per_piece and not _pieces.is_empty():
		_work -= _work_per_piece
		_detach(_nearest(point), toward, loose == 0)
		loose += 1
	if loose > 0:
		for i in _unsupported():
			_detach(i, toward, false)
	if _pieces.is_empty():
		for i in _buried:
			BlockDebris.burst(self, (_buried[i].body as Node3D).global_position, _up, 2, 0.3)
		queue_free()
	return true


## El trozo que se suelta: el más cercano al golpe, algo antes los de arriba.
func _nearest(point: Vector3) -> int:
	var best := -1
	var best_score := INF
	for i in _pieces:
		var center: Vector3 = (_pieces[i].body as Node3D).global_position
		var score := center.distance_to(point) - (center - global_position).dot(_up) * 0.25
		if score < best_score:
			best_score = score
			best = i
	return best


## Los trozos que ya no sostiene nada: sin camino de vecinos hasta uno que toca el suelo o uno
## enterrado.
func _unsupported() -> Array:
	var held := {}
	var open: Array = _buried.keys()
	for i in _pieces:
		if _pieces[i].grounded:
			open.append(i)
	while not open.is_empty():
		var i: int = open.pop_back()
		if held.has(i):
			continue
		held[i] = true
		var entry: Dictionary = _pieces[i] if _pieces.has(i) else _buried[i]
		for j in entry.piece.neighbors:
			if not held.has(j) and (_pieces.has(j) or _buried.has(j)):
				open.append(j)
	return _pieces.keys().filter(func(i: int) -> bool: return not held.has(i))


func _detach(index: int, toward: Vector3, loud: bool) -> void:
	var entry: Dictionary = _pieces[index]
	_pieces.erase(index)
	var body: StaticBody3D = entry.body
	var xf := body.global_transform
	var center := global_position
	var out := xf.origin - center
	out = out - _up * out.dot(_up)
	out = (out.normalized() if out.length_squared() > 1e-6 else toward) * 0.6 + toward * 0.4
	BlockDebris.burst(self, xf.origin, _up, 3 if loud else 1, 0.25)
	if loud:
		AudioManager.play_material(&"block_impact", &"rock", xf.origin, {"pitch": 0.8})
	var exclude: Array[RID] = [body.get_rid()]
	for other in _pieces.values() + _buried.values():
		exclude.append((other.body as StaticBody3D).get_rid())
	var fragment := RockFragment.new()
	get_parent().add_child(fragment)
	fragment.setup(entry.piece.mesh, xf, _item, entry.stones, entry.piece.volume, _up, out.normalized(),
		exclude)
	body.queue_free()


func _physics_process(delta: float) -> void:
	_despawn_check -= delta
	if _despawn_check > 0.0:
		return
	_despawn_check = 1.0
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_to(global_position) > DESPAWN_DISTANCE:
		queue_free()
