extends PlanetaryBody
const PLATFORM_ATTACH_DIST := 1.5
const PLATFORM_DETACH_DIST := 2.5
const PLATFORM_MAX_TILT_DEG := 75.0

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

@export var main_menu: Control
@export var spawn_point: Marker3D
@export var start_first_person: bool = false
@export var animator_tree: AnimationTree
@export var mouse_sensitivity: float = 0.002
@export var invert_y: bool = false
@export var swimming_pitch_angle: float = 90.0 
@export var swimming_rotation_speed: float = 5.0 
@export var swimming_offset: float = 1.0
@export var ray_distance: float = 8.0
@export_flags_3d_physics var ray_collision_mask: int = 3

@export var float_depth := 1.0
@export var surface_stiffness := 10.0
@export var surface_damping := 5.0
@export var max_correction_speed := 8.0

## Cinematic settings
@export var cinematic_duration: float = 16.0
@export var cinematic_ease: Tween.EaseType = Tween.EASE_OUT
@export var cinematic_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var entity_id: String = "player"
var save_category: String = "player"

var _ray_hit: Dictionary = {}

var _platform_body: DynamicGridBody = null
var _platform_prev_xform: Transform3D

var current_water_time: float = 0.0
var water_sampler: WaterHeightSampler
var mouse_captured = true
var free_flight_enabled = false
var current_swimming_pitch: float = 0.0
var current_animation = config.ANIMATION.IDLE
var play_attack_once = false

var _water_surface_radius: float = 0.0
var _water_surface_center: Vector3 = Vector3.ZERO

var equiped_weapon: ItemData

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

func equip_item(equip: bool, slot: ItemData.ArmorSlot, scene: PackedScene, data: ItemData, category: ItemData.Category) -> void:
	if equip:
		match category:
			ItemData.Category.TOOL:
				equiped_weapon = data
				var item = scene.instantiate()
				player_model.get_node("Armature/Skeleton3D/RigthHandAttachment").add_child(item)
			ItemData.Category.ARMOR:
				var item = scene.instantiate()
				item.item_data = ItemData.clone(data)
				player_model.get_node("Armature/Skeleton3D").add_child(item)
	else:		
		match category:
			ItemData.Category.TOOL:
				var equipped_child = player_model.get_node("Armature/Skeleton3D/RigthHandAttachment").get_child(0)
				player_model.get_node("Armature/Skeleton3D/RigthHandAttachment").remove_child(equipped_child)
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

	if new_is_block:
		building_system.select_block(new_data.block_id)
		building_system.set_material_by_id(new_data.build_material_id)
		building_system.set_build_mode(true)
		if old_is_equippable:
			_unequip_right_hand()
	elif new_is_equippable:
		building_system.set_build_mode(false)
		_equip_from_hotbar(old_data, new_data)
	else:
		building_system.set_build_mode(false)
		if old_is_equippable:
			_unequip_right_hand()

	inventory.inventory_changed.emit()


func _equip_from_hotbar(old_data: ItemData, new_data: ItemData) -> void:
	var new_item_slot := -1

	# 1. Buscar i treure el nou item de l'inventari
	for i in inventory.items.size():
		if inventory.items[i] and inventory.items[i].data.id == new_data.id:
			new_item_slot = i
			break
	if new_item_slot >= 0:
		inventory.items[new_item_slot] = null

	# 2. Desequipar anterior
	var old_is_equippable := old_data != null and (old_data.category == ItemData.Category.TOOL or old_data.category == ItemData.Category.WEAPON)
	if old_is_equippable:
		var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
		if eq_slot and eq_slot.has_item():
			var unequipped = character_window.unequip_item(eq_slot)
			if unequipped:
				var target = new_item_slot if new_item_slot >= 0 else inventory.find_empty_slot()
				if target >= 0:
					inventory.items[target] = InventoryItem.new(unequipped.data, 1)
					new_item_slot = -1

	# 3. Equipar nou
	var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
	if eq_slot:
		var inv_item := InventoryItem.new(new_data, 1)
		var returned = character_window.equip_item(eq_slot, inv_item)
		if returned:
			var target = new_item_slot if new_item_slot >= 0 else inventory.find_empty_slot()
			if target >= 0:
				inventory.items[target] = InventoryItem.new(returned.data, 1)


func _unequip_right_hand() -> void:
	var eq_slot = character_window.equipment_slots.get(ItemData.ArmorSlot.RIGHT_HAND)
	if eq_slot and eq_slot.has_item():
		var unequipped = character_window.unequip_item(eq_slot)
		if unequipped:
			var target = inventory.find_empty_slot()
			if target >= 0:
				inventory.items[target] = InventoryItem.new(unequipped.data, 1)
	
	
func _ready():
	safe_margin = 0.008
	floor_max_angle = deg_to_rad(70.0)    # acceptar pendents més empinades
	floor_snap_length = 0.1
	platform_floor_layers = 0
	add_to_group(GameManager.SAVEABLE_GROUP)
	add_to_group("player")
	GameManager.register_player(self)
	GameManager.state_changed.connect(_on_game_state_changed)
	hotbar.selection_changed.connect(_on_hotbar_selection_changed)
	movement.landed.connect(_on_landed)
	health_component.died.connect(_on_player_died)
	# Start in free flight with no input (space view for the menu)
	free_flight_enabled = true
	visible = false
	collision_model.disabled = true
	build_menu.setup(hotbar, building_system)

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
	inventory.add_item(config.get_item(&"wood_01"), 100)
	inventory.add_item(config.get_item(&"stone_01"), 100)

	inventory_ui.setup(inventory, character_window, hotbar)
	hotbar.selection_changed.connect(_on_hotbar_selection_changed)	
	character_window.equipment_changed.connect(on_equipment_changed)
	var btnSave := main_menu.find_child("btnSaveGame")
	btnSave.visible = false
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
			water_sampler.setup(planet.water_sphere.quadtree_material)
			
			
func get_save_data() -> Dictionary:
	# Inventario: array de { item_id, quantity, slot_index }
	var inventory_data: Array[Dictionary] = []
	for i in inventory.items.size():
		var item: InventoryItem = inventory.items[i]
		if item != null and item.data != null:
			inventory_data.append({
				"item_id": str(item.data.id),
				"quantity": item.quantity,
				"slot_index": i
			})

	# Equipamiento: ArmorSlot (int) -> item_id
	var equipment_data: Dictionary = {}
	for slot_type in character_window.equipment_slots:
		var eq_slot: EquipmentSlot = character_window.equipment_slots[slot_type]
		if eq_slot.has_item() and eq_slot.equipped_item.data != null:
			equipment_data[str(int(slot_type))] = str(eq_slot.equipped_item.data.id)

	return {
		"position": {
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z
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

	# Cámara
	camera_controller.camera_pivot.rotation.y = save.camera.yaw
	camera_controller.camera_pivot.get_node("PitchPivot").rotation.x = save.camera.pitch
	camera_controller.camera_distance = save.camera.distance
	camera_controller.update_camera_transform()
	
	# Estado
	free_flight_enabled = save.game_state.free_flight
	input_enabled = save.game_state.input_enabled
	current_water_time = save.game_state.get("current_water_time", 0.0)

	# Desequipar todo lo visual antes de limpiar inventario
	_clear_visual_equipment()

	# Limpiar y restaurar inventario respetando posiciones
	inventory.clear()
	for entry in save.inventory:
		var item_data: ItemData = config.get_item(StringName(entry.item_id))
		if item_data:
			inventory.add_item_at(item_data, int(entry.quantity), int(entry.slot_index))
		else:
			push_warning("SaveSystem: item desconocido '%s'" % entry.item_id)

	# Limpiar slots de equipamiento en CharacterWindow
	for slot_type in character_window.equipment_slots:
		var eq_slot: EquipmentSlot = character_window.equipment_slots[slot_type]
		if eq_slot.has_item():
			eq_slot.clear()

	# Restaurar equipamiento
	for slot_key_str in save.equipment:
		var slot_type: ItemData.ArmorSlot = int(slot_key_str) as ItemData.ArmorSlot
		var item_id: String = save.equipment[slot_key_str]
		var item_data: ItemData = config.get_item(StringName(item_id))
		if item_data and character_window.equipment_slots.has(slot_type):
			var eq_slot: EquipmentSlot = character_window.equipment_slots[slot_type]
			var inv_item := InventoryItem.new(item_data, 1)
			eq_slot.set_item(inv_item)
			# Instanciar visual
			equip_item(true, item_data.armor_slot, load(item_data.scene_path), item_data, item_data.category)
	if save.has("hotbar"):
		hotbar.restore_save_data(save.hotbar, config)
	if save.has("hotbar_selected") and save.hotbar_selected >= 0:
		hotbar.select_slot(save.hotbar_selected)
	_activate_player()
# Desde cualquier script (ej: tu player, un manager, etc.)

func place_block_at_player() -> void:
	var block_data: BlockData = BlockDatabase.get_block(BlockDatabase.BLOCK_SLOPE_ID)

	# Crear el nodo
	var block := StaticBody3D.new()
	block.name = "Block_%s" % block_data.block_name

	# Mesh
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = block_data.mesh
	block.add_child(mesh_instance)

	# Collider
	var collider := CollisionShape3D.new()
	collider.shape = block_data.collision_shape
	# BoxShape3D está centrada, nuestra mesh tiene origen en la base
	if block_data.collision_shape is BoxShape3D:
		collider.position.y = block_data.cell_size * 0.5
	block.add_child(collider)

	# Posicionar donde está el player
	block.global_position = global_position

	# Añadir al mundo
	get_tree().current_scene.add_child(block)
func post_restore() -> void:
	# Redescubrir planeta más cercano
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
			water_sampler.setup(planet.water_sphere.quadtree_material)

	# Estado visual coherente
	if input_enabled:
		visible = true
		collision_model.disabled = false		
	
	if planet:
		gravity_direction = planet.get_gravity_direction(global_position)
		up_direction = -gravity_direction

	# Reset modelo
	current_swimming_pitch = 0.0
	player_model.rotation = Vector3.ZERO
	inventory.clear()
	inventory.add_item(config.get_item(&"wood_01"), 100)
	inventory.add_item(config.get_item(&"stone_01"), 100)
	

func _clear_visual_equipment() -> void:
	# Limpiar arma de la mano
	var hand = player_model.get_node("Armature/Skeleton3D/RigthHandAttachment")
	for child in hand.get_children():
		hand.remove_child(child)
		child.queue_free()
	equiped_weapon = null

	# Limpiar piezas de armadura del esqueleto
	var skeleton = player_model.get_node("Armature/Skeleton3D")
	for child in skeleton.get_children():
		if "item_data" in child and child.item_data:
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
		action_controller.is_attacking or
		movement.is_running or
		movement.is_sprinting or
		movement.is_swimming or
		movement.is_falling or
		inventory_ui.visible
	)


# ---------- GameManager integration ----------

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

	# Body position
	_cinematic_tween.tween_property(
		self, "global_position",
		end_pos, cinematic_duration
	).from(start_pos).set_ease(cinematic_ease).set_trans(cinematic_trans)

	# Body rotation (slerp handles roll alignment to surface)
	_cinematic_tween.tween_method(
		_interpolate_rotation.bind(start_quat, end_quat),
		0.0, 1.0, cinematic_duration
	).set_ease(cinematic_ease).set_trans(cinematic_trans)

	# Progressive yaw → 0
	_cinematic_tween.tween_property(
		camera_controller.camera_pivot, "rotation:y",
		spawn_point.rotation.y, cinematic_duration
	).from(saved_yaw).set_ease(cinematic_ease).set_trans(cinematic_trans)

	# Progressive pitch → 0
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


# ---------- Health ----------

func _on_landed(impact_speed: float) -> void:
	health_component.take_fall_damage(impact_speed)

func _on_player_died() -> void:
	# TODO: pantalla de muerte, respawn, etc.
	print("[Player] Died — impact or damage")

func _interpolate_rotation(t: float, from_quat: Quaternion, to_quat: Quaternion) -> void:
	global_basis = Basis(from_quat.slerp(to_quat, t))

## Keep camera following player during cinematic
func _process(_delta: float) -> void:
	if GameManager.current_state == GameManager.State.CINEMATIC:
		camera_controller.camera_pivot.global_position = global_position
	_perform_raycast()


func _activate_player() -> void:
	free_flight_enabled = false
	collision_model.disabled = false
	visible = true
	player_model.rotation = Vector3.ZERO
	current_swimming_pitch = 0.0

	while not is_ground_ready():
		await get_tree().create_timer(.5).timeout
	mouse_captured = true
	input_enabled = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
# ---------- Input ----------
func is_mouse_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	
func _input(event):
	if Input.is_action_just_pressed("ui_cancel"):
		if inventory_ui.visible:
			inventory_ui.close()
			capture_mouse(true)
			return
		if character_window.visible:
			character_window.toggle()
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
 
	if event is InputEventKey and event.pressed:
		if event.is_action_pressed("open_build_menu"):
			build_menu.toggle()
			if build_menu.visible:
				capture_mouse(false)
			else:
				capture_mouse(true)
 
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
 
	if building_system.build_mode:
		_handle_build_input(event)

	if free_flight_enabled:
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
		else:
			var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
			var item_data = action_controller.handle_pickup(camera, ray_origin)
			if item_data != null:
				inventory.add_item(item_data, 1)
	elif event.is_action_pressed("ui_cancel") and visible:
		inventory_ui.close()
 
	# ---- BUILD MODE INPUT (was in BuildPreview._unhandled_input) ----
 
	# ---- ATTACK (only outside build mode) ----
	if Input.is_action_just_pressed("attack_1") && can_perform_action() && !building_system.build_mode:
		var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
		action_controller.handle_attack(camera, ray_origin, planet.planet, _on_target_destroyed)
		play_attack_once = true
	elif Input.is_action_just_pressed("attack_2"):
		var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
		var raycast_result = action_controller.perform_raycast(ray_origin, camera.global_rotation, true)
		if raycast_result["has_hit"]:
			print("hit_pos:", raycast_result["hit_pos"], "\nhit_distance: ", raycast_result["hit_distance"])
			var deer = load("res://scenes/animals/Bear.tscn").instantiate() as CharacterBody3D
			get_tree().current_scene.add_child(deer)
			deer.planets = planets
			deer.global_position = raycast_result["hit_pos"] - gravity_direction * 10

 
 
func _handle_build_input(event: InputEvent) -> void:
	var shift_held := Input.is_action_pressed("left_shift")

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# Ahora el click izquierdo es contextual (construye o elimina)
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
	
func _check_needs_swimming(delta: float):
	if !planet || !planet.planet.has_water || not is_inside_tree():
		return

	var to_center := global_position - planet.global_position
	var distance_from_center := to_center.length()
	var wave_height := water_sampler.get_height_at(global_position, current_water_time, planet.global_pos)
		
	var base_water_radius: float = planet.planet.radius - planet.planet.water_radius
	var water_surface_radius := base_water_radius + wave_height
	_water_surface_radius = water_surface_radius
	planet.water_sphere.underwater._water_surface_radius = _water_surface_radius
	var mat = planet.water_sphere.mesh_manager.default_material as ShaderMaterial
	mat.set_shader_parameter("water_time", current_water_time)
	_water_surface_center = planet.global_position
	movement.is_swimming = distance_from_center <= (_water_surface_radius - swimming_offset)
	
	current_water_time += delta


# ---------- Physics ----------

func _physics_process(delta: float):
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
				water_sampler.setup(_planet.water_sphere.quadtree_material)
			planet = _planet
			building_system.current_planet = planet

			
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
		if Input.is_action_just_released("camera_zoom_in"):
			camera_controller.camera_distance -= 1
			camera_controller.update_camera_transform()
		if Input.is_action_just_released("camera_zoom_out"):
			camera_controller.camera_distance += 1
			camera_controller.update_camera_transform()
			
		update_normal_movement(delta)


# ---------- Movement helpers ----------

func update_free_flight(delta: float) -> void:
	free_flight_controller.update_free_flight(delta, camera)
	velocity = free_flight_controller.velocity
	move_and_slide()

func rotate_toward_movement(input_dir: Vector3, delta: float):
	if input_dir.length() < 0.1:
		return
	# El player gira hacia donde apunta la cámara, no hacia el input.
	# project_on_gravity_plane y rotate_toward_direction vienen de PlanetaryBody.
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

func _update_platform_tracking() -> void:
	var detected := _detect_platform_raycast()
	
	if detected and detected != _platform_body:
		if _platform_body:
			_platform_body._is_being_controlled = false
		_platform_body = detected
		_platform_body._is_being_controlled = true
		_platform_prev_xform = _platform_body.global_transform
	elif not detected and _platform_body:
		if not is_instance_valid(_platform_body):
			_platform_body = null
		else:
			var body_up := _platform_body.global_transform.basis.y.normalized()
			var height_above := (global_position - _platform_body.global_position).dot(body_up)
			
			if height_above > PLATFORM_DETACH_DIST or height_above < -0.5:
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
	
	var input_dir = movement.handle_run_movement(delta, action_controller.is_attacking, gravity_direction, camera)
	movement.handle_jump_movement(delta, planet.gravity_strength, gravity_direction, is_on_floor())
	movement.handle_idle_movement(delta, gravity_direction, is_on_floor(), planet.gravity_strength, velocity)
	current_animation = movement.current_animation

	if equiped_weapon != null && action_controller.is_attacking:
		current_animation = equiped_weapon.attack_animation

	animation_controller.handle_animations(delta, current_animation, free_flight_enabled)
	velocity = movement.velocity

	if movement.is_running || movement.is_sprinting:
		rotate_toward_movement(input_dir, delta)

	if movement.is_swimming:
		apply_swimming_pitch(input_dir, delta)
		if !movement.is_running:
			_apply_water_buoyancy(delta)

	if was_swimming:
		current_swimming_pitch = 0.0
		player_model.rotation = Vector3.ZERO

	if on_platform and is_on_floor():
		align_to_gravity(-_platform_body.global_transform.basis.y.normalized(), 1.0)
	else:
		align_to_gravity(gravity_direction, delta)

	camera_controller.update_camera_rotation()
	
	if on_platform and not movement.is_jumping:
		var normal_comp := velocity.dot(up_direction)
		if normal_comp < 0.0:
			velocity -= up_direction * normal_comp

	var pre_slide_velocity := velocity
	move_and_slide()

	if is_on_floor() and not movement.is_swimming:
		step_up.try_step_up(delta, gravity_direction, pre_slide_velocity)

	_update_platform_tracking()
