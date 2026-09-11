extends Node3D

var failures := 0
var terrain: VoxelLodTerrain
var observer: VoxelViewer
var ocean: OceanSystem
var map: PlanetWorldMap
var habitat: WaterBirdHabitat
var rng := RandomNumberGenerator.new()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _ready() -> void:
	_run.call_deferred()


func shore(distance: float) -> void:
	for i in map.map.shore_size.x * map.map.shore_size.y:
		map.map.shore_offsets[i * 4 + 3] = distance


func _run() -> void:
	GameManager.current_state = GameManager.State.PLAYING
	rng.seed = 769
	terrain = VoxelLodTerrain.new()
	var generator := VoxelGeneratorFlat.new()
	generator.height = 980.0
	terrain.generator = generator
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 3
	terrain.view_distance = 128
	terrain.streaming_system = VoxelLodTerrain.STREAMING_SYSTEM_CLIPBOX
	add_child(terrain)
	observer = VoxelViewer.new()
	observer.position = Vector3(0, 1002, 0)
	observer.view_distance = 128
	terrain.add_child(observer)
	var camera := Camera3D.new()
	observer.add_child(camera)
	camera.current = true
	ocean = OceanSystem.new()
	ocean.radius = 1000.0
	ocean.quadtree_material = load("res://data/resources/WaterSphere_material.tres")
	map = PlanetWorldMap.new()
	map._center_node = terrain
	map.map = WorldMapData.new()
	map.map.size = Vector2i(32, 16)
	map.map.radius = 1000.0
	map.map.sea_level_radius = 1000.0
	map.map.has_water = true
	map.map.height_min = -100.0
	map.map.height_span = 200.0
	map.map.heights.resize(512)
	map.map.heights.fill(0.4)
	map.map.shore_size = Vector2i(32, 16)
	map.map.shore_offsets.resize(2048)
	map.map.shore_range = 300.0
	map.map.body_ids.resize(512)
	map.map.body_ids.fill(0)
	map.map.bodies = [{"type": WorldMapData.WaterType.OCEAN}]
	add_child(map)
	var profile: WaterBirdProfile = load("res://data/fauna/river_ducks.tres").duplicate()
	habitat = WaterBirdHabitat.new()
	habitat.setup(terrain, observer, ocean, map, {}, profile)
	shore(50.0)
	for attempt in 100:
		if habitat._water.terrain_is_clear(observer.global_position, 1.0):
			break
		await get_tree().create_timer(0.05).timeout
	check(habitat.is_spawn_valid(observer.global_position, 0.7), "Water birds spawn in real loaded voxel airspace")
	check(not habitat.is_spawn_valid(Vector3(0, 979, 0), 0.7), "Water birds cannot spawn in the seabed")
	check(not habitat.is_spawn_valid(Vector3(5000, 1002, 0), 0.7), "Unloaded terrain cannot admit a spawn")
	check(habitat.habitat_allowed(observer.global_position), "Coastal water inside offshore range is eligible")
	shore(profile.max_offshore_distance + 1.0)
	check(not habitat.habitat_allowed(observer.global_position), "Ocean beyond species offshore limit is excluded")
	shore(-profile.coast_inland_distance)
	check(habitat.habitat_allowed(observer.global_position), "Shore band includes its inland boundary")
	shore(-profile.coast_inland_distance - 1.0)
	check(not habitat.habitat_allowed(observer.global_position), "Deep inland is excluded")
	shore(300.0)
	profile.max_offshore_distance = 500.0
	check(not habitat.habitat_allowed(observer.global_position), "Saturated shore distance does not classify the open ocean as coastal")
	map.map.heights.fill(0.6)
	check(habitat.habitat_allowed(observer.global_position), "Extended offshore range requires confirmed nearby land")
	map.map.heights.fill(0.4)
	profile.max_offshore_distance = 80.0
	var river := Image.create(32, 16, false, Image.FORMAT_RF)
	river.fill(Color.WHITE)
	habitat.rivers = {"dist": river, "carve_range": 220.0}
	check(not habitat.habitat_allowed(observer.global_position), "River mouth data cannot bypass the maximum offshore distance")
	shore(-300.0)
	check(habitat.habitat_allowed(observer.global_position), "Wet river channels are eligible independently of coastal distance")
	var voxels := terrain.get_voxel_tool()
	voxels.channel = VoxelBuffer.CHANNEL_SDF
	voxels.mode = VoxelTool.MODE_ADD
	voxels.do_sphere(Vector3(0, 1000, 0), 5.0)
	check(habitat.habitat_allowed(observer.global_position), "Solid river banks allow flight near a wet channel")
	voxels.do_sphere(Vector3(0, 1000, 0), 40.0)
	check(not habitat.habitat_allowed(observer.global_position), "Dry river channels cannot spawn water birds")
	voxels.mode = VoxelTool.MODE_REMOVE
	voxels.do_sphere(Vector3(0, 1000, 0), 41.0)
	habitat.rivers = {}
	shore(50.0)
	for resource in ["coastal_gulls", "river_ducks"]:
		var species: WaterBirdProfile = load("res://data/fauna/%s.tres" % resource).duplicate()
		check(species.flight_time_min >= 8.0 and species.flight_time_max >= species.flight_time_min,
			resource + " default flights last substantially longer than a short hop")
		# Short deterministic duration, but enough required travel to distinguish
		# actual sustained flight from waiting in the air for a timer to expire.
		species.flight_time_min = 6.0 if resource == "coastal_gulls" else 1.0
		species.flight_time_max = species.flight_time_min
		species.flight_distance_min = 10.0 if resource == "coastal_gulls" else 60.0
		species.perch_time_min = 20.0
		species.perch_time_max = 20.0
		habitat.settings = species
		var accepted := 0
		for attempt in 60:
			var point: Variant = habitat.sample_spawn(observer.global_position, species, rng)
			if point is Vector3 and habitat.is_spawn_valid(point, species.clearance):
				if accepted == 0:
					check(point.distance_to(observer.global_position) <= species.spawn_radius, resource + " spawn respects player radius")
				accepted += 1
		check(accepted > 0, resource + " spawns without trees or branches")
		var bird: AmbientWaterBird = species.animal_scene.instantiate()
		bird.profile = species
		terrain.add_child(bird)
		bird.activate(Vector3(15, 1005, 0), habitat, rng)
		check(bird._cruising and bird._perch.is_empty(), resource + " starts in cruise without reserving an immediate landing")
		var airborne_time := 0.0
		var started_frame := Engine.get_physics_frames()
		var previous := bird.global_position
		var flown := 0.0
		var farthest := 0.0
		var early_landing := false
		var cruising_samples := 0
		var moving_samples := 0
		var landed := false
		for attempt in 400:
			await get_tree().create_timer(0.05).timeout
			airborne_time = float(Engine.get_physics_frames() - started_frame) / Engine.physics_ticks_per_second
			flown += (bird.global_position - previous).slide(habitat.up_at(previous)).length()
			previous = bird.global_position
			farthest = maxf(farthest, bird.global_position.distance_to(Vector3(15, 1005, 0)))
			if bird._cruising and airborne_time > 1.0:
				cruising_samples += 1
				if bird.velocity.length() > bird._speed * 0.5:
					moving_samples += 1
			if airborne_time < species.flight_time_min - 0.2 and not bird._cruising:
				early_landing = true
			if bird.state == AmbientBird.State.PERCHED:
				landed = true
				break
		check(not early_landing and airborne_time >= species.flight_time_min - 0.2, resource + " respects configurable minimum flight time")
		check(bird._cruise_distance >= species.flight_distance_min, resource + " finishes the required cruise distance before starting its landing approach")
		check(flown >= species.flight_distance_min - 1.0 and farthest > 20.0, resource + " covers real distance in broad flights before landing")
		check(cruising_samples > 0 and moving_samples > cruising_samples * 0.8, resource + " keeps flying through waypoints without stopping")
		check(landed, resource + " flies and lands on the actual wave surface")
		print("CRUISE %s: %.1f s, %.1f m travelled, %.1f m from start" % [resource, airborne_time, flown, farthest])
		if landed:
			var before := bird.global_position
			await get_tree().create_timer(1.0).timeout
			check((bird.global_position - before).slide(habitat.up_at(before)).length() > species.swim_speed * 0.5,
				resource + " swims at its configurable speed")
			check(absf(bird.global_position.distance_to(terrain.global_position) - habitat._water.surface_radius(bird.global_position) + 0.08) < 0.15,
				resource + " stays afloat as waves change")
			var before_local := bird.position
			terrain.position += Vector3(-4000, 0, 3000)
			var anchor := habitat.resolve(bird._perch)
			check(not anchor.is_empty() and terrain.to_local(anchor.point).distance_to(before_local) < 0.15,
				resource + " water anchor survives origin rebasing")
			terrain.position = Vector3.ZERO
			species.flight_time_min = 4.0
			species.flight_time_max = 4.0
			bird._timer = 0.0
			await get_tree().create_timer(2.0).timeout
			check(bird._cruising and bird._perch.is_empty() and bird._cruise_distance > 10.0,
				resource + " takes off into another sustained flight after resting")
		bird.deactivate()
		check(habitat._owners.is_empty(), resource + " recycling releases water reservation")
		bird.queue_free()
		await get_tree().process_frame
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(habitat.settings, habitat, observer)
	terrain.add_child(spawner)
	for attempt in 10:
		spawner.update_population()
		await get_tree().create_timer(0.1).timeout
	check(spawner._pool.any(func(bird: AmbientAnimal) -> bool: return bird.active), "Shared population spawner activates water birds around a real observer")
	spawner.queue_free()
	await get_tree().process_frame
	var ship := DynamicGridBody.new()
	ship.freeze = true
	ship.damage_enabled = false
	ship.position = Vector3(0, 1003, 0)
	terrain.add_child(ship)
	ship._aggregate_box = {"pos": Vector3.ZERO, "half": Vector3(4, 4, 4)}
	ship._recalc_boxes = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not habitat.is_spawn_valid(ship.global_position, 0.7), "Empty boat decks are excluded from spawning by the full hull envelope")
	ship.queue_free()
	terrain.queue_free()
	map.queue_free()
	await get_tree().process_frame
	ocean.free()
	print("WATER BIRD TESTS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
