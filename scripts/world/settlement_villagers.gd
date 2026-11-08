class_name SettlementVillagers extends Node

## La gente de los poblados (Villager). Cuando el jugador se acerca a uno con todas sus casas levantadas
## (SettlementManager), sus vecinos (SettlementPopulation) se visten en un hilo de fondo, de uno en uno
## (crear un humano cuesta ~100 ms: en el hilo principal sería un tirón por cada uno), y cada uno
## aparece donde le toca a esa hora: en su lecho de noche, en la plaza de día. La plaza tiene su hoguera
## (SettlementFire). Al alejarse se van. No se guardan: salen siempre iguales del plano.

const CHECK_INTERVAL := 0.5

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
## Por vestir: {"village", "generation", "resident", "pieces"}; y vestidos: [trabajo, humano].
var _jobs: Array = []
var _done: Array = []
var _lock := Mutex.new()
var _task := -1
var _timer := 0.0


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
	if _player == null or not is_instance_valid(_player) or _terrain == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_INTERVAL
		_update()
	for v: int in _active:
		(_active[v] as SettlementVillage).update(delta)
	_lock.lock()
	var ready: Array = _done.pop_front() if not _done.is_empty() else []
	_lock.unlock()
	if not ready.is_empty():
		_spawn(ready[0], ready[1])
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _task < 0 and not _jobs.is_empty():
		_task = WorkerThreadPool.add_task(_dress_all, false, "Villagers")


## Da gente a los poblados cercanos con las casas levantadas y se la quita a los lejanos.
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


## El poblado [v] se llena: sus vecinos, por vestir.
func _arrive(v: int) -> void:
	var village := SettlementVillage.new(v, _villages[v], _prefabs, _terrain)
	village.door_of = _manager.door_of.bind(v)
	village.player = _player
	village.name = SettlementPopulation.village_name(v, _seed)
	village.relations = _manager.relations
	village.trade = _manager.trade
	village.quests = _manager.quests
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
	var generation: int = _generation.get(v, 0)
	_lock.lock()
	for who in SettlementPopulation.residents(_villages[v], v, _prefabs, _seed):
		# Su casa ya es del jugador (la ha tocado): ahí no vive nadie. Ni quien se ha ido con él.
		if not village.homes.has(who.home) or not _manager.is_settled(v, who.home) \
				or _manager.get_companions().has(String(who.id)):
			continue
		_jobs.append({"village": v, "generation": generation, "resident": who, "pieces": pieces_of(who),
			"tool": tool_of(who)})
	_lock.unlock()


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
	if village.fire != null and is_instance_valid(village.fire):
		village.fire.queue_free()
	_lock.lock()
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
	var village: SettlementVillage = _active.get(job.village)
	if village == null or int(job.generation) != int(_generation.get(job.village, 0)):
		model.free()
		return
	var villager := Villager.new()
	villager.setup(job.resident, village, model)
	village.villagers.append(villager)
	_host.add_child(villager)


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
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	for ready: Array in _done:
		(ready[1] as Node).free()
	_done.clear()
