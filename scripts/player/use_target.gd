class_name UseTarget
extends RefCounted

## Lo que la E usa cuando se apunta directamente a algo: el rayo del centro de la pantalla se prueba
## contra el volumen de cada cosa usable al alcance (lechos, cofres, tronos, hogueras, hornos,
## bancos, botines, colonos y aldeanos, cadáveres, lo soltado, las lanzas clavadas y lo que se recoge
## del suelo) y gana la primera que atraviesa. Muchas de ellas no tienen colisión, así que no basta
## el raycast físico; este solo sirve para saber si algo se interpone (una pared).

## Alcance desde el pecho hasta el punto más cercano del volumen (m).
const REACH := 2.6
## Lo que se agranda cada caja, para que lo pequeño no exija puntería de píxel (m).
const PAD := 0.12
## Personas (colonos, aldeanos): cápsula vertical desde los pies.
const PERSON_LOW := 0.2
const PERSON_HIGH := 1.7
const PERSON_RADIUS := 0.4
## Cadáveres: esfera alrededor del centro del cuerpo, como mínimo de este radio.
const CORPSE_RADIUS := 0.6
## Cambiar la clave invalida las cajas antiguas si el script se recarga durante la partida.
const BOX_META := &"use_target_geometry_box_v2"


## Lo que se apunta y está al alcance, o null. [ray_hit] es el raycast físico de la cámara (vacío si
## no da en nada cerca).
static func aimed(player: PlayerController, from: Vector3, dir: Vector3, ray_hit: Dictionary) -> Node:
	var chest := player.global_position - player.gravity_direction * 1.0
	var tree := player.get_tree()
	# En tercera persona la cámara va detrás: lo que el rayo cruza antes de llegar a la altura del
	# jugador (un colono a su espalda) no se está mirando: el rayo arranca ahí.
	var near_t := maxf((chest - from).dot(dir) - 0.5, 0.0)
	from += dir * near_t
	var best: Node = null
	var best_t := INF
	var wall_t := INF
	var wall: Node = null
	if not ray_hit.is_empty():
		wall = ray_hit.get("collider") as Node
		wall_t = (ray_hit["position"] - from).dot(dir)
		if wall is ItemPhysics and chest.distance_to(ray_hit["position"]) <= REACH:
			best = wall
			best_t = wall_t
		# En un barco muchas piezas comparten cuerpo físico: solo la forma golpeada puede
		# pertenecer al objeto, no cualquier pared del casco que sea ancestro suyo.
		if wall is CollisionObject3D and ray_hit.has("shape"):
			var body := wall as CollisionObject3D
			var owner_id := body.shape_find_owner(int(ray_hit["shape"]))
			var shape_node := body.shape_owner_get_owner(owner_id) as Node
			if shape_node != null:
				wall = shape_node

	var boxed: Array[Node3D] = []
	for group in [Bedroll.GROUP, Storage.GROUP, Throne.GROUP, Campfire.GROUP, Furnace.GROUP,
			Workstation.GROUP, DeathLoot.GROUP, DroppedItem.GROUP, WoodenDoor.GROUP]:
		for node in tree.get_nodes_in_group(group):
			boxed.append(node)
	for node in tree.get_nodes_in_group(CombatProjectile.PICKUP_GROUP):
		boxed.append(node)
	for body in GroundPickup.nearby(player, REACH + 1.0):
		boxed.append(body)

	for node in boxed:
		if not _usable(node) or node.global_position.distance_to(chest) > REACH + 4.0:
			continue
		var box := _local_box(node)
		var xf := node.global_transform
		var t := _ray_box(xf.affine_inverse() * from, (xf.basis.inverse() * dir), box)
		if t < 0.0 or t >= best_t:
			continue
		var reach := WoodenDoor.REACH if node is WoodenDoor else REACH
		if chest.distance_to(xf * _closest_in_box(xf.affine_inverse() * chest, box)) > reach:
			continue
		if _blocked(t, wall_t, wall, node):
			continue
		best = node
		best_t = t

	for group in [Companion.GROUP, Villager.GROUP]:
		for node in tree.get_nodes_in_group(group):
			var person := node as Node3D
			if person == null or not person.is_inside_tree() or person.global_position.distance_to(chest) > REACH + 2.0:
				continue
			var up := person.global_basis.y.normalized()
			var a := person.global_position + up * PERSON_LOW
			var b := person.global_position + up * PERSON_HIGH
			var t := _ray_capsule(from, dir, a, b, PERSON_RADIUS)
			if t < 0.0 or t >= best_t:
				continue
			if chest.distance_to(Geometry3D.get_closest_point_to_segment(chest, a, b)) > REACH + PERSON_RADIUS:
				continue
			if _blocked(t, wall_t, wall, person):
				continue
			best = person
			best_t = t

	for corpse in _corpses(player):
		var center: Vector3 = corpse.get_lock_point()
		var radius := CORPSE_RADIUS
		if corpse is FaunaCorpse:
			radius = maxf(radius, (corpse as FaunaCorpse).butcher_shape().y * 0.5)
		var t := _ray_sphere(from, dir, center, radius)
		if t < 0.0 or t >= best_t:
			continue
		if chest.distance_to(center) > REACH + radius:
			continue
		if _blocked(t, wall_t, wall, corpse):
			continue
		best = corpse
		best_t = t
	return best


## Usa [target] (lo que devuelve aimed). true si ha hecho algo.
static func use(player: PlayerController, target: Node) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target is WoodenDoor:
		target.toggle(player.global_position - player.gravity_direction)
	elif target is Bedroll:
		player.survival.open_bedroll(target)
	elif target is Storage:
		player.survival.open_storage(target)
	elif target is Throne:
		return player.throne_view.try_sit(target)
	elif target is Campfire or target is Furnace or target is Workstation:
		return player.survival.open_workplace(target)
	elif target is DeathLoot:
		player.survival.open_death_loot(target)
	elif target is Companion or target is Villager:
		return player.villager_chat.try_talk(target)
	elif target is FaunaCorpse or target is NPCController:
		player.survival.open_corpse(target)
	elif target is DroppedItem:
		return (target as DroppedItem).pick_into(player.inventory)
	elif target is CombatProjectile:
		return player.combat.try_pickup(target)
	elif target is VoxelInstancerRigidBody:
		return GroundPickup.pick_body(player, player.inventory, target)
	elif target is ItemPhysics:
		var data: ItemData = (target as ItemPhysics).item_data
		if data == null or player.inventory.add_item(data, 1) != 0:
			return false
		target.queue_free()
		AudioManager.play_ui(&"item_pickup")
	else:
		return false
	return true


static func _usable(node: Node3D) -> bool:
	if node == null or not node.is_inside_tree() or node.is_queued_for_deletion():
		return false
	if node is DeathLoot:
		return not (node as DeathLoot).is_empty()
	if node is DroppedItem:
		return (node as DroppedItem).item_data != null and (node as DroppedItem).quantity > 0
	if node is CombatProjectile:
		return (node as CombatProjectile).is_pickable()
	return true


## Los cadáveres que se pueden despiezar o saquear: animales pequeños (FaunaCorpse) y grandes
## (NPCController muerto).
static func _corpses(player: PlayerController) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for corpse in FaunaCorpse._alive:
		if is_instance_valid(corpse) and corpse.is_inside_tree() and corpse.butcherable():
			found.append(corpse)
	for node in player.get_tree().get_nodes_in_group("npc"):
		var npc := node as NPCController
		if npc != null and is_instance_valid(npc) and npc.is_dead:
			found.append(npc)
	return found


## Si el raycast físico da en algo ajeno a [node] antes de llegar a él. Lo que lo contiene (el
## cuerpo de la pieza a la que va pegado) o lo que cuelga de él cuenta como suyo.
static func _blocked(t: float, wall_t: float, wall: Node, node: Node) -> bool:
	if wall == null or wall_t >= t - 0.05:
		return false
	if wall == node or node.is_ancestor_of(wall):
		return false
	# El terreno cuelga del planeta como lo colocado, pero no lo contiene.
	return wall is VoxelLodTerrain or wall is VoxelTerrain or not wall.is_ancestor_of(node)


## La caja de [node] en su espacio local: la de sus mallas (o sus formas de colisión), agrandada.
## Se calcula una vez; lo colocado no cambia de forma.
static func _local_box(node: Node3D) -> AABB:
	if node.has_meta(BOX_META):
		return node.get_meta(BOX_META)
	var inv := node.global_transform.affine_inverse()
	var box := AABB()
	var found := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var part := AABB()
		var has := false
		# VisualInstance3D incluye luces y calcos: su AABB mide el área iluminada/proyectada,
		# no el objeto. Una OmniLight de la hoguera abarcaba toda la cabaña y ganaba con t = 0.
		if (n is MeshInstance3D or n is MultiMeshInstance3D) and (n as Node3D).is_visible_in_tree():
			part = (inv * (n as Node3D).global_transform) * (n as VisualInstance3D).get_aabb()
			has = part.size != Vector3.ZERO
		elif n is CollisionShape3D and (n as CollisionShape3D).shape != null:
			var mesh := (n as CollisionShape3D).shape.get_debug_mesh()
			if mesh != null:
				part = (inv * (n as Node3D).global_transform) * mesh.get_aabb()
				has = true
		if has:
			box = part if not found else box.merge(part)
			found = true
		for child in n.get_children():
			stack.append(child)
	if not found:
		box = AABB(Vector3(-0.25, 0.0, -0.25), Vector3(0.5, 0.5, 0.5))
	box = box.grow(PAD)
	# Lo que se mueve (lo soltado, las lanzas) no se cachea: su malla puede cambiar de sitio.
	if not (node is DroppedItem or node is CombatProjectile or node is RigidBody3D):
		node.set_meta(BOX_META, box)
	return box


## Distancia a lo largo del rayo hasta la entrada en [box] (0 si empieza dentro); -1 si no la toca.
static func _ray_box(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var t_min := 0.0
	var t_max := INF
	for axis in 3:
		var o := origin[axis]
		var d := dir[axis]
		var lo := box.position[axis]
		var hi := box.end[axis]
		if absf(d) < 1e-6:
			if o < lo or o > hi:
				return -1.0
			continue
		var t1 := (lo - o) / d
		var t2 := (hi - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return -1.0
	# La dirección local puede no ser unitaria (escala): se devuelve en metros del mundo.
	return t_min


static func _closest_in_box(p: Vector3, box: AABB) -> Vector3:
	return p.clamp(box.position, box.end)


static func _ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var t := maxf((center - origin).dot(dir), 0.0)
	if (origin + dir * t).distance_to(center) > radius:
		return -1.0
	return t


## Aproximación: el punto del rayo más cercano al eje de la cápsula, si queda dentro del radio.
static func _ray_capsule(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var far := origin + dir * 100.0
	var pts := Geometry3D.get_closest_points_between_segments(origin, far, a, b)
	if pts[0].distance_to(pts[1]) > radius:
		return -1.0
	return origin.distance_to(pts[0])
