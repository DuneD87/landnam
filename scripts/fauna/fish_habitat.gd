class_name FishHabitat
extends WaterFaunaHabitat

## Población pescable de costa, lagos y ríos. El SDF vivo demuestra que hay agua;
## el mapa grueso solo elige las especies, nunca descarta una orilla o un cauce estrecho.
## Incluye el mayor alto de las tres especies del pack, con margen (0,45 m en total).
const HALF_HEIGHT := 0.30
const SURFACE_MARGIN := 0.20
var rivers: Dictionary = {}
var _river: Dictionary = {}
var _river_anchor := Vector3.INF
var _spawn_shape := CylinderShape3D.new()


func _init() -> void:
	min_depth = 1.0
	max_depth = 2.6


func sample_spawn(anchor: Vector3, profile: AmbientFaunaProfile, rng: RandomNumberGenerator) -> Variant:
	if not is_instance_valid(terrain) or not is_instance_valid(ocean):
		return null
	_update_river(anchor, profile.spawn_radius)
	var up := (anchor - center()).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var angle := rng.randf_range(0.0, TAU)
	var direction := (anchor - center() + (right * cos(angle) + right.cross(up) * sin(angle))
		* profile.sample_spawn_distance(rng)).normalized()
	if not _river.is_empty() and rng.randf() < 0.7:
		# Buscar a lo largo del cauce evita desperdiciar casi todos los intentos en las riberas.
		var along: Vector3 = _river.tangent
		var across := along.cross(_river.direction as Vector3).normalized()
		direction = ((_river.direction as Vector3) * ocean.radius
			+ along * rng.randf_range(-profile.spawn_radius, profile.spawn_radius)
			+ across * rng.randf_range(-1.0, 1.0) * minf(float(_river.half_width) * 0.7, 8.0)).normalized()
	var surface := center() + direction * ocean.radius
	var observer_depth := maxf(ocean.radius - anchor.distance_to(center()), 0.0)
	var low := maxf(min_depth, observer_depth - 3.0)
	var high := maxf(max_depth, observer_depth + 2.0)
	return center() + direction * (surface_radius(surface) - rng.randf_range(low, high))


func _update_river(anchor: Vector3, reach: float) -> void:
	var local := anchor - center()
	if local.distance_squared_to(_river_anchor) < 64.0:
		return
	_river_anchor = local
	_river = RiverField.nearby_channel_at(rivers, local.normalized(), reach)


func _in_river(point: Vector3) -> bool:
	if _river.is_empty():
		return false
	var local := (point - center()).normalized() * ocean.radius
	var a: Vector3 = _river.start
	var ab: Vector3 = (_river.end as Vector3) - a
	var t := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return local.distance_to(a + ab * t) <= float(_river.half_width) + 1.0


func water_type_at(point: Vector3) -> int:
	if _in_river(point):
		return WorldMapData.WaterType.RIVER
	if world_map == null or not world_map.is_ready():
		return -1
	var body := world_map.map.nearby_water_body_at_dir((point - center()).normalized())
	return int(body.type) if not body.is_empty() else WorldMapData.WaterType.POND


func is_swimmable(point: Vector3, clearance: float) -> bool:
	return surface_radius(point) - point.distance_to(center()) >= HALF_HEIGHT + SURFACE_MARGIN \
		and terrain_is_clear(point, clearance)


func terrain_is_clear(point: Vector3, clearance: float) -> bool:
	var tool := _voxels as VoxelToolLodTerrain
	var up := (point - center()).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var local := terrain.to_local(point)
	var reach := clearance + 1.5
	if not tool.is_area_editable(AABB(local - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)):
		return false
	# En agua libre basta una copia nativa del SDF. Si todos los vóxeles son aire,
	# sus interpolaciones también lo son: evita 27 consultas al terreno por pez.
	# Cerca del fondo o de una pared se conserva el muestreo preciso del cilindro.
	var low := Vector3i((local - Vector3.ONE * reach).floor())
	var high := Vector3i((local + Vector3.ONE * reach).ceil())
	var size := high - low + Vector3i.ONE
	_clearance_buffer.create(size.x, size.y, size.z)
	tool.copy(Vector3(low), _clearance_buffer, 1 << VoxelBuffer.CHANNEL_SDF, false)
	if _buffer_is_clear(_clearance_buffer):
		return true
	# Un pez alargado no necesita un metro de agua por encima y por debajo de su cuerpo.
	# Sondear el cilindro que lo envuelve permite nadar en fondos someros sin aceptar sólidos.
	for level: float in [-HALF_HEIGHT, 0.0, HALF_HEIGHT]:
		var at: Vector3 = point + up * level
		if tool.get_voxel_f_interpolated(terrain.to_local(at)) <= 0.0:
			return false
		for i in 8:
			var angle := TAU * float(i) / 8.0
			var sample: Vector3 = at + (right * cos(angle) + right.cross(up) * sin(angle)) * clearance
			if tool.get_voxel_f_interpolated(terrain.to_local(sample)) <= 0.0:
				return false
	return true


func is_spawn_valid(point: Vector3, clearance: float) -> bool:
	if not is_swimmable(point, clearance) or intersects_ship(point, clearance):
		return false
	_spawn_shape.radius = clearance
	_spawn_shape.height = HALF_HEIGHT * 2.0
	var up := (point - center()).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _spawn_shape
	query.transform = Transform3D(Basis(right, up, right.cross(up)), point)
	query.collision_mask = PhysicsLayers.WORLD
	return terrain.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func swim_target(point: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var up := (point - center()).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var surface := surface_radius(point)
	var depth := clampf(surface - point.distance_to(center()), min_depth, max_depth)
	for attempt in 5:
		var tangent := right.rotated(up, rng.randf_range(0.0, TAU))
		var direction := (point - center() + tangent * rng.randf_range(2.0, 6.0)).normalized()
		var target := center() + direction * (surface - maxf(min_depth, depth + rng.randf_range(-0.25, 0.25)))
		if is_swimmable(target, AmbientFish.CLEARANCE):
			return target
	return point
