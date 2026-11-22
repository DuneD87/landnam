class_name QuestDirector extends Node

## Lo que los encargos (SettlementQuests) ponen en el mundo, mirado cada CHECK s:
##   - el plazo: el que se pasa se pierde y baja la confianza (SettlementQuests.fail);
##   - rescate: el perdido sale, malherido, donde se perdió (spot, en el suelo) al acercarse el jugador a
##     LOST_SPAWN m, como un compañero que va por un encargo (Companion.ward) y espera; a LOST_BEASTS m
##     salen unas fieras que van a por él. Encontrado, se le dice que siga al jugador (la charla) y, al
##     llegar a HOME_REACH m de su plaza, se va a su casa: el encargo queda para cobrar. Si muere, se
##     pierde. Con el jugador lejos (DESPAWN m) y el perdido esperando, se quita (vuelve a salir luego);
##   - escolta: quien lo pide va con el jugador (start_escort, desde la charla); a ARRIVE_REACH m de la plaza
##     del poblado vecino paga y se vuelve. Por el camino, lejos de los dos poblados (AMBUSH_FROM m), cada
##     AMBUSH_EVERY s salen fieras al paso (hasta AMBUSH_MAX), la primera a por él. Si muere, se pierde;
##   - fiera con nombre: sale en su sitio al acercarse el jugador a BEAST_SPAWN m, más grande (BEAST_SIZE)
##     y dura (BEAST_HEALTH) que ninguna de su especie, con su nombre encima. Muerta (on_killed, por quien
##     sea), suelta su trofeo (SettlementQuests.trophy_of) y el encargo queda para cobrar.
## Lo crea SettlementManager. Ver docs/villagers.md (Encargos).

const CHECK := 1.0
const LOST_SPAWN := 150.0
const LOST_FOUND := 8.0
const LOST_BEASTS := 70.0
const LOST_PACK := 2
## La vida con la que sale el perdido (parte de la suya).
const LOST_HEALTH := 0.45
const DESPAWN := 450.0
const HOME_REACH := 40.0
const ARRIVE_REACH := 45.0
const AMBUSH_EVERY := Vector2(110.0, 200.0)
const AMBUSH_FROM := 250.0
const AMBUSH_MAX := 2
const AMBUSH_PACK := Vector2i(2, 3)
const AMBUSH_DISTANCE := Vector2(28.0, 42.0)
const BEAST_SPAWN := 220.0
const BEAST_SIZE := 1.3
const BEAST_HEALTH := 2.5
## Las fieras que salen si no se sabe de ninguna por allí (las del rescate, las emboscadas).
const DEFAULT_BEAST := &"Wolf"
const SCENES := "res://scenes/animals/%s.tscn"
const META := &"quest_beast"

var manager: SettlementManager
var _terrain: Node3D
var _player: Node3D
var _check := 0.0
## Quien lo pidió ("who") -> la fiera con nombre que ha salido; las que van a por el perdido; lo que falta
## para la siguiente emboscada.
var _beasts := {}
var _packs := {}
var _ambush_left := {}


func setup(owner_manager: SettlementManager, terrain: Node3D, player: Node3D) -> void:
	manager = owner_manager
	_terrain = terrain
	_player = player
	name = "QuestDirector"


func _process(delta: float) -> void:
	if manager == null or _terrain == null or not is_instance_valid(_terrain) or _player == null \
			or not is_instance_valid(_player):
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK
	tick(CHECK)


func tick(dt: float) -> void:
	var quests := manager.quests
	for id in quests.overdue():
		_fail(id, "VQUEST_FAILED_LATE")
	for quest: Dictionary in quests.open_list().duplicate():
		match String(quest.kind):
			"rescue":
				_rescue(quest)
			"escort":
				_escort(quest, dt)
			"beast":
				_beast(quest)


# --- Rescate --------------------------------------------------------------------------------------

func _rescue(quest: Dictionary) -> void:
	var id := String(quest.who)
	var stage := String(quest.stage)
	if stage == "home":
		return
	var companions := manager.get_companions()
	var ward := companions.ward_of(id)
	if ward == null:
		if companions.is_dead(String(quest.lost)):
			_fail(id, "VQUEST_FAILED_DEAD")
			return
		var spot := ground(SettlementQuests.vec(quest.spot))
		if spot.is_finite() and _player.global_position.distance_to(spot) < LOST_SPAWN:
			_spawn_lost(quest, spot)
		return
	var distance := ward.global_position.distance_to(_player.global_position)
	if stage == "search":
		if distance < LOST_FOUND:
			manager.quests.set_stage(id, "found")
			_notify(tr("VQUEST_FOUND") % quest.lost_name)
		elif distance < LOST_BEASTS and not _packs.has(id):
			_packs[id] = _spawn_pack(_species(quest), LOST_PACK, ward.global_position, Vector2(16.0, 24.0), ward)
	if ward.mode == Companion.Mode.WAIT and distance > DESPAWN and stage == "search":
		# Lejos y esperando: se quita hasta que vuelva el jugador (las fieras también).
		_free_pack(id)
		ward.queue_free()
		return
	var home := _terrain.global_transform * manager.quests.center_of(int(quest.village))
	if ward.global_position.distance_to(home) < HOME_REACH:
		manager.quests.set_stage(id, "home")
		ward.go_home()
		_free_pack(id)
		_notify(tr("VQUEST_RESCUE_DONE") % [quest.lost_name, quest.name])


## El perdido, malherido y esperando, en [spot] (mundo, en el suelo).
func _spawn_lost(quest: Dictionary, spot: Vector3) -> void:
	var v := int(quest.village)
	var who := {}
	for resident: Dictionary in manager.quests.residents_of.call(v):
		if String(resident.id) == String(quest.lost):
			who = resident
			break
	if who.is_empty():
		return
	var model := Villager.build_model(who, SettlementVillagers.pieces_of(who), SettlementVillagers.tool_of(who))
	var up := (spot - _terrain.global_position).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var forward := side.rotated(up, randf() * TAU)
	var at := Transform3D(Basis(up.cross(forward).normalized(), up, forward), spot + up * 0.05)
	var c := manager.get_companions().add_ward(String(quest.who), Companion.Mode.WAIT, null, v, who, model, at)
	c.health.health = c.health.max_health * LOST_HEALTH


# --- Escolta --------------------------------------------------------------------------------------

## Se ha aceptado [quest]: el perdido de un rescate, si anda por su poblado, se va de allí (está en el
## monte).
func on_accepted(quest: Dictionary) -> void:
	if String(quest.kind) != "rescue":
		return
	var village := manager.village_of(int(quest.village))
	if village == null:
		return
	for villager in village.villagers.duplicate():
		if is_instance_valid(villager) and String(villager.resident.get("id", "")) == String(quest.lost):
			village.villagers.erase(villager)
			villager.queue_free()


## Acepta la escolta de [villager]: se va con el jugador como compañero de encargo.
func start_escort(villager: Villager, quest: Dictionary) -> Companion:
	var c := manager.get_companions().add_ward(String(quest.who), Companion.Mode.FOLLOW, villager)
	_ambush_left[String(quest.who)] = randf_range(AMBUSH_EVERY.x, AMBUSH_EVERY.y)
	return c


func _escort(quest: Dictionary, dt: float) -> void:
	var id := String(quest.who)
	if String(quest.stage) != "travel":
		return
	var companions := manager.get_companions()
	var ward := companions.ward_of(id)
	if ward == null:
		if companions.is_dead(id):
			_fail(id, "VQUEST_FAILED_DEAD")
		return
	var to_local := _terrain.global_transform.affine_inverse()
	var dest := manager.quests.center_of(int(quest.dest))
	var here := to_local * ward.global_position
	if here.distance_to(dest) < ARRIVE_REACH:
		_arrive(quest, ward)
		return
	# Emboscadas: lejos de los dos poblados, con el escoltado siguiendo al jugador.
	var player_here := to_local * _player.global_position
	if ward.mode != Companion.Mode.FOLLOW or player_here.distance_to(dest) < AMBUSH_FROM \
			or player_here.distance_to(manager.quests.center_of(int(quest.village))) < AMBUSH_FROM \
			or int(quest.get("ambushes", 0)) >= AMBUSH_MAX:
		return
	var left := float(_ambush_left.get(id, AMBUSH_EVERY.y)) - dt
	_ambush_left[id] = left
	if left > 0.0:
		return
	_ambush_left[id] = randf_range(AMBUSH_EVERY.x, AMBUSH_EVERY.y)
	var up := player_here.normalized()
	var ahead := (dest - player_here).slide(up).normalized()
	var pack := _spawn_pack(_species(quest), randi_range(AMBUSH_PACK.x, AMBUSH_PACK.y), _player.global_position,
		AMBUSH_DISTANCE,
		ward, _terrain.global_transform.basis * ahead)
	if not pack.is_empty():
		quest.ambushes = int(quest.get("ambushes", 0)) + 1
		_notify(tr("VQUEST_AMBUSH") % quest.name)


## Han llegado: le paga ahí mismo y se vuelve.
func _arrive(quest: Dictionary, ward: Companion) -> void:
	var id := String(quest.who)
	manager.quests.set_stage(id, "arrived")
	var result := manager.quests.complete(id)
	var reward: Dictionary = result.get("reward", {})
	var inventory := _player.get("inventory") as Inventory
	if inventory != null:
		BuildCost.give(reward, inventory, _player, _player.get("gravity_direction"))
	var said := VillagerTalk.pick(&"ESCORT_ARRIVED", RandomNumberGenerator.new())
	_notify(tr("VQUEST_SAYS") % [quest.name, said.text])
	if not reward.is_empty():
		_notify(tr("VQUEST_REWARD") % [quest.name, reward_text(reward)])
	_ambush_left.erase(id)
	ward.go_home()


# --- Fiera con nombre -----------------------------------------------------------------------------

func _beast(quest: Dictionary) -> void:
	var id := String(quest.who)
	if String(quest.stage) == "slain":
		return
	var beast: NPCController = _beasts.get(id)
	if beast != null and is_instance_valid(beast) and not beast.is_dead:
		if beast.global_position.distance_to(_player.global_position) > DESPAWN * 1.5:
			beast.queue_free()
			_beasts.erase(id)
		return
	var spot := ground(SettlementQuests.vec(quest.spot))
	if not spot.is_finite() or _player.global_position.distance_to(spot) > BEAST_SPAWN:
		return
	var up := (spot - _terrain.global_position).normalized()
	beast = spawn_creature(StringName(quest.species), spot, up)
	if beast == null:
		return
	beast.set_meta(META, id)
	var biggest: CreatureVariant
	for v in beast.variants:
		if biggest == null or v.size.y > biggest.size.y:
			biggest = v
	beast.apply_variant(biggest, (biggest.size.y if biggest != null else 1.0) * BEAST_SIZE)
	beast.health_component.max_health *= BEAST_HEALTH
	beast.health_component.health = beast.health_component.max_health
	var label := Label3D.new()
	label.text = tr(String(quest.beast_name))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.font_size = 30
	label.outline_size = 8
	label.modulate = Color(1.0, 0.72, 0.4)
	label.visibility_range_end = 45.0
	label.position = Vector3.UP * (2.2 * beast.body_size)
	beast.add_child(label)
	_beasts[id] = beast
	_notify(tr("VQUEST_BEAST_NEAR") % tr(String(quest.beast_name)))


## Ha caído [creature] (por quien sea): si era la fiera con nombre de un encargo, suelta su trofeo y el
## encargo queda para cobrar.
func on_killed(creature: NPCController) -> void:
	if creature == null or not is_instance_valid(creature) or not creature.has_meta(META):
		return
	var id := String(creature.get_meta(META))
	var quest := manager.quests.open_of(id)
	_beasts.erase(id)
	if quest.is_empty() or String(quest.kind) != "beast":
		return
	manager.quests.set_stage(id, "slain")
	var up := (creature.global_position - _terrain.global_position).normalized()
	var trophy := SettlementQuests.trophy_of(StringName(quest.species))
	for item_id: StringName in trophy:
		var data := ItemCatalog.get_item(item_id)
		if data != null:
			DroppedItem.spawn_at(creature, data, int(trophy[item_id]), creature.global_position + up * 1.0, -up)
	_notify(tr("VQUEST_BEAST_DEAD") % [tr(String(quest.beast_name)), quest.name])


# --- Lo común -------------------------------------------------------------------------------------

func _fail(id: String, reason: String) -> void:
	var result := manager.quests.fail(id)
	if result.is_empty():
		return
	var quest: Dictionary = result.quest
	_free_pack(id)
	_ambush_left.erase(id)
	if _beasts.has(id):
		var beast: NPCController = _beasts[id]
		if is_instance_valid(beast) and not beast.is_dead:
			beast.queue_free()
		_beasts.erase(id)
	# El escoltado o el perdido que aún va con el jugador se vuelve a casa.
	var ward := manager.get_companions().ward_of(id)
	if ward != null:
		ward.ward = ""
		ward.go_home()
	_notify(tr(reason) % [quest.name, roundi(float(result.lost))])


## Las fieras que van con el encargo: las que rondan su sitio (las de la caza) o, si no, lobos.
func _species(quest: Dictionary) -> StringName:
	var species := StringName(quest.get("beasts", ""))
	return species if species != &"" else DEFAULT_BEAST


## [count] de [species] a [distance] m de [center] (mundo) hacia [toward] (o alrededor), en el suelo; la
## primera va a por [target].
func _spawn_pack(species: StringName, count: int, center: Vector3, distance: Vector2, target: Node3D,
		toward := Vector3.ZERO) -> Array[NPCController]:
	var out: Array[NPCController] = []
	var up := (center - _terrain.global_position).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var base := toward.slide(up).normalized() if toward != Vector3.ZERO else side.rotated(up, randf() * TAU)
	var leader: NPCController
	for i in count:
		var dir := base.rotated(up, deg_to_rad(randf_range(-35.0, 35.0)))
		var at := ground(_terrain.global_transform.affine_inverse() * (center + dir * randf_range(distance.x, distance.y)))
		if not at.is_finite():
			continue
		var animal := spawn_creature(species, at, up)
		if animal == null:
			continue
		if leader == null:
			leader = animal
			if target != null and animal.ai_controller != null:
				animal.ai_controller.target = target
		else:
			animal.join_group(leader)
		out.append(animal)
	return out


func _free_pack(id: String) -> void:
	for animal: NPCController in _packs.get(id, []):
		if is_instance_valid(animal) and not animal.is_dead \
				and animal.global_position.distance_to(_player.global_position) > 60.0:
			animal.queue_free()
	_packs.erase(id)


## Una [species] (npc_type) en [at] (mundo, en el suelo), como las de la consola, o null.
func spawn_creature(species: StringName, at: Vector3, up: Vector3) -> NPCController:
	var path := SCENES % String(species)
	if not ResourceLoader.exists(path):
		path = SCENES % String(DEFAULT_BEAST)
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var animal := scene.instantiate() as NPCController
	if animal == null:
		return null
	get_tree().current_scene.add_child(animal)
	animal.planets = _player.get("planets")
	animal.corpse_duration = 120.0
	animal.global_position = at + up * 1.2
	animal.add_to_group("floating_origin")
	return animal


## El suelo bajo [local] (marco del terreno), en el mundo, o Vector3.INF si aún no está cargado.
func ground(local: Vector3) -> Vector3:
	if not local.is_finite():
		return Vector3.INF
	var at := _terrain.global_transform * local
	var up := (at - _terrain.global_position).normalized()
	var query := PhysicsRayQueryParameters3D.create(at + up * 120.0, at - up * 120.0, PhysicsLayers.WORLD)
	var hit := _terrain.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else Vector3.INF


static func reward_text(reward: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_id: StringName in reward:
		var data := ItemCatalog.get_item(item_id)
		if data != null:
			parts.append("%s ×%d" % [data.get_display_name(), int(reward[item_id])])
	return ", ".join(parts)


func _notify(text: String) -> void:
	var hotbar: Node = _player.get("hotbar") if _player != null and is_instance_valid(_player) else null
	if hotbar != null:
		hotbar.notify(text)
