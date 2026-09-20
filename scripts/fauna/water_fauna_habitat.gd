class_name WaterFaunaHabitat extends AmbientFaunaHabitat

var min_depth: float = 4.0
var max_depth: float = 16.0
var terrain: VoxelLodTerrain
var ocean: OceanSystem
var world_map: PlanetWorldMap
var sampler := WaterHeightSampler.new()
var _voxels: VoxelTool
var _clearance_shape := SphereShape3D.new()


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
	var angle := rng.randf_range(0.0, TAU)
	var distance := profile.sample_spawn_distance(rng)
	var direction := (anchor - center() + (right * cos(angle) + forward * sin(angle)) * distance).normalized()
	var point := center() + direction * ocean.radius
	# Near the surface populate the water below; when diving follow the observer's depth.
	var observer_depth := maxf(ocean.radius - anchor.distance_to(center()), 0.0)
	var depth := rng.randf_range(maxf(min_depth, observer_depth - 8.0), maxf(max_depth, observer_depth + 8.0))
	return center() + direction * (surface_radius(point) - depth)


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
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				if _voxels.get_voxel_f(Vector3i(x, y, z)) <= 0.0:
					return false
	return true
