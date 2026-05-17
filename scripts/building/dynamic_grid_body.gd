class_name DynamicGridBody
extends RigidBody3D

## Tipos de movimiento disponibles
enum MovementType { BOAT, LAND_VEHICLE, SPACESHIP }

## RigidBody3D con gravedad planetaria y flotación.

@export var movement_type: MovementType = MovementType.BOAT
@export var turn_speed: float = 2.0

var planet_node: Node3D = null

var _water_sampler: WaterHeightSampler = null
var _water_drag: float = 300.0

var _grids: Array = []
var _buoyancy_points: PackedVector3Array = []
var _buoyancy_force: float = 100.0
var _recalc_points: bool = true
var _is_being_controlled: bool = false

# ---- Boat speed levels ----
var _boat_speed_levels: Array[float] = [0.0, 5.0, 10.0, 20.0]
var _boat_speed_index: int = 0
var _boat_target_speed: float = 0.0
var _boat_current_speed: float = 0.0
@export var boat_acceleration: float = 3.0
@export var boat_deceleration: float = 5.0

# ---- Señales ----
signal speed_changed(level: int, speed: float)

func on_block_removed(grid_pos: Vector3i) -> void:
	mark_points_dirty()

func on_block_placed(grid_pos: Vector3i, block_id: int) -> void:
	mark_points_dirty()

func mark_points_dirty() -> void:
	_recalc_points = true

func _recalculate_buoyancy_points() -> void:
	_recalc_points = false
	_buoyancy_points.clear()
	
	if get_child_count() == 0:
		return
	
	var aabb := AABB()
	var first := true
	for child in get_children():
		if child is CollisionShape3D:
			var pos: Vector3 = child.transform.origin
			if first:
				aabb = AABB(pos, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(pos)
	
	if first:
		return
	
	aabb = aabb.grow(0.5)
	var o: Vector3 = aabb.position
	var s: Vector3 = aabb.size
	
	for xi in 3:
		for zi in 3:
			var fx: float = float(xi) / 2.0
			var fz: float = float(zi) / 2.0
			_buoyancy_points.append(o + Vector3(s.x * fx, 0, s.z * fz))
	
	_buoyancy_points.append(aabb.get_center())

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

func unregister_grid(grid) -> void:
	_grids.erase(grid)

# ============================================================
#  INPUT
# ============================================================

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

func _handle_land_input(_delta: float) -> void:
	# TODO: implementar movimiento de vehículo terrestre
	pass

func _handle_spaceship_input(_delta: float) -> void:
	# TODO: implementar movimiento de nave espacial
	pass

# ============================================================
#  PHYSICS
# ============================================================

func _physics_process(delta: float) -> void:
	if not planet_node or not is_inside_tree():
		return
	
	_handle_input(delta)
	
	var planet_pos: Vector3 = planet_node.global_pos
	var dir: Vector3 = (planet_pos - global_position).normalized()
	var up: Vector3 = -dir
	var gravity_force: Vector3 = dir * planet_node.gravity_strength * mass

	if not planet_node.planet.has_water or not _water_sampler:
		apply_central_force(gravity_force)
		return
	
	if _recalc_points:
		_recalculate_buoyancy_points()
	
	if _buoyancy_points.is_empty():
		apply_central_force(gravity_force)
		return
	
	var mat: ShaderMaterial = planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
	var water_time: float = mat.get_shader_parameter("water_time")
	var base_water_radius: float = planet_node.planet.radius - planet_node.planet.water_radius
	
	var submerged_count: float = 0.0
	var point_count: int = _buoyancy_points.size()
	
	for local_pos in _buoyancy_points:
		var world_pos: Vector3 = global_transform * local_pos
		var wave_h: float = _water_sampler.get_height_at(world_pos, water_time, planet_pos)
		var water_r: float = base_water_radius + wave_h
		var dist: float = (world_pos - planet_pos).length()
		
		if dist < water_r:
			var depth: float = water_r - dist
			var ratio: float = clampf(depth / 1.0, 0.0, 1.0)
			apply_force(up * _buoyancy_force * ratio, world_pos - global_position)
			submerged_count += ratio
	
	var ratio_sub: float = clampf(submerged_count / float(point_count), 0.0, 1.0)
	gravity_force *= (1.0 - ratio_sub)
	
	if submerged_count > 0.0:
		apply_central_force(-linear_velocity * _water_drag * ratio_sub)
		
		var ang: Vector3 = angular_velocity
		var yaw_component: Vector3 = up * ang.dot(up)
		var tilt_component: Vector3 = ang - yaw_component
		apply_torque(-tilt_component * _water_drag * 15.0 * ratio_sub)
		apply_torque(-yaw_component * _water_drag * 5.0 * ratio_sub)
		
		var radial_vel: float = linear_velocity.dot(up)
		if absf(radial_vel) > 0.5:
			apply_central_force(-up * radial_vel * mass * ratio_sub * 2.0)
	
	apply_central_force(gravity_force)

# ============================================================
#  API PÚBLICA
# ============================================================

func get_current_speed_level() -> int:
	return _boat_speed_index

func get_current_speed() -> float:
	return _boat_current_speed

func stop() -> void:
	_boat_speed_index = 0
	_boat_target_speed = 0.0
