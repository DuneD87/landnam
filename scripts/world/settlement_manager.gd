class_name SettlementManager extends Node

## Levanta las construcciones de los poblados (Planet.get_settlements, de SettlementField) cuando el
## jugador se acerca y las quita cuando se aleja: cada una de su prefab, con su zócalo y su rampa, en
## varios fotogramas: uno pone los bloques y luego se malla un chunk por fotograma, que es lo caro (unos
## 12 ms la casa larga entera, unos 6 cada uno de sus dos chunks).
##
## Mientras nadie las toque no se guardan (GridBase.settlement): salen siempre iguales del plano, y si
## cambia un prefab cambian con él. En cuanto el jugador pone o quita un bloque o un colocable, rompe uno,
## o sus grids desaparecen por otra vía (desmontarla, convertirla en dinámica), la casa pasa a ser una
## construcción normal: se guarda con la partida como cualquier otra y el poblado apunta que esa ya no
## la levanta él (get_save_data).
##
## Cada casa lleva sus lechos (SettlementPrefab.beds) y sus sitios de trabajo (SettlementDecor), decorado
## que no se guarda; y los poblados cercanos, su gente (SettlementVillagers), menos quien se ha ido con
## el jugador (SettlementCompanions). Lleva la confianza de cada poblado, el trueque y los encargos, que se
## guardan con la partida; y cuenta las fieras que caen para los encargos de caza (creature_killed).
##
## De lejos (hasta far_distance), cada poblado es una malla barata (SettlementFar). Apunta los poblados que
## el jugador ha visto de cerca (a menos de load_distance), que el mapa nombra (map_sites).

## Cada cuánto se mira a qué distancia está el jugador (s).
const CHECK_INTERVAL := 0.5
## Lo que tiene que medir una casa a lo largo de X o de Z (celdas) para centrarla en su grid (_centering).
const CENTER_ABOVE := 12
const BED_VISUAL := "res://scenes/world/bedroll_visual.tscn"
## La colisión del lecho (la del Bedroll del jugador).
const BED_SIZE := Vector3(0.85, 0.13, 2.0)

var entity_id := ""
var save_category := "planet"

## Padre de las grids (el PlanetLoader) y marco del terreno, en el que va el plano.
var _planet: Node3D
var _terrain: Node3D
var _player: Node3D
var _villages: Array = []
var _prefabs := {}
var _load_distance := 600.0
var _unload_distance := 800.0
## Las mallas de lejos de los poblados.
var _far: SettlementFar
## Poblado -> true: los que el jugador ha visto de cerca. Se guarda con la partida.
var _known := {}
## Los sitios para el mapa (map_sites), sin los nombres.
var _sites: Array = []
## La semilla de los poblados (la de sus nombres).
var _seed := 1
## "<poblado>:<casa>" -> true: las que ya son de la partida.
var _claimed := {}
## "<poblado>:<casa>" -> las grids levantadas.
var _built := {}
## Casas por levantar (poblado, casa), y las mismas como claves.
var _queue: Array[Vector2i] = []
var _queued := {}
## La casa con los bloques puestos y a medio mallar: {"key", "grids", "data", "chunks": lo que falta
## por mallar, [grid, chunk]}.
var _pending := {}
var _timer := 0.0
## "<poblado>:<casa>" -> su decorado: los lechos, los sitios de trabajo y los adornos.
var _decor := {}
## Poblado -> su cerca (SettlementWall), mientras está cerca; sus calles las pinta el terreno (SettlementStreets).
var _walls := {}
var _people: SettlementVillagers
## Los que se han ido con el jugador: se guardan aparte, en la categoría "npc".
var _companions: SettlementCompanions
## Lo que es el jugador para cada poblado (la confianza): se guarda con la partida.
var relations := SettlementRelations.new()
## Lo que tiene cada vecino para cambiar y lo que se ha llevado el jugador hoy: se guarda con la partida.
var trade := SettlementTrade.new(relations, 1)
## Lo que piden los vecinos y lo que el jugador tiene entre manos: se guarda con la partida.
var quests := SettlementQuests.new(relations, 1)
## Lo que los encargos ponen en el mundo (el perdido, el escoltado, las emboscadas, la fiera con nombre).
var director: QuestDirector


## [planet]: el PlanetLoader; [terrain]: su VoxelLodTerrain; [field]: Planet.get_settlements().
func setup(planet: Node3D, terrain: Node3D, player: Node3D, field: Dictionary, cfg: Dictionary) -> void:
	_planet = planet
	_terrain = terrain
	_player = player
	_villages = field.get("villages", [])
	cfg = SettlementField.settings(cfg)
	trade = SettlementTrade.new(relations, int(cfg.seed))
	quests = SettlementQuests.new(relations, int(cfg.seed))
	quests.villages = _villages
	var seed := int(cfg.seed)
	_seed = seed
	quests.residents_of = func(v: int) -> Array:
		return SettlementPopulation.residents(_villages[v], v, _prefabs, seed) if v >= 0 and v < _villages.size() else []
	_load_distance = float(cfg.load_distance)
	_unload_distance = maxf(float(cfg.unload_distance), _load_distance + 50.0)
	for t in SettlementField.load_templates():
		var prefabs: Array = t.all_prefabs()
		for p: SettlementPrefab in prefabs:
			if p != null:
				_prefabs[p.id] = p
	add_to_group(GameManager.SAVEABLE_GROUP)
	add_to_group(NPCController.KILLS_GROUP)
	_far = SettlementFar.new()
	_far.setup(_villages, _prefabs, planet.global_transform.affine_inverse() * terrain.global_transform,
		float(cfg.far_distance))
	planet.add_child(_far)
	_companions = SettlementCompanions.new()
	_companions.name = "Companions"
	_companions.entity_id = entity_id + "_companions"
	add_child(_companions)
	_companions.setup(self, planet, terrain, player, field, _prefabs, cfg)
	_people = SettlementVillagers.new()
	_people.name = "Villagers"
	add_child(_people)
	_people.setup(self, planet, terrain, player, field, _prefabs, cfg)
	director = QuestDirector.new()
	director.setup(self, terrain, player)
	add_child(director)


func _exit_tree() -> void:
	# La malla de lejos cuelga del planeta, no de aquí.
	if _far != null and is_instance_valid(_far):
		_far.queue_free()


func _process(delta: float) -> void:
	relations.advance(WorldTime.hours_elapsed(delta))
	if _player == null or not is_instance_valid(_player) or _terrain == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_INTERVAL
		_update()
	if not _pending.is_empty():
		_advance()
	elif not _queue.is_empty():
		var job: Vector2i = _queue.pop_front()
		_queued.erase(job)
		_build(job.x, job.y)


## Encola las casas de los poblados cercanos y quita las de los lejanos.
func _update() -> void:
	_find_lost()
	var local := _terrain.global_transform.affine_inverse() * _player.global_position
	for v in _villages.size():
		var plan: Dictionary = _villages[v]
		var d := local.distance_to((plan.center as Vector3) * float(plan.ground))
		var count := (plan.buildings as Array).size()
		if d < _load_distance:
			_known[v] = true
			if not _walls.has(v):
				_walls[v] = _build_grounds(v, plan)
			for b in count:
				var job := Vector2i(v, b)
				var key := _key(v, b)
				if not _claimed.has(key) and not _is_up(key) and not _queued.has(job):
					_queue.append(job)
					_queued[job] = true
		elif d > _unload_distance:
			_free_wall(v)
			for b in count:
				_unbuild(_key(v, b))
				var job := Vector2i(v, b)
				if _queued.has(job):
					_queued.erase(job)
					_queue.erase(job)
	if _far != null:
		_far.update(local, _claimed, _village_up)


## Si todas las casas del poblado [v] están levantadas (o son de la partida): entonces no hace falta su
## malla de lejos.
func _village_up(v: int) -> bool:
	for b in (_villages[v].buildings as Array).size():
		var key := _key(v, b)
		if not _claimed.has(key) and not _built.has(key):
			return false
	return true


## Empieza la casa [b] del poblado [v], si sigue por levantar: las grids de su prefab con sus bloques y
## el zócalo y la rampa del plano en la principal, sin mallar todavía (lo hace _advance).
func _build(v: int, b: int) -> void:
	var key := _key(v, b)
	if _claimed.has(key) or _is_up(key):
		return
	var info: Dictionary = _villages[v].buildings[b]
	var prefab: SettlementPrefab = _prefabs.get(info.prefab)
	if prefab == null or prefab.load_data().is_empty():
		return
	var data := prefab.load_data().duplicate(true)
	var main: Dictionary = (data.grids as Array)[0]
	var blocks: Dictionary = main.blocks
	var extra: PackedInt32Array = info.extra
	for i in range(0, extra.size(), 5):
		var rot := Basis(Vector3.UP, extra[i + 4] * PI * 0.5)
		blocks["%d,%d,%d" % [extra[i], extra[i + 1], extra[i + 2]]] = {"block_id": extra[i + 3],
			"material_id": prefab.foundation_material, "rotation_basis": GridBase._basis_to_array(rot)}
	data.block_count = int(data.get("block_count", 0)) + extra.size() / 5
	var frame := _terrain.global_transform
	var basis := frame.basis * (info.basis as Basis)
	var shift := _centering(data)
	var grids := GridBlueprint.create_grids(data, _planet, frame * (info.origin as Vector3) - basis * shift,
		basis, String(info.prefab))
	for i in grids.size():
		var grid: GridBase = grids[i]
		var moved := Vector3i((shift / grid.cell_size).round())
		grid.settlement = key
		grid.set_source_blueprint(String(info.prefab), i, shift)
		grid.begin_bulk_edit()
		var blocks_i := GridBlueprint.blocks_dict(data.grids[i])
		for pos: Vector3i in blocks_i:
			GridBlueprint.place_block(grid, pos + moved, blocks_i[pos])
	_pending = {"key": key, "grids": grids, "data": data, "shift": shift, "prefab": prefab}


## Sigue con la casa empezada: un chunk de malla por fotograma y, en el siguiente, sus colocables (las
## puertas); desde ahí escucha si la tocan.
func _advance() -> void:
	var key: String = _pending.key
	var grids: Array = _pending.grids
	if not _pending.has("chunks"):
		var todo: Array = []
		for grid: GridBase in grids:
			for chunk: Vector3i in grid.end_bulk_edit(false):
				todo.append([grid, chunk])
		_pending.chunks = todo
	var chunks: Array = _pending.chunks
	if not chunks.is_empty():
		var job: Array = chunks.pop_back()
		(job[0] as GridBase).rebuild_chunk(job[1])
		return
	var data: Dictionary = _pending.data
	var shift: Vector3 = _pending.shift
	var prefab: SettlementPrefab = _pending.prefab
	_pending = {}
	for i in grids.size():
		var grid: GridBase = grids[i]
		if grid.settlement != key:
			continue
		var moved := Vector3i((shift / grid.cell_size).round())
		for prop: Dictionary in data.grids[i].get("props", []):
			var placed := prop.duplicate()
			placed.cell = GridBase._vec3i_to_array(GridBase._array_to_vec3i(prop.get("cell", [])) + moved)
			var xform := GridBase._array_to_transform(prop.get("local_transform", []))
			xform.origin += shift
			placed.local_transform = GridBase._transform_to_array(xform)
			GridBlueprint.place_prop(grid, placed)
		grid.block_placed.connect(func(_p: Vector3i, _id: int) -> void: _on_edited(grid, key))
		grid.block_removed.connect(func(_p: Vector3i) -> void: _on_edited(grid, key))
		grid.props_changed.connect(func() -> void: _on_edited(grid, key))
	_built[key] = grids
	if not grids.is_empty() and (grids[0] as GridBase).settlement == key:
		_place_beds(key, grids[0], prefab, shift)
		_place_work(key)


## Los lechos de la casa [key] en su grid principal [grid] (corrida [shift], _centering): el del jugador
## sin lo que lo hace un objeto de la partida, que no se guarda ni se recoge.
func _place_beds(key: String, grid: GridBase, prefab: SettlementPrefab, shift: Vector3) -> void:
	var beds: Array[Node3D] = []
	for pose in prefab.beds:
		var bed := Node3D.new()
		bed.name = "SettlementBed_%s_%d" % [key.replace(":", "_"), beds.size()]
		bed.add_child((load(BED_VISUAL) as PackedScene).instantiate())
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = BED_SIZE
		shape.shape = box
		shape.position = Vector3(0.0, BED_SIZE.y * 0.5, 0.0)
		body.add_child(shape)
		bed.add_child(body)
		bed.transform = grid._prop_anchor_transform(Transform3D(pose.basis, pose.origin + shift))
		grid.planet_node.add_child(bed)
		beds.append(bed)
	_decor[key] = beds


## Los sitios de trabajo de la casa [key] (SettlementLayout._workplace, ya en el suelo).
func _place_work(key: String) -> void:
	var parts := key.split(":")
	var info: Dictionary = _villages[int(parts[0])].buildings[int(parts[1])]
	var frame := _planet.global_transform.affine_inverse() * _terrain.global_transform
	var decor: Array = _decor.get_or_add(key, [] as Array[Node3D])
	for work: Dictionary in info.get("work", []):
		var node := SettlementDecor.make(work, frame)
		node.name = "SettlementWork_%s_%d" % [key.replace(":", "_"), decor.size()]
		_planet.add_child(node)
		decor.append(node)
	var props: Array = info.get("props", [])
	for i in props.size():
		var prop: Dictionary = props[i]
		if StringName(prop.kind) == &"pen":
			_place_pen(key, prop, frame, decor)
			continue
		var node := SettlementDecor.prop(prop, frame)
		if node == null:
			continue
		node.name = "SettlementProp_%s_%d" % [key.replace(":", "_"), decor.size()]
		if SettlementStash.KINDS.has(StringName(prop.kind)):
			# Los arcones, cajas, barriles y sacos se abren (SettlementStash).
			var stash := SettlementStash.new()
			stash.name = node.name
			stash.key = "%s:%d" % [key, i]
			stash.kind = StringName(prop.kind)
			stash.village_index = int(parts[0])
			stash.manager = self
			stash.transform = node.transform
			node.transform = Transform3D.IDENTITY
			node.name = "Prop"
			stash.add_child(node)
			node = stash
		_planet.add_child(node)
		decor.append(node)


## Lo que el poblado [v] (su plano [plan]) tiene fuera de las casas: la cerca y, en una villa, las calles
## y la plaza (que pinta el terreno: SettlementStreets).
func _build_grounds(v: int, plan: Dictionary) -> Array[Node3D]:
	var frame := _planet.global_transform.affine_inverse() * _terrain.global_transform
	var nodes: Array[Node3D] = []
	if not (plan.get("wall", {}) as Dictionary).is_empty():
		var wall := SettlementWall.build(plan.wall, frame, hash([v, "wall"]))
		wall.name = "SettlementWall_%d" % v
		nodes.append(wall)
	if plan.has("streets"):
		SettlementStreets.show(v, plan, _terrain.global_transform)
	for node in nodes:
		_planet.add_child(node)
	return nodes


func _free_wall(v: int) -> void:
	SettlementStreets.hide(v)
	for node: Node3D in _walls.get(v, []):
		if is_instance_valid(node):
			node.queue_free()
	_walls.erase(v)


## Un cercado (SettlementProp &"pen", ya en el suelo): la cerca de varas por su contorno y sus animales
## (SettlementAnimal) repartidos dentro, en [decor] con lo demás de la casa [key].
func _place_pen(key: String, prop: Dictionary, frame: Transform3D, decor: Array) -> void:
	var outline: PackedVector3Array = prop.get("outline", PackedVector3Array())
	if outline.size() >= 3:
		var open := PackedByteArray()
		open.resize(outline.size())
		var fence := SettlementWall.build({"kind": &"fence", "points": outline, "open": open}, frame, hash([key, "pen"]))
		fence.name = "SettlementPen_%s_%d" % [key.replace(":", "_"), decor.size()]
		_planet.add_child(fence)
		decor.append(fence)
	var pose: Transform3D = prop.pose
	var size: Vector2 = prop.get("size", Vector2(6.0, 6.0))
	var animals: Array = prop.get("animals", [])
	for i in animals.size():
		var seed := hash([key, "animal", i])
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var at := pose * Vector3(rng.randf_range(-0.3, 0.3) * size.x, 0.0, rng.randf_range(-0.3, 0.3) * size.y)
		var animal := SettlementAnimal.create(StringName(animals[i]), at, _terrain, seed, pose, size)
		if animal == null:
			continue
		_planet.add_child(animal)
		decor.append(animal)


func _free_decor(key: String) -> void:
	for node: Node3D in _decor.get(key, []):
		if is_instance_valid(node):
			node.queue_free()
	_decor.erase(key)


## Lo que se mueven las celdas de [data] (m, en el espacio de sus grids) para centrar la casa en el
## origen de la grid a lo largo de X y de Z cuando mide más de CENTER_ABOVE celdas: así cae en dos chunks
## (de 16 celdas) parecidos y _advance malla cada mitad en su fotograma, en vez de casi toda de una vez.
## La casa no se mueve en el mundo: la grid se corre lo contrario. Cero si alguna grid no tiene un
## número entero de celdas en ese desplazamiento.
static func _centering(data: Dictionary) -> Vector3:
	var grids: Array = data.grids
	var cell := float(grids[0].get("cell_size", 1.0))
	var lo := GridBase._array_to_vec3(data.get("bounds_min", [0, 0, 0]))
	var hi := GridBase._array_to_vec3(data.get("bounds_max", [0, 0, 0]))
	var shift := Vector3.ZERO
	for axis in [0, 2]:
		if (hi[axis] - lo[axis]) / cell > CENTER_ABOVE:
			shift[axis] = -roundf((lo[axis] + hi[axis]) * 0.5 / cell) * cell
	for g: Dictionary in grids:
		var size := float(g.get("cell_size", 1.0))
		for axis in 3:
			if absf(shift[axis] / size - roundf(shift[axis] / size)) > 0.001:
				return Vector3.ZERO
	return shift


## Quita la casa [key] si está levantada y nadie la ha tocado.
func _unbuild(key: String) -> void:
	var grids: Array = _built.get(key, [])
	_built.erase(key)
	_free_decor(key)
	for grid: GridBase in grids:
		if grid.settlement != key:
			continue
		# Antes de quitarla: al vaciarse avisa de que cambió, y no es que la haya tocado nadie.
		grid.settlement = ""
		if GridManager.get_grid(grid.grid_id) == grid:
			GridManager.remove_grid(grid.grid_id)


func _on_edited(grid: GridBase, key: String) -> void:
	if grid.settlement == key:
		_claim(key)


## La casa [key] pasa a ser de la partida: sus grids se guardan y el poblado ya no la levanta.
func _claim(key: String) -> void:
	for grid: GridBase in _built.get(key, []):
		if grid.settlement == key:
			grid.settlement = ""
	_built.erase(key)
	_claimed[key] = true
	if _far != null:
		_far.changed(int(key.get_slice(":", 0)))


## Las casas a las que les ha desaparecido alguna grid sin quitarlas el poblado (desmontada, convertida
## en dinámica): son de la partida.
func _find_lost() -> void:
	for key: String in _built.keys():
		for grid: GridBase in _built[key]:
			if GridManager.get_grid(grid.grid_id) != grid:
				_claim(key)
				break


## Si la casa [key] está levantada o a medias.
func _is_up(key: String) -> bool:
	return _built.has(key) or _pending.get("key", "") == key


static func _key(v: int, b: int) -> String:
	return "%d:%d" % [v, b]


## El jugador se ha llevado [items] (id -> cuántos, que valen [value]) de [stash]: se apunta, y si lo ve
## alguien del poblado, es robar (SettlementVillage.robbed).
func stash_taken(stash: SettlementStash, items: Dictionary, value: float) -> void:
	trade.take_stash(stash.key, items)
	var village := village_of(stash.village_index)
	if village != null and _player != null and is_instance_valid(_player):
		village.robbed(value, _player.global_position)


## El SettlementManager de [loader] (un PlanetLoader), o null.
static func of(loader: Object) -> SettlementManager:
	return (loader as Node).get_node_or_null(^"Settlements") as SettlementManager if loader is Node else null


## Los poblados para el mapa: [{"v", "dir": su centro (unitario, marco del terreno, como los trazos de
## TrailMap), "kind": la plantilla (&"granja", &"aldea", &"poblado", &"villa"), "name": "" si el jugador
## no lo conoce}]. Lo conoce si lo ha visto de cerca o si un encargo abierto lo nombra.
func map_sites() -> Array:
	if _sites.size() != _villages.size():
		_sites.clear()
		for v in _villages.size():
			var plan: Dictionary = _villages[v]
			_sites.append({"v": v, "dir": (plan.center as Vector3).normalized(),
				"kind": StringName(plan.get("template", &"")), "name": ""})
	var named := _known.duplicate()
	for quest: Dictionary in quests.open_list():
		for field in ["village", "dest"]:
			if quest.get(field) != null:
				named[int(quest[field])] = true
	for site: Dictionary in _sites:
		var v: int = site.v
		if named.has(v) and String(site.name).is_empty():
			site.name = SettlementPopulation.village_name(v, _seed)
		elif not named.has(v):
			site.name = ""
	return _sites


## Si el jugador conoce el poblado [v] (map_sites).
func is_known(v: int) -> bool:
	return _known.has(v)


## Los poblados levantados: {casa: grids}. Para las pruebas.
func get_built() -> Dictionary:
	return _built


## La gente de los poblados.
func get_people() -> SettlementVillagers:
	return _people


func get_companions() -> SettlementCompanions:
	return _companions


## El poblado [v] con su gente, si está a la vista (SettlementVillagers), o null.
func village_of(v: int) -> SettlementVillage:
	return _people.village(v) if _people != null else null


## Si el poblado [v] tiene todas sus casas levantadas (o ya son de la partida): puede tener gente.
func village_ready(v: int) -> bool:
	for b in (_villages[v].buildings as Array).size():
		var key := _key(v, b)
		if not _claimed.has(key) and (not _built.has(key) or _queued.has(Vector2i(v, b))):
			return false
	return true


## Si la casa [b] del poblado [v] está levantada y sigue siendo del poblado.
func is_settled(v: int, b: int) -> bool:
	return _built.has(_key(v, b))


## La puerta (WoodenDoor) de la casa [b] del poblado [v], o null. (El poblado va detrás: SettlementVillage
## la pide con door_of.bind(v).)
func door_of(b: int, v: int) -> WoodenDoor:
	for grid: GridBase in _built.get(_key(v, b), []):
		for info: Dictionary in grid.get_all_props().values():
			if info.get("item_id") != &"wooden_door":
				continue
			var anchor: Node = info.get("node")
			if anchor != null and is_instance_valid(anchor):
				for child in anchor.get_children():
					if child is WoodenDoor:
						return child
	return null


## Ha caído [creature] (NPCController.KILLS_GROUP): si ha sido el jugador o su compañero, cuenta para los
## encargos de caza, y se avisa de cómo van.
func creature_killed(creature: NPCController, killer: Object) -> void:
	if director != null:
		director.on_killed(creature)
	if killer == null or not is_instance_valid(killer) or (killer != _player and not killer is Companion) \
			or _terrain == null or not is_instance_valid(creature):
		return
	var at := _terrain.global_transform.affine_inverse() * creature.global_position
	var hotbar: Node = _player.get("hotbar") if _player != null and is_instance_valid(_player) else null
	for quest: Dictionary in quests.killed(creature.npc_type, at):
		if hotbar != null:
			hotbar.notify(tr("VQUEST_PROGRESS") % [quest.name, VillagerTalk.quest_status(quest)])


func get_save_data() -> Dictionary:
	return {"claimed": _claimed.keys(), "relations": relations.save_data(), "trade": trade.save_data(),
		"quests": quests.save_data(), "known": _known.keys()}


## Antes de cargar una partida: GridManager va a quitar todas las grids, y al vaciarse avisan; las del
## poblado se sueltan antes para que no cuenten como tocadas.
func prepare_restore() -> void:
	if not _pending.is_empty():
		_built[_pending.key] = _pending.grids
		_pending = {}
	for key: String in _built:
		for grid: GridBase in _built[key]:
			if grid.settlement == key:
				grid.settlement = ""
	_built.clear()
	for key: String in _decor.keys():
		_free_decor(key)
	for v: int in _walls.keys():
		_free_wall(v)
	if _people != null:
		_people.clear()
	_queue.clear()
	_queued.clear()


func restore_save_data(data: Dictionary) -> void:
	prepare_restore()
	_claimed.clear()
	for key in data.get("claimed", []):
		_claimed[str(key)] = true
	_known.clear()
	for v in data.get("known", []):
		_known[int(v)] = true
	if _far != null:
		_far.reset()
	relations.restore(data.get("relations", {}))
	trade.restore(data.get("trade", {}))
	quests.restore(data.get("quests", {}))
	_timer = 0.0
