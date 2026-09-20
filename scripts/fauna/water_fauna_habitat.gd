class_name WaterFaunaHabitat extends AmbientFaunaHabitat

var min_depth: float = 4.0
var max_depth: float = 16.0
var terrain: VoxelLodTerrain
var ocean: OceanSystem
var world_map: PlanetWorldMap
var sampler := WaterHeightSampler.new()
var _voxels: VoxelTool
var _clearance_shape := SphereShape3D.new()
var _clearance_buffer := VoxelBuffer.new()


func setup(ground: VoxelLodTerrain, sea: OceanSystem, map: PlanetWorldMap) -> void:
	terrain = ground
	ocean = sea
	world_map = map
	_voxels = terrain.get_voxel_tool()
	_voxels.channel = VoxelBuffer.CHANNEL_SDF
	sampler.setup(ocean.quadtree_material as ShaderMaterial, map, ocean.radius)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		sampler.free()


func host() -> Node3D:
	return terrain


func is_underwater() -> bool:
	return true


func surface_radius(point: Vector3) -> float:
	var time := WaterHeightSampler.get_water_time(ocean.quadtree_material as ShaderMaterial)
	return ocean.radius + sampler.get_height_at(point, time, center())


func sample_spawn(anchor: Vector3, profile: AmbientFaunaProfile,
		rng: RandomNumberGenerator) -> Variant:
	if not is_instance_valid(terrain) or not is_instance_valid(ocean):
		return null
	var up := (anchor - center()).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := up.cross(right)
	var angle := _spawn_angle(anchor, right, forward, rng)
	var distance := profile.sample_spawn_distance(rng)
	var direction := (anchor - center() + (right * cos(angle) + forward * sin(angle)) * distance).normalized()
	var point := center() + direction * ocean.radius
	# Near the surface populate the water below; when diving follow the observer's depth.
	var observer_depth := maxf(ocean.radius - anchor.distance_to(center()), 0.0)
	var depth := rng.randf_range(maxf(min_depth, observer_depth - 8.0), maxf(max_depth, observer_depth + 8.0))
	return center() + direction * (surface_radius(point) - depth)


## Heading of a spawn around the observer, measured from `right` towards `forward`.
func _spawn_angle(_anchor: Vector3, _right: Vector3, _forward: Vector3,
		rng: RandomNumberGenerator) -> float:
	return rng.randf_range(0.0, TAU)


func is_spawn_valid(point: Vector3, clearance: float) -> bool:
	if not is_swimmable(point, clearance):
		return false
	# Reject the whole hull envelope, including open decks and flooded compartments.
	# Independent of the camera-limited dry-interior rendering mask.
	if intersects_ship(point, clearance):
		return false
	_clearance_shape.radius = clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance_shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	return terrain.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func intersects_ship(point: Vector3, clearance: float) -> bool:
	for body in nearby_ships():
		if is_instance_valid(body) and body is DynamicGridBody and body.contains_point(point, clearance + 0.5):
			return true
	return false


func is_swimmable(point: Vector3, clearance: float) -> bool:
	if surface_radius(point) - point.distance_to(center()) < clearance + 0.8:
		return false
	if world_map != null and world_map.is_ready():
		var water_type := world_map.get_water_type_at(point)
		if water_type != WorldMapData.WaterType.OCEAN and water_type != WorldMapData.WaterType.SEA:
			return false
	return terrain_is_clear(point, clearance)


func terrain_is_clear(point: Vector3, clearance: float) -> bool:
	var local := terrain.to_local(point)
	# Unloaded voxels can read as air: never infer water from missing data.
	var reach := clearance + 1.5
	if not _voxels.is_area_editable(AABB(local - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)):
		return false
	# Cover the surrounding voxel lattice, not just the centre of the fish.
	var low := Vector3i((local - Vector3.ONE * clearance).floor())
	var high := Vector3i((local + Vector3.ONE * clearance).ceil())
	# Small fish need only a few samples. Large bodies used to acquire the terrain
	# data lock once per voxel (about 100,000 times for a whale's spawn envelope).
	if clearance > 2.0:
		var size := high - low + Vector3i.ONE
		_clearance_buffer.create(size.x, size.y, size.z)
		_voxels.copy(Vector3(low), _clearance_buffer, 1 << VoxelBuffer.CHANNEL_SDF, false)
		return _buffer_is_clear(_clearance_buffer)
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				if _voxels.get_voxel_f(Vector3i(x, y, z)) <= 0.0:
					return false
	return true


func terrain_cylinder_is_clear(point: Vector3, up: Vector3, radius: float, half_height: float) -> bool:
	if not cylinder_is_loaded(point, up, radius, half_height):
		return false
	var local := terrain.to_local(point)
	var local_up := (terrain.global_basis.inverse() * up).normalized()
	# Expand by one voxel diagonal to cover SDF interpolation at the envelope.
	radius += sqrt(3.0)
	half_height += sqrt(3.0)
	var extent := _cylinder_extent(local_up, radius, half_height)
	var low := Vector3i((local - extent).floor())
	var high := Vector3i((local + extent).ceil())
	var size := high - low + Vector3i.ONE
	_clearance_buffer.create(size.x, size.y, size.z)
	_voxels.copy(Vector3(low), _clearance_buffer, 1 << VoxelBuffer.CHANNEL_SDF, false)
	return _cylinder_buffer_is_clear(_clearance_buffer, low, local, local_up, radius, half_height)


## True when every voxel the cylinder check reads is loaded at full detail.
## Far from the observer only coarse LODs exist, and missing data is never water.
func cylinder_is_loaded(point: Vector3, up: Vector3, radius: float, half_height: float) -> bool:
	var local_up := (terrain.global_basis.inverse() * up).normalized()
	var reach := _cylinder_extent(local_up, radius + sqrt(3.0), half_height + sqrt(3.0)) + Vector3.ONE * 1.5
	var local := terrain.to_local(point)
	return _voxels.is_area_editable(AABB(local - reach, reach * 2.0))


static func _cylinder_extent(up: Vector3, radius: float, half_height: float) -> Vector3:
	var lateral := Vector3(sqrt(maxf(0.0, 1.0 - up.x * up.x)), sqrt(maxf(0.0, 1.0 - up.y * up.y)), sqrt(maxf(0.0, 1.0 - up.z * up.z)))
	return lateral * radius + up.abs() * half_height


static func _cylinder_buffer_is_clear(buffer: VoxelBuffer, low: Vector3i, origin: Vector3,
		up: Vector3, radius: float, half_height: float) -> bool:
	var size := buffer.get_size()
	var half := Vector3(size - Vector3i.ONE) * 0.5
	var offset := Vector3(low) + half - origin
	var vertical := absf(offset.dot(up))
	var support := half.dot(up.abs())
	var horizontal := offset.slide(up).length()
	var lateral_support := half.length()
	if vertical - support > half_height or horizontal - lateral_support > radius:
		return true
	if vertical + support <= half_height and horizontal + lateral_support <= radius:
		return _buffer_is_clear(buffer)
	buffer.compress_uniform_channels()
	if buffer.is_uniform(VoxelBuffer.CHANNEL_SDF) and buffer.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) > 0.0:
		return true
	if size.x * size.y * size.z > 512:
		var axis := Vector3(size).max_axis_index()
		var split := size[axis] / 2
		for side in 2:
			var part_low := Vector3i.ZERO
			var part_high := size
			if side == 0:
				part_high[axis] = split
			else:
				part_low[axis] = split
			var part := VoxelBuffer.new()
			var part_size := part_high - part_low
			part.create(part_size.x, part_size.y, part_size.z)
			part.set_channel_depth(VoxelBuffer.CHANNEL_SDF, buffer.get_channel_depth(VoxelBuffer.CHANNEL_SDF))
			part.copy_channel_from_area(buffer, part_low, part_high, Vector3i.ZERO, VoxelBuffer.CHANNEL_SDF)
			if not _cylinder_buffer_is_clear(part, low + part_low, origin, up, radius, half_height):
				return false
		return true
	for z in size.z:
		for x in size.x:
			for y in size.y:
				var relative := Vector3(low + Vector3i(x, y, z)) - origin
				if absf(relative.dot(up)) <= half_height and relative.slide(up).length_squared() <= radius * radius:
					if buffer.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF) <= 0.0:
						return false
	return true


static func _buffer_is_clear(buffer: VoxelBuffer) -> bool:
	const CHANNEL := VoxelBuffer.CHANNEL_SDF
	# Native scan of contiguous memory. Far from the bottom, SDF values saturate
	# to the same positive value, so no GDScript loop is needed at all.
	buffer.compress_uniform_channels()
	if buffer.is_uniform(CHANNEL):
		return buffer.get_voxel_f(0, 0, 0, CHANNEL) > 0.0
	var size := buffer.get_size()
	if size.x * size.y * size.z > 4096:
		# A giant animal can cover millions of voxels. Split nonuniform volumes
		# in native code so large uniform portions never enter a script loop.
		var axis := Vector3(size).max_axis_index()
		var split := size[axis] / 2
		for half in 2:
			var low := Vector3i.ZERO
			var high := size
			if half == 0:
				high[axis] = split
			else:
				low[axis] = split
			var part := VoxelBuffer.new()
			var part_size := high - low
			part.create(part_size.x, part_size.y, part_size.z)
			part.set_channel_depth(CHANNEL, buffer.get_channel_depth(CHANNEL))
			part.copy_channel_from_area(buffer, low, high, Vector3i.ZERO, CHANNEL)
			if not _buffer_is_clear(part):
				return false
		return true
	var bytes := buffer.get_channel_as_byte_array(CHANNEL)
	# Integer SDF storage is signed; zero and the sign bit mean solid/boundary.
	# Inspect every sample, including thin obstacles. Never substitute a sparse grid.
	match buffer.get_channel_depth(CHANNEL):
		VoxelBuffer.DEPTH_8_BIT:
			for value in bytes:
				if value == 0 or value >= 128:
					return false
		VoxelBuffer.DEPTH_16_BIT:
			for index in range(0, bytes.size(), 2):
				if bytes[index + 1] >= 128 or (bytes[index + 1] == 0 and bytes[index] == 0):
					return false
		VoxelBuffer.DEPTH_32_BIT:
			return Array(bytes.to_float32_array()).min() > 0.0
		VoxelBuffer.DEPTH_64_BIT:
			return Array(bytes.to_float64_array()).min() > 0.0
		_:
			return false
	return true
