class_name WaterBirdHabitat extends AmbientBirdHabitat

var settings: WaterBirdProfile
var ocean: OceanSystem
var world_map: PlanetWorldMap
var rivers: Dictionary = {}
var _water := WaterFaunaHabitat.new()
var _owners: Dictionary = {}
var _shape := SphereShape3D.new()


func setup(ground: VoxelLodTerrain, player: Node3D, sea: OceanSystem,
		map: PlanetWorldMap, river_data: Dictionary, profile: WaterBirdProfile) -> void:
	terrain = ground
	observer = player
	ocean = sea
	world_map = map
	rivers = river_data
	settings = profile
	_water.setup(ground, sea, map)
	_shape.radius = 0.35


func surface_point(point: Vector3) -> Vector3:
	return terrain.global_position + up_at(point) * _water.surface_radius(point)


func _river_distance(point: Vector3) -> float:
	return RiverField.distance_at(rivers, up_at(point))


func habitat_allowed(point: Vector3) -> bool:
	var coast_allowed := false
	if world_map != null and world_map.is_ready() and world_map.has_shore_field():
		var shore := world_map.shore_sample_local(point - terrain.global_position)
		var range_m := world_map.map.shore_range
		if absf(shore.w) < range_m * 0.98:
			# River mouths cannot bypass the ocean's maximum distance to land.
			if shore.w > settings.max_offshore_distance:
				return false
			coast_allowed = shore.w >= -settings.coast_inland_distance
		elif shore.w > 0.0:
			# Saturation is unknown distance, not exactly shore_range metres.
			coast_allowed = settings.max_offshore_distance >= range_m and _land_within(point, settings.max_offshore_distance)
			if not coast_allowed:
				return false
	# River proximity alone cannot populate dry upland channels: only a wet
	# channel at ocean level is eligible in this project's river renderer.
	if _river_distance(point) <= settings.river_bank_distance:
		var water := surface_point(point)
		if _water.terrain_is_clear(water - up_at(point) * 0.25, 0.1):
			return true
		# Flying above a solid bank is valid if a wet channel is nearby.
		var up := up_at(point)
		var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		for ring in [0.5, 1.0]:
			for i in 8:
				var angle := TAU * float(i) / 8.0
				var nearby := surface_point(point + (right * cos(angle) + right.cross(up) * sin(angle)) * settings.river_bank_distance * ring)
				if _river_distance(nearby) <= settings.river_bank_distance and _water.terrain_is_clear(nearby - up_at(nearby) * 0.25, 0.1):
					return true
	return coast_allowed


func _land_within(point: Vector3, limit: float) -> bool:
	var up := up_at(point)
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := right.cross(up)
	for ring in range(1, 9):
		var arc := limit * float(ring) / 8.0 / ocean.radius
		for i in 32:
			var angle := TAU * float(i) / 32.0
			var direction := up * cos(arc) + (right * cos(angle) + forward * sin(angle)) * sin(arc)
			var sample := terrain.global_position + direction * ocean.radius
			if world_map.get_surface_radius(sample) > ocean.radius:
				return true
	return false


func sample_spawn(anchor: Vector3, profile: AmbientFaunaProfile, rng: RandomNumberGenerator) -> Variant:
	var up := up_at(anchor)
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := right.cross(up)
	var angle := rng.randf_range(0.0, TAU)
	var radius := profile.sample_spawn_distance(rng)
	var candidate := anchor + (right * cos(angle) + forward * sin(angle)) * radius
	var height := rng.randf_range(minf(settings.flight_height_min, settings.flight_height_max), maxf(settings.flight_height_min, settings.flight_height_max))
	var water := surface_point(candidate)
	# Stay near the player, including when the player stands on a river bank.
	candidate += up_at(candidate) * maxf(0.8, water.distance_to(terrain.global_position) + height - candidate.distance_to(terrain.global_position))
	var distance := candidate.distance_to(anchor)
	if distance < profile.spawn_min_distance or distance > profile.spawn_radius or not habitat_allowed(candidate):
		return null
	return candidate


func is_spawn_valid(point: Vector3, clearance: float) -> bool:
	return habitat_allowed(point) and point.distance_to(terrain.global_position) > _water.surface_radius(point) + 0.4 and point_free(point, clearance)


func point_free(point: Vector3, clearance: float = 0.35) -> bool:
	if not _water.terrain_is_clear(point, clearance) or _water.intersects_ship(point, clearance):
		return false
	_shape.radius = clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform.origin = point
	query.collision_mask = 1
	return terrain.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _water_is_open(point: Vector3) -> bool:
	var up := up_at(point)
	return habitat_allowed(point) and _water.terrain_is_clear(point - up * 0.25, 0.1) and point_free(point + up * 0.35)


func reserve(owner_id: int, near: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	release(owner_id)
	var up := up_at(near)
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	for attempt in 12:
		var angle := rng.randf_range(0.0, TAU)
		var candidate := surface_point(near + (right * cos(angle) + right.cross(up) * sin(angle)) * rng.randf_range(3.0, 20.0))
		if not _water_is_open(candidate):
			continue
		# Settle beyond the distance the observer would flush it from.
		if is_instance_valid(observer) and candidate.distance_to(observer.global_position) < settings.flush_distance_max:
			continue
		var occupied := false
		for other in _owners.values():
			if (other as Vector3).distance_to(terrain.to_local(candidate)) < 1.2:
				occupied = true
				break
		if occupied:
			continue
		_owners[owner_id] = terrain.to_local(candidate)
		var perch := _anchor(owner_id, right)
		perch.approach = candidate + up_at(candidate) * rng.randf_range(settings.flight_height_min, maxf(settings.flight_height_min, settings.flight_height_max))
		return perch
	return {}


func _anchor(owner_id: int, right: Vector3) -> Dictionary:
	if not _owners.has(owner_id):
		return {}
	var point := surface_point(terrain.to_global(_owners[owner_id]))
	var up := up_at(point)
	right = right.slide(up).normalized()
	return {"owner": owner_id, "point": point - up * 0.08, "right": right, "up": up,
		"basis": Basis(right, up, right.cross(up)).orthonormalized()}


func resolve(anchor: Dictionary) -> Dictionary:
	if anchor.is_empty():
		return {}
	var current := _anchor(anchor.owner, anchor.right)
	if current.is_empty():
		return {}
	# A streamed-out region or a moving hull invalidates a resting place too.
	if not _water.terrain_is_clear(current.point, 0.1) or _water.intersects_ship(current.point, 0.4):
		release(anchor.owner)
		return {}
	return current


func drift(anchor: Dictionary, delta: float) -> void:
	if anchor.is_empty() or not _owners.has(anchor.owner):
		return
	var position := surface_point(anchor.point - (anchor.basis as Basis).z * settings.swim_speed * delta)
	if _water_is_open(position):
		_owners[anchor.owner] = terrain.to_local(position)


func release(owner_id: int) -> void:
	_owners.erase(owner_id)


func flight_route(from: Vector3, perch: Dictionary) -> Array[Vector3]:
	var target: Vector3 = perch.approach
	if path_clear(from, target):
		return [target]
	var up := up_at(from)
	var rise := from + up * maxf(3.0, (target - from).dot(up) + 2.0)
	if path_clear(from, rise) and path_clear(rise, target):
		return [rise, target]
	return []


func path_clear(from: Vector3, to: Vector3, check_foliage: bool = false) -> bool:
	if not super.path_clear(from, to, check_foliage):
		return false
	# A flight across a bay must respect the offshore limit between endpoints too.
	var steps := clampi(int(ceil(from.distance_to(to) / 5.0)), 1, 16)
	for step in range(1, steps + 1):
		if not habitat_allowed(from.lerp(to, float(step) / steps)):
			return false
	return true
