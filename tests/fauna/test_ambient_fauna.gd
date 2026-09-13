extends Node

class OpenWater extends WaterFaunaHabitat:
	func surface_radius(_point: Vector3) -> float:
		return 1000.0
	func terrain_is_clear(_point: Vector3, _clearance: float) -> bool:
		return true

class GenericHabitat extends AmbientFaunaHabitat:
	var valid: bool = true
	var calls: int = 0
	func sample_spawn(anchor: Vector3, _profile: AmbientFaunaProfile,
			_rng: RandomNumberGenerator) -> Variant:
		calls += 1
		return anchor + Vector3(20, 0, 0)
	func is_spawn_valid(_point: Vector3, _clearance: float) -> bool:
		return valid

class SlowHabitat extends GenericHabitat:
	func sample_spawn(anchor: Vector3, settings: AmbientFaunaProfile,
			rng: RandomNumberGenerator) -> Variant:
		# Una consulta indivisible ya excede el presupuesto: no debe arrancar la siguiente.
		OS.delay_usec(AmbientFaunaSpawner.FRAME_BUDGET_USEC + 1000)
		return super.sample_spawn(anchor, settings, rng)

var _failures: int = 0
var _world: Node3D


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	GameManager.current_state = GameManager.State.PLAYING
	_test_species_geometry()
	await _test_population()
	await _test_shared_spawn_budget()
	await _test_water_and_collisions()
	await _test_loaded_voxel_habitat()
	_world.queue_free()
	await get_tree().process_frame
	print("FAUNA TESTS: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _test_species_geometry() -> void:
	var distinct: Dictionary = {}
	for kind in SimpleFishMesh.TYPES.size():
		var mesh := SimpleFishMesh.mesh(kind)
		var bounds := SimpleFishMesh.collision_bounds(kind)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var contained := true
		var radius_safe := true
		for vertex in vertices:
			for sign_x in [-1.0, 1.0]:
				var animated := vertex + Vector3(sign_x * SimpleFishMesh.ANIMATION_MARGIN, 0, 0)
				contained = contained and bounds.has_point(animated)
				radius_safe = radius_safe and animated.length() * SimpleFishMesh.MAX_SCALE <= AmbientFish.CLEARANCE
		var name: String = SimpleFishMesh.TYPES[kind].name
		_check(contained and radius_safe, name + ": collision and spawn clearance contain the largest animated mesh")
		_check(mesh.get_surface_count() == 1 and vertices.size() / 3 < 2500, name + ": single surface and bounded triangle count")
		_check(mesh == SimpleFishMesh.mesh(kind), name + ": species instances reuse the cached mesh")
		distinct[mesh.get_instance_id()] = true
	_check(distinct.size() == 6, "All six species have distinct geometry, not just different colors")


func _test_population() -> void:
	var observer := Node3D.new()
	_world.add_child(observer)
	var habitat := GenericHabitat.new()
	var profile := AmbientFaunaProfile.new()
	var template := AmbientAnimal.new()
	profile.animal_scene = PackedScene.new()
	profile.animal_scene.pack(template)
	template.free()
	profile.population = 5
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(profile, habitat, observer)
	_world.add_child(spawner)
	spawner.set_physics_process(false)
	spawner.update_population()
	_check(spawner._pool.size() == 2, "Generic population respects activation budget")
	spawner.update_population()
	spawner.update_population()
	_check(spawner._pool.size() == 5, "Generic population reaches configured cap")
	var original_ids: Array[int] = []
	for animal in spawner._pool:
		original_ids.append(animal.get_instance_id())
	observer.position.x = 200.0
	spawner.update_population()
	spawner.update_population()
	spawner.update_population()
	var reused := true
	for animal in spawner._pool:
		reused = reused and animal.get_instance_id() in original_ids and animal.global_position.x > 200.0
	_check(reused, "Distant population reuses the same nodes around the observer")
	observer.position.x = 400.0
	habitat.valid = false
	var previous_calls := habitat.calls
	spawner.update_population()
	_check(habitat.calls - previous_calls == profile.attempts_per_update, "Invalid habitat exhausts only the bounded attempt budget")
	_check(spawner._pool.all(func(animal: AmbientAnimal) -> bool: return not animal.active), "Invalid spawn positions leave the pool inactive")
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.current = true
	await get_tree().process_frame
	_check(spawner._in_view(Vector3(0, 0, -10)), "Camera frustum rejects visible spawn candidates")
	_check(not spawner._in_view(Vector3(0, 0, 10)), "Camera frustum permits candidates behind the camera")
	camera.queue_free()
	spawner.queue_free()
	observer.queue_free()
	await get_tree().process_frame


func _test_shared_spawn_budget() -> void:
	var observer := Node3D.new()
	_world.add_child(observer)
	var profile := AmbientFaunaProfile.new()
	var template := AmbientAnimal.new()
	profile.animal_scene = PackedScene.new()
	profile.animal_scene.pack(template)
	template.free()
	var slow := SlowHabitat.new()
	var other := GenericHabitat.new()
	var spawners: Array[AmbientFaunaSpawner] = []
	for habitat in [slow, other]:
		var spawner := AmbientFaunaSpawner.new()
		spawner.setup(profile, habitat, observer)
		_world.add_child(spawner)
		spawner.set_physics_process(false)
		spawners.append(spawner)
	await get_tree().process_frame
	var start := Time.get_ticks_usec()
	spawners[0]._physics_process(1.0)
	spawners[1]._physics_process(1.0)
	spawners[0]._physics_process(1.0) # Simula otro tick de recuperación del mismo frame.
	_check(slow.calls == 1 and other.calls == 0, "Spawn budget is shared across species and catch-up ticks")
	_check(spawners[0]._pool.size() == 1, "A slow valid attempt completes, so expensive habitats cannot starve forever")
	print("SPAWN_BUDGET_TEST one_frame_ms=%.3f" % ((Time.get_ticks_usec() - start) / 1000.0))
	await get_tree().process_frame
	spawners[1]._physics_process(0.0)
	_check(other.calls > 0, "Deferred species gets its turn on the next frame")
	for spawner in spawners:
		spawner.queue_free()
	observer.queue_free()
	await get_tree().process_frame


func _test_water_and_collisions() -> void:
	var terrain := VoxelLodTerrain.new()
	_world.add_child(terrain)
	var water := OpenWater.new()
	water.terrain = terrain
	var unloaded := WaterFaunaHabitat.new()
	unloaded.terrain = terrain
	unloaded._voxels = terrain.get_voxel_tool()
	_check(not unloaded.terrain_is_clear(Vector3(0, 990, 0), 0.8), "Unloaded terrain is not treated as free water")
	_check(not water.is_spawn_valid(Vector3(0, 1001, 0), 0.8), "Spawn above the surface is rejected")
	_check(not water.is_spawn_valid(Vector3(0, 999, 0), 0.8), "Spawn must keep the whole fish below the surface")
	await get_tree().physics_frame
	_check(water.is_spawn_valid(Vector3(0, 990, 0), 0.8), "Free submerged position is accepted")
	var hull := DynamicGridBody.new()
	hull.freeze = true
	hull.damage_enabled = false
	hull.position = Vector3(0, 990, 0)
	_world.add_child(hull)
	hull._aggregate_box = {"pos": Vector3.ZERO, "half": Vector3(4, 3, 8)}
	hull._recalc_boxes = false
	if not hull.is_in_group("dynamic_grid_body"):
		hull.add_to_group("dynamic_grid_body")
	await get_tree().physics_frame
	_check(not water.is_spawn_valid(Vector3(0, 990, 0), 0.8), "Empty/flooded hull interior is rejected without relying on collider surfaces")
	hull.rotation.y = PI / 2.0
	_check(not water.is_spawn_valid(Vector3(7, 990, 0), 0.8), "Rotated hull envelope rejects interior spawns")
	_check(water.is_spawn_valid(Vector3(12, 990, 0), 0.8), "Water outside the hull remains available")
	hull.queue_free()
	await get_tree().process_frame
	var fish: AmbientFish = load("res://scenes/animals/ambient_fish.tscn").instantiate()
	terrain.add_child(fish)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var variants_reset := true
	for kind in SimpleFishMesh.TYPES.size():
		fish.fish_type = kind
		fish.activate(Vector3(0, 990, 0), water, rng)
		fish.set_physics_process(false)
		var visual := fish.get_node("Visual") as MeshInstance3D
		var shape_node := fish.get_node("CollisionShape3D") as CollisionShape3D
		var expected := SimpleFishMesh.collision_bounds(kind)
		variants_reset = variants_reset and fish.current_type == kind and visual.mesh == SimpleFishMesh.mesh(kind)
		variants_reset = variants_reset and (shape_node.shape as BoxShape3D).size.is_equal_approx(expected.size * visual.scale.x)
		variants_reset = variants_reset and shape_node.position.is_equal_approx(expected.get_center() * visual.scale.x)
		fish.deactivate()
	_check(variants_reset, "Reusing a fish across all six types resets the mesh and matching collision box")
	fish.fish_type = -1
	fish.activate(Vector3(0, 990, 0), water, rng)
	fish.set_physics_process(false)
	_check(fish.get_node("Visual").mesh.get_surface_count() == 1, "Simple fish uses one shared mesh surface")
	# Swept collision against a stationary thin wall.
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 990, -2)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 10, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	_world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	fish.global_basis = Basis.IDENTITY
	var hit := fish.move_and_collide(Vector3(0, 0, -10))
	_check(hit != null and fish.global_position.z > -2.0, "Fish box sweep cannot cross a thin hull wall")
	wall.queue_free()
	await get_tree().process_frame
	# A boat-speed rigid wall moving towards a stationary/slow fish.
	var moving_wall := DynamicGridBody.new()
	moving_wall.damage_enabled = false
	moving_wall.gravity_scale = 0.0
	moving_wall.linear_damp = 0.0
	moving_wall.collision_layer = 1
	moving_wall.collision_mask = 0
	moving_wall.position = Vector3(-4, 990, 0)
	var moving_shape := CollisionShape3D.new()
	var moving_box := BoxShape3D.new()
	moving_box.size = Vector3(0.25, 20, 30)
	moving_shape.shape = moving_box
	moving_wall.add_child(moving_shape)
	_world.add_child(moving_wall)
	moving_wall._aggregate_box = {"pos": Vector3.ZERO, "half": moving_box.size * 0.5}
	moving_wall._recalc_boxes = false
	fish.activate(Vector3(0, 990, 0), water, rng)
	fish.set_physics_process(false)
	moving_wall.linear_velocity = Vector3(20, 0, 0)
	for _frame in 25:
		await get_tree().physics_frame
		if fish.active:
			fish._swim(1.0 / 60.0)
	_check(not fish.active or fish.global_position.x > moving_wall.global_position.x,
		"Moving rigid hull at 20 m/s cannot leave an active fish behind its wall")
	_check(water._blood_pool.size() == 1, "A fast moving hull produces exactly one blood cloud")
	print("Moving hull x=%.3f fish x=%.3f" % [moving_wall.position.x, fish.global_position.x])
	moving_wall.queue_free()
	await get_tree().process_frame
	await _test_impact_threshold(fish, water, rng)
	fish.activate(Vector3(0, 990, 0), water, rng)
	fish.set_physics_process(false)
	var before := fish._target_local
	terrain.position += Vector3(-4000, 0, 3000)
	_check(fish._target_local.is_equal_approx(before) and fish.global_position.is_equal_approx(Vector3(-4000, 990, 3000)),
		"Origin rebase moves fish and preserves its terrain-local swim target")
	fish.deactivate()
	_check(fish.get_node("CollisionShape3D").disabled and not fish.visible, "Recycled fish disables collision and rendering")
	fish.queue_free()
	terrain.queue_free()
	await get_tree().process_frame


func _test_impact_threshold(fish: AmbientFish, water: WaterFaunaHabitat, rng: RandomNumberGenerator) -> void:
	var ship := DynamicGridBody.new()
	ship.freeze = true
	ship.damage_enabled = false
	ship.position = Vector3(0, 990, -2)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 10, 0.2)
	collider.shape = box
	ship.add_child(collider)
	_world.add_child(ship)
	ship._aggregate_box = {"pos": Vector3.ZERO, "half": box.size * 0.5}
	ship._recalc_boxes = false
	fish.activate(Vector3(0, 990, 0), water, rng)
	fish.set_physics_process(false)
	fish.global_basis = Basis.IDENTITY
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := fish.move_and_collide(Vector3(0, 0, -10), true)
	_check(hit != null, "Impact threshold fixture contacts the actual boat collider")
	if hit != null:
		_check(not fish._resolve_ship_hit(hit, Vector3(0, 0, -4.99)) and fish.active, "Impact below 5 m/s keeps the fish alive")
		_check(not fish._resolve_ship_hit(hit, Vector3(0, 0, -5.0)) and fish.active, "Impact at exactly 5 m/s keeps the fish alive")
		_check(not fish._resolve_ship_hit(hit, Vector3(12, 0, -0.1)) and fish.active, "Fast tangential graze is not a violent normal impact")
		var before := water._blood_pool.size()
		_check(fish._resolve_ship_hit(hit, Vector3(0, 0, -5.01)) and not fish.active, "Impact above 5 m/s kills the fish")
		_check(water._blood_pool.size() == before + 1, "Lethal impact creates a small independent blood effect")
		fish._resolve_ship_hit(hit, Vector3(0, 0, -20))
		_check(water._blood_pool.size() == before + 1, "The same fish cannot burst twice")
	_check(is_zero_approx(AmbientAnimal.closing_speed(Vector3(10, 0, 0), Vector3(10, 0, 0), Vector3.RIGHT)),
		"Equal fish and boat velocities do not count as an impact")
	for cloud in water._blood_pool:
		cloud._process(BloodCloud.LIFETIME + 0.2)
	_check(water._blood_pool.all(func(cloud: BloodCloud) -> bool: return not cloud.active and not cloud.visible),
		"Blood clouds dissipate and stop processing after three seconds")
	var pool_size := water._blood_pool.size()
	water.burst_blood(Vector3(0, 990, 0))
	_check(water._blood_pool.size() == pool_size, "Blood effects reuse an expired cloud")
	for _i in 12:
		water.burst_blood(Vector3(0, 990, 0))
	_check(water._blood_pool.size() <= 8, "Blood effects have a bounded pool under repeated impacts")
	ship.queue_free()


func _test_loaded_voxel_habitat() -> void:
	var terrain := VoxelLodTerrain.new()
	var generator := VoxelGeneratorFlat.new()
	generator.height = 980.0
	terrain.generator = generator
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 3
	terrain.view_distance = 128
	terrain.streaming_system = VoxelLodTerrain.STREAMING_SYSTEM_CLIPBOX
	_world.add_child(terrain)
	var observer := VoxelViewer.new()
	observer.position = Vector3(0, 995, 0)
	observer.view_distance = 128
	_world.add_child(observer)
	var ocean := OceanSystem.new()
	ocean.radius = 1000.0
	ocean.quadtree_material = load("res://data/resources/WaterSphere_material.tres")
	var habitat := WaterFaunaHabitat.new()
	habitat.setup(terrain, ocean, null)
	var ready := false
	for _attempt in 100:
		await get_tree().create_timer(0.05).timeout
		if habitat.terrain_is_clear(Vector3(0, 990, 0), 0.95):
			ready = true
			break
	_check(ready, "Real streamed voxel terrain supports valid water queries without changing its cache settings")
	_check(not habitat.terrain_is_clear(Vector3(0, 979, 0), 0.95), "Real SDF rejects fish inside the sea floor")
	if ready:
		var profile: AmbientFaunaProfile = load("res://data/fauna/coastal_fish.tres")
		var rng := RandomNumberGenerator.new()
		rng.seed = 123
		var accepted := 0
		for _attempt in 60:
			var candidate: Variant = habitat.sample_spawn(observer.global_position, profile, rng)
			if candidate is Vector3 and habitat.is_spawn_valid(candidate, profile.clearance):
				accepted += 1
		_check(accepted > 0, "Real ocean sampler and loaded terrain produce underwater spawn candidates")
		print("Real habitat accepted %d/60 candidates" % accepted)
		var spawner := AmbientFaunaSpawner.new()
		spawner.setup(profile, habitat, observer)
		terrain.add_child(spawner)
		for _step in 20:
			await get_tree().create_timer(0.05).timeout
			spawner.update_population()
		var active := 0
		for animal in spawner._pool:
			if animal.active:
				active += 1
		_check(active > 0, "Real fish spawn and remain swimming in the streamed habitat")
		print("Real habitat active fish: ", active)
	observer.queue_free()
	terrain.queue_free()
	await get_tree().process_frame
	ocean.free()
