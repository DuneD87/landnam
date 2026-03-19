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

@export var planets: Node3D
@export var animator_tree: AnimationTree
@export var mouse_sensitivity: float = 0.002
@export var invert_y: bool = false
@export var swimming_pitch_angle: float = 90.0 
@export var swimming_rotation_speed: float = 5.0 
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
	capture_mouse(true)
	water_sampler = WaterHeightSampler.new()

	'''var item_stone = config.get_item(&"stone_01")
	var item_wood = config.get_item(&"wood_01")
	inventory.add_item(item_stone, 15)	
	inventory.add_item(item_wood, 15)'''
	inventory.add_item(config.get_item(&"firstage_skin_boots"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_hands"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_pants"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_chest"), 1)
	inventory.add_item(config.get_item(&"firstage_skin_hood"), 1)

	inventory.add_item(config.get_item(&"stone_axe_01"), 1)
	inventory.add_item(config.get_item(&"stone_pickaxe_01"), 1)
	inventory_ui.setup(inventory, character_window)
	character_window.equipment_changed.connect(on_equipment_changed)
	

func can_perform_action() -> bool:
	return not (
		action_controller.is_attacking or
		movement.is_running or
		movement.is_sprinting or
		movement.is_swimming or
		movement.is_falling or
		inventory_ui.visible
	)

func _input(event):
	if free_flight_enabled:
		visible = false
		if event is InputEventMouseMotion and mouse_captured:
			free_flight_controller.delta_yaw += -event.relative.x * mouse_sensitivity
			free_flight_controller.delta_pitch += -event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
	else:
		visible = true
		camera_controller._input(event)
		
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
		capture_mouse(not mouse_captured)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
		capture_mouse(true)
	
	if Input.is_action_just_pressed("attack_1") && can_perform_action():
		var ray_origin = $PlayerModel.global_position - gravity_direction * 2.5
		action_controller.handle_attack(camera, ray_origin, planet.planet, _on_target_destroyed)
		play_attack_once = true
		
	if event.is_action_pressed("toggle_free_flight"):
		free_flight_enabled = !free_flight_enabled
		if free_flight_enabled:
			print("Free flight activado")
			free_flight_controller.orientation = Quaternion(camera.global_transform.basis)
		else:
			print("Free flight desactivado")

func _apply_water_buoyancy(delta: float):
	var to_center := global_position - _water_surface_center
	var distance := to_center.length()
	var radial_dir := to_center.normalized() 
	var surface_offset := distance - _water_surface_radius
	var target_offset := -1.0
	var error := surface_offset - target_offset
	var buoyancy_strength := 1500.0
	var damping := 5.0
	var radial_velocity := velocity.dot(radial_dir)
	var correction := (-error * buoyancy_strength - radial_velocity * damping) * delta
	
	velocity += radial_dir * correction
	
func _check_needs_swimming(delta: float):
	if !planet || !planet.planet.has_water:
		return
	
	var to_center := global_position - planet.global_position
	var distance_from_center := to_center.length()
	var wave_height := water_sampler.get_height_at(global_position, current_water_time)
		
	var base_water_radius: float = planet.planet.radius - planet.planet.water_radius
	var water_surface_radius := base_water_radius + wave_height
	_water_surface_radius = water_surface_radius
	
	var mat = planet.water_sphere.mesh_manager.default_material as ShaderMaterial
	mat.set_shader_parameter("water_time", current_water_time)
	_water_surface_center = planet.global_position
	movement.is_swimming = distance_from_center <= _water_surface_radius
	
	current_water_time += delta


func _physics_process(delta: float):
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
		_apply_water_buoyancy(delta)

	if was_swimming:
		current_swimming_pitch = 0.0
		player_model.rotation = Vector3(0.0, 0.0, 0.0)
			
	align_to_gravity(gravity_direction, delta)
	camera_controller.update_camera_rotation()
	
	move_and_slide()
