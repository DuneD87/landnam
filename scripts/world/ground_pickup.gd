class_name GroundPickup
extends RefCounted

## Lo que se recoge del suelo con la tecla de acción: los objetos del planeta marcados "pickup" en
## su JSON (ramas caídas y piedras pequeñas). Cerca del jugador llevan un cuerpo en
## Planet.PICKUP_LAYER, que no estorba a nadie; al cogerlo se quita de la multimalla del instancer.
## Las piedras dan munición según su tamaño, y las más grandes (escala > MAX_ROCK_SCALE) no se
## levantan.

const Config = preload("res://scripts/config.gd")

const PICK_RANGE := 2.4
const STONE_ID := &"stone_01"
## Piedras: hasta qué escala de instancia se levantan (a escala 1 miden unos 18 cm) y cuántas da
## cada una por unidad de escala.
const MAX_ROCK_SCALE := 3.0
const STONES_PER_SCALE := 1.5

## Todos los planetas con cosas que recoger (la escena tiene más de uno: la Tierra y la Luna). Los
## library_id se repiten entre planetas, así que cada cuerpo se mira en el suyo.
static var _planets: Array[Planet] = []


static func setup(world: Planet) -> void:
	_planets = _planets.filter(func(p: Planet) -> bool: return is_instance_valid(p))
	if world != null and world not in _planets:
		_planets.append(world)


## Recoge lo más cercano a [picker] (a menos de PICK_RANGE m) y lo mete en [inventory]. Falso si
## no había nada al alcance o no cabe.
static func try_pickup(picker: Node3D, inventory: Inventory) -> bool:
	# Todo lo que toca la esfera vale (una rama larga puede tener el centro más lejos que la punta);
	# entre ello, lo de centro más cercano.
	var best: VoxelInstancerRigidBody = null
	var best_d := INF
	for body in _nearby(picker, PICK_RANGE):
		var d := body.global_position.distance_to(picker.global_position)
		if d < best_d:
			best = body
			best_d = d
	if best == null:
		return false
	var item_id := _item_of(best)
	var count := 1
	if item_id == STONE_ID:
		count = clampi(roundi(best.global_basis.get_scale().x * STONES_PER_SCALE), 1, 5)
	if inventory.add_item(Config.get_item(item_id), count) == count:
		return false
	AudioManager.play_material(&"block_impact", &"rock" if item_id == STONE_ID else &"wood",
		best.global_position, {"volume_offset_db": -14.0})
	best.queue_free_and_notify_instancer()
	return true


## Lo que se puede recoger a menos de [reach] m de [around].
static func _nearby(around: Node3D, reach: float) -> Array[VoxelInstancerRigidBody]:
	var found: Array[VoxelInstancerRigidBody] = []
	var shape := SphereShape3D.new()
	shape.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = around.global_position
	query.collision_mask = Planet.PICKUP_LAYER
	for hit in around.get_world_3d().direct_space_state.intersect_shape(query, 256):
		var body := hit.collider as VoxelInstancerRigidBody
		var item_id := _item_of(body)
		if item_id == &"":
			continue
		if item_id == STONE_ID and body.global_basis.get_scale().x > MAX_ROCK_SCALE:
			continue
		found.append(body)
	return found


## Para la consola: lo recogible a menos de 12 m, por objeto.
static func report(around: Node3D) -> String:
	var counts: Dictionary = {}
	for body in _nearby(around, 12.0):
		var item_id := _item_of(body)
		counts[item_id] = counts.get(item_id, 0) + 1
	if counts.is_empty():
		return "Nada que recoger a 12 m."
	return "Recogible a 12 m: %s" % str(counts)


## Lo que da [body] al recogerlo, según el planeta al que pertenece; vacío si no es recogible.
static func _item_of(body: VoxelInstancerRigidBody) -> StringName:
	if body == null:
		return &""
	for world in _planets:
		if is_instance_valid(world) and world.voxel_instancer != null and world.voxel_instancer.is_ancestor_of(body):
			return world.pickup_library_ids.get(body.get_library_item_id(), &"")
	return &""
