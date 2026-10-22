class_name SurvivalActions
extends Node

## Lo que hace el jugador para cubrir sus necesidades (SurvivalNeeds):
## - Con algo de comer, un remedio (RemedyTrait: emplasto, bebedizo, tablilla) o un odre seleccionado
##   en la barra, el clic lo come, se lo pone o bebe un trago; en el inventario, el doble clic.
## - Junto al agua dulce (un río, un lago o una charca), E bebe un trago; con la sed saciada,
##   llena los odres. El agua del mar no quita la sed.
## - E sobre un animal muerto lo despelleja si se lleva en la mano algo que despelleje (el seax:
##   SkinningTrait), lo que lleva un rato (Butchering), y abre lo que da (HuntingLoot) como un botín.
##   También los pequeños (FaunaCorpse: conejos, zorros, aves; a las aves, se las despluma).
## - E junto a una hoguera la abre (InventoryUI.open_campfire); junto a una estación de trabajo,
##   abre la ventana de fabricar en sus recetas (InventoryUI.open_station).
## - Con algo que se planta seleccionado (una hoguera, un banco de trabajo: GroundPlaceableTrait),
##   se ve dónde iría y el clic lo planta en el suelo.
## Los avisos salen sobre la barra rápida (Hotbar.notify). Ver docs/items.md.

const USE_COOLDOWN := 0.7
const WaterAccessQuery = preload("res://scripts/player/water_access.gd")
## Hasta dónde se planta (m desde los pies).
const PLACE_RANGE := 4.5
const GHOST_OK := Color(0.6, 0.9, 0.55, 0.5)
const GHOST_BAD := Color(0.95, 0.35, 0.3, 0.5)

var _player: PlayerController
var _butchering: Butchering
var _cooldown := 0.0
var _ghost: Node3D
var _ghost_scene: PackedScene
var _ghost_material: StandardMaterial3D
var _place_ok := false
var _place_xform := Transform3D.IDENTITY


func setup(player: PlayerController) -> void:
	_player = player
	_butchering = Butchering.new()
	_butchering.name = "Butchering"
	add_child(_butchering)
	_butchering.setup(player)
	_butchering.finished.connect(_on_butchered)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_ghost()
	# La hoguera abierta se cierra al alejarse.
	var fire := _player.inventory_ui.open_campfire_node()
	if fire != null and fire.global_position.distance_to(_player.global_position) > Campfire.REACH + 1.5:
		_player.inventory_ui.close_campfire()


func notify(text: String) -> void:
	if _player.hotbar != null:
		_player.hotbar.notify(text)


# --- Clic con lo seleccionado ---------------------------------------------------------------------

## Clic con algo de la barra que no se empuña: lo come, bebe del odre o lo planta. true si era de
## esto (y el clic ya no hace otra cosa).
func use_selected() -> bool:
	var data := _player.hotbar.get_selected_data()
	if data == null or _player.inventory_ui.visible:
		return false
	return use_item(data)


## Come [data], bebe de él o lo planta. Desde el inventario ([from_inventory], doble clic) no se
## planta: hace falta ver dónde, con la hoguera seleccionada en la barra. true si era de esto.
func use_item(data: ItemData, from_inventory: bool = false) -> bool:
	var ground := data.get_trait(GroundPlaceableTrait) as GroundPlaceableTrait
	if ground != null:
		if from_inventory:
			notify(tr("SURV_PLACE_FROM_BAR"))
		else:
			_place(data, ground)
		return true
	if data.get_trait(WaterContainerTrait) != null:
		_drink_from_skin()
		return true
	var edible := data.get_trait(EdibleTrait) as EdibleTrait
	var remedy := data.get_trait(RemedyTrait) as RemedyTrait
	if edible != null or remedy != null:
		_consume(data, edible, remedy)
		return true
	return false


## Come [data] o se pone el remedio: lo que dé a las necesidades ([edible]) y lo que cure
## ([remedy]). Un remedio que no es comida no se gasta si no hay nada que curar.
func _consume(data: ItemData, edible: EdibleTrait, remedy: RemedyTrait) -> void:
	if _cooldown > 0.0:
		return
	if _player.inventory.get_item_count(data) <= 0:
		notify(tr("SURV_NONE_LEFT") % data.get_display_name().to_lower())
		return
	if edible == null and not _needs_remedy(remedy):
		notify(tr("SURV_NOT_NEEDED"))
		return
	_cooldown = USE_COOLDOWN
	_player.inventory.remove_item(data, 1)
	var poisoned := _player.needs.eat(edible) if edible != null else false
	if remedy != null:
		_treat(remedy)
	if poisoned and _player.combat != null and _player.combat.status != null:
		_player.combat.status.apply(&"intoxication", &"", edible.intoxication_severity)
		notify(tr("SURV_POISONED"))
	elif remedy != null and remedy.use_text != "":
		notify(tr(remedy.use_text))
	else:
		notify(tr("SURV_EAT") % data.get_display_name().to_lower())


## Lo que hace [remedy]: vida, recuperación, sangrado, heridas y estados.
func _treat(remedy: RemedyTrait) -> void:
	var health := _player.health_component
	if remedy.health > 0.0:
		health.heal(remedy.health)
	var combat := _player.combat
	if combat == null:
		return
	if remedy.recovery_time > 0.0 and combat.status != null:
		combat.status.apply(RemedyTrait.RECOVERING, &"", 0.5, remedy.recovery_time)
	if combat.body_damage != null:
		combat.body_damage.treat(remedy.stanch, remedy.mend)
	if combat.status != null:
		for tag in remedy.cures:
			combat.status.cure(tag)


## Si [remedy] tiene algo que hacer: vida que falta, heridas que sangran o que cerrar, o un estado
## que cura.
func _needs_remedy(remedy: RemedyTrait) -> bool:
	var combat := _player.combat
	if combat != null and combat.status != null:
		for tag in remedy.cures:
			if combat.status.can_cure(tag):
				return true
	if remedy.health <= 0.0 and remedy.recovery_time <= 0.0 and remedy.stanch <= 0.0 and remedy.mend <= 0.0:
		return false
	var health := _player.health_component
	if health.health < health.max_health:
		return true
	return combat != null and combat.body_damage != null and combat.body_damage.is_hurt()


func _drink_from_skin() -> void:
	if _cooldown > 0.0:
		return
	var needs := _player.needs
	if needs.water <= 0:
		notify(tr("SURV_SKIN_EMPTY"))
		return
	_cooldown = USE_COOLDOWN
	needs.water -= 1
	needs.drink()
	notify(tr("SURV_DRINK_SKIN") % [needs.water, needs.water_capacity()])


# --- E --------------------------------------------------------------------------------------------

## Despelleja (o despluma) [body] si hace falta (con un cuchillo en la mano; lleva un rato) y, ya
## despellejado, abre lo que da. [body] es un NPCController muerto o un FaunaCorpse.
func open_corpse(body: Node3D) -> void:
	var bird := _is_bird(body)
	if not body.butchered:
		if _butchering.is_active():
			return
		if _skinning_tool() == null:
			notify(tr("SURV_NEED_KNIFE_PLUCK" if bird else "SURV_NEED_KNIFE_SKIN"))
			return
		_butchering.start(body)
		if body.butcher_progress == 0.0:
			notify(tr("SURV_PLUCK_START" if bird else "SURV_SKIN_START"))
		else:
			notify(tr("SURV_PLUCK_RESUME" if bird else "SURV_SKIN_RESUME"))
		return
	_open_loot(body)


func _on_butchered(body: Node3D) -> void:
	var knife := _skinning_tool()
	HuntingLoot.fill(body, knife.yield_mult if knife != null else 1.0)
	body.butchered = true
	notify(tr("SURV_PLUCKED" if _is_bird(body) else "SURV_SKINNED"))
	_open_loot(body)


func _open_loot(body: Node3D) -> void:
	var inventory: Inventory = body.inventory
	if inventory.get_free_slots() >= inventory.max_slots:
		notify(tr("SURV_NOTHING_LEFT"))
		return
	_player.inventory_ui.open_loot(inventory)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Si [body] es un ave (se despluma en vez de despellejarse).
static func _is_bird(body: Node3D) -> bool:
	var corpse := body as FaunaCorpse
	return corpse != null and corpse.plume.a > 0.0


## Abre el descanso en el lecho de al lado, si lo hay.
func open_nearby_bedroll() -> bool:
	var bed := Bedroll.nearest(get_tree(), _player.global_position)
	if bed == null:
		return false
	# El lecho suele estar junto al fuego: deja usar la hoguera o el banco si están más cerca.
	var distance := bed.global_position.distance_to(_player.global_position)
	for other in [Campfire.nearest(get_tree(), _player.global_position),
			Workstation.nearest(get_tree(), _player.global_position)]:
		if other != null and other.global_position.distance_to(_player.global_position) < distance:
			return false
	_player.inventory_ui.close()
	_player.resting.open(bed)
	return true


## Abre la hoguera de al lado, si la hay.
func open_nearby_campfire() -> bool:
	var fire := Campfire.nearest(get_tree(), _player.global_position)
	if fire == null:
		return false
	_player.inventory_ui.open_campfire(fire)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return true


## Abre la ventana de fabricar en las recetas de la estación de trabajo de al lado, si la hay.
func open_nearby_station() -> bool:
	var station := Workstation.nearest(get_tree(), _player.global_position)
	if station == null:
		return false
	_player.inventory_ui.open_station(station)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return true


## Bebe (o llena los odres) si hay agua al alcance. true si había agua, dulce o salada.
func drink_here() -> bool:
	var kind := water_here()
	if kind == &"":
		return false
	if kind == &"salt":
		notify(tr("SURV_SEA_WATER"))
		return true
	var needs := _player.needs
	if needs.thirst < 0.98:
		needs.drink()
		notify(tr("SURV_DRINK_FRESH"))
	elif needs.water < needs.water_capacity():
		needs.water = needs.water_capacity()
		notify(tr("SURV_FILL_SKINS") % needs.water)
	elif needs.water_capacity() > 0:
		notify(tr("SURV_NOT_THIRSTY_FULL"))
	else:
		notify(tr("SURV_NOT_THIRSTY"))
	return true


## Qué agua hay al alcance: &"fresh" (río, lago, charca), &"salt" (mar) o &"".
func water_here() -> StringName:
	var body: Node3D = _player.planet
	var planet: Planet = body.get("planet") as Planet if body != null else null
	if planet == null or not planet.has_water:
		return &""
	var map: PlanetWorldMap = body.get("world_map")
	return WaterAccessQuery.kind_at(_player.global_position, planet.voxel_terrain,
		map.map if map != null and map.is_ready() else null,
		planet.get_river_network(), planet.radius - planet.water_radius)


func _skinning_tool() -> SkinningTrait:
	var data := _player._get_right_hand_item()
	return data.get_trait(SkinningTrait) as SkinningTrait if data != null else null


# --- Plantar --------------------------------------------------------------------------------------

func _selected_placeable() -> GroundPlaceableTrait:
	var data := _player.hotbar.get_selected_data() if _player.hotbar != null else null
	return data.get_trait(GroundPlaceableTrait) as GroundPlaceableTrait if data != null else null


func _update_ghost() -> void:
	var ground := _selected_placeable()
	var active := ground != null and ground.preview_scene != null and not _player.inventory_ui.visible \
		and not _player.free_flight_enabled and _player.input_enabled and _player.visible
	if not active:
		if _ghost != null:
			_ghost.visible = false
		_place_ok = false
		return
	if _ghost == null or _ghost_scene != ground.preview_scene:
		_make_ghost(ground.preview_scene)
	var cam := _player.camera
	var from := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * (PLACE_RANGE + 8.0), PhysicsLayers.WORLD)
	query.exclude = [_player.get_rid()]
	var space := _player.get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit.position as Vector3).distance_to(_player.global_position) > PLACE_RANGE:
		_ghost.visible = false
		_place_ok = false
		return
	var up := -_player.gravity_direction.normalized()
	var at: Vector3 = hit.position
	var exclude: Array[RID] = [_player.get_rid()]
	var fit := GroundFit.fit(space, at, up, _player.global_position - at, ground.radius, PhysicsLayers.WORLD, exclude,
		ground.max_tilt, ground.settle, ground.max_settle)
	if not fit.ok:
		_ghost.visible = false
		_place_ok = false
		return
	_place_xform = fit.transform
	var crowded := _crowded(at, ground.spacing)
	var wet: bool = _player.movement.is_swimming
	_place_ok = fit.tilt <= ground.max_slope and fit.rough <= ground.max_rough and not crowded and not wet
	_ghost.global_transform = _place_xform
	_ghost_material.albedo_color = GHOST_OK if _place_ok else GHOST_BAD
	_ghost.visible = true


## Si hay algo plantado (una hoguera, una estación) a menos de [spacing] de [at].
func _crowded(at: Vector3, spacing: float) -> bool:
	for node in get_tree().get_nodes_in_group(GroundPlaceableTrait.PLACED_GROUP):
		if node is Node3D and (node as Node3D).global_position.distance_to(at) < spacing:
			return true
	return false


## La vista previa: lo que se ve del objeto, todo translúcido.
func _make_ghost(scene: PackedScene) -> void:
	if _ghost != null:
		_ghost.queue_free()
	if _ghost_material == null:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_scene = scene
	_ghost = scene.instantiate() as Node3D
	add_child(_ghost)
	for node in _ghost.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.material_override = _ghost_material
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in _ghost.find_children("*", "Decal", true, false):
		(node as Decal).visible = false


func _place(data: ItemData, ground: GroundPlaceableTrait) -> void:
	if _cooldown > 0.0:
		return
	if _player.inventory.get_item_count(data) <= 0:
		notify(tr("SURV_NONE_LEFT") % data.get_display_name().to_lower())
		return
	if not _place_ok:
		notify(tr("SURV_CANT_PLACE"))
		return
	var scene := load(ground.scene_path) as PackedScene
	if scene == null:
		return
	_cooldown = USE_COOLDOWN
	var node := scene.instantiate() as Node3D
	var parent: Node = _player.planet if _player.planet != null else get_tree().current_scene
	parent.add_child(node)
	node.global_transform = _place_xform
	_player.inventory.remove_item(data, 1)
	notify(tr("SURV_PLACED") % data.get_display_name())
