extends CharacterBody3D
const config = preload("res://scripts/config.gd")
const data = preload("res://scripts/Inventory/item_data.gd")
@onready var movement: Movement = $Movement
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
@export var main_menu: Control
@export var spawn_point: Marker3D
@export var start_first_person: bool = false
@export var planets: Node3D
@export var animator_tree: AnimationTree
@export var mouse_sensitivity: float = 0.002
@export var invert_y: bool = false
@export var swimming_pitch_angle: float = 90.0 
@export var swimming_rotation_speed: float = 5.0 
@export var swimming_offset: float = 1.0

@export var float_depth := 1.0
@export var surface_stiffness := 10.0
@export var surface_damping := 5.0
@export var max_correction_speed := 8.0

## Cinematic settings
@export var cinematic_duration: float = 16.0
@export var cinematic_ease: Tween.EaseType = Tween.EASE_OUT
@export var cinematic_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var entity_id: String = "player"

var current_water_time: float = 0.0
var gravity_direction: Vector3 = Vector3.DOWN
var planet: Node3D
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

func _ready():
	add_to_group(GameManager.SAVEABLE_GROUP)
	GameManager.register_player(self)
	GameManager.state_changed.connect(_on_game_state_changed)
	
	# Start in free flight with no input (space view for the menu)
	free_flight_enabled = true
	visible = false
	collision_model.disabled = true
	
	capture_mouse(false)
	water_sampler = WaterHeightSampler.new()
	add_child(water_sampler)

	inventory.add_item(config.get_item(&"firstage_skin_boots"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_hands"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_pants"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_chest"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_hood"), 1)
	inventory.add_item(config.get_item(&"stone_axe_01"), 1)
	inventory.add_item(config.get_item(&"stone_pickaxe_01"), 1)
	inventory_ui.setup(inventory, character_window)
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
		}
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
	await get_tree().create_timer(5.0).timeout
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
		if planet and planet.planet.has_water:
			water_sampler.setup(planet.water_sphere.quadtree_material)

	# Estado visual coherente
	if input_enabled:
		visible = true
		collision_model.disabled = false
		capture_mouse(true)
		
	
	if planet:
		gravity_direction = planet.get_gravity_direction(global_position)
		up_direction = -gravity_direction

	# Reset modelo
	current_swimming_pitch = 0.0
	player_model.rotation = Vector3.ZERO


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

func _interpolate_rotation(t: float, from_quat: Quaternion, to_quat: Quaternion) -> void:
	global_basis = Basis(from_quat.slerp(to_quat, t))

## Keep camera following player during cinematic
func _process(_delta: float) -> void:
	if GameManager.current_state == GameManager.State.CINEMATIC:
		camera_controller.camera_pivot.global_position = global_position

func _activate_player() -> void:
	free_flight_enabled = false
	collision_model.disabled = false
	visible = true
	input_enabled = true
	player_model.rotation = Vector3.ZERO
	current_swimming_pitch = 0.0
	capture_mouse(true)


# ---------- Input ----------

func _input(event):
	if not input_enabled:
		return

	if free_flight_enabled:
		visible = false
		if event is InputEventMouseMotion and mouse_captured:
			free_flight_controller.delta_yaw += -event.relative.x * mouse_sensitivity
			free_flight_controller.delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	else:
		visible = true
		camera_controller._input(event)
	if event.is_action_pressed("toggle_free_flight"):
		free_flight_enabled = !free_flight_enabled
		if free_flight_enabled:
			print("Free flight activado")
			free_flight_controller.orientation = Quaternion(camera.global_transform.basis)
		else:
			print("Free flight desactivado")
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
		var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
		var item_data = action_controller.handle_pickup(camera, ray_origin)
		if item_data != null:
			inventory.add_item(item_data, 1)
	elif event.is_action_pressed("ui_cancel") and visible:
		inventory_ui.close()
			
	if event.is_action_pressed("ui_cancel"):
		if mouse_captured:
			main_menu.fade_in()
		else:
			main_menu.fade_out()
		capture_mouse(not mouse_captured)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
		capture_mouse(true)
	
	if Input.is_action_just_pressed("attack_1") && can_perform_action():
		var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
		action_controller.handle_attack(camera, ray_origin, planet.planet, _on_target_destroyed)
		play_attack_once = true


# ---------- Water / buoyancy ----------

func _apply_water_buoyancy(delta: float):
	var to_center := global_position - _water_surface_center
	var distance := to_center.length()
	var radial_dir := to_center.normalized() 
	var surface_offset := distance - (_water_surface_radius - swimming_offset)
	var target_offset := -1.0
	var error := surface_offset - target_offset
	var buoyancy_strength := 100.0
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
			
	free_flight_controller.enabled = free_flight_enabled

	if free_flight_enabled:
		collision_model.disabled = true
		camera_controller.camera_pivot.global_position = global_position
		update_free_flight(delta)
	else:
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
	
	var forward = -camera.global_transform.basis.z
	var target_dir = movement.project_on_plane(forward, gravity_direction).normalized()
	var current_dir = global_transform.basis.z
	var angle = acos(clamp(current_dir.dot(target_dir), -1.0, 1.0))
	
	if angle > deg_to_rad(10.0):
		var rotation_axis = current_dir.cross(target_dir)
		if rotation_axis.length() > 0.1:
			var rotation_amount = angle * delta * 3.0
			var rot = Quaternion(rotation_axis.normalized(), rotation_amount)
			global_transform.basis = Basis(rot) * global_transform.basis
			orthonormalize()

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

func align_to_gravity(gravity_dir: Vector3, delta: float):	
	var up_dir = -gravity_dir.normalized()
	var current_up = global_transform.basis.y
	var rotation_axis = current_up.cross(up_dir)
	var angle = acos(clamp(current_up.dot(up_dir), -1.0, 1.0))

	if angle > 0.001 and rotation_axis.length() > 0.001:
		var rot = Quaternion(rotation_axis.normalized(), angle * delta * 5.0)
		global_transform.basis = Basis(rot) * global_transform.basis
		orthonormalize()


func update_normal_movement(delta: float) -> void:
	gravity_direction = planet.get_gravity_direction(global_position)
	up_direction = -gravity_direction
	
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
		player_model.rotation = Vector3(0.0, 0.0, 0.0)
			
	align_to_gravity(gravity_direction, delta)
	camera_controller.update_camera_rotation()
	
	move_and_slide()
