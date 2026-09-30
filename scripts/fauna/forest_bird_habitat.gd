class_name ForestBirdHabitat extends AmbientBirdHabitat

## Birds never choose to land this close to the observer: they settle out of reach and
## are flushed from there, instead of perching next to the player and bolting at once.
const LANDING_CLEARANCE := 7.0
## Ground foraging happens around tree trunks, between these distances from the trunk.
const GROUND_RING_MIN := 1.5
const GROUND_RING_MAX := 7.0
## Steepest ground a foraging bird accepts (cosine of the slope).
const GROUND_MIN_UP := 0.85

var planet: Planet
## Optional: keeps ground foraging out of the sea on coasts.
var ocean: OceanSystem
var debug_perches: bool = false
var _trees: Dictionary = {}
var _reservations: Dictionary = {}
## Ground resting places by owner, in terrain space: {local, right, approach}.
var _ground: Dictionary = {}
## Resting place behind the last position sample_spawn returned, for claim_spawn_perch().
var _offer: Dictionary = {}
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
	# Filter first and sort only the trees with perches, by a distance computed once: sorting
	# all 256 hits with a comparator that reads positions cost more than the query itself.
	var centre := observer.global_position
	var candidates: Array = []
	for hit in hits:
		var body := hit.collider as VoxelInstancerRigidBody
		if body == null:
			continue
		var data: Dictionary = planet.tree_perch_catalog.get(body.get_library_item_id(), {})
		if data.is_empty() or not planet.voxel_instancer.is_ancestor_of(body):
			continue
		candidates.append([body.global_position.distance_squared_to(centre), body, data])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var found: Dictionary = {}
	for candidate in candidates.slice(0, 48):
		var body: Node3D = candidate[1]
		found[body.get_instance_id()] = _entry(body, candidate[2])
	_trees = found
	for key in _reservations.keys():
		if not is_instance_id_valid(_reservations[key]):
			_reservations.erase(key)
	for owner_id in _ground.keys():
		if not is_instance_id_valid(owner_id):
			_ground.erase(owner_id)
	if debug_perches:
		_draw_debug()


## Also used by deterministic previews/tests with explicitly placed tree instances.
func register_tree(body: Node3D, data: Dictionary) -> void:
	_trees[body.get_instance_id()] = _entry(body, data)


func _entry(body: Node3D, data: Dictionary) -> Dictionary:
	var entry := {"body": weakref(body), "data": data}
	entry.reach = _reach(entry, body)
	return entry


func _anchor(tree_id: int, index: int) -> Dictionary:
	var entry: Dictionary = _trees.get(tree_id, {})
	if entry.is_empty() or index < 0 or index >= entry.data.get("perches", []).size():
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
	if anchor.get("ground", false):
		return _ground_anchor(anchor.owner)
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
		# Whole trees out of range cost one distance instead of one anchor per branch.
		var body: Node3D = entry.body.get_ref()
		if not is_instance_valid(body) or body.global_position.distance_to(near) > radius + _reach(entry, body):
			continue
		for index in entry.data.get("perches", []).size():
			var anchor := _anchor(tree_id, index)
			if anchor.is_empty() or _reservations.has(anchor.key):
				continue
			if near.distance_to(anchor.point) <= radius and not _near_observer(anchor.point):
				result.append(anchor)
	return result


## Radius around the tree's origin that holds all its branches, after instance scaling.
func _reach(entry: Dictionary, body: Node3D) -> float:
	if entry.has("reach"):
		return entry.reach
	var bounds: AABB = entry.data.get("bounds", AABB())
	var extent := Vector3(maxf(absf(bounds.position.x), absf(bounds.end.x)),
		maxf(absf(bounds.position.y), absf(bounds.end.y)), maxf(absf(bounds.position.z), absf(bounds.end.z)))
	return (extent * body.global_basis.get_scale().abs()).length()


func _near_observer(point: Vector3) -> bool:
	return is_instance_valid(observer) and point.distance_to(observer.global_position) < LANDING_CLEARANCE


## Live tree bodies whose branches may reach within [radius] of [near], or of the annulus
## [inner]..[radius] around it when [inner] is positive.
func _trees_near(near: Vector3, radius: float, inner: float = 0.0) -> Array:
	var result := []
	for tree_id in _trees:
		var entry: Dictionary = _trees[tree_id]
		var body: Node3D = entry.body.get_ref()
		if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion():
			continue
		var distance := body.global_position.distance_to(near)
		var reach := maxf(_reach(entry, body), GROUND_RING_MAX)
		if distance - reach <= radius and distance + reach >= inner:
			result.append(tree_id)
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
	_offer = {}
	if not has_tree or profile.spawn_radius <= 0.0 or profile.spawn_min_distance > profile.spawn_radius:
		return null
	var settings := profile as AmbientBirdProfile
	if settings != null and rng.randf() < settings.perched_spawn_chance:
		# Discovered already resting instead of popping into the sky. A failed offer falls
		# back to a flying arrival, so sparse forests still get their birds.
		var ground := rng.randf() < settings.ground_chance
		var offer := _offer_ground(anchor, profile, rng) if ground else _offer_branch(anchor, profile, rng)
		if not offer.is_empty():
			_offer = offer
			return offer.point
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
	var point := anchor + (right * cos(angle) + forward * sin(angle)) * horizontal + up * height
	# Over real terrain, arrive at canopy height instead of the player's: in hills the
	# player's height is underground on one side and far up in the air on the other.
	var hit := ground_below(point)
	if not hit.is_empty():
		var aloft: Vector3 = hit.position + up_at(hit.position) * rng.randf_range(3.0, 8.0)
		var aloft_distance := aloft.distance_to(anchor)
		if aloft_distance >= profile.spawn_min_distance and aloft_distance <= profile.spawn_radius:
			return aloft
	return point


## A free branch inside the spawn annulus around [anchor], ready to be claimed.
func _offer_branch(anchor: Vector3, profile: AmbientFaunaProfile, rng: RandomNumberGenerator) -> Dictionary:
	var trees := _trees_near(anchor, profile.spawn_radius, profile.spawn_min_distance)
	if trees.is_empty():
		return {}
	for _attempt in 8:
		var tree_id: int = trees[rng.randi() % trees.size()]
		var count: int = _trees[tree_id].data.get("perches", []).size()
		if count == 0:
			continue
		var perch := _anchor(tree_id, rng.randi() % count)
		if perch.is_empty() or _reservations.has(perch.key):
			continue
		var distance := (perch.point as Vector3).distance_to(anchor)
		if distance < profile.spawn_min_distance or distance > profile.spawn_radius:
			continue
		if not point_free(perch.point) or not _feet_supported(perch):
			continue
		var approach: Variant = _approach_point(perch)
		if approach is Vector3:
			perch.approach = approach
			return perch
	return {}


## A patch of open ground under a tree inside the spawn annulus, ready to be claimed.
func _offer_ground(anchor: Vector3, profile: AmbientFaunaProfile, rng: RandomNumberGenerator) -> Dictionary:
	var trees := _trees_near(anchor, profile.spawn_radius, profile.spawn_min_distance)
	if trees.is_empty():
		return {}
	for _attempt in 4:
		var body: Node3D = _trees[trees[rng.randi() % trees.size()]].body.get_ref()
		var spot := _ground_spot(body, rng)
		if spot.is_empty():
			continue
		var distance := (spot.point as Vector3).distance_to(anchor)
		if distance >= profile.spawn_min_distance and distance <= profile.spawn_radius:
			return spot
	return {}


func claim_spawn_perch(owner_id: int, point: Vector3) -> Dictionary:
	if _offer.is_empty() or (_offer.point as Vector3).distance_to(point) > 0.01:
		return {}
	var offer := _offer
	_offer = {}
	if offer.get("ground", false):
		return _take_ground(owner_id, offer) if _ground_free(offer.point) else {}
	if _reservations.has(offer.key):
		return {}
	_reservations[offer.key] = owner_id
	return offer


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
		# A tree whose branches cannot reach the segment is skipped before touching its meshes:
		# most of the 48 nearby trees are nowhere near a short flight leg.
		var base := body.global_position
		var reach: float = entry.reach if entry.has("reach") else _reach(entry, body)
		if Geometry3D.get_closest_point_to_segment(base, from, to).distance_squared_to(base) > reach * reach:
			continue
		var inv := body.global_transform.affine_inverse()
		var wood: TriangleMesh = entry.data.get("wood")
		if wood != null and not wood.intersect_segment(inv * from, inv * to).is_empty():
			return false
		var foliage: TriangleMesh = entry.data.get("foliage")
		# Leaf textures occupy only part of their cards. Treat these conservatively
		# for resting headroom, but not as solid walls blocking all forest flight.
		if check_foliage and foliage != null and not foliage.intersect_segment(inv * from, inv * to).is_empty():
			return false
	return true


func reserve(owner_id: int, near: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	refresh()
	# Sampled, not enumerated: listing every anchor of 48 trees (thousands of transforms) and
	# sorting them cost several milliseconds per search. Near trees and low branches are
	# still preferred, through biased random picks.
	var trees := _trees_near(near, 45.0)
	if trees.is_empty():
		return {}
	var distances := {}
	for tree_id in trees:
		distances[tree_id] = (_trees[tree_id].body.get_ref() as Node3D).global_position.distance_squared_to(near)
	trees.sort_custom(func(a: int, b: int) -> bool: return distances[a] < distances[b])
	var checks := 0
	for _attempt in 32:
		var tree_id: int = trees[mini(int(pow(rng.randf(), 2.0) * trees.size()), trees.size() - 1)]
		var order := _low_first(_trees[tree_id].data)
		if order.is_empty():
			continue
		var index := order[mini(int(pow(rng.randf(), 2.0) * order.size()), order.size() - 1)]
		var perch := _anchor(tree_id, index)
		if perch.is_empty() or _reservations.has(perch.key) or _near_observer(perch.point) \
				or near.distance_to(perch.point) > 45.0:
			continue
		# The geometric checks are the expensive part: at most 12 of them per search.
		checks += 1
		if point_free(perch.point) and _feet_supported(perch):
			var approach: Variant = _approach_point(perch)
			if approach is Vector3:
				perch.approach = approach
				_reservations[perch.key] = owner_id
				return perch
		if checks >= 12:
			break
	return {}


## Perch indices of a tree ordered from the lowest branch up, computed once per tree type.
func _low_first(data: Dictionary) -> PackedInt32Array:
	if data.has("low_first"):
		return data.low_first
	var perches: Array = data.get("perches", [])
	var indices := range(perches.size())
	indices.sort_custom(func(a: int, b: int) -> bool:
		return (perches[a].point as Vector3).y < (perches[b].point as Vector3).y)
	var order := PackedInt32Array(indices)
	data.low_first = order
	return order


func reserve_ground(owner_id: int, near: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	refresh()
	var trees := _trees_near(near, 30.0)
	if trees.is_empty():
		return {}
	for _attempt in 6:
		var body: Node3D = _trees[trees[rng.randi() % trees.size()]].body.get_ref()
		var spot := _ground_spot(body, rng)
		if not spot.is_empty():
			return _take_ground(owner_id, spot)
	return {}


## One try at a foraging spot around [body]'s trunk: bare, gentle, dry ground with headroom,
## and a clear glide in from outside. Empty when this try fails.
func _ground_spot(body: Node3D, rng: RandomNumberGenerator) -> Dictionary:
	if not is_instance_valid(body):
		return {}
	var base := body.global_position
	var up := up_at(base)
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var outward := up.cross(reference).normalized().rotated(up, rng.randf_range(0.0, TAU))
	var hit := ground_below(base + outward * rng.randf_range(GROUND_RING_MIN, GROUND_RING_MAX), 3.0, 6.0)
	if not _ground_hit_ok(hit):
		return {}
	var point: Vector3 = hit.position
	up = up_at(point)
	if _near_observer(point) or not _ground_free(point):
		return {}
	var approach := point + up * 1.2 + outward * 1.2
	if not point_free(approach) or not path_clear(approach, point + up * 0.2):
		return {}
	var right := up.cross(outward.rotated(up, rng.randf_range(-PI, PI))).normalized()
	return {"ground": true, "point": point, "up": up, "right": right, "approach": approach}


func _ground_hit_ok(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	# Only static footing: tree and rock bodies, animals and hulls are not the ground.
	var collider: Object = hit.collider
	if collider is RigidBody3D or collider is CharacterBody3D or collider is VoxelInstancerRigidBody:
		return false
	var point: Vector3 = hit.position
	if (hit.normal as Vector3).dot(up_at(point)) < GROUND_MIN_UP:
		return false
	return ocean == null or point.distance_to(terrain.global_position) > ocean.radius + 0.4


## Room for a bird standing on the ground at [point], away from other foraging birds.
func _ground_free(point: Vector3, except_owner: int = -1) -> bool:
	var local := terrain.to_local(point)
	for owner_id in _ground:
		if owner_id != except_owner and (_ground[owner_id].local as Vector3).distance_to(local) < 0.6:
			return false
	var up := up_at(point)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _bird_shape
	query.transform.origin = point + up * 0.32
	query.collision_mask = 1
	if not terrain.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	return path_clear(point + up * 0.15, point + up * 1.2, true)


func _take_ground(owner_id: int, spot: Dictionary) -> Dictionary:
	var inverse := terrain.global_basis.inverse()
	_ground[owner_id] = {"local": terrain.to_local(spot.point), "right": inverse * (spot.right as Vector3),
		"approach": terrain.to_local(spot.approach)}
	return _ground_anchor(owner_id)


func _ground_anchor(owner_id: int) -> Dictionary:
	var spot: Dictionary = _ground.get(owner_id, {})
	if spot.is_empty():
		return {}
	var point := terrain.to_global(spot.local)
	var up := up_at(point)
	var right := (terrain.global_basis * (spot.right as Vector3)).slide(up).normalized()
	return {"ground": true, "owner": owner_id, "key": "g:%d" % owner_id, "point": point, "up": up,
		"right": right, "basis": Basis(right, up, right.cross(up)).orthonormalized(),
		"approach": terrain.to_global(spot.approach)}


func hop(anchor: Dictionary, offset: Vector3) -> Dictionary:
	if not anchor.get("ground", false) or not _ground.has(anchor.owner):
		return {}
	var hit := ground_below((anchor.point as Vector3) + offset, 0.4, 0.6)
	if not _ground_hit_ok(hit) or not _ground_free(hit.position, anchor.owner):
		return {}
	_ground[anchor.owner].local = terrain.to_local(hit.position)
	return _ground_anchor(anchor.owner)


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
	if perch.get("ground", false):
		# Out of the canopy first, then down onto the clearing.
		var rise := from + up * maxf(3.0, (approach - from).dot(up) + 2.0)
		if point_free(rise) and path_clear(from + up * 0.20, rise + up * 0.20) and path_clear(rise + up * 0.20, approach + up * 0.20):
			return [rise, approach]
		return []
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
	_ground.erase(owner_id)


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
