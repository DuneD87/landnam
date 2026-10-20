class_name RockMining
extends Node3D

## Picar las rocas del instancer con el pico, como la tala de los árboles (TreeFelling). Al primer
## golpe la roca se cambia por sus trozos de Voronoi (RockFracture) colocados tal cual
## (FracturedRock): cada golpe suma trabajo y, a cada trozo de trabajo, se suelta el trozo más
## cercano al golpe y cae al suelo (RockFragment), con lo que se quede sin apoyo. Los trozos caídos
## se pican en piedras sueltas que se recogen. Lo que no es un pico apenas mella la roca.
##
## Cuanto más grande la roca, más trozos (de PIECES): las rocas grandes sueltan trozos grandes, que
## se parten otra vez al picarlos. Las fracturas se calculan en hilos al cargar la vegetación
## (prepare).
##
## Las rocas cuelgan del instancer cerca del jugador. El item lleva la escena de la roca
## (Planet._register_multi_mesh_item) y el módulo puede dar con ella dos cosas: la escena entera
## (un Item con su malla y su colisión) o solo un cuerpo suyo (VoxelInstancerRigidBody) con la
## colisión, dibujando la malla en su MultiMesh. Se aceptan las dos: del cuerpo, la malla y el
## material salen de la escena registrada de su item. El trabajo va con el tamaño de la roca y las
## piedras también.
##
## Cuelga del terreno, como la tala: la roca rota y sus trozos siguen al planeta y al origen
## flotante. La roca sale del instancer en el primer golpe; sus trozos solo duran la sesión.

const META := &"rock_mining"
## Trabajo (daño de pico) para soltar todos los trozos: fijo más por metro de tamaño de la roca.
const WORK := 30.0
const WORK_PER_METER := 40.0
## Piedras por metro de tamaño, entre estos límites (por el rendimiento de la roca, Item.mining_yield:
## un afloramiento de mena da menos).
const STONES_PER_METER := 3.0
const STONES := Vector2i(2, 40)
## En cuántos trozos se parte una roca: los primeros de estos que dejen cada trozo en
## PIECE_VOLUME m³ o menos (las rocas llenan la mitad de su caja, más o menos).
const PIECES := [6, 10, 16, 24]
const PIECE_VOLUME := 0.3
const FILL := 0.5
## Lo que mella lo que no es un pico: los golpes contundentes algo, los filos y las puntas casi nada.
const BLUNT_FACTOR := 0.4
const OTHER_FACTOR := 0.1
## Holgura del tajo contra la roca (m).
const STRIKE_WIDTH := 0.35

var planet: Planet


func _init(p_planet: Planet) -> void:
	name = "RockMining"
	planet = p_planet
	planet.voxel_instancer.set_meta(META, self)
	set_process(false)


## Lanza en hilos las fracturas de las rocas de la vegetación cargada: así el primer golpe no
## espera a recortar la malla.
func prepare() -> void:
	for id in planet.planet_item_scenes:
		if planet.pickup_library_ids.has(id):
			continue
		# Los árboles chocan con un cilindro; las rocas, con su envolvente.
		var library_item := planet.voxel_instancer.library.get_item(id) as VoxelInstanceLibraryMultiMeshItem
		if library_item != null and not library_item.collision_shapes.is_empty() \
				and library_item.collision_shapes[0] is CylinderShape3D:
			continue
		var mesh := _mesh_of(planet.planet_item_scenes[id] as Item)
		if mesh != null:
			for count in PIECES:
				RockFracture.prepare(mesh, count)
	set_process(true)


func _process(_delta: float) -> void:
	if not RockFracture.collect():
		set_process(false)


## Herramientas que el combate deja golpear sin enemigos delante, para picar.
static func mines(data: ItemData) -> bool:
	return data != null and data.tool_type == ItemData.ToolType.PICKAXE


## Mella de un golpe ligero con [data] en la roca, antes de los multiplicadores del golpe.
static func mine_power(data: ItemData) -> float:
	if data == null:
		return 0.0
	var power := float(data.damage) * data.harvest_multiplier
	if data.tool_type == ItemData.ToolType.PICKAXE:
		return power
	if data.damage_kind == ItemData.DamageKind.BLUNT:
		return power * BLUNT_FACTOR
	return power * OTHER_FACTOR


## La roca de la que cuelga [node] (un cuerpo del instancer o la escena que creó) y su minería,
## o [].
static func rock_of(node: Node) -> Array:
	var rock: Node3D = null
	var instancer: Node = node
	while instancer != null and not (instancer is VoxelInstancer):
		if rock == null and (instancer is Item or instancer is VoxelInstancerRigidBody):
			rock = instancer
		instancer = instancer.get_parent()
	if rock == null or instancer == null or not instancer.has_meta(META):
		return []
	var mining := instancer.get_meta(META) as RockMining
	return [rock, mining] if not mining._shape_of(rock).is_empty() else []


## Lo que recibe un golpe dado desde [feet] (los pies) hacia [forward], con [up] el del planeta:
## una roca, una roca a medio picar o un trozo caído. {body, point, distance} o {}. Mismo tajo que
## TreeFelling.strike: un tramo a la altura del pecho hacia delante y otro que baja delante hasta
## el suelo.
static func strike(scene_tree: SceneTree, space: PhysicsDirectSpaceState3D, feet: Vector3,
		forward: Vector3, up: Vector3) -> Dictionary:
	if space == null:
		return {}
	var flat := forward - up * forward.dot(up)
	if flat.length_squared() < 1e-6:
		return {}
	flat = flat.normalized()
	var chest := feet + up * TreeFelling.STRIKE_HEIGHT
	var segments := [[chest + flat * 0.15, chest + flat * TreeFelling.STRIKE_REACH],
		[chest + flat * 0.9, feet + flat * 0.9 - up * 0.3]]
	var best := {}
	var best_distance := INF
	for node in scene_tree.get_nodes_in_group(RockFragment.GROUP):
		var fragment := node as RockFragment
		if fragment == null or not fragment.is_ready():
			continue
		for segment in segments:
			var point := Geometry3D.get_closest_point_to_segment(fragment.center(), segment[0], segment[1])
			if point.distance_to(fragment.center()) - fragment.radius <= STRIKE_WIDTH + 0.1:
				var distance := _flat_distance(feet, point, up)
				if distance < best_distance:
					best_distance = distance
					best = {"body": fragment, "point": point, "distance": distance}
	# Las rocas (enteras o a medio picar), contra su colisión: son irregulares, un tajo que la roza
	# ya entra.
	var capsule := CapsuleShape3D.new()
	capsule.radius = STRIKE_WIDTH
	var query := PhysicsShapeQueryParameters3D.new()
	query.collide_with_areas = false 
	query.collide_with_bodies = true
	query.collision_mask = PhysicsLayers.WORLD
	query.shape = capsule
	for segment in segments:
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var axis := b - a
		capsule.height = axis.length() + STRIKE_WIDTH * 2.0
		var y := axis.normalized()
		var x := y.cross(up if absf(y.dot(up)) < 0.95 else flat).normalized()
		query.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
		for result in space.intersect_shape(query, 16):
			var collider := result.get("collider") as Node3D
			if collider == null:
				continue
			var target: Node3D = null
			var center := Vector3.INF
			if collider.get_parent() is FracturedRock:
				target = collider.get_parent()
				center = collider.global_position
			else:
				var found := rock_of(collider)
				if not found.is_empty():
					target = found[0]
					center = (found[1] as RockMining)._shape_of(found[0]).center
			if target == null:
				continue
			var point := Geometry3D.get_closest_point_to_segment(center, a, b)
			var distance := _flat_distance(feet, point, up)
			if distance < best_distance:
				best_distance = distance
				best = {"body": target, "point": point, "distance": distance}
	return best


static func _flat_distance(feet: Vector3, point: Vector3, up: Vector3) -> float:
	var offset := point - feet
	return (offset - up * offset.dot(up)).length()


## [total] repartido según [weights] (por el mayor resto): a los pequeños les puede tocar 0.
static func share(total: int, weights: Array) -> PackedInt32Array:
	var shares := PackedInt32Array()
	shares.resize(weights.size())
	shares.fill(0)
	var sum := 0.0
	for weight in weights:
		sum += maxf(float(weight), 0.0)
	if weights.is_empty() or total <= 0 or sum <= 0.0:
		return shares
	var rests: Array = []
	var left := total
	for i in weights.size():
		var exact := total * maxf(float(weights[i]), 0.0) / sum
		shares[i] = floori(exact)
		left -= shares[i]
		rests.append([exact - shares[i], i])
	rests.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for k in left:
		shares[rests[k % rests.size()][1]] += 1
	return shares


## Golpe de [power] en [body] (una roca, una a medio picar o un trozo caído) por [point], dado
## desde [miner]. Devuelve true si ha hecho algo.
static func hit_any(body: Node, point: Vector3, power: float, miner: Node3D) -> bool:
	if body is RockFragment:
		return (body as RockFragment).hit(power, miner)
	if body is FracturedRock:
		return (body as FracturedRock).hit(point, power, miner)
	var found := rock_of(body)
	return not found.is_empty() and (found[1] as RockMining).mine(found[0], point, power, miner)


## Malla de la roca y su transform (mundo, con la escala), centro, radio y tamaño (m), y el
## material que da (item); {} si no es una roca que se pique. Un cuerpo del instancer lo saca de la
## escena registrada de su item: no es un árbol (eso es la tala) ni lo que se recoge del suelo, y
## tiene malla y material.
func _shape_of(rock: Node3D) -> Dictionary:
	var template: Node = rock
	var xf := Transform3D.IDENTITY
	if rock is VoxelInstancerRigidBody:
		var id := (rock as VoxelInstancerRigidBody).get_library_item_id()
		if planet.pickup_library_ids.has(id) or planet.tree_felling.is_choppable(rock):
			return {}
		template = planet.planet_item_scenes.get(id)
		xf = rock.global_transform
	var item := template as Item
	var mesh_node := _mesh_node_of(item)
	if mesh_node == null:
		return {}
	# La escena en el mundo ya tiene su transform; la registrada, el de la malla bajo su raíz.
	xf = mesh_node.global_transform if rock is Item else xf * mesh_node.transform
	var box := mesh_node.mesh.get_aabb()
	var size := box.size * xf.basis.get_scale()
	return {"mesh": mesh_node.mesh, "transform": xf, "center": xf * box.get_center(),
		"radius": maxf(maxf(size.x, size.y), size.z) * 0.5,
		"size": pow(maxf(size.x * size.y * size.z, 0.001), 1.0 / 3.0), "item": item.item_data,
		"ore_yield": item.mining_yield}


## La malla de la roca de la escena [item] (un Item con material), o null.
static func _mesh_node_of(item: Item) -> MeshInstance3D:
	if item == null or item.item_data == null:
		return null
	for child in item.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			return child
	return null


static func _mesh_of(item: Item) -> Mesh:
	var mesh_node := _mesh_node_of(item)
	return mesh_node.mesh if mesh_node != null else null


static func _colliders_of(node: Node, out: Array[RID]) -> void:
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_colliders_of(child, out)


## Primer golpe de [power] en [rock] por [point], dado desde [miner]: la cambia por sus trozos y
## el golpe ya cuenta.
func mine(rock: Node3D, point: Vector3, power: float, miner: Node3D) -> bool:
	var shape := _shape_of(rock)
	if shape.is_empty() or power <= 0.0 or not rock.is_inside_tree():
		return false
	var size: float = shape.size
	var count: int = PIECES.back()
	for option: int in PIECES:
		if FILL * size * size * size <= option * PIECE_VOLUME:
			count = option
			break
	var pieces := RockFracture.pieces_of(shape.mesh, count)
	if pieces.is_empty():
		return false
	var center: Vector3 = shape.center
	var up := (center - planet.voxel_terrain.global_position).normalized()
	var ignore: Array[RID] = []
	_colliders_of(rock, ignore)
	var fractured := FracturedRock.new()
	add_child(fractured)
	var stones := clampi(roundi(STONES_PER_METER * size * float(shape.ore_yield)), STONES.x, STONES.y)
	fractured.setup(pieces, shape.transform, shape.item, stones, WORK + WORK_PER_METER * size, up, ignore)
	# Fuera del instancer (y de su guardado, si es un cuerpo suyo).
	if rock is VoxelInstancerRigidBody:
		(rock as VoxelInstancerRigidBody).queue_free_and_notify_instancer()
	else:
		rock.queue_free()
	return fractured.hit(point, power, miner)
