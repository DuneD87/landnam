class_name ForestBirdHabitat extends AmbientBirdHabitat
var planet: Planet
var debug_perches: bool = false
var _trees: Dictionary = {}
var _reservations: Dictionary = {}
var _refresh_at: int = 0
var _search_shape := SphereShape3D.new()
var _bird_shape := SphereShape3D.new()
var _debug: MultiMeshInstance3D


func setup(ground: Node3D, player: Node3D, world: Planet = null) -> void:
	terrain = ground
	observer = player
	planet = world
	_bird_shape.radius = 0.20


func up_at(point: Vector3) -> Vector3:
	return (point - terrain.global_position).normalized()


func refresh() -> void:
	if planet == null or Time.get_ticks_msec() < _refresh_at:
		return
	_refresh_at = Time.get_ticks_msec() + 1000
	_search_shape.radius = 65.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _search_shape
	query.transform.origin = observer.global_position
	query.collision_mask = 1
	var hits := terrain.get_world_3d().direct_space_state.intersect_shape(query, 256)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.collider as Node3D).global_position.distance_squared_to(observer.global_position) < (b.collider as Node3D).global_position.distance_squared_to(observer.global_position))
	var found: Dictionary = {}
	for hit in hits:
		var body := hit.collider as VoxelInstancerRigidBody
		if body == null or not planet.voxel_instancer.is_ancestor_of(body):
			continue
		var data: Dictionary = planet.tree_perch_catalog.get(body.get_library_item_id(), {})
		if data.is_empty():
			continue
		found[body.get_instance_id()] = {"body": weakref(body), "data": data}
		if found.size() >= 48:
			break
	_trees = found
	for key in _reservations.keys():
		if not is_instance_id_valid(_reservations[key]):
			_reservations.erase(key)
	if debug_perches:
		_draw_debug()


## Also used by deterministic previews/tests with explicitly placed tree instances.
func register_tree(body: Node3D, data: Dictionary) -> void:
	_trees[body.get_instance_id()] = {"body": weakref(body), "data": data}


func _anchor(tree_id: int, index: int) -> Dictionary:
	var entry: Dictionary = _trees.get(tree_id, {})
	if entry.is_empty() or index < 0 or index >= entry.data.perches.size():
		return {}
	var body: Node3D = entry.body.get_ref()
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not body.is_inside_tree():
		return {}
	var perch: Dictionary = entry.data.perches[index]
	var xf := body.global_transform
	var point: Vector3 = xf * (perch.point as Vector3)
	var up := up_at(point)
	var normal := (xf.basis.inverse().transposed() * (perch.normal as Vector3)).normalized()
	if normal.dot(up) < 0.60:
		return {}
	var right := (xf.basis * (perch.tangent as Vector3)).slide(up).normalized()
	if right.is_zero_approx():
		return {}
	return {"tree": tree_id, "index": index, "key": "%d:%d" % [tree_id, index],
		"point": point + up * 0.005, "right": right, "up": up,
		"height": maxf(0.0, (point - body.global_position).dot(up)),
		"basis": Basis(right, up, right.cross(up)).orthonormalized(), "pose": body.transform}


func resolve(anchor: Dictionary) -> Dictionary:
	if anchor.is_empty():
		return {}
	var current := _anchor(anchor.tree, anchor.index)
	# Instancer bodies may be reassigned to a different instance after removal.
	# Their local transform changes; an origin rebase only changes their ancestors.
	if not current.is_empty() and not (current.pose as Transform3D).is_equal_approx(anchor.pose):
		return {}
	return current


func _available(near: Vector3, radius: float) -> Array[Dictionary]:
	refresh()
	var result: Array[Dictionary] = []
	for tree_id in _trees:
		var entry: Dictionary = _trees[tree_id]
		for index in entry.data.perches.size():
			var anchor := _anchor(tree_id, index)
			if anchor.is_empty() or _reservations.has(anchor.key):
				continue
			if near.distance_to(anchor.point) <= radius:
				result.append(anchor)
	return result


func sample_spawn(anchor: Vector3, profile: AmbientFaunaProfile, rng: RandomNumberGenerator) -> Variant:
	# Forest presence enables flight; branch height and reservations only matter
	# later, when the bird chooses somewhere to land.
	refresh()
	var has_tree := false
	for entry in _trees.values():
		var body: Node3D = entry.body.get_ref()
		if is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion():
			has_tree = true
			break
	if not has_tree or profile.spawn_radius <= 0.0 or profile.spawn_min_distance > profile.spawn_radius:
		return null
	var up := up_at(anchor)
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := up.cross(reference).normalized()
	var forward := right.cross(up).normalized()
	var angle := rng.randf_range(0.0, TAU)
	var distance := profile.sample_spawn_distance(rng)
	# Near the player's height, with room to flap. Preserve the full 3D radius
	# rather than adding altitude after sampling the horizontal distance.
	var height := rng.randf_range(0.8, 2.5) * minf(1.0, distance / 3.0)
	var horizontal := sqrt(maxf(0.0, distance * distance - height * height))
	return anchor + (right * cos(angle) + forward * sin(angle)) * horizontal + up * height


func is_spawn_valid(point: Vector3, _clearance: float) -> bool:
	return point_free(point)


func point_free(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _bird_shape
	query.transform.origin = point + up_at(point) * 0.18
	query.collision_mask = 1
	if not terrain.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	if terrain is VoxelLodTerrain:
		var tool := (terrain as VoxelLodTerrain).get_voxel_tool()
		var local := terrain.to_local(point)
		if not tool.is_area_editable(AABB(local - Vector3.ONE, Vector3.ONE * 2.0)):
			return false
		tool.channel = VoxelBuffer.CHANNEL_SDF
		if tool.get_voxel_f(Vector3i(local.round())) <= 0.0:
			return false
	return path_clear(point + up_at(point) * 0.04, point + up_at(point) * 0.40, true)


func path_clear(from: Vector3, to: Vector3, check_foliage: bool = false) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if not terrain.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	for entry in _trees.values():
		var body: Node3D = entry.body.get_ref()
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var inv := body.global_transform.affine_inverse()
		if not (entry.data.wood as TriangleMesh).intersect_segment(inv * from, inv * to).is_empty():
			return false
		var foliage: TriangleMesh = entry.data.get("foliage")
		# Leaf textures occupy only part of their cards. Treat these conservatively
		# for resting headroom, but not as solid walls blocking all forest flight.
		if check_foliage and foliage != null and not foliage.intersect_segment(inv * from, inv * to).is_empty():
			return false
	return true


func reserve(owner_id: int, near: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var options := _available(near, 45.0)
	_prefer_low_branches(options, near)
	# Bounded geometric checks even when a dense canopy supplies hundreds of anchors.
	for _attempt in mini(options.size(), 12):
		# Try low branches first, then widen the search if they are obstructed.
		var last := mini(options.size() - 1, 7) if _attempt < 8 else options.size() - 1
		var index := rng.randi_range(0, last)
		var perch: Dictionary = options[index]
		options.remove_at(index)
		if point_free(perch.point) and _feet_supported(perch):
			var approach: Variant = _approach_point(perch)
			if approach is Vector3:
				perch.approach = approach
				_reservations[perch.key] = owner_id
				return perch
	return {}


func _prefer_low_branches(options: Array[Dictionary], near: Vector3) -> void:
	# Height is measured in world metres after instance scaling, relative to the
	# tree's base and planet up. One metre higher costs as much as four metres farther.
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.height * 4.0 + near.distance_to(a.point) < b.height * 4.0 + near.distance_to(b.point))


func _approach_point(perch: Dictionary) -> Variant:
	var body: Node3D = _trees[perch.tree].body.get_ref()
	var outward := ((perch.point as Vector3) - body.global_position).slide(perch.up).normalized()
	for direction in [outward, perch.right, -perch.right, Vector3.ZERO]:
		var point: Vector3 = perch.point + perch.up * 0.8 + direction * 0.8
		if point_free(point) and path_clear(point + perch.up * 0.20, perch.point + perch.up * 0.20):
			return point
	return null


func _feet_supported(perch: Dictionary) -> bool:
	var entry: Dictionary = _trees[perch.tree]
	var body: Node3D = entry.body.get_ref()
	var inv := body.global_transform.affine_inverse()
	for side in [-1.0, 1.0]:
		var foot: Vector3 = perch.point + perch.right * side * 0.045
		if (entry.data.wood as TriangleMesh).intersect_segment(inv * (foot + perch.up * 0.06), inv * (foot - perch.up * 0.10)).is_empty():
			return false
	return true


func flight_route(from: Vector3, perch: Dictionary) -> Array[Vector3]:
	var approach: Vector3 = perch.approach
	var up: Vector3 = perch.up
	if path_clear(from + up * 0.20, approach + up * 0.20):
		return [approach]
	# A bird coming from below must rise outside the branches before landing on
	# top. Otherwise the same direct approach repeatedly hits their underside.
	var entry: Dictionary = _trees[perch.tree]
	var body: Node3D = entry.body.get_ref()
	var bounds: AABB = entry.data.bounds
	var scale := body.global_basis.get_scale().abs()
	var radius := Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)) * scale.x,
		maxf(absf(bounds.position.z), absf(bounds.end.z)) * scale.z).length() + 1.0
	var outward := (from - body.global_position).slide(up).normalized()
	if outward.is_zero_approx():
		outward = perch.right
	for direction in [outward, perch.right, -perch.right, -outward]:
		var side: Vector3 = body.global_position + direction * radius + up * (from - body.global_position).dot(up)
		var above: Vector3 = side + up * (approach - side).dot(up)
		if not point_free(side) or not point_free(above):
			continue
		if path_clear(from + up * 0.20, side + up * 0.20) and path_clear(side + up * 0.20, above + up * 0.20) and path_clear(above + up * 0.20, approach + up * 0.20):
			return [side, above, approach]
	return []


func release(owner_id: int) -> void:
	for key in _reservations.keys():
		if _reservations[key] == owner_id:
			_reservations.erase(key)


func _draw_debug() -> void:
	if not is_instance_valid(_debug):
		_debug = MultiMeshInstance3D.new()
		_debug.name = "BirdPerchesDebug"
		_debug.multimesh = MultiMesh.new()
		_debug.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var ball := SphereMesh.new()
		ball.radius = 0.07
		ball.height = 0.14
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 1.0, 0.3)
		ball.material = mat
		_debug.multimesh.mesh = ball
		terrain.add_child(_debug)
	var points := _available(observer.global_position, 65.0)
	_debug.multimesh.instance_count = points.size()
	for i in points.size():
		_debug.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, terrain.to_local(points[i].point)))
