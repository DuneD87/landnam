class_name SettlementCompanions extends Node

## Los aldeanos que se han ido con el jugador (Companion): los que lo acompañan y los que viven en su
## base (colonos, Companion.Mode.SETTLE). Se recluta en la charla (VillagerChat) a quien
## sea de un poblado que se fía bastante (SettlementRelations.RECRUIT_TRUST): el aldeano deja su poblado,
## que ya no lo saca mientras vaya con el jugador (SettlementVillagers), y se lleva su humano. Se guardan
## con la partida (categoría "npc"): su poblado, su vecino (que se vuelve a sacar del plano, como en el
## poblado), si sigue, espera o vive en la base (y dónde la tiene), dónde está (en el marco del
## terreno), lo que lleva y su vida. Ver docs/villagers.md.

## Cuántos acompañan a la vez, y cuántos viven en la base.
const MAX := 1
const MAX_SETTLERS := 20
## Para que la charla (VillagerChat) lo encuentre.
const GROUP := &"settlement_companions"

var entity_id := ""
var save_category := "npc"

var _manager: SettlementManager
var _host: Node3D
var _terrain: Node3D
var _player: Node3D
var _villages: Array = []
var _prefabs := {}
var _seed := 1
var _list: Array[Companion] = []


## Como SettlementVillagers.setup.
func setup(manager: SettlementManager, host: Node3D, terrain: Node3D, player: Node3D, field: Dictionary,
		prefabs: Dictionary, cfg: Dictionary) -> void:
	_manager = manager
	_host = host
	_terrain = terrain
	_player = player
	_villages = field.get("villages", [])
	_prefabs = prefabs
	_seed = int(SettlementField.settings(cfg).seed)
	add_to_group(GameManager.SAVEABLE_GROUP)
	add_to_group(GROUP)


## Los de ahora (también el que se está yendo a casa).
func get_companions() -> Array[Companion]:
	var out: Array[Companion] = []
	for c in _list:
		if is_instance_valid(c):
			out.append(c)
	return out


## Los encargos (los de SettlementManager), para la charla con un compañero.
func quests() -> SettlementQuests:
	return _manager.quests if _manager != null else null


## Si el vecino [id] (SettlementPopulation: "id") va con el jugador o se está yendo: su poblado no lo saca.
func has(id: String) -> bool:
	for c in get_companions():
		if String(c.resident.get("id", "")) == id:
			return true
	return false


## Si ya van todos los que caben (MAX), sin contar al que se va a casa ni a los colonos.
func is_full() -> bool:
	var count := 0
	for c in get_companions():
		if c.mode == Companion.Mode.FOLLOW or c.mode == Companion.Mode.WAIT:
			count += 1
	return count >= MAX


## Los que viven en la base.
func settler_count() -> int:
	var count := 0
	for c in get_companions():
		if c.mode == Companion.Mode.SETTLE:
			count += 1
	return count


func settlers_full() -> bool:
	return settler_count() >= MAX_SETTLERS


## [villager] se va con el jugador: el compañero que lo sustituye, donde estaba y con su humano.
func recruit(villager: Villager) -> Companion:
	var v := villager.village.index
	var who := villager.resident
	var at := villager.global_transform
	var model := villager.leave_with_player()
	villager.queue_free()
	return _add(v, who, model, at, Companion.Mode.FOLLOW)


func _add(v: int, who: Dictionary, model: Node3D, at: Transform3D, mode: Companion.Mode) -> Companion:
	var plan: Dictionary = _villages[v]
	var companion := Companion.new()
	companion.setup(who, v, SettlementPopulation.village_name(v, _seed), _manager.relations, model, _terrain,
		_player, (plan.center as Vector3) * float(plan.ground))
	companion.gravity = float(_host.get("gravity_strength")) if _host.get("gravity_strength") != null else 9.8
	companion.mode = mode
	companion.transform = _host.global_transform.affine_inverse() * at
	companion.tree_exiting.connect(func() -> void: _list.erase(companion))
	_list.append(companion)
	_host.add_child(companion)
	companion.reset_physics_interpolation()
	return companion


func get_save_data() -> Dictionary:
	var out: Array = []
	var to_local := _terrain.global_transform.affine_inverse()
	for c in get_companions():
		# El que vuelve a casa ya es del poblado.
		if c.mode == Companion.Mode.LEAVE:
			continue
		var at := to_local * c.global_position
		var facing := to_local.basis * c.facing()
		var entry := {"village": c.village, "id": String(c.resident.get("id", "")), "mode": int(c.mode),
			"at": [at.x, at.y, at.z], "facing": [facing.x, facing.y, facing.z], "pack": c.pack.get_save_data(),
			"health": c.health.health}
		if c.mode == Companion.Mode.SETTLE:
			entry.base = [c.base.x, c.base.y, c.base.z]
		out.append(entry)
	return {"companions": out}


## Antes de cargar una partida: los de ahora se van (si la partida no trae ninguno, no queda ninguno).
func prepare_restore() -> void:
	for c in get_companions():
		_list.erase(c)
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
		c.queue_free()


## Cada uno, vestido aquí mismo (es al cargar: un humano son ~100 ms), donde estaba.
func restore_save_data(data: Dictionary) -> void:
	prepare_restore()
	AppearanceCatalog.categories()
	for entry: Dictionary in data.get("companions", []):
		var v := int(entry.get("village", -1))
		if v < 0 or v >= _villages.size():
			continue
		var who := _resident(v, str(entry.get("id", "")))
		if who.is_empty():
			continue
		var raw: Array = entry.get("at", [])
		var facing_raw: Array = entry.get("facing", [])
		if raw.size() != 3:
			continue
		var local := Vector3(raw[0], raw[1], raw[2])
		var up := local.normalized()
		var forward := Vector3(facing_raw[0], facing_raw[1], facing_raw[2]) if facing_raw.size() == 3 \
			else Vector3.FORWARD
		forward = (forward - up * forward.dot(up)).normalized()
		if not forward.is_finite() or forward.is_zero_approx():
			forward = (Vector3.FORWARD - up * up.z).normalized()
		var at := _terrain.global_transform * Transform3D(Basis(up.cross(forward), up, forward), local)
		var model := Villager.build_model(who, SettlementVillagers.pieces_of(who), SettlementVillagers.tool_of(who))
		var saved_mode := int(entry.get("mode", 0))
		var mode := Companion.Mode.WAIT if saved_mode == Companion.Mode.WAIT else Companion.Mode.FOLLOW
		var companion := _add(v, who, model, at, mode)
		var base_raw: Array = entry.get("base", [])
		if saved_mode == Companion.Mode.SETTLE and base_raw.size() == 3:
			companion.settle_here(Vector3(base_raw[0], base_raw[1], base_raw[2]))
		if entry.has("pack"):
			companion.pack.restore_save_data(entry.pack)
		companion.restore_health(float(entry.get("health", -1.0)))


## El vecino [id] del poblado [v], como lo saca su poblado, o {}.
func _resident(v: int, id: String) -> Dictionary:
	for who in SettlementPopulation.residents(_villages[v], v, _prefabs, _seed):
		if String(who.id) == id:
			return who
	return {}
