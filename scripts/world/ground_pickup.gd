class_name GroundPickup
extends RefCounted

## Lo que se recoge del suelo con la tecla de acción: los objetos del planeta marcados "pickup" en
## su JSON (ramas caídas, piedras pequeñas, los arbustos, que dan fibra, y las hierbas como la
## milenrama). Cerca del jugador llevan un cuerpo en PhysicsLayers.PICKUP, que no estorba a nadie; al
## cogerlo se quita de la multimalla del instancer. Una rama caída da un puñado de ramas (BRANCHES),
## las piedras dan munición según su tamaño, y las más grandes (escala > MAX_ROCK_SCALE) no se
## levantan. Las plantas (PLANTS) solo se arrancan mirándolas: hay tantas, sobre todo en las
## orillas, que si no se llevarían la tecla de beber o de recoger lo soltado. Todo suena igual al
## recogerlo (item_pickup), como lo soltado.

const PICK_RANGE := 2.4
const STONE_ID := &"stone_01"
const BRANCH_ID := &"branch_01"
const PICKING := &"ground_pickup_claimed"
## Ramas que da cada rama caída (al azar entre los dos).
const BRANCHES := Vector2i(5, 10)
## Piedras: hasta qué escala de instancia se levantan (a escala 1 miden unos 18 cm) y cuántas da
## cada una por unidad de escala.
const MAX_ROCK_SCALE := 3.0
const STONES_PER_SCALE := 1.5
## Plantas: lo que da una mata por unidad de escala (entre 1 y 4), y lo cerca del centro de la vista
## que tiene que estar para arrancarla (grados).
const FIBER_ID := &"plant_fiber"
const PLANTS := {FIBER_ID: 2.5, &"yarrow": 1.6}
const LOOK_ANGLE := 30.0

## Todos los planetas con cosas que recoger (la escena tiene más de uno: la Tierra y la Luna). Los
## library_id se repiten entre planetas, así que cada cuerpo se mira en el suyo.
static var _planets: Array[Planet] = []


static func setup(world: Planet) -> void:
	# Sin filter: un planeta liberado no entra en un parámetro tipado.
	for i in range(_planets.size() - 1, -1, -1):
		if not is_instance_valid(_planets[i]):
			_planets.remove_at(i)
	if world != null and world not in _planets:
		_planets.append(world)


## Recoge lo más cercano a [picker] (a menos de PICK_RANGE m) y lo mete en [inventory]; lo que no
## cabe se queda en el suelo (DroppedItem). Falso si no había nada al alcance o no cabe nada. Los
## arbustos, solo si la vista ([view_from] hacia [view_dir]) apunta a ellos.
static func try_pickup(picker: Node3D, inventory: Inventory, view_from: Vector3 = Vector3.ZERO,
		view_dir: Vector3 = Vector3.ZERO) -> bool:
	# Todo lo que toca la esfera vale (una rama larga puede tener el centro más lejos que la punta);
	# entre ello, lo de centro más cercano.
	var best: VoxelInstancerRigidBody = null
	var best_d := INF
	for body in _nearby(picker, PICK_RANGE):
		if PLANTS.has(_item_of(body)) and not _looked_at(body, view_from, view_dir):
			continue
		var d := body.global_position.distance_to(picker.global_position)
		if d < best_d:
			best = body
			best_d = d
	if best == null:
		return false
	var item_id := _item_of(best)
	var data := ItemCatalog.get_item(item_id)
	var count := 1
	if item_id == STONE_ID:
		count = clampi(roundi(best.global_basis.get_scale().x * STONES_PER_SCALE), 1, 5)
	elif item_id == BRANCH_ID:
		count = randi_range(BRANCHES.x, BRANCHES.y)
	elif PLANTS.has(item_id):
		count = clampi(roundi(best.global_basis.get_scale().x * float(PLANTS[item_id])), 1, 4)
	# Reserva el cuerpo antes de emitir las señales de add_item.
	best.set_meta(PICKING, true)
	var left := inventory.add_item(data, count)
	if left == count:
		best.remove_meta(PICKING)
		return false
	if left > 0:
		var up := (picker as CharacterBody3D).up_direction if picker is CharacterBody3D else picker.global_basis.y
		DroppedItem.spawn_at(picker, data, left, best.global_position + up * 0.3, -up)
	AudioManager.play_ui(&"item_pickup")
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
	query.collision_mask = PhysicsLayers.PICKUP
	for hit in around.get_world_3d().direct_space_state.intersect_shape(query, 256):
		var body := hit.collider as VoxelInstancerRigidBody
		if body == null or body.is_queued_for_deletion() or body.has_meta(PICKING):
			continue
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
		return TranslationServer.translate(&"CON_LITTER_NONE")
	return TranslationServer.translate(&"CON_LITTER_REPORT") % str(counts)


## Si la vista apunta a [body] (al centro de su forma, que en una mata está a media altura).
static func _looked_at(body: VoxelInstancerRigidBody, view_from: Vector3, view_dir: Vector3) -> bool:
	if view_dir == Vector3.ZERO:
		return false
	var aim := body.global_position
	for child in body.get_children():
		if child is CollisionShape3D:
			aim = (child as CollisionShape3D).global_position
			break
	return rad_to_deg(view_dir.angle_to(aim - view_from)) <= LOOK_ANGLE


## Lo que da [body] al recogerlo, según el planeta al que pertenece; vacío si no es recogible.
static func _item_of(body: VoxelInstancerRigidBody) -> StringName:
	if body == null:
		return &""
	for world in _planets:
		if is_instance_valid(world) and world.voxel_instancer != null and world.voxel_instancer.is_ancestor_of(body):
			return world.pickup_library_ids.get(body.get_library_item_id(), &"")
	return &""
