class_name SurvivalActions
extends Node

## Lo que hace el jugador para cubrir sus necesidades (SurvivalNeeds):
## - Con algo de comer o un odre seleccionado en la barra, el clic lo come o bebe un trago; en el
##   inventario, el doble clic.
## - Junto al agua dulce (un río, un lago o una charca), E bebe un trago; con la sed saciada,
##   llena los odres. El agua del mar no quita la sed.
## - E sobre un animal muerto lo despelleja si se lleva en la mano algo que despelleje (el seax:
##   SkinningTrait) y abre lo que da (HuntingLoot) como un botín.
## - E junto a una hoguera la abre (InventoryUI.open_campfire); junto a una estación de trabajo,
##   abre la ventana de fabricar en sus recetas (InventoryUI.open_station).
## - Con algo que se planta seleccionado (una hoguera, un banco de trabajo: GroundPlaceableTrait),
##   se ve dónde iría y el clic lo planta en el suelo.
## Los avisos salen sobre la barra rápida (Hotbar.notify). Ver docs/items.md.

const USE_COOLDOWN := 0.7
const WaterAccessQuery = preload("res://scripts/player/water_access.gd")
## Hasta dónde se planta (m desde los pies).
const PLACE_RANGE := 4.5
## Terreno, grids y barcos (como DroppedItem.WORLD_MASK).
const WORLD_MASK := 1
const GHOST_OK := Color(0.6, 0.9, 0.55, 0.5)
const GHOST_BAD := Color(0.95, 0.35, 0.3, 0.5)

var _player: PlayerController
var _cooldown := 0.0
var _ghost: Node3D
var _ghost_scene: PackedScene
var _ghost_material: StandardMaterial3D
var _place_ok := false
var _place_xform := Transform3D.IDENTITY


func setup(player: PlayerController) -> void:
	_player = player


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
			notify("Selecciónalo en la barra y haz clic en el suelo para plantarlo")
		else:
			_place(data, ground)
		return true
	if data.get_trait(WaterContainerTrait) != null:
		_drink_from_skin()
		return true
	var edible := data.get_trait(EdibleTrait) as EdibleTrait
	if edible != null:
		_eat(data, edible)
		return true
	return false


func _eat(data: ItemData, edible: EdibleTrait) -> void:
	if _cooldown > 0.0:
		return
	if _player.inventory.get_item_count(data) <= 0:
		notify("No te queda %s" % data.display_name.to_lower())
		return
	_cooldown = USE_COOLDOWN
	_player.inventory.remove_item(data, 1)
	var poisoned := _player.needs.eat(edible)
	if poisoned and _player.combat != null and _player.combat.status != null:
		_player.combat.status.apply(&"intoxication", &"", edible.intoxication_severity)
		notify("Te ha sentado mal: intoxicación")
	else:
		notify("Comes %s" % data.display_name.to_lower())


func _drink_from_skin() -> void:
	if _cooldown > 0.0:
		return
	var needs := _player.needs
	if needs.water <= 0:
		notify("El odre está vacío: llénalo junto a un río o un lago (E)")
		return
	_cooldown = USE_COOLDOWN
	needs.water -= 1
	needs.drink()
	notify("Bebes del odre · %d/%d tragos" % [needs.water, needs.water_capacity()])


# --- E --------------------------------------------------------------------------------------------

## Despelleja [npc] si hace falta (con un cuchillo en la mano) y abre lo que da.
func open_corpse(npc: NPCController) -> void:
	if not npc.butchered:
		var knife := _skinning_tool()
		if knife == null:
			notify("Necesitas un cuchillo en la mano para despellejarlo")
			return
		HuntingLoot.fill(npc, knife.yield_mult)
		npc.butchered = true
		notify("Lo despellejas")
	if npc.inventory.get_free_slots() >= npc.inventory.max_slots:
		notify("Ya no queda nada que aprovechar")
		return
	_player.inventory_ui.open_loot(npc.inventory)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


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
		notify("El agua del mar no quita la sed")
		return true
	var needs := _player.needs
	if needs.thirst < 0.98:
		needs.drink()
		notify("Bebes agua dulce")
	elif needs.water < needs.water_capacity():
		needs.water = needs.water_capacity()
		notify("Llenas los odres · %d tragos" % needs.water)
	elif needs.water_capacity() > 0:
		notify("No tienes sed y los odres están llenos")
	else:
		notify("No tienes sed")
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
	var query := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * (PLACE_RANGE + 8.0), WORLD_MASK)
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
	var fit := GroundFit.fit(space, at, up, _player.global_position - at, ground.radius, WORLD_MASK, exclude,
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
		notify("No te queda %s" % data.display_name.to_lower())
		return
	if not _place_ok:
		notify("Ahí no se puede: busca suelo llano y despejado")
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
	notify("%s en el suelo · E para usarlo" % data.display_name)
