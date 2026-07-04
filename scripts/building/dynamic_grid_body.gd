class_name DynamicGridBody
extends RigidBody3D

## RigidBody3D de una grid dinámica: gravedad planetaria + flotación de Arquímedes (empuje por
## volumen sumergido de las cajas de colisión fusionadas, aplicado en su centroide; masa por
## densidad de bloque), y movimiento según movement_type (barco; vehículo y nave pendientes).

enum MovementType { BOAT, LAND_VEHICLE, SPACESHIP }

@export var movement_type: MovementType = MovementType.BOAT
@export var turn_speed: float = 2.0
@export var buoyancy_lod_distance: float = 150.0
@export var linear_drag: float = 0.3
@export var heave_drag: float = 1.0
@export var angular_drag: float = 0.15

const BLOCK_DENSITY := 500.0
const WATER_DENSITY := 1000.0
const MIN_MASS := 10.0
const MAX_WAVE_SAMPLES := 16

var planet_node: Node3D = null

var _water_sampler: WaterHeightSampler = null

var _grids: Array = []
var _buoyancy_boxes: Array = []
var _aggregate_box: Dictionary = {}
var _drag_length_sq: float = 1.0
var _recalc_boxes: bool = true
var _is_being_controlled: bool = false

var _boat_speed_levels: Array[float] = [0.0, 5.0, 10.0, 20.0]
var _boat_speed_index: int = 0
var _boat_target_speed: float = 0.0
var _boat_current_speed: float = 0.0
@export var boat_acceleration: float = 3.0
@export var boat_deceleration: float = 5.0

signal speed_changed(level: int, speed: float)

func on_block_removed(grid_pos: Vector3i) -> void:
	mark_points_dirty()

func on_block_placed(grid_pos: Vector3i, block_id: int) -> void:
	mark_points_dirty()

func mark_points_dirty() -> void:
	_recalc_boxes = true

## Reconstruye la lista de cajas de volumen del casco desde los colliders del body:
## cajas fusionadas de cubos tal cual, rampas/esquinas como caja de su celda a medio volumen.
func _recalculate_buoyancy_boxes() -> void:
	_recalc_boxes = false
	_buoyancy_boxes.clear()
	_aggregate_box = {}

	var aabb := AABB()
	var first := true
	var total_volume := 0.0

	for child in get_children():
		if not (child is CollisionShape3D) or child.is_queued_for_deletion():
			continue
		var col := child as CollisionShape3D

		var half: Vector3
		var volume: float
		if col.shape is BoxShape3D:
			half = (col.shape as BoxShape3D).size * 0.5
			volume = half.x * half.y * half.z * 8.0
		else:
			half = Vector3.ONE * 0.5 * col.scale.x
			volume = col.scale.x * col.scale.x * col.scale.x * 0.5

		var pos: Vector3 = col.transform.origin
		_buoyancy_boxes.append({"pos": pos, "half": half, "volume": volume})
		total_volume += volume

		if first:
			aabb = AABB(pos - half, half * 2.0)
			first = false
		else:
			aabb = aabb.expand(pos - half)
			aabb = aabb.expand(pos + half)

	if _buoyancy_boxes.is_empty():
		return

	_aggregate_box = {"pos": aabb.get_center(), "half": aabb.size * 0.5, "volume": total_volume}
	_drag_length_sq = maxf(1.0, (aabb.size * 0.5).length_squared())

func _is_ground_ready() -> bool:
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 5,
		planet_node.global_pos
	)
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty()

func _ready() -> void:
	collision_layer = 3
	collision_mask = 1
	add_to_group("floating_origin")
	_setup_water_sampler()

func _setup_water_sampler() -> void:
	if not planet_node:
		return
	if not planet_node.planet.has_water:
		return
	_water_sampler = WaterHeightSampler.new()
	add_child(_water_sampler)
	var mat: ShaderMaterial = planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
	if mat:
		_water_sampler.setup(mat)

func register_grid(grid) -> void:
	if not _grids.has(grid):
		_grids.append(grid)
	mark_points_dirty()

func unregister_grid(grid) -> void:
	_grids.erase(grid)
	update_mass_from_grids()
	mark_points_dirty()

## Masa total del body: volumen de bloques de TODAS las grids (multi-size) por densidad de bloque.
func update_mass_from_grids() -> void:
	var total_volume := 0.0
	for grid in _grids:
		total_volume += grid.get_total_volume()
	mass = maxf(MIN_MASS, total_volume * BLOCK_DENSITY)


func _handle_input(delta: float) -> void:
	if not _is_being_controlled:
		return

	match movement_type:
		MovementType.BOAT:
			_handle_boat_input(delta)
		MovementType.LAND_VEHICLE:
			_handle_land_input(delta)
		MovementType.SPACESHIP:
			_handle_spaceship_input(delta)

func _handle_boat_input(delta: float) -> void:
	if Input.is_action_just_pressed("ui_up"):
		_boat_speed_index = mini(_boat_speed_index + 1, _boat_speed_levels.size() - 1)
		_boat_target_speed = _boat_speed_levels[_boat_speed_index]
		speed_changed.emit(_boat_speed_index, _boat_target_speed)

	if Input.is_action_just_pressed("ui_down"):
		_boat_speed_index = maxi(_boat_speed_index - 1, 0)
		_boat_target_speed = _boat_speed_levels[_boat_speed_index]
		speed_changed.emit(_boat_speed_index, _boat_target_speed)

	if _boat_current_speed < _boat_target_speed:
		_boat_current_speed = minf(_boat_current_speed + boat_acceleration * delta, _boat_target_speed)
	elif _boat_current_speed > _boat_target_speed:
		_boat_current_speed = maxf(_boat_current_speed - boat_deceleration * delta, _boat_target_speed)

	if _boat_current_speed > 0.01:
		var forward := global_transform.basis.z
		var current_forward_speed := linear_velocity.dot(forward)
		if current_forward_speed < _boat_current_speed:
			var speed_deficit := _boat_current_speed - current_forward_speed
			var force_factor := clampf(speed_deficit / _boat_current_speed, 0.0, 1.0)
			apply_central_force(forward * _boat_current_speed * mass * force_factor)

	if Input.is_action_pressed("ui_left"):
		angular_velocity += global_transform.basis.y * turn_speed * delta
	if Input.is_action_pressed("ui_right"):
		angular_velocity -= global_transform.basis.y * turn_speed * delta

## Sin implementar: movimiento de vehículo terrestre.
func _handle_land_input(_delta: float) -> void:
	pass

## Sin implementar: movimiento de nave espacial.
func _handle_spaceship_input(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if not planet_node or not is_inside_tree():
		return

	_handle_input(delta)

	var planet_pos: Vector3 = planet_node.global_pos
	var dir: Vector3 = (planet_pos - global_position).normalized()
	var up: Vector3 = -dir
	var gravity: float = planet_node.gravity_strength

	apply_central_force(dir * gravity * mass)

	if not planet_node.planet.has_water or not _water_sampler:
		return

	if _recalc_boxes:
		_recalculate_buoyancy_boxes()

	if _buoyancy_boxes.is_empty():
		return

	var mat: ShaderMaterial = planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
	var water_time: float = WaterHeightSampler.get_water_time(mat)
	var base_water_radius: float = planet_node.planet.radius - planet_node.planet.water_radius

	var boxes: Array = _buoyancy_boxes
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_squared_to(global_position) > buoyancy_lod_distance * buoyancy_lod_distance:
		boxes = [_aggregate_box]

	var shared_wave := boxes.size() > MAX_WAVE_SAMPLES
	var wave_h_shared := 0.0
	if shared_wave:
		wave_h_shared = _water_sampler.get_height_at(global_position, water_time, planet_pos)

	var basis_w := global_transform.basis
	var submerged_volume := 0.0

	for box: Dictionary in boxes:
		var half: Vector3 = box["half"]
		var world_center: Vector3 = global_transform * (box["pos"] as Vector3)

		var h_half: float = absf((basis_w.x * half.x).dot(up)) \
			+ absf((basis_w.y * half.y).dot(up)) \
			+ absf((basis_w.z * half.z).dot(up))
		h_half = maxf(h_half, 0.05)

		var wave_h: float = wave_h_shared if shared_wave else _water_sampler.get_height_at(world_center, water_time, planet_pos)
		var water_r: float = base_water_radius + wave_h
		var dist: float = (world_center - planet_pos).length()

		var frac: float = clampf((water_r - (dist - h_half)) / (2.0 * h_half), 0.0, 1.0)
		if frac <= 0.0:
			continue

		var displaced: float = box["volume"] * frac
		var centroid: Vector3 = world_center + up * h_half * (frac - 1.0)
		apply_force(up * WATER_DENSITY * gravity * displaced, centroid - global_position)
		submerged_volume += displaced

	if submerged_volume > 0.0:
		var displaced_mass: float = submerged_volume * WATER_DENSITY
		apply_central_force(-linear_velocity * linear_drag * displaced_mass)
		var radial_vel: float = linear_velocity.dot(up)
		apply_central_force(-up * radial_vel * heave_drag * displaced_mass)
		apply_torque(-angular_velocity * angular_drag * displaced_mass * _drag_length_sq)


func get_current_speed_level() -> int:
	return _boat_speed_index

func get_current_speed() -> float:
	return _boat_current_speed

func stop() -> void:
	_boat_speed_index = 0
	_boat_target_speed = 0.0
