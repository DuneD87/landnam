extends PlanetaryBody
class_name PlayerController

## Controlador del jugador: orquesta movimiento, cámara, nado/flotación, construcción, combate,
## inventario/equipamiento, la cinemática de entrada y el guardado/carga, sobre un cuerpo planetario.

const PLATFORM_ATTACH_DIST := 1.5
const PLATFORM_DETACH_DIST := 2.5
const PLATFORM_MAX_TILT_DEG := 75.0
const PLATFORM_DETACH_GRACE := 0.2

## Comprobaciones seguidas de suelo listo antes de activar al jugador, y cada cuánto sondear.
## Varias confirmaciones evitan activar sobre una malla visual cuya colisión aún se hornea.
const GROUND_READY_CONFIRMATIONS := 3
const GROUND_READY_POLL_INTERVAL := 0.1
## Tope de espera de suelo: si se agota (p. ej. guardado en el aire, o terreno que no carga) se
## activa igual y el jugador cae con normalidad, en vez de quedar congelado esperando un suelo
## que no existe bajo sus pies. Un spawn normal confirma suelo mucho antes de este tope.
const GROUND_READY_TIMEOUT := 15.0

## Altura de la boca del cañón sobre el origen de PlayerModel, que está a ras de pies. Es la del
## centro de la cápsula del jugador (0.901 en third_person_player.tscn): la bala sale del pecho.
const MUZZLE_HEIGHT := 0.9
## Segundos manteniendo el gatillo para llegar al boquete máximo. La carga escala el RADIO, y el
## radio decide la energía, así que un disparo cargado del todo cuesta ~500 veces más que uno seco.
const CANNON_CHARGE_TIME := 3.0

const config = preload("res://scripts/config.gd")
const data = preload("res://scripts/items/item_data.gd")
@onready var movement: Movement = $Movement
@onready var health_component: HealthComponent = $HealthComponent
@onready var camera_controller: CameraController = $CameraController
@onready var camera: Camera3D = $CameraPivot/PitchPivot/Camera3D
@onready var animation_controller: AnimationController = $AnimationController
@onready var free_flight_controller: FreeFlightController = $FreeFlightController
@onready var collision_model: CollisionShape3D = $CollisionShape3D
@onready var player_model: Node3D = $PlayerModel
@onready var action_controller: ActionController = $ActionController
@onready var inventory: Inventory = $Inventory
@onready var inventory_ui: InventoryUI = $InventoryUI
@onready var character_window: CharacterWindow = $CharacterWindow
@onready var hotbar: Hotbar = $Hotbar
@onready var building_system: BuildingSystem = $BuildingSystem
@onready var build_preview: BuildPreview = $BuildPreview
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var build_menu: BuildMenu = $BuildMenu
@onready var step_up: StepUpSystem = $StepUpSystem

var ship_spawn_menu: ShipSpawnMenu
var grid_manipulator_menu: GridManipulatorMenu
var world_map_ui: WorldMapUI
var blueprint_placer: BlueprintPlacer
var debug_stats: DebugStats
## Aplica la apariencia de GameManager.character al PlayerModel (ver CharacterAppearanceRig).
var appearance_rig: CharacterAppearanceRig
## Combate cuerpo a cuerpo y a distancia, esquivas, objetivo fijado y muerte (ver PlayerCombat).
var combat: PlayerCombat

@export var main_menu: Control
@export var spawn_point: Marker3D
@export var start_first_person: bool = false
@export var animator_tree: AnimationTree
@export var mouse_sensitivity: float = 0.002
@export var invert_y: bool = false
@export var swimming_pitch_angle: float = 90.0 
@export var swimming_rotation_speed: float = 5.0 
## Profundidad de agua (m) a la que se empieza a nadar. Se compara contra el origen del cuerpo, que
## en third_person_player.tscn está en los PIES (cápsula de 1.81 m centrada en y = 0.901), así que
## este número es literalmente cuánta agua hay que tener encima. A 1.0 se nadaba con el agua por la
## cintura, en calma y sin que llegara ninguna ola: se leía como que el nado se adelantaba al oleaje.
@export var swimming_offset: float = 1.45
@export var ray_distance: float = 8.0
@export_flags_3d_physics var ray_collision_mask: int = 3

@export var float_depth := 1.0
@export var surface_stiffness := 10.0
@export var surface_damping := 5.0
@export var max_correction_speed := 8.0

@export var cinematic_duration: float = 16.0
@export var cinematic_ease: Tween.EaseType = Tween.EASE_OUT
@export var cinematic_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var entity_id: String = "player"
var save_category: String = "player"

var _ray_hit: Dictionary = {}

var _platform_body: DynamicGridBody = null
var _platform_prev_xform: Transform3D
var _platform_miss_time: float = 0.0

var current_water_time: float = 0.0
var water_sampler: WaterHeightSampler
var mouse_captured = true
var free_flight_enabled = false

## Gatillo del cañón: se carga mientras se mantiene y dispara al soltar. La acumulación va en
## _physics_process y no por eventos, para que funcione igual en vuelo libre, cuyo camino de input
## corta antes de llegar al ataque.
var _cannon_charging: bool = false
var _cannon_charge: float = 0.0
var current_swimming_pitch: float = 0.0
var current_animation = config.ANIMATION.IDLE

var _water_surface_radius: float = 0.0
var _water_surface_center: Vector3 = Vector3.ZERO
## Corriente del agua en la posición del jugador, muestreada en _check_needs_swimming.
var _water_flow: Vector3 = Vector3.ZERO
## Si los pies estaban dentro del agua en la ultima comprobacion. El chapoteo va en el CRUCE de
## la lamina, no en el estado de nado, que empieza metro y medio mas abajo.
var _feet_in_water: bool = false

var equiped_weapon: ItemData
var right_hand_equipped: bool = false
var is_holding_atack: bool = false

## Materiales con iluminación planetaria que el jugador lleva encima (cuerpo, armaduras,
## herramienta en mano) y el nodo Planet en el que están dados de alta (no el loader).
## Ver _register_worn_node.
var _worn_planet_materials: Array[ShaderMaterial] = []
var _worn_materials_planet: Node = null

var input_enabled: bool = false
var _cinematic_tween: Tween

func _perform_raycast() -> void:
	_ray_hit = {}
	if not camera or not camera.current:
		return
 
	var viewport := get_viewport()
	var screen_center := viewport.get_visible_rect().size * 0.5
	var space_state := get_world_3d().direct_space_state
 
	var player_rid: RID = get_rid()
 
	var cam_origin := camera.project_ray_origin(screen_center)
	var cam_dir := camera.project_ray_normal(screen_center)
	var extra := 0.0 if free_flight_enabled else camera.global_position.distance_to(global_position)
	var cam_end := cam_origin + cam_dir * (ray_distance + extra) 
	var cam_query := PhysicsRayQueryParameters3D.create(cam_origin, cam_end)
	cam_query.collision_mask = ray_collision_mask
	if player_rid.is_valid():
		cam_query.exclude = [player_rid]
 
	var cam_hit := space_state.intersect_ray(cam_query)
	if cam_hit.is_empty():
		if building_system.build_mode:
			building_system.clear_target()
		return
 
	var hit_pos: Vector3 = cam_hit["position"]
	var reference_pos := camera.global_position if free_flight_enabled else global_position
	if reference_pos.distance_to(hit_pos) > ray_distance:
		if building_system.build_mode:
			building_system.clear_target()
		return
 
	_ray_hit = cam_hit
	if building_system.build_mode:
		var hit_normal: Vector3 = _ray_hit["normal"]
		var hit_collider: Object = _ray_hit["collider"]
		building_system.process_raycast(hit_collider, hit_normal, hit_pos, _ray_hit)
	

func _on_voxel_mined(item_id: StringName, amount: int) -> void:
	var item_data := config.get_item(item_id)
	if item_data:
		var excess := inventory.add_item(item_data, amount)
		print("+%d %s" % [amount - excess, item_data.display_name])

func _on_target_destroyed(position: Vector3, amount: int, item_data: ItemData) -> void:
	var excess = inventory.add_item(item_data, amount)
	print("+%d %s" % [amount - excess, item_data.display_name])
	if excess > 0:
		_spawn_dropped_items(item_data, excess, position)
	

func _spawn_dropped_items(item_data: ItemData, amount: int, position: Vector3) -> void:
	pass
	
func capture_mouse(capture: bool):
	mouse_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)

## Da de alta en el planeta los materiales de iluminación planetaria de un nodo que el jugador
## pasa a llevar encima (armadura, herramienta) para que reciban el push de sol cada frame.
func _register_worn_node(node: Node) -> void:
	for mat in _collect_planet_materials(node):
		if not _worn_planet_materials.has(mat):
			_worn_planet_materials.append(mat)
			if _worn_materials_planet != null:
				_worn_materials_planet.register_planet_material(mat)


## Contrario de _register_worn_node: se llama ANTES de sacar el nodo del esqueleto.
func _unregister_worn_node(node: Node) -> void:
	for mat in _collect_planet_materials(node):
		_worn_planet_materials.erase(mat)
		if _worn_materials_planet != null:
			_worn_materials_planet.unregister_planet_material(mat)


## ShaderMaterials del subárbol que usan la iluminación planetaria, mirando override de nodo,
## overrides de superficie y los materiales propios de la malla (donde viven los de los .tscn
## de equipo). Se identifican por tener el uniform light_direction: así entra cualquier shader
## que incluya planet_lighting.gdshaderinc sin listar rutas.
func _collect_planet_materials(node: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for mesh in _find_mesh_instances(node):
		var candidates: Array[Material] = [mesh.material_override, mesh.material_overlay]
		for surface in mesh.get_surface_override_material_count():
			candidates.append(mesh.get_surface_override_material(surface))
			if mesh.mesh != null:
				candidates.append(mesh.mesh.surface_get_material(surface))
		for mat in candidates:
			var shader_mat := mat as ShaderMaterial
			if shader_mat == null or shader_mat.shader == null or found.has(shader_mat):
				continue
			for uniform in shader_mat.shader.get_shader_uniform_list():
				if uniform.name == "light_direction":
					found.append(shader_mat)
					break
	return found


func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		meshes.append_array(_find_mesh_instances(child))
	return meshes


## Traslada el registro de lo que lleva puesto al planeta actual. El push de sol lo hace cada
## planeta sobre su propia lista, así que al cambiar de planeta hay que rehacerlo o el equipo
## se quedaría iluminado con el centro y el sol del anterior. Mientras el planeta no haya
## terminado de cargar no hay a quién registrarse y se reintenta en el siguiente frame.
func _rebind_worn_materials() -> void:
	var core: Node = planet.planet if planet != null and is_instance_valid(planet) else null
	if core == _worn_materials_planet:
		return
	if _worn_materials_planet != null and is_instance_valid(_worn_materials_planet):
		for mat in _worn_planet_materials:
			_worn_materials_planet.unregister_planet_material(mat)
	_worn_materials_planet = core
	if core != null:
		for mat in _worn_planet_materials:
			core.register_planet_material(mat)


func equip_item(equip: bool, slot: ItemData.ArmorSlot, scene: PackedScene, data: ItemData, category: ItemData.Category) -> void:
	if equip:
		match category:
			ItemData.Category.TOOL, ItemData.Category.WEAPON:
				equiped_weapon = data
				var item = scene.instantiate()
				# El combate decide la mano y el marco de agarre (armas en metros, arco en la
				# izquierda, herramientas antiguas con su propia escala).
				combat.attach_weapon(item, data)
				_register_worn_node(item)
				right_hand_equipped = true
			ItemData.Category.ARMOR:
				var item = scene.instantiate()
				item.item_data = ItemData.clone(data)
				player_model.get_node("Armature/Skeleton3D").add_child(item)
				# Made for the old scan; the rig fits it to this character's body.
				appearance_rig.dress(item, data.armor_slot == ItemData.ArmorSlot.HEAD)
				_register_worn_node(item)
	else:
		match category:
			ItemData.Category.TOOL, ItemData.Category.WEAPON:
				var equipped_child := combat.detach_weapon()
				if equipped_child != null:
					_unregister_worn_node(equipped_child)
					equipped_child.queue_free()
				right_hand_equipped = false
			ItemData.Category.ARMOR:
				var children = player_model.get_node("Armature/Skeleton3D").get_children()
				for child in children:
					if "item_data" in child and child.item_data:
						var remove_condition = data.armor_slot == ItemData.ArmorSlot.LEGS && child.item_data.armor_slot == ItemData.ArmorSlot.LEGS
						remove_condition = remove_condition || data.armor_slot == ItemData.ArmorSlot.CHEST && child.item_data.armor_slot == ItemData.ArmorSlot.CHEST
						remove_condition = remove_condition || data.armor_slot == ItemData.ArmorSlot.HEAD && child.item_data.armor_slot == ItemData.ArmorSlot.HEAD
						remove_condition = remove_condition || data.armor_slot == ItemData.ArmorSlot.HANDS && child.item_data.armor_slot == ItemData.ArmorSlot.HANDS
						remove_condition = remove_condition || data.armor_slot == ItemData.ArmorSlot.FEET && child.item_data.armor_slot == ItemData.ArmorSlot.FEET

						if remove_condition:
							appearance_rig.undress(child)
							_unregister_worn_node(child)
							player_model.get_node("Armature/Skeleton3D").remove_child(child)
						
		
func on_equipment_changed(slot: ItemData.ArmorSlot, item: InventoryItem, equip: bool) -> void:
	var data = item.data
	var scene: PackedScene = load(item.data.scene_path)
	var category = data.category
	if category == ItemData.Category.TOOL || category == ItemData.Category.WEAPON || category == ItemData.Category.ARMOR:
		equip_item(equip, slot, scene, data, category)

func _on_hotbar_selection_changed(old_data: ItemData, new_data: ItemData) -> void:
	var old_is_block := old_data != null and old_data.category == ItemData.Category.BLOCK
	var new_is_block := new_data != null and new_data.category == ItemData.Category.BLOCK
	var old_is_equippable := old_data != null and (old_data.category == ItemData.Category.TOOL or old_data.category == ItemData.Category.WEAPON)
	var new_is_equippable := new_data != null and (new_data.category == ItemData.Category.TOOL or new_data.category == ItemData.Category.WEAPON)

	var new_is_placeable := new_data != null and new_data.placeable

	if new_is_block:
		building_system.select_block(new_data.block_id)
		building_system.set_material_by_id(new_data.build_material_id)
		building_system.set_build_mode(true)
		if old_is_equippable:
			_unequip_right_hand()
	elif new_is_placeable:
		building_system.select_placeable(new_data)
		building_system.set_build_mode(true)
		if old_is_equippable:
			_unequip_right_hand()
	elif new_is_equippable:
		building_system.select_placeable(null)
		building_system.set_build_mode(false)
		_equip_from_hotbar(old_data, new_data)
	else:
		building_system.select_placeable(null)
		building_system.set_build_mode(false)
		if old_is_equippable:
			_unequip_right_hand()

	inventory.inventory_changed.emit()


func _equip_from_hotbar(old_data: ItemData, new_data: ItemData) -> void:
	# Consume una sola unidad del item a equipar, conservando el resto del stack.
	for i in inventory.items.size():
		if inventory.items[i] and inventory.items[i].data.id == new_data.id:
			inventory.items[i].remove(1)
			if inventory.items[i].is_empty():
				inventory.items[i] = null
			break

	var old_is_equippable := old_data != null and (old_data.category == ItemData.Category.TOOL or old_data.category == ItemData.Category.WEAPON)
	if old_is_equippable:
		var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
		if eq_slot and eq_slot.has_item():
			var unequipped = character_window.unequip_item(eq_slot)
			if unequipped:
				inventory.add_item(unequipped.data, 1)

	var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
	if eq_slot:
		var inv_item := InventoryItem.new(new_data, 1)
		var returned = character_window.equip_item(eq_slot, inv_item)
		if returned:
			inventory.add_item(returned.data, 1)
	inventory.inventory_changed.emit()


func _unequip_right_hand() -> void:
	var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
	if eq_slot and eq_slot.has_item():
		var unequipped = character_window.unequip_item(eq_slot)
		if unequipped:
			var target = inventory.find_empty_slot()
			if target >= 0:
				inventory.items[target] = InventoryItem.new(unequipped.data, 1)
				current_animation = config.ANIMATION.IDLE


func _get_right_hand_item() -> ItemData:
	var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
	if eq_slot and eq_slot.has_item() and eq_slot.equipped_item:
		return eq_slot.equipped_item.data
	return null


## Consume el item equipado en la mano derecha (al colocar el prop que llevas en la mano):
## lo desequipa sin devolverlo al inventario.
func _consume_right_hand_item() -> bool:
	var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
	if eq_slot == null or not eq_slot.has_item():
		return false
	var unequipped = character_window.unequip_item(eq_slot)
	if unequipped:
		current_animation = config.ANIMATION.IDLE
		return true
	return false
	
	
func _ready():
	add_to_group(GameManager.SAVEABLE_GROUP)
	add_to_group("player")
	GameManager.register_player(self)
	GameManager.state_changed.connect(_on_game_state_changed)
	hotbar.selection_changed.connect(_on_hotbar_selection_changed)
	building_system.set_equipped_item_hooks(_get_right_hand_item, _consume_right_hand_item)
	movement.landed.connect(_on_landed)
	health_component.died.connect(_on_player_died)
	action_controller.voxel_mined.connect(_on_voxel_mined)
	free_flight_enabled = true
	visible = false
	collision_model.disabled = true
	build_menu.setup(hotbar, building_system)
	ship_spawn_menu = ShipSpawnMenu.new()
	ship_spawn_menu.spawn_requested.connect(_on_ship_spawn_requested)
	add_child(ship_spawn_menu)
	grid_manipulator_menu = GridManipulatorMenu.new()
	grid_manipulator_menu.save_requested.connect(_on_grid_save_requested)
	grid_manipulator_menu.delete_requested.connect(_on_grid_delete_requested)
	grid_manipulator_menu.convert_requested.connect(_on_grid_convert_requested)
	grid_manipulator_menu.load_requested.connect(_on_blueprint_load_requested)
	grid_manipulator_menu.closed.connect(capture_mouse.bind(true))
	add_child(grid_manipulator_menu)
	blueprint_placer = BlueprintPlacer.new()
	blueprint_placer.aim_collision_mask = ray_collision_mask
	blueprint_placer.finished.connect(_set_scroll_consumers_enabled.bind(true))
	add_child(blueprint_placer)
	debug_stats = DebugStats.new()
	add_child(debug_stats)
	combat = PlayerCombat.new()
	add_child(combat)
	combat.setup(self)
	world_map_ui = WorldMapUI.new()
	world_map_ui.setup(self)
	add_child(world_map_ui)

	capture_mouse(false)
	water_sampler = WaterHeightSampler.new()
	add_child(water_sampler)
	inventory.clear()
	inventory.add_item(config.get_item(&"firstage_skin_boots"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_hands"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_pants"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_chest"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_hood"), 1)
	inventory.add_item(config.get_item(&"stone_axe_01"), 1)
	inventory.add_item(config.get_item(&"stone_pickaxe_01"), 1)
	# Armas para plantar cara a la fauna hostil: una de cada familia y su munición.
	for weapon_id in [&"iron_sword", &"battle_axe", &"iron_mace", &"hunting_bow", &"slingshot"]:
		inventory.add_item(config.get_item(weapon_id), 1)
	inventory.add_item(config.get_item(&"spear"), 3)
	inventory.add_item(config.get_item(&"arrow"), 40)
	inventory.add_item(config.get_item(&"wood_01"), 100)
	inventory.add_item(config.get_item(&"stone_01"), 100)

	inventory_ui.setup(inventory, character_window, hotbar)
	hotbar.selection_changed.connect(_on_hotbar_selection_changed)
	character_window.equipment_changed.connect(on_equipment_changed)
	# El cuerpo del jugador no pasa por el equipamiento: se registra aquí para que también
	# reciba el sol si su malla usa un material planetario.
	_register_worn_node(player_model)
	appearance_rig = CharacterAppearanceRig.new()
	appearance_rig.name = "AppearanceRig"
	player_model.add_child(appearance_rig)
	# The body comes from the rig; until a character is created or loaded it is the default one.
	appearance_rig.apply(GameManager.character.appearance if GameManager.character else CharacterAppearance.new())
	var btnSave := main_menu.find_child("btnSaveGame")
	btnSave.visible = false
	# Si hay partida guardada, el SpawnPoint se adelanta a la posición guardada del jugador antes de
	# usarlo, para que el terreno empiece a streamearse ahí y el planeta elegido sea el correcto.
	if spawn_point:
		GameManager.apply_saved_spawn_point(GameManager.MAIN_SLOT, spawn_point)
	if spawn_point and planets and planets.get_child_count() > 0:
		var closest: Node3D = null
		var closest_dist := INF
		for p in planets.get_children():
			var dist := spawn_point.global_position.distance_to(p.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = p
		planet = closest
		if planet and planet.planet.has_water:
			water_sampler.setup(planet.water_sphere.quadtree_material, planet.world_map)
			
			
func get_save_data() -> Dictionary:
	var inventory_data: Array[Dictionary] = []
	for i in inventory.items.size():
		var item: InventoryItem = inventory.items[i]
		if item != null and item.data != null:
			inventory_data.append({
				"item_id": str(item.data.id),
				"quantity": item.quantity,
				"slot_index": i
			})

	var equipment_data: Dictionary = {}
	for slot_type in character_window.equipment_slots:
		var eq_slot: EquipmentSlot = character_window.equipment_slots[slot_type]
		if eq_slot.has_item() and eq_slot.equipped_item.data != null:
			equipment_data[str(int(slot_type))] = str(eq_slot.equipped_item.data.id)

	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	var save_pos: Vector3 = fo.to_canonical(global_position) if fo != null else global_position
	return {
		"position": {
			"x": save_pos.x,
			"y": save_pos.y,
			"z": save_pos.z
		},
		"basis": {
			"xx": global_basis.x.x, "xy": global_basis.x.y, "xz": global_basis.x.z,
			"yx": global_basis.y.x, "yy": global_basis.y.y, "yz": global_basis.y.z,
			"zx": global_basis.z.x, "zy": global_basis.z.y, "zz": global_basis.z.z,
		},
		"camera": {
			"yaw": camera_controller.camera_pivot.rotation.y,
			"pitch": camera_controller.camera_pivot.get_node("PitchPivot").rotation.x,
			"distance": camera_controller.camera_distance,
		},
		"inventory": inventory_data,
		"equipment": equipment_data,
		"game_state": {
			"free_flight": free_flight_enabled,
			"input_enabled": input_enabled,
			"current_water_time": current_water_time,
		},
		"hotbar": hotbar.get_save_data(),
		"hotbar_selected": hotbar.selected_index,
		"character": GameManager.character.to_dict() if GameManager.character else {},
	}

	
func restore_save_data(save: Dictionary) -> void:
	input_enabled = false
	global_position = Vector3(save.position.x, save.position.y, save.position.z)
	var b = save.basis
	global_basis = Basis(
		Vector3(b.xx, b.xy, b.xz),
		Vector3(b.yx, b.yy, b.yz),
		Vector3(b.zx, b.zy, b.zz),
	)

	camera_controller.camera_pivot.rotation.y = save.camera.yaw
	camera_controller.camera_pivot.get_node("PitchPivot").rotation.x = save.camera.pitch
	camera_controller.camera_distance = save.camera.distance
	camera_controller.update_camera_transform()
	
	var character_data: Variant = save.get("character")
	if character_data is Dictionary and not character_data.is_empty():
		GameManager.character = CharacterData.from_dict(character_data)
		appearance_rig.apply(GameManager.character.appearance)

	free_flight_enabled = save.game_state.free_flight
	input_enabled = save.game_state.input_enabled
	current_water_time = save.game_state.get("current_water_time", 0.0)

	_clear_visual_equipment()

	inventory.clear()
	for entry in save.inventory:
		var item_data: ItemData = config.get_item(StringName(entry.item_id))
		if item_data:
			inventory.add_item_at(item_data, int(entry.quantity), int(entry.slot_index))
		else:
			push_warning("SaveSystem: item desconocido '%s'" % entry.item_id)

	for slot_type in character_window.equipment_slots:
		var eq_slot: EquipmentSlot = character_window.equipment_slots[slot_type]
		if eq_slot.has_item():
			eq_slot.clear()

	for slot_key_str in save.equipment:
		var slot_type: ItemData.ArmorSlot = int(slot_key_str) as ItemData.ArmorSlot
		var item_id: String = save.equipment[slot_key_str]
		var item_data: ItemData = config.get_item(StringName(item_id))
		if item_data and character_window.equipment_slots.has(slot_type):
			var eq_slot: EquipmentSlot = character_window.equipment_slots[slot_type]
			var inv_item := InventoryItem.new(item_data, 1)
			eq_slot.set_item(inv_item)
			equip_item(true, item_data.armor_slot, load(item_data.scene_path), item_data, item_data.category)
	if save.has("hotbar"):
		hotbar.restore_save_data(save.hotbar, config)
	if save.has("hotbar_selected") and save.hotbar_selected >= 0:
		hotbar.select_slot(save.hotbar_selected)
	combat.on_restored()
	_activate_player()

func place_block_at_player() -> void:
	var block_data: BlockData = BlockDatabase.get_block(BlockDatabase.BLOCK_SLOPE_ID)

	var block := StaticBody3D.new()
	block.name = "Block_%s" % block_data.block_name

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = block_data.mesh
	block.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	collider.shape = block_data.collision_shape
	if block_data.collision_shape is BoxShape3D:
		collider.position.y = block_data.cell_size * 0.5
	block.add_child(collider)

	block.global_position = global_position

	get_tree().current_scene.add_child(block)
	block.add_to_group("floating_origin")
## Reposiciona a mano el CameraPivot (top_level) tras un rebase de FloatingOrigin.
func shift_origin(offset: Vector3) -> void:
	var pivot: Node3D = camera_controller.camera_pivot
	pivot.global_position -= offset
	pivot.reset_physics_interpolation()

	# La transform cacheada de la plataforma vive en el marco pre-rebase; desplázala
	# también o _apply_platform_movement le aplicaría un salto de 'offset' extra al jugador.
	if _platform_body and is_instance_valid(_platform_body):
		_platform_prev_xform.origin -= offset


func post_restore() -> void:
	if planets and planets.get_child_count() > 0:
		var closest: Node3D = null
		var closest_dist := INF
		for p in planets.get_children():
			var dist := global_position.distance_to(p.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = p
		planet = closest
		building_system.current_planet = planet

		if planet and planet.planet.has_water:
			water_sampler.setup(planet.water_sphere.quadtree_material, planet.world_map)

	if input_enabled:
		visible = true
		collision_model.disabled = false		
	
	if planet:
		gravity_direction = planet.get_gravity_direction(global_position)
		up_direction = -gravity_direction

	current_swimming_pitch = 0.0
	player_model.rotation = Vector3.ZERO


func _clear_visual_equipment() -> void:
	var weapon_node := combat.detach_weapon()
	if weapon_node != null:
		_unregister_worn_node(weapon_node)
		weapon_node.queue_free()
	equiped_weapon = null
	right_hand_equipped = false

	var skeleton = player_model.get_node("Armature/Skeleton3D")
	for child in skeleton.get_children():
		if "item_data" in child and child.item_data:
			_unregister_worn_node(child)
			skeleton.remove_child(child)
			child.queue_free()

			
func _find_nearby_corpse(max_dist: float = 4.0) -> NPCController:
	for node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node):
			continue
		var npc := node as NPCController
		if npc and npc.is_dead and global_position.distance_to(npc.global_position) <= max_dist:
			return npc
	return null


func can_perform_action() -> bool:
	return not (
		combat.is_busy() or
		action_controller.is_attacking or
		movement.is_running or
		movement.is_sprinting or
		movement.is_swimming or
		movement.is_falling or
		inventory_ui.visible
	)



func _on_game_state_changed(new_state: GameManager.State) -> void:
	print("[Player] State changed to: %s" % GameManager.State.keys()[new_state])
	match new_state:
		GameManager.State.MENU:
			input_enabled = false
			var btnSave := main_menu.find_child("btnSaveGame")
			btnSave.visible = false
			var btnStartGame := main_menu.find_child("btnStartGame")
			btnStartGame.visible = true
		GameManager.State.CINEMATIC:
			input_enabled = false
			if GameManager.character:
				appearance_rig.apply(GameManager.character.appearance)
			_play_cinematic()
		GameManager.State.PLAYING:
			var btnSave := main_menu.find_child("btnSaveGame")
			btnSave.visible = true
			var btnStartGame := main_menu.find_child("btnStartGame")
			btnStartGame.visible = false
			_activate_player()

func _play_cinematic() -> void:
	
	if not spawn_point:
		push_error("Player: No spawn_point assigned!")
		GameManager.cinematic_completed()
		return
		
	var pitch_pivot := camera_controller.camera_pivot.get_node("PitchPivot")
	var saved_yaw: float = camera_controller.camera_pivot.rotation.y
	var saved_pitch: float = pitch_pivot.rotation.x
	
	var start_pos := global_position
	var start_quat := Quaternion(global_basis)
	var end_pos := spawn_point.global_position
	var end_quat := Quaternion(spawn_point.global_basis.orthonormalized())


	if _cinematic_tween and _cinematic_tween.is_valid():
		_cinematic_tween.kill()

	_cinematic_tween = create_tween()
	_cinematic_tween.set_parallel(true)

	_cinematic_tween.tween_property(
		self, "global_position",
		end_pos, cinematic_duration
	).from(start_pos).set_ease(cinematic_ease).set_trans(cinematic_trans)

	_cinematic_tween.tween_method(
		_interpolate_rotation.bind(start_quat, end_quat),
		0.0, 1.0, cinematic_duration
	).set_ease(cinematic_ease).set_trans(cinematic_trans)

	_cinematic_tween.tween_property(
		camera_controller.camera_pivot, "rotation:y",
		spawn_point.rotation.y, cinematic_duration
	).from(saved_yaw).set_ease(cinematic_ease).set_trans(cinematic_trans)

	_cinematic_tween.tween_property(
		pitch_pivot, "rotation:x",
		spawn_point.rotation.x, cinematic_duration
	).from(saved_pitch).set_ease(cinematic_ease).set_trans(cinematic_trans)
	
	_cinematic_tween.tween_property(
		camera_controller.camera_pivot, "rotation:z",
		spawn_point.rotation.z, cinematic_duration
	).from(camera_controller.camera_pivot.rotation.z).set_ease(cinematic_ease).set_trans(cinematic_trans)
	
	_cinematic_tween.set_parallel(false)
	_cinematic_tween.tween_callback(_on_cinematic_tween_finished)

func _on_cinematic_tween_finished() -> void:
	GameManager.cinematic_completed()



func _on_landed(impact_speed: float) -> void:
	health_component.take_fall_damage(impact_speed)

func _on_player_died() -> void:
	# TODO: pantalla de muerte, respawn, etc.
	print("[Player] Died — impact or damage")

func _interpolate_rotation(t: float, from_quat: Quaternion, to_quat: Quaternion) -> void:
	global_basis = Basis(from_quat.slerp(to_quat, t))

## Keep camera following player during cinematic
func _process(_delta: float) -> void:
	_advance_water_time(_delta)
	if GameManager.current_state == GameManager.State.CINEMATIC:
		camera_controller.camera_pivot.global_position = global_position
	_perform_raycast()
	if blueprint_placer and blueprint_placer.is_active():
		blueprint_placer.update_aim()


func _activate_player() -> void:
	free_flight_enabled = false
	collision_model.disabled = false
	visible = true
	player_model.rotation = Vector3.ZERO
	current_swimming_pitch = 0.0

	update_nearest_planet()
	if planet:
		gravity_direction = planet.get_gravity_direction(global_position)
		up_direction = -gravity_direction

	var confirmations := 0
	var waited := 0.0
	while confirmations < GROUND_READY_CONFIRMATIONS and waited < GROUND_READY_TIMEOUT:
		await get_tree().create_timer(GROUND_READY_POLL_INTERVAL).timeout
		waited += GROUND_READY_POLL_INTERVAL
		confirmations = confirmations + 1 if is_ground_ready() else 0
	mouse_captured = true
	input_enabled = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	inventory.add_item(config.get_item(&"stone_pickaxe_01"), 1)
	
func is_mouse_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	
func _input(event):
	# La pantalla de creación de personaje gestiona su propio Escape.
	if GameManager.current_state == GameManager.State.CHARACTER_CREATION:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		if blueprint_placer and blueprint_placer.is_active():
			blueprint_placer.cancel()
			return
		if inventory_ui.visible:
			inventory_ui.close()
			capture_mouse(true)
			return
		if character_window.visible:
			character_window.toggle()
			capture_mouse(true)
			return
		if ship_spawn_menu and ship_spawn_menu.visible:
			ship_spawn_menu.toggle()
			capture_mouse(true)
			return
		if grid_manipulator_menu and grid_manipulator_menu.visible:
			grid_manipulator_menu.close()
			capture_mouse(true)
			return
		if world_map_ui and world_map_ui.visible:
			world_map_ui.close()
			capture_mouse(true)
			return
		if is_mouse_captured():
			input_enabled = false
			main_menu.fade_in()
			capture_mouse(false)
		else:
			input_enabled = true
			main_menu.fade_out()
			capture_mouse(true)
 
	if not input_enabled:
		return
	# Muerto no se hace nada hasta reaparecer (el menú de Escape sí, arriba).
	if combat.is_dead():
		return
 
	if event is InputEventKey and event.pressed and not blueprint_placer.is_active():
		if event.is_action_pressed("open_build_menu"):
			build_menu.toggle()
			if build_menu.visible:
				capture_mouse(false)
			else:
				capture_mouse(true)
		elif event.is_action_pressed("open_ship_menu") and not _is_text_field_focused():
			ship_spawn_menu.toggle()
			capture_mouse(not ship_spawn_menu.visible)
		elif event.is_action_pressed("open_grid_menu") and not _is_text_field_focused():
			grid_manipulator_menu.toggle(building_system.get_aimed_grid(_ray_hit))
			capture_mouse(not grid_manipulator_menu.visible)
		elif event.is_action_pressed("world_map") and not _is_text_field_focused():
			world_map_ui.toggle()
			capture_mouse(not world_map_ui.visible)

	# Con el menú de grids o el mapa abiertos el ratón es de la UI: los clics que van a sus
	# botones (o que arrastran el mapa) no deben además colocar bloques ni girar la cámara.
	if grid_manipulator_menu.visible or world_map_ui.visible:
		return

	if blueprint_placer.is_active() and _handle_blueprint_placement(event):
		return

	if free_flight_enabled:
		player_model.visible = false
		if event is InputEventMouseMotion and mouse_captured:
			free_flight_controller.delta_yaw += -event.relative.x * mouse_sensitivity
			free_flight_controller.delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	else:
		if !camera_controller.first_person:
			player_model.visible = true
		camera_controller._input(event)
 
	if event.is_action_pressed("toggle_free_flight"):
		free_flight_enabled = !free_flight_enabled
		if free_flight_enabled:
			print("Free flight activado")
			free_flight_controller.orientation = Quaternion(camera.global_transform.basis)
		else:
			print("Free flight desactivado")
 
	if building_system.build_mode and not blueprint_placer.is_active():
		_handle_build_input(event)

	# El cañón sí se dispara volando: es la forma cómoda de probar impactos contra barcos sin
	# tener que acercarse por tierra. Va ANTES del corte de vuelo libre, que apaga todo el input
	# de personaje de aquí abajo.
	if free_flight_enabled:
		if Input.is_action_just_pressed("attack_1") and right_hand_equipped 				and not building_system.build_mode and not inventory_ui.visible 				and equiped_weapon != null 				and equiped_weapon.weapon_type == ItemData.WeaponType.CANNON:
			_begin_cannon_charge()
		return

	# Colocando un blueprint no se ataca, ni se recoge, ni se abre el inventario: el clic es
	# para confirmar. Input.is_action_just_pressed sigue viendo el clic ya consumido en los
	# eventos siguientes del mismo frame, así que el corte tiene que ser por modo.
	if blueprint_placer.is_active():
		return

	if event.is_action_pressed("inventory"):
		inventory_ui.toggle()
		if inventory_ui.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
 
	if event.is_action_pressed("character_window"):
		character_window.toggle()
 
	if event.is_action_pressed("action") && !free_flight_enabled:
		var corpse := _find_nearby_corpse()
		if corpse:
			inventory_ui.open_loot(corpse.inventory)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif combat.try_pickup():
			pass
		else:
			var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
			var item_data = action_controller.handle_pickup(camera, ray_origin)
			if item_data != null:
				inventory.add_item(item_data, 1)
	elif event.is_action_pressed("ui_cancel") and visible:
		inventory_ui.close()
 
 
	# Golpes, esquivas, apuntar y fijar objetivo. Lo que el combate no consume (talar o picar
	# con una herramienta sin enemigos cerca, el cañón) sigue abajo.
	if combat.handle_input(event):
		return

	if Input.is_action_just_pressed("attack_1") && can_perform_action() && !building_system.build_mode && right_hand_equipped:
		if equiped_weapon.weapon_type == ItemData.WeaponType.CANNON:
			_begin_cannon_charge()
			return
		if !equiped_weapon.is_attack_animation:
			is_holding_atack = true
			return
		var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
		action_controller.handle_attack(camera, ray_origin, planet.planet, _on_target_destroyed)
	elif Input.is_action_just_released("attack_1"):
		is_holding_atack = false


func _begin_cannon_charge() -> void:
	_cannon_charging = true
	_cannon_charge = 0.0


## Acumula la carga y dispara en cuanto el gatillo deja de estar pulsado. Se resuelve por sondeo y
## no por el evento de soltar porque el camino de input se corta en varios sitios (menús, vuelo
## libre) y un release perdido dejaría el gatillo cargado para siempre.
func _update_cannon_charge(delta: float) -> void:
	if not _cannon_charging:
		return

	if inventory_ui.visible or grid_manipulator_menu.visible or world_map_ui.visible:
		_cannon_charging = false
		return

	if Input.is_action_pressed("attack_1"):
		_cannon_charge = minf(_cannon_charge + delta, CANNON_CHARGE_TIME)
		return

	_cannon_charging = false
	_fire_cannon(_cannon_charge / CANNON_CHARGE_TIME)


## Lanza una bala desde el centro del personaje hacia donde mira la cámara. En vuelo libre el
## modelo está oculto y la colisión desactivada, pero el cuerpo sí sigue a la cámara
## (update_free_flight hace move_and_slide), así que el origen vale igual en los dos modos.
func _fire_cannon(charge: float) -> void:
	var muzzle = $PlayerModel.global_position - gravity_direction * MUZZLE_HEIGHT
	var blast := lerpf(Cannonball.DEFAULT_RADIUS, Cannonball.MAX_CHARGED_RADIUS, clampf(charge, 0.0, 1.0))
	action_controller.fire_cannonball(camera, muzzle, equiped_weapon, planet, blast)


## true si el foco está en un campo de texto (p. ej. el SpinBox del menú de barco), donde las
## teclas deben escribirse en vez de disparar acciones del jugador.
func _is_text_field_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


## Genera el barco de prueba con las dimensiones del menú y devuelve el control al jugador.
func _on_ship_spawn_requested(length: int, width: int, height: int, compartments: int, decks: int) -> void:
	capture_mouse(true)
	building_system.debug_spawn_ship(true, compartments, length, width, height, decks)


## Guarda como blueprint el grupo de grids apuntado; el menú sigue abierto para seguir operando.
func _on_grid_save_requested(blueprint_name: String) -> void:
	var target: GridBase = grid_manipulator_menu.target_grid
	if not target:
		return

	var blocks := building_system.save_grid_blueprint(target.grid_id, blueprint_name)
	if blocks < 0:
		grid_manipulator_menu.set_status("No se ha podido guardar '%s'." % blueprint_name)
	else:
		grid_manipulator_menu.set_status("Guardado '%s' (%d bloques)." % [blueprint_name, blocks])


## Elimina el grupo de grids apuntado y devuelve el control al jugador.
func _on_grid_delete_requested() -> void:
	var target: GridBase = grid_manipulator_menu.target_grid
	if not target:
		return

	var removed := GridManager.remove_grid_group(target.grid_id)
	grid_manipulator_menu.close()
	capture_mouse(true)
	print("[Player] Grupo de grids eliminado (%d grids)" % removed)


func _on_grid_convert_requested() -> void:
	var target: GridBase = grid_manipulator_menu.target_grid
	if not target:
		return

	var converted := GridManager.convert_to_dynamic(target.grid_id)
	if converted.is_empty():
		grid_manipulator_menu.set_status("No se ha podido convertir a dinámica.")
		return

	# La conversión sustituye las PlanetGrid por DynamicPlanetGrid nuevas: reapunta el menú a
	# la grid resultante o seguiría mostrando (y borrando) las estáticas ya vaciadas.
	grid_manipulator_menu.open(converted[0])
	grid_manipulator_menu.set_status("Convertida a dinámica (%d grids)." % converted.size())


## Cierra el menú y pasa a modo colocación: el blueprint sigue al puntero hasta que confirmes.
func _on_blueprint_load_requested(blueprint_name: String, as_static: bool) -> void:
	var data := GridBlueprint.load_from_disk(blueprint_name)
	if data.is_empty():
		grid_manipulator_menu.set_status("No se ha podido leer '%s'." % blueprint_name)
		return

	if not planet:
		grid_manipulator_menu.set_status("Sin planeta al que anclar la grid.")
		return

	grid_manipulator_menu.close()
	capture_mouse(true)
	blueprint_placer.begin(data, planet, self, camera, as_static)
	# La rueda solo se le cede al placer si de verdad ha arrancado; si no, el zoom se quedaría
	# apagado para siempre.
	if blueprint_placer.is_active():
		_set_scroll_consumers_enabled(false)
	print("[Player] Colocando '%s': clic izq. confirma · der. cancela · rueda gira · ctrl+rueda aleja/acerca · shift+rueda sube/baja" % blueprint_name)


## Clics y rueda del modo colocación. Devuelve true si el evento se ha consumido; la rotación
## de cámara tiene que seguir pasando o no se puede apuntar.
func _handle_blueprint_placement(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				blueprint_placer.confirm()
				get_viewport().set_input_as_handled()
				return true
			MOUSE_BUTTON_RIGHT:
				blueprint_placer.cancel()
				get_viewport().set_input_as_handled()
				return true
			MOUSE_BUTTON_WHEEL_UP:
				_blueprint_wheel(1)
				get_viewport().set_input_as_handled()
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_blueprint_wheel(-1)
				get_viewport().set_input_as_handled()
				return true
	return false


## Rueda durante la colocación: ctrl aleja/acerca, shift sube/baja, sin modificador gira.
func _blueprint_wheel(steps: int) -> void:
	if Input.is_action_pressed("left_ctrl"):
		blueprint_placer.move_depth(steps)
	elif Input.is_action_pressed("left_shift"):
		blueprint_placer.move_height(steps)
	else:
		blueprint_placer.add_yaw(steps)


## Silencia los otros usos de la rueda mientras se coloca un blueprint. Ambos nodos tienen su
## propio _input y, por ser hijos, lo reciben antes que este: consumir el evento aquí llega
## tarde. La cámara se apaga por bandera y no con set_process_input porque su _input también
## acumula el giro de ratón, que sí hace falta para apuntar.
func _set_scroll_consumers_enabled(enabled: bool) -> void:
	camera_controller.zoom_enabled = enabled
	free_flight_controller.set_process_input(enabled)


func _handle_build_input(event: InputEvent) -> void:
	var shift_held := Input.is_action_pressed("left_shift")

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				building_system.execute_primary_action(_ray_hit)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				building_system.toggle_build_mode()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				if shift_held:
					building_system.increase_cell_size()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if shift_held:
					building_system.decrease_cell_size()
				get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed:
		if event.is_action_pressed("toggle_symmetry_mode"):
			building_system.toggle_symmetry(_ray_hit)
			get_viewport().set_input_as_handled()

		elif event.is_action_pressed("switch_symmetry_plane"):
			building_system.switch_symmetry_plane()
			get_viewport().set_input_as_handled()

		if event.is_action_pressed("switch_build_modes"):
			building_system.toggle_action_mode()
			get_viewport().set_input_as_handled()
			
		elif event.is_action_pressed("rotate_block_x"):
			building_system.rotate_block_x()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("rotate_block_y"):
			building_system.rotate_block_y()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("rotate_block_z"):
			building_system.rotate_block_z()
			get_viewport().set_input_as_handled()
		if event.is_action_pressed("convert_dynamic"):
			building_system.convert_aimed_grid(_ray_hit)


func _apply_water_buoyancy(delta: float):
	var to_center := global_position - _water_surface_center
	var distance := to_center.length()
	var radial_dir := to_center.normalized() 
	var surface_offset := distance - (_water_surface_radius - swimming_offset)
	var target_offset := -1.0
	var error := surface_offset - target_offset
	var buoyancy_strength := 1.0
	var damping := 400.0
	var radial_velocity := velocity.dot(radial_dir)
	var correction := (-error * buoyancy_strength - radial_velocity * damping) * delta
	
	velocity += radial_dir * correction


## Monta al nadador sobre el agua: la componente tangencial de la corriente se suma a la velocidad
## como una cinta transportadora. La radial se queda fuera porque de esa ya se ocupa
## _apply_water_buoyancy, que clava al jugador en la superficie y lo sube y baja con ella.
func _apply_water_flow() -> void:
	if _water_flow.is_zero_approx():
		return
	var radial_dir := (global_position - _water_surface_center).normalized()
	velocity += _water_flow - radial_dir * _water_flow.dot(radial_dir)


## El reloj de la ola avanza por FOTOGRAMA, no por tick de física. La interpolación de
## física del proyecto suaviza transforms, no uniforms: con la física a 60 Hz y el render
## sin tope, la fase de la ola —y todo lo que la sigue, incluidos los haces de luz— se
## movía a saltos de 60 Hz mientras el resto iba fluido. La física lee esta misma variable,
## así que el muestreo CPU del oleaje y lo que se dibuja siguen sobre un único reloj.
func _advance_water_time(delta: float) -> void:
	if !planet || !planet.planet.has_water || not is_inside_tree():
		return
	current_water_time += delta
	var sphere: Variant = planet.water_sphere
	if sphere == null or sphere.mesh_manager == null:
		return
	var mat := sphere.mesh_manager.default_material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("water_time", current_water_time)


func _check_needs_swimming(_delta: float):
	if !planet || !planet.planet.has_water || not is_inside_tree():
		AudioManager.set_underwater(false)
		return

	var to_center := global_position - planet.global_position
	var distance_from_center := to_center.length()
	# El mapa del planeta se hornea en un hilo y puede llegar mucho después de que se monte este
	# sampler. setup() lo captura una sola vez, y sin él get_height_at ignora la máscara de temporal
	# y TODA la familia de olas de orilla: la CPU calcularía oleaje de mar abierto a plena amplitud
	# hasta la playa, en otra fase que la rompiente dibujada. Reasignarlo aquí cuesta nada y es lo
	# mismo que hace OceanSystem con su sampler de la línea de flotación por este motivo exacto.
	water_sampler.world_map = planet.world_map
	var wave_height := water_sampler.get_height_at(global_position, current_water_time, planet.global_pos)
		
	# La corriente sale del mismo muestreo, sin coste extra.
	_water_flow = water_sampler.last_flow

	var base_water_radius: float = planet.planet.radius - planet.planet.water_radius
	var water_surface_radius := base_water_radius + wave_height
	_water_surface_radius = water_surface_radius
	# Para la muestra del frame siguiente: la profundidad no se sabe hasta tener la superficie.
	water_sampler.flow_depth = maxf(_water_surface_radius - distance_from_center, 0.0)
	var mat = planet.water_sphere.mesh_manager.default_material as ShaderMaterial
	mat.set_shader_parameter("water_time", current_water_time)
	_water_surface_center = planet.global_position
	# En un compartimento seco de un barco el agua no existe: sin nado bajo la superficie.
	movement.is_swimming = distance_from_center <= (_water_surface_radius - swimming_offset) \
		and not GridManager.is_point_in_dry_interior(global_position)

	# Chapoteo al cruzar la lámina con los pies. El origen del cuerpo está en los pies, así que la
	# comparación es directa; el nado no sirve de disparador porque arranca mucho más abajo.
	var feet_wet := distance_from_center <= _water_surface_radius
	if feet_wet != _feet_in_water:
		_feet_in_water = feet_wet
		var up := to_center / maxf(distance_from_center, 0.001)
		movement.water_crossed.emit(absf(movement.velocity.dot(up)), feet_wet)

	# El filtro submarino lo decide la cámara, no el cuerpo: en tercera persona se nada con los
	# oídos fuera del agua, y el sonido tiene que ir con lo que se ve. El radio de superficie es
	# el muestreado en el jugador; a la distancia de cámara la diferencia es una ola.
	var ears := camera.global_position if camera else global_position
	AudioManager.set_underwater(ears.distance_to(_water_surface_center) <= _water_surface_radius)



func _physics_process(delta: float):
	var _t0 := Time.get_ticks_usec()
	_physics_step(delta)
	DebugStats.report_cost(&"player:control", Time.get_ticks_usec() - _t0)


func _physics_step(delta: float):
	_update_cannon_charge(delta)
	if not input_enabled:
		if GameManager.current_state == GameManager.State.PLAYING:
			camera_controller.update_camera_transform()

		return

	if !mouse_captured || planets == null || planets.get_child_count() == 0:
		return
		
	var closest_distance = global_position.distance_to(planets.get_child(0).position)
	for _planet in planets.get_children():
		var distance = global_position.distance_to(_planet.position)
		if distance <= closest_distance:
			closest_distance = distance
			if _planet != null && _planet.planet.has_water && _planet != planet:
				water_sampler.setup(_planet.water_sphere.quadtree_material, _planet.world_map)
			planet = _planet
			building_system.current_planet = planet

	_rebind_worn_materials()

	free_flight_controller.enabled = free_flight_enabled

	if free_flight_enabled:
		collision_model.disabled = true
		camera_controller.camera_pivot.global_position = global_position
		update_free_flight(delta)
		_check_needs_swimming(delta)
	else:
		if Input.is_action_pressed("left_ctrl") || (Input.is_action_pressed("left_shift") && building_system.build_mode):
			return
		collision_model.disabled = false
		# Colocando un blueprint la rueda es suya: ni zoom, aunque el evento se consuma en _input
		# (esto es polling, no llega por evento).
		if not blueprint_placer.is_active():
			if Input.is_action_just_released("camera_zoom_in"):
				camera_controller.camera_distance -= 1
				camera_controller.update_camera_transform()
			if Input.is_action_just_released("camera_zoom_out"):
				camera_controller.camera_distance += 1
				camera_controller.update_camera_transform()
			
		update_normal_movement(delta)



func update_free_flight(delta: float) -> void:
	free_flight_controller.update_free_flight(delta, camera)
	velocity = free_flight_controller.velocity
	move_and_slide()

func rotate_toward_movement(input_dir: Vector3, delta: float):
	if input_dir.length() < 0.1:
		return
	var target_dir := project_on_gravity_plane(-camera.global_transform.basis.z)
	rotate_toward_direction(target_dir, delta, 3.0)

func apply_swimming_pitch(input_dir: Vector3, delta: float):
	var vertical_component = 0.0
	if input_dir.length() > 0.1:
		var camera_forward = -camera.global_transform.basis.z
		var camera_pitch = asin(clamp(camera_forward.dot(gravity_direction), -1.0, 1.0))
		vertical_component = camera_pitch * 0.5 
	
	var target_pitch = 0.0
	if abs(vertical_component) > 0.1:
		target_pitch = clamp(vertical_component * deg_to_rad(swimming_pitch_angle), -deg_to_rad(swimming_pitch_angle), deg_to_rad(swimming_pitch_angle))
	
	current_swimming_pitch = lerp(current_swimming_pitch, target_pitch, delta * swimming_rotation_speed)
	player_model.rotation = Vector3(current_swimming_pitch, 0, 0)

func _get_platform_point_velocity() -> Vector3:
	if not _platform_body or not is_instance_valid(_platform_body):
		return Vector3.ZERO
	var r := global_position - _platform_body.global_position
	return _platform_body.linear_velocity + _platform_body.angular_velocity.cross(r)
	
func _apply_platform_movement() -> void:
	if not _platform_body or not is_instance_valid(_platform_body):
		return

	var cur_xform := _platform_body.global_transform
	var prev_xform := _platform_prev_xform

	var delta_basis := cur_xform.basis * prev_xform.basis.inverse()
	var offset := global_position - prev_xform.origin
	global_position = cur_xform.origin + delta_basis * offset
	global_basis = (delta_basis * global_basis).orthonormalized()
	
func _detect_platform_raycast() -> DynamicGridBody:
	var space := get_world_3d().direct_space_state
	var origin := global_position
	var end := origin + gravity_direction.normalized() * PLATFORM_DETACH_DIST
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = ray_collision_mask
	query.exclude = [get_rid()]

	var result := space.intersect_ray(query)
	if result.is_empty():
		return null

	var collider = result["collider"]
	if collider is DynamicGridBody:
		return collider
	var parent = collider.get_parent() if collider else null
	if parent is DynamicGridBody:
		return parent
	return null

func _update_platform_tracking(delta: float) -> void:
	var detected := _detect_platform_raycast()

	if detected:
		_platform_miss_time = 0.0
		if detected != _platform_body:
			if _platform_body:
				_platform_body._is_being_controlled = false
			_platform_body = detected
			_platform_body._is_being_controlled = true
			_platform_prev_xform = _platform_body.global_transform
	elif _platform_body:
		if not is_instance_valid(_platform_body):
			_platform_body = null
		else:
			_platform_miss_time += delta
			if _platform_miss_time > PLATFORM_DETACH_GRACE:
				_platform_body._is_being_controlled = false
				_platform_body = null
				
	if _platform_body and is_instance_valid(_platform_body):
		var platform_up := _platform_body.global_transform.basis.y.normalized()
		var player_up := -gravity_direction.normalized()
		var angle := rad_to_deg(acos(clamp(platform_up.dot(player_up), -1.0, 1.0)))
		if angle > PLATFORM_MAX_TILT_DEG:
			_platform_body._is_being_controlled = false
			_platform_body = null
			return
			
	if _platform_body and is_instance_valid(_platform_body):
		_platform_prev_xform = _platform_body.global_transform

func update_normal_movement(delta: float) -> void:
	_apply_platform_movement()
	gravity_direction = planet.get_gravity_direction(global_position)
	var on_platform := _platform_body != null and is_instance_valid(_platform_body)
	
	if on_platform:
		var platform_up := _platform_body.global_transform.basis.y.normalized()
		up_direction = platform_up
		gravity_direction = -up_direction
	else:
		up_direction = -gravity_direction
	
	movement.on_platform = on_platform and is_on_floor()
	
	var was_swimming = movement.is_swimming
	_check_needs_swimming(delta)
	was_swimming = was_swimming && !movement.is_swimming
	var idle_animation = config.ANIMATION.IDLE if !right_hand_equipped else equiped_weapon.idle_animation
	var run_animation = config.ANIMATION.RUN if !right_hand_equipped else equiped_weapon.running_animation
	var input_dir = movement.handle_run_movement(delta, action_controller.is_attacking, gravity_direction, camera, idle_animation, run_animation)
	movement.handle_jump_movement(delta, planet.gravity_strength, gravity_direction, is_on_floor())

	
	movement.handle_idle_movement(delta, gravity_direction, is_on_floor(), planet.gravity_strength, velocity)
	current_animation = movement.current_animation

	if right_hand_equipped && (action_controller.is_attacking || (is_holding_atack && !movement.is_running)):
		current_animation = equiped_weapon.attack_animation

	combat.physics_update(delta, input_dir)
	animation_controller.handle_animations(delta, current_animation, free_flight_enabled)
	velocity = combat.apply_motion(movement.velocity)

	if combat.update_facing(delta, input_dir):
		pass
	elif movement.is_running || movement.is_sprinting:
		rotate_toward_movement(input_dir, delta)

	if movement.is_swimming:
		apply_swimming_pitch(input_dir, delta)
		if !movement.is_running:
			_apply_water_buoyancy(delta)
		_apply_water_flow()

	if was_swimming:
		current_swimming_pitch = 0.0
		player_model.rotation = Vector3.ZERO

	if on_platform and is_on_floor():
		align_to_gravity(-_platform_body.global_transform.basis.y.normalized(), 1.0)
	else:
		align_to_gravity(gravity_direction, delta)

	camera_controller.update_camera_rotation()
	
	if on_platform and is_on_floor() and not movement.is_jumping:
		var normal_comp := velocity.dot(up_direction)
		if normal_comp < 0.0:
			velocity -= up_direction * normal_comp

	var pre_slide_velocity := velocity
	move_and_slide()

	if is_on_floor() and not movement.is_swimming:
		step_up.try_step_up(delta, gravity_direction, pre_slide_velocity)

	_update_platform_tracking(delta)
