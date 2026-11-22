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
					if _manager.get_companions().has(String(entry.who.id)):
						continue
					var spot := Villager.spawn_point(entry.who, village)
					var d := (spot.at as Vector3).distance_to(local)
					if d < (NEAR_INSIDE if spot.inside else NEAR):
						wanted.append([d, v, entry])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
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
	# El que se ha ido con el jugador mientras se vestía (o lo ha sacado la consola) ya no sale.
	if village == null or int(job.generation) != int(_generation.get(job.village, 0)) \
			or _manager.get_companions().has(String(job.resident.id)):
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
