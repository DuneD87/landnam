class_name SettlementVillagers extends Node

## La gente de los poblados (Villager). Cuando el jugador se acerca a uno con todas sus casas levantadas
## (SettlementManager), el poblado cobra vida (SettlementVillage, con su hoguera, SettlementFire), y sus
## vecinos (SettlementPopulation) salen por cercanía: cada uno aparece donde le toca a esa hora (en su
## lecho de noche, en su puesto en hora de trabajo, en la plaza si no), y solo si ese sitio está a menos de
## NEAR del jugador (NEAR_INSIDE si es dentro de una casa), los más cercanos primero y como mucho
## MAX_PEOPLE a la vez. Se visten en un hilo de fondo, de uno en uno (crear un humano cuesta ~100 ms: en el
## hilo principal sería un tirón por cada uno). Quien queda a más de FAR se va, y vuelve a salir donde le
## toque cuando el jugador se acerca. Así una villa de cien vecinos solo tiene en pie a los de alrededor.
## Al alejarse del poblado se va todo el mundo. No se guardan: salen siempre iguales del plano.

const CHECK_INTERVAL := 0.5
## Hasta dónde sale la gente (m): a su sitio de fuera, a uno de dentro de una casa, y cuándo se va.
const NEAR := 90.0
const NEAR_INSIDE := 30.0
const FAR := 130.0
## Los que pueden estar en pie a la vez, entre todos los poblados.
const MAX_PEOPLE := 60
## Un perro por cada tantas casas con gente, y como mucho estos.
const DOG_HOMES := 3
const MAX_DOGS := 6
## Las miradas (CHECK_INTERVAL) que un figurante lleva vestido antes de hacerle su cuerpo de multitud.
const STAND_IN_SETTLE := 3

var _manager: SettlementManager
var _host: Node3D
var _terrain: Node3D
var _player: Node3D
var _villages: Array = []
var _prefabs := {}
var _seed := 1
var _spawn_distance := 200.0
var _despawn_distance := 260.0
## Poblado -> SettlementVillage, los que tienen gente.
var _active := {}
## Poblado -> cuántas veces se ha ido su gente: lo que se esté vistiendo de antes se tira.
var _generation := {}
## Poblado -> sus perros (SettlementAnimal), sueltos mientras tiene vida.
var _dogs := {}
## Poblado -> sus vecinos: {"who" (SettlementPopulation), "state": AWAY (sin cuerpo), DRESSING o OUT, y "villager"}.
var _roster := {}
enum { AWAY, DRESSING, OUT }
## Por vestir: {"village", "generation", "resident", "pieces"}; y vestidos: [trabajo, humano].
var _jobs: Array = []
var _done: Array = []
var _lock := Mutex.new()
var _task := -1
var _timer := 0.0
## La multitud de lejos: los vecinos que aún no tienen cuerpo (lejos, o vistiéndose) se ven de pie en su
## sitio, sin nodo ni esqueleto (CrowdBody en un MultiMesh). Poblado -> {"nodes", "signature"}.
var _crowds := {}
## Vecino ("id") -> [el sitio que se buscó, dónde dio con el suelo o null]; y si va con la malla de lejos.
var _crowd_ground := {}
var _crowd_far := {}
## Los figurantes: un vecino de cada clase (sexo y ropa) que se viste solo para hacer su cuerpo de
## multitud, que luego llevan de lejos todos los de su clase. Clase -> true (pedido), y los que se
## están ajustando: {"model", "rig", "kind", "wait", "asked"}.
var _stand_in_kinds := {}
var _stand_ins: Array = []


## [manager]: el que levanta las casas; [host]: el padre de los aldeanos (el de las grids);
## [field]: Planet.get_settlements(); [cfg]: settlement_settings.
func setup(manager: SettlementManager, host: Node3D, terrain: Node3D, player: Node3D, field: Dictionary,
		prefabs: Dictionary, cfg: Dictionary) -> void:
	_manager = manager
	_host = host
	_terrain = terrain
	_player = player
	_villages = field.get("villages", [])
	_prefabs = prefabs
	cfg = SettlementField.settings(cfg)
	_seed = int(cfg.seed)
	_spawn_distance = float(cfg.villager_distance)
	_despawn_distance = _spawn_distance + 60.0


func _process(delta: float) -> void:
	CrowdShader.tick(delta)
	if _player == null or not is_instance_valid(_player) or _terrain == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_INTERVAL
		_update()
		_update_stand_ins()
	for v: int in _active:
		(_active[v] as SettlementVillage).update(delta)
	_lock.lock()
	var ready: Array = _done.pop_front() if not _done.is_empty() else []
	_lock.unlock()
	if not ready.is_empty():
		var t0 := Time.get_ticks_usec()
		_spawn(ready[0], ready[1])
		DebugStats.report_cost(&"aldeanos:salir", Time.get_ticks_usec() - t0)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _task < 0 and not _jobs.is_empty():
		_task = WorkerThreadPool.add_task(_dress_all, false, "Villagers")


## Da vida a los poblados cercanos con las casas levantadas y se la quita a los lejanos; y en los vivos,
## saca a los vecinos que tocan y retira a los que quedan lejos (_stream).
func _update() -> void:
	var local := _terrain.global_transform.affine_inverse() * _player.global_position
	for v in _villages.size():
		var plan: Dictionary = _villages[v]
		var d := local.distance_to((plan.center as Vector3) * float(plan.ground))
		if _active.has(v):
			if d > _despawn_distance:
				_leave(v)
		elif d < _spawn_distance and _manager.village_ready(v):
			_arrive(v)
	_stream(local)


## Los vecinos por cercanía al jugador en [local] (marco del terreno): fuera los que se han alejado, y a
## vestir los que tocan, los más cercanos primero, hasta MAX_PEOPLE.
func _stream(local: Vector3) -> void:
	var people := 0
	var wanted: Array = []
	for v: int in _roster:
		var village: SettlementVillage = _active[v]
		for entry: Dictionary in _roster[v]:
			match int(entry.state):
				OUT:
					var villager: Villager = entry.villager
					if not is_instance_valid(villager):
						entry.state = AWAY
					elif villager.local_position().distance_to(local) > FAR and villager.act != Villager.Act.CHAT:
						# Que suelte la puerta si la estaba cruzando, o se quedaría abierta.
						villager._abort_leg()
						village.villagers.erase(villager)
						villager.queue_free()
						entry.state = AWAY
						entry.villager = null
					else:
						people += 1
				DRESSING:
					people += 1
				AWAY:
					if _manager.absent(String(entry.who.id)):
						continue
					var spot := Villager.spawn_point(entry.who, village)
					var d := (spot.at as Vector3).distance_to(local)
					if d < (NEAR_INSIDE if spot.inside else NEAR):
						wanted.append([d, v, entry])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for v: int in _roster:
		_update_crowd(v)
	_lock.lock()
	for item: Array in wanted:
		if people >= MAX_PEOPLE:
			break
		var entry: Dictionary = item[2]
		entry.state = DRESSING
		people += 1
		_jobs.append({"village": item[1], "generation": int(_generation.get(item[1], 0)), "resident": entry.who,
			"pieces": pieces_of(entry.who), "tool": tool_of(entry.who), "entry": entry, "distance": item[0]})
	# Lo que espera, también por cercanía: el que se acerca pasa delante.
	_jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	_lock.unlock()


## La multitud del poblado [v]: una figura por vecino sin cuerpo que ahora estaría fuera, en su sitio
## (Villager.spawn_pose) y con el cuerpo de multitud suyo o de uno de su clase. Solo se rehace si cambia.
func _update_crowd(v: int) -> void:
	var t0 := Time.get_ticks_usec()
	_rebuild_crowd(v)
	DebugStats.report_cost(&"aldeanos:multitud", Time.get_ticks_usec() - t0)


func _rebuild_crowd(v: int) -> void:
	var village: SettlementVillage = _active.get(v)
	if village == null:
		return
	var frame := _terrain.global_transform
	var local := frame.affine_inverse() * _player.global_position
	var space := _host.get_world_3d().direct_space_state if _host.is_inside_tree() else null
	var figures: Array = []
	var signature := 0
	for entry: Dictionary in _roster.get(v, []):
		if int(entry.state) == OUT or _manager.absent(String(entry.who.id)):
			continue
		var pose := Villager.spawn_pose(entry.who, village)
		if pose.inside:
			continue
		var id := String(entry.who.id)
		var kind := CrowdBody.kind_of(entry.who)
		var body := CrowdBody.borrow(id, kind)
		if body == null:
			_ask_stand_in(v, entry.who, kind)
			continue
		# En el suelo de verdad: el sitio del plano puede quedar algo por encima o por debajo.
		var at: Vector3 = pose.at
		var known: Array = _crowd_ground.get(id, [])
		if known.is_empty() or known[0] != at or known[1] == null:
			var above := at.normalized()
			var hit := {}
			if space != null:
				hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(frame * (at + above * 4.0), frame * (at - above * 8.0), 1))
			known = [at, frame.affine_inverse() * (hit.position as Vector3) if not hit.is_empty() else null]
			_crowd_ground[id] = known
		if known[1] == null:
			continue
		# Lejos, con la malla más ligera del cuerpo.
		var far := (known[1] as Vector3).distance_to(local) > CrowdBody.DISTANT_REACH + (0.0 if _crowd_far.get(id, false) else 6.0)
		_crowd_far[id] = far
		figures.append([body, known[1], pose.forward, pose.clip, id, far])
		signature = hash([signature, body.get_instance_id(), known[1], pose.clip, id, far])
	var crowd: Dictionary = _crowds.get(v, {})
	if not crowd.is_empty() and int(crowd.signature) == signature:
		return
	_free_crowd(v)
	if figures.is_empty():
		return
	var up := village.center.normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var origin := Transform3D(Basis(east, up, east.cross(up)), village.center)
	var by_body := {}
	for figure: Array in figures:
		(by_body.get_or_add([figure[0], figure[5]], []) as Array).append(figure)
	var nodes: Array[Node3D] = []
	for key: Array in by_body:
		var body: CrowdBody = key[0]
		var group: Array = by_body[key]
		var node := body.instance(group.size(), key[1])
		var bounds := AABB()
		for i in group.size():
			var at: Vector3 = group[i][1]
			var y := at.normalized()
			var forward: Vector3 = group[i][2]
			if forward == Vector3.ZERO:
				forward = Villager._tangent(village.center - at, at)
			if forward == Vector3.ZERO:
				forward = y.cross(Vector3.RIGHT).normalized()
			var placed := origin.affine_inverse() * Transform3D(Basis(y.cross(forward), y, forward), at)
			node.multimesh.set_instance_transform(i, placed)
			# Cada uno por su punto del clip.
			node.multimesh.set_instance_custom_data(i, CrowdClips.params(group[i][3], 1.0, (hash(group[i][4]) % 997) * 0.01))
			var box := AABB(placed.origin + CrowdBody.BOUNDS.position, CrowdBody.BOUNDS.size)
			bounds = box if i == 0 else bounds.merge(box)
		node.multimesh.custom_aabb = bounds
		node.name = "SettlementCrowd_%d_%d" % [v, nodes.size()]
		node.transform = _host.global_transform.affine_inverse() * frame * origin
		_host.add_child(node)
		nodes.append(node)
	_crowds[v] = {"nodes": nodes, "signature": signature}


func _free_crowd(v: int) -> void:
	for node: Node3D in _crowds.get(v, {}).get("nodes", []):
		if is_instance_valid(node):
			node.queue_free()
	_crowds.erase(v)


## Pide un figurante de la clase [kind] (como [who]), si no hay ya un cuerpo de esa clase ni se ha pedido:
## se viste en la cola de todos, el último.
func _ask_stand_in(v: int, who: Dictionary, kind: String) -> void:
	if _stand_in_kinds.has(kind) or CrowdBody.has_kind(kind):
		return
	_stand_in_kinds[kind] = true
	_lock.lock()
	_jobs.append({"village": v, "generation": int(_generation.get(v, 0)), "resident": who, "pieces": pieces_of(who),
		"tool": "", "distance": 1.0e9, "stand_in": kind})
	_lock.unlock()


## Los figurantes ya vestidos: cuando acaba el ajuste de su ropa se les hace el cuerpo de multitud
## (HumanMerge, en su hilo) y se van.
func _update_stand_ins() -> void:
	var t0 := Time.get_ticks_usec()
	_pick_stand_ins()
	DebugStats.report_cost(&"aldeanos:figurantes", Time.get_ticks_usec() - t0)


func _pick_stand_ins() -> void:
	HumanMerge.pump()
	for stand_in: Dictionary in _stand_ins.duplicate():
		var model: Node3D = stand_in.model
		var rig: CharacterAppearanceRig = stand_in.rig
		if not stand_in.asked:
			if rig != null and rig.is_dressing():
				stand_in.wait = 0
				continue
			stand_in.wait += 1
			if stand_in.wait < STAND_IN_SETTLE:
				continue
			var job := HumanMerge.gather(model)
			if job.is_empty():
				_stand_ins.erase(stand_in)
				model.queue_free()
				continue
			job.far_only = true
			HumanMerge.request(model.get_instance_id(), job)
			stand_in.asked = true
			continue
		var result: Variant = HumanMerge.take(model.get_instance_id())
		if result == null:
			continue
		if not (result as Dictionary).is_empty():
			var body := HumanMerge.crowd(result)
			if body != null:
				body.kind = stand_in.kind
				CrowdBody.remember("kind:" + String(stand_in.kind), body)
		_stand_ins.erase(stand_in)
		model.queue_free()


## El poblado [v] se llena: sus vecinos, por vestir.
func _arrive(v: int) -> void:
	var village := SettlementVillage.new(v, _villages[v], _prefabs, _terrain)
	village.door_of = _manager.door_of.bind(v)
	village.player = _player
	village.name = SettlementPopulation.village_name(v, _seed)
	village.relations = _manager.relations
	village.trade = _manager.trade
	village.quests = _manager.quests
	village.deaths = _manager.deaths
	village.neighbour = _neighbour(v, village.center)
	_active[v] = village
	var fire := SettlementFire.new()
	fire.name = "SettlementFire_%d" % v
	var up := village.center.normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	fire.transform = _host.global_transform.affine_inverse() * _terrain.global_transform \
		* Transform3D(Basis(east, up, east.cross(up)), village.center)
	_host.add_child(fire)
	village.fire = fire
	# Lo que se busca en el catálogo, aquí: en el hilo se cruzaría con el jugador.
	AppearanceCatalog.categories()
	var away := _manager.quests.away_ids()
	var roster: Array = []
	for who in SettlementPopulation.residents(_villages[v], v, _prefabs, _seed):
		# Su casa ya es del jugador (la ha tocado): ahí no vive nadie. Ni quien se ha ido con él, ni el que
		# anda perdido en el monte (un encargo de rescate).
		if not village.homes.has(who.home) or not _manager.is_settled(v, who.home) \
				or _manager.get_companions().has(String(who.id)) or away.has(String(who.id)):
			continue
		roster.append({"who": who, "state": AWAY, "villager": null})
	_roster[v] = roster
	_dogs[v] = _release_dogs(v, village)


## Los perros del poblado [v]: uno por cada DOG_HOMES casas con gente (hasta MAX_DOGS), que van de la
## plaza a la puerta de las casas.
func _release_dogs(v: int, village: SettlementVillage) -> Array[SettlementAnimal]:
	var spots := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, v, "dogs"])
	for i in 6:
		spots.append(village.plaza_spot(rng))
	for b: int in village.homes:
		spots.append(village.homes[b].outside as Vector3)
	var dogs: Array[SettlementAnimal] = []
	for i in clampi(village.homes.size() / DOG_HOMES, 1, MAX_DOGS):
		var kind: StringName = SettlementAnimal.DOGS[rng.randi() % SettlementAnimal.DOGS.size()]
		var dog := SettlementAnimal.create(kind, spots[rng.randi() % spots.size()], _terrain, hash([_seed, v, "dog", i]),
			Transform3D.IDENTITY, Vector2.ZERO, spots)
		if dog == null:
			continue
		_host.add_child(dog)
		dogs.append(dog)
	return dogs


## Lo que viste [who] (SettlementPopulation.residents), para Villager.build_model: [ruta de la escena, si
## tapa el pelo] por pieza.
static func pieces_of(who: Dictionary) -> Array:
	var pieces: Array = []
	for id in who.get("outfit", []):
		var item := ItemCatalog.get_item(StringName(id))
		if item != null and item.scene_path != "":
			pieces.append([item.scene_path, item.armor_slot == ItemData.ArmorSlot.HEAD])
	return pieces


## La escena de la herramienta de [who], o "".
static func tool_of(who: Dictionary) -> String:
	var job: Dictionary = who.get("job", {})
	if not job.has("tool"):
		return ""
	var item := ItemCatalog.get_item(StringName(job.tool))
	return item.scene_path if item != null else ""


## El poblado más cercano a [v] (SettlementVillage.neighbour), de lo que hablan sus vecinos.
func _neighbour(v: int, center: Vector3) -> Dictionary:
	var best := -1
	var best_distance := INF
	for o in _villages.size():
		if o == v:
			continue
		var plan: Dictionary = _villages[o]
		var d := center.distance_to((plan.center as Vector3) * float(plan.ground))
		if d < best_distance:
			best = o
			best_distance = d
	if best < 0:
		return {}
	var there: Vector3 = (_villages[best].center as Vector3) * float(_villages[best].ground)
	var up := center.normalized()
	return {"name": SettlementPopulation.village_name(best, _seed), "toward": (there - center).slide(up).normalized(),
		"distance": best_distance}


## El jugador se ha ido: su gente también, y lo que quedaba por vestir.
func _leave(v: int) -> void:
	var village: SettlementVillage = _active[v]
	_active.erase(v)
	_generation[v] = int(_generation.get(v, 0)) + 1
	for villager in village.villagers:
		if is_instance_valid(villager):
			villager.queue_free()
	village.villagers.clear()
	_roster.erase(v)
	for dog: SettlementAnimal in _dogs.get(v, []):
		if is_instance_valid(dog):
			dog.queue_free()
	_dogs.erase(v)
	if village.fire != null and is_instance_valid(village.fire):
		village.fire.queue_free()
	_free_crowd(v)
	_lock.lock()
	# El figurante que esperaba en su cola se vuelve a pedir cuando haga falta.
	for job: Dictionary in _jobs:
		if job.village == v and job.has("stand_in"):
			_stand_in_kinds.erase(job.stand_in)
	_jobs = _jobs.filter(func(job: Dictionary) -> bool: return job.village != v)
	_lock.unlock()


## En el hilo: viste a los que esperan, de uno en uno.
func _dress_all() -> void:
	while true:
		_lock.lock()
		var job: Dictionary = _jobs.pop_front() if not _jobs.is_empty() else {}
		_lock.unlock()
		if job.is_empty():
			return
		var model := Villager.build_model(job.resident, job.pieces, job.tool)
		_lock.lock()
		_done.append([job, model])
		_lock.unlock()


func _spawn(job: Dictionary, model: Node3D) -> void:
	if job.has("stand_in"):
		# Un figurante: no sale; se queda oculto mientras se le ajusta la ropa (_update_stand_ins).
		model.visible = false
		add_child(model)
		_stand_ins.append({"model": model, "rig": model.get_node_or_null("AppearanceRig"), "kind": job.stand_in,
			"wait": 0, "asked": false})
		return
	var village: SettlementVillage = _active.get(job.village)
	# El que se ha ido con el jugador mientras se vestía (o lo ha sacado la consola) ya no sale.
	if village == null or int(job.generation) != int(_generation.get(job.village, 0)) \
			or _manager.absent(String(job.resident.id)):
		model.free()
		if job.has("entry"):
			job.entry.state = AWAY
		return
	var villager := Villager.new()
	villager.setup(job.resident, village, model)
	village.villagers.append(villager)
	_host.add_child(villager)
	if job.has("entry"):
		job.entry.state = OUT
		job.entry.villager = villager
	# Su figura de multitud se va en el mismo fotograma.
	_update_crowd(job.village)


## Los aldeanos de ahora (para la consola y las pruebas).
func get_villagers() -> Array[Villager]:
	var out: Array[Villager] = []
	for v: int in _active:
		for villager in (_active[v] as SettlementVillage).villagers:
			if is_instance_valid(villager):
				out.append(villager)
	return out


## El poblado [v] si tiene gente ahora, o null.
func village(v: int) -> SettlementVillage:
	return _active.get(v)


## Cuántos quedan por vestir o por aparecer.
func pending() -> int:
	_lock.lock()
	var count := _jobs.size() + _done.size()
	_lock.unlock()
	return count + (1 if _task >= 0 else 0)


## Se va todo el mundo (al cargar una partida): lo que se esté vistiendo se tira al acabar.
func clear() -> void:
	for v: int in _active.keys():
		_leave(v)


func _exit_tree() -> void:
	HumanMerge.shutdown()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	for ready: Array in _done:
		(ready[1] as Node).free()
	_done.clear()
