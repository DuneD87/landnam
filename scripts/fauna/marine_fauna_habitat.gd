class_name MarineFaunaHabitat extends WaterFaunaHabitat

## Fraction of spawn samples aimed away from the nearest coast (offshore species only).
const OFFSHORE_BIAS := 0.75
## Samples on the inner and outer bathymetry rings of the body footprint.
const FOOTPRINT_RINGS := [[0.5, 6], [1.0, 12]]

var settings: MarineFaunaProfile
var _body_shape := CylinderShape3D.new()


func habitat_allowed(point: Vector3) -> bool:
	# Without a ready map we cannot distinguish seas from lakes or prove open sea.
	if world_map == null or not world_map.is_ready():
		return false
	var water_type := world_map.get_water_type_at(point)
	if water_type != WorldMapData.WaterType.OCEAN and water_type != WorldMapData.WaterType.SEA:
		return false
	if settings.min_offshore_distance <= 0.0:
		return true
	if not world_map.has_shore_field():
		return false
	# Saturated distance is only a lower bound; never invent a larger distance.
	var required := settings.min_offshore_distance + settings.clearance
	return world_map.map.shore_range * 0.98 >= required and world_map.shore_sample_local(point - center()).w >= required


func sample_spawn(anchor: Vector3, profile: AmbientFaunaProfile,
		rng: RandomNumberGenerator) -> Variant:
	min_depth = maxf(settings.min_swim_depth, surface_clearance(anchor) + 1.0)
	max_depth = maxf(min_depth, settings.max_swim_depth)
	var point: Variant = super.sample_spawn(anchor, profile, rng)
	if point == null or not habitat_allowed(point):
		return null
	if not settings.use_bathymetry:
		return point
	# Rise above the shallowest seabed under the body instead of discarding the sample.
	var local: Vector3 = point - center()
	var lowest := footprint_seabed_radius(local) + settings.vertical_clearance + settings.bathymetry_margin
	if local.length() >= lowest:
		return point
	if lowest > surface_radius(point) - min_depth:
		return null
	return center() + local.normalized() * lowest


func _spawn_angle(anchor: Vector3, right: Vector3, forward: Vector3,
		rng: RandomNumberGenerator) -> float:
	var uniform := rng.randf_range(0.0, TAU)
	if settings.min_offshore_distance <= 0.0 or world_map == null or not world_map.has_shore_field():
		return uniform
	# The shore field points landward on both sides of the coast.
	var shore := world_map.shore_sample_local(anchor - center())
	var seaward := -Vector3(shore.x, shore.y, shore.z)
	var x := seaward.dot(right)
	var y := seaward.dot(forward)
	if x * x + y * y < 0.01 or rng.randf() >= OFFSHORE_BIAS:
		return uniform
	return atan2(y, x) + rng.randf_range(-PI * 0.5, PI * 0.5)


## Repeated while swimming, so it must stay cheap. Bodies checked by bathymetry leave
## rocks the heightmap misses to their collision box: a full voxel scan of a whale
## costs several milliseconds whenever the seabed is near.
func is_swimmable(point: Vector3, clearance: float) -> bool:
	if not _water_column_allowed(point):
		return false
	if settings.use_bathymetry:
		return bathymetry_is_clear(point, 0.0)
	return terrain_is_clear(point, clearance)


func _water_column_allowed(point: Vector3) -> bool:
	return habitat_allowed(point) and surface_radius(point) - point.distance_to(center()) >= surface_clearance(point) + 0.8


func surface_clearance(point: Vector3) -> float:
	# A tangent body curves closer to the spherical sea at its distant ends.
	return settings.vertical_clearance + settings.clearance ** 2 / maxf(2.0 * point.distance_to(center()), 1.0)


func terrain_is_clear(point: Vector3, _clearance: float) -> bool:
	var up := (point - center()).normalized()
	return terrain_cylinder_is_clear(point, up, settings.clearance, settings.vertical_clearance)


## Seabed below the whole body, plus `margin`, according to the planetary heightmap.
func bathymetry_is_clear(point: Vector3, margin: float) -> bool:
	if world_map == null or not world_map.is_ready():
		return false
	var local := point - center()
	# A flat body tangent to the sphere only rises away from the centre at its ends.
	var bottom := local.length() - settings.vertical_clearance - margin
	return footprint_seabed_radius(local) < bottom


## Highest seabed radius sampled over the body's horizontal footprint.
func footprint_seabed_radius(local: Vector3) -> float:
	var up := local.normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := up.cross(right)
	var highest := seabed_radius(local)
	for ring in FOOTPRINT_RINGS:
		var reach: float = settings.clearance * ring[0]
		var count: int = ring[1]
		for index in count:
			var angle := TAU * index / float(count)
			highest = maxf(highest, seabed_radius(local + (right * cos(angle) + forward * sin(angle)) * reach))
	return highest


func seabed_radius(local: Vector3) -> float:
	return ocean.radius - world_map.water_depth_local(local)


func is_spawn_valid(point: Vector3, clearance: float) -> bool:
	if not _water_column_allowed(point) or intersects_ship(point, clearance):
		return false
	if settings.use_bathymetry:
		# Cheap prefilter first: with the margin, the voxels around the body are nearly
		# always uniform water and the exact scan below resolves in native code.
		if not bathymetry_is_clear(point, settings.bathymetry_margin):
			return false
		var up := (point - center()).normalized()
		if cylinder_is_loaded(point, up, settings.clearance, settings.vertical_clearance) \
				and not terrain_cylinder_is_clear(point, up, settings.clearance, settings.vertical_clearance):
			return false
	elif not terrain_is_clear(point, clearance):
		return false
	_body_shape.radius = settings.clearance
	_body_shape.height = settings.vertical_clearance * 2.0
	var up := (point - center()).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body_shape
	query.transform = Transform3D(Basis(right, up, right.cross(up)), point)
	query.collision_mask = 1
	return terrain.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
