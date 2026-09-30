extends Node3D

## Natural behaviour of forest birds: resting spawns, roaming without hovering, flushing by
## the observer's pace, alarm spreading through a flock, and lock-on over every creature.

var failures := 0
var forest: ForestBirdHabitat
var ground: Node3D
var observer: Node3D
var profile: AmbientBirdProfile
var rng := RandomNumberGenerator.new()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameManager.current_state = GameManager.State.PLAYING
	rng.seed = 913
	ground = Node3D.new()
	add_child(ground)
	# Flat solid ground whose top is at y = 1000, so birds can forage on it.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	floor_shape.shape = box
	floor_body.position = Vector3(0, 999, 0)
	floor_body.add_child(floor_shape)
	ground.add_child(floor_body)
	# Ground "up" is +Y near the fixture: the planet centre is far below.
	ground.position = Vector3.ZERO
	observer = Node3D.new()
	observer.position = Vector3(0, 1001, 30)
	ground.add_child(observer)
	forest = ForestBirdHabitat.new()
	forest.setup(ground, observer)
	for i in 2:
		var name := "pine_01" if i == 0 else "olive_01"
		var source: Node3D = load("res://scenes/planet/planet_items/vegetation/trees/%s.tscn" % name).instantiate()
		var meshes: Array = source.get_child(0).bake_lods()
		var tree := Node3D.new()
		tree.position = Vector3(-4 if i == 0 else 4, 1000, 0)
		tree.rotation.y = 0.4 + i
		tree.scale = Vector3.ONE * (0.6 if i == 0 else 2.0)
		ground.add_child(tree)
		forest.register_tree(tree, TreePerchBaker.bake(meshes[0]))
		source.free()
	profile = (load("res://data/fauna/forest_birds.tres") as AmbientBirdProfile).duplicate()
	profile.spawn_min_distance = 10.0
	profile.spawn_radius = 45.0
	for _frame in 3:
		await get_tree().physics_frame
	await _test_resting_spawns()
	await _test_roaming_never_hovers()
	await _test_flush_by_pace()
	await _test_alarm_spreads()
	_test_lock_api()
	ground.queue_free()
	await get_tree().process_frame
	print("BIRD BEHAVIOUR TESTS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func _spawn(point: Vector3) -> AmbientBird:
	var bird: AmbientBird = profile.animal_scene.instantiate()
	ground.add_child(bird)
	bird.bird_type = 0
	bird.profile = profile
	bird.activate(point, forest, rng)
	return bird


func _test_resting_spawns() -> void:
	profile.perched_spawn_chance = 1.0
	profile.ground_chance = 0.0
	var branch: AmbientBird
	for attempt in 20:
		var point: Variant = forest.sample_spawn(observer.global_position, profile, rng)
		if point is Vector3:
			branch = _spawn(point)
			break
	check(branch != null and branch.state == AmbientBird.State.PERCHED and not branch._perch.get("ground", false)
		and forest._reservations.values().has(branch.get_instance_id()),
		"A resting spawn appears already perched on a reserved branch")
	profile.ground_chance = 1.0
	var forager: AmbientBird
	for attempt in 40:
		var point: Variant = forest.sample_spawn(observer.global_position, profile, rng)
		if point is Vector3:
			forager = _spawn(point)
			break
	check(forager != null and forager.state == AmbientBird.State.PERCHED and forager._perch.get("ground", false),
		"Ground foraging spawns appear on the ground under the trees")
	if forager != null:
		check(absf(forager.global_position.y - 1000.0) < 0.05, "A foraging bird stands on the ground surface")
		var start := forager.global_position
		var pecked := false
		forager._timer = 30.0
		for frame in 360:
			await get_tree().physics_frame
			pecked = pecked or forager._peck >= 0.0
		check(pecked, "A foraging bird pecks at the ground while resting")
		check(forager.state == AmbientBird.State.PERCHED and absf(forager.global_position.y - 1000.0) < 0.05
			and forager.global_position.distance_to(start) < 3.0,
			"Hops keep the forager on the ground near where it landed")
		print("FORAGER moved=", forager.global_position.distance_to(start))
	profile.perched_spawn_chance = 0.0
	var aloft := 0
	for attempt in 10:
		var flying: Variant = forest.sample_spawn(observer.global_position, profile, rng)
		if flying is Vector3 and (flying as Vector3).y > 1003.0:
			aloft += 1
	check(aloft >= 8, "Flying arrivals come in at canopy height above the ground")
	for bird in [branch, forager]:
		if bird != null:
			bird.deactivate()
			bird.queue_free()
	check(forest._reservations.is_empty() and forest._ground.is_empty(), "Recycled resting birds free branches and ground spots")


func _test_roaming_never_hovers() -> void:
	# A habitat with no trees at all: the bird has nowhere to land and must keep flying.
	var empty := ForestBirdHabitat.new()
	empty.setup(ground, observer)
	var bird: AmbientBird = profile.animal_scene.instantiate()
	ground.add_child(bird)
	bird.profile = profile
	bird.activate(Vector3(0, 1006, 0), empty, rng)
	var samples := 0
	var moving := 0
	var lowest := INF
	var left_at := -1.0
	for frame in 1800:
		await get_tree().physics_frame
		if not bird.active:
			left_at = bird.global_position.distance_to(observer.global_position)
			break
		samples += 1
		if bird.velocity.length() > bird._speed * 0.4:
			moving += 1
		lowest = minf(lowest, bird.global_position.y - 1000.0)
	print("ROAMING moving=%d/%d lowest=%.2f left_at=%.1f" % [moving, samples, lowest, left_at])
	check(samples > 240 and moving > samples * 0.9,
		"Without anywhere to land a bird keeps flying instead of hovering in place")
	check(lowest > 1.0, "Roaming flight stays clear of the ground")
	check(left_at > profile.spawn_radius,
		"After repeated failed searches it flies off and returns to the pool once far away")
	bird.deactivate()
	bird.queue_free()


func _test_flush_by_pace() -> void:
	profile.perched_spawn_chance = 1.0
	profile.ground_chance = 0.0
	profile.long_rest_chance = 0.0
	profile.perch_time_min = 60.0
	profile.perch_time_max = 60.0
	var bird: AmbientBird
	for attempt in 20:
		var point: Variant = forest.sample_spawn(observer.global_position, profile, rng)
		if point is Vector3:
			bird = _spawn(point)
			break
	if bird == null:
		check(false, "Fixture provides a resting bird for the flush test")
		return
	bird._timer = 60.0
	var up := Vector3.UP
	var side := (observer.global_position - bird.global_position).slide(up).normalized()
	# Standing still at 7.5 m: calmer than even the most nervous bird's walking distance.
	observer.global_position = bird.global_position + side * 7.5
	# The fixture's teleport is not a sprint: start the speed measurement afresh.
	forest._speed_frame = -1
	forest._observer_speed = 0.0
	for frame in 30:
		await get_tree().physics_frame
	check(bird.state == AmbientBird.State.PERCHED, "A still observer at 7.5 m does not flush a resting bird")
	# Running past at 8 m/s at the same distance.
	var tangent := side.cross(up).normalized()
	var centre := bird.global_position
	var elapsed := 0.0
	for frame in 30:
		elapsed += 1.0 / Engine.physics_ticks_per_second
		var sweep := tangent * elapsed * 8.0
		observer.global_position = centre + (side * 7.5 + sweep).normalized() * 7.5
		await get_tree().physics_frame
		if bird.state != AmbientBird.State.PERCHED:
			break
	check(bird.state == AmbientBird.State.TAKEOFF and bird._fleeing, "A running observer flushes the same bird from farther away")
	var start := bird.global_position
	var threat := observer.global_position
	for frame in 90:
		await get_tree().physics_frame
	check(bird.global_position.distance_to(threat) > start.distance_to(threat) + 2.0,
		"A flushed bird bolts away from the threat")
	bird.deactivate()
	bird.queue_free()
	observer.position = Vector3(0, 1001, 30)


func _test_alarm_spreads() -> void:
	profile.perched_spawn_chance = 1.0
	profile.ground_chance = 0.0
	var flock: Array[AmbientBird] = []
	for attempt in 60:
		if flock.size() >= 2:
			break
		var point: Variant = forest.sample_spawn(observer.global_position, profile, rng)
		if not point is Vector3:
			continue
		if flock.size() == 1 and flock[0].global_position.distance_to(point) > profile.alarm_radius * 0.9:
			forest._offer = {}
			continue
		flock.append(_spawn(point))
	if flock.size() < 2:
		check(false, "Fixture provides two resting birds close together")
		return
	for bird in flock:
		bird._timer = 60.0
	for frame in 5:
		await get_tree().physics_frame
	check(flock.all(func(b: AmbientBird) -> bool: return b.state == AmbientBird.State.PERCHED), "Both flock birds rest calmly with the observer far away")
	# An arrow lands right under the first bird only.
	AmbientAnimal.startle_near(get_tree(), flock[0].global_position, 0.3)
	var first_left := -1
	var second_left := -1
	for frame in 60:
		await get_tree().physics_frame
		if first_left < 0 and flock[0].state != AmbientBird.State.PERCHED:
			first_left = frame
		if second_left < 0 and flock[1].state != AmbientBird.State.PERCHED:
			second_left = frame
	print("ALARM first=", first_left, " second=", second_left)
	check(first_left >= 0 and first_left < 20, "An impact startles the bird resting next to it")
	check(second_left > first_left, "Its neighbour follows it into the air a moment later")
	for bird in flock:
		bird.deactivate()
		bird.queue_free()


func _test_lock_api() -> void:
	var bird: AmbientBird = profile.animal_scene.instantiate()
	ground.add_child(bird)
	bird.profile = profile
	var empty := ForestBirdHabitat.new()
	empty.setup(ground, observer)
	bird.activate(Vector3(0, 1006, 0), empty, rng)
	var combat := PlayerCombat.new()
	check(bird.lockable() and combat._lockable(bird), "Birds are valid lock-on targets while alive")
	check(combat._lock_point(bird).distance_to(bird.global_position + Vector3.UP * 0.18) < 0.01,
		"The lock point is the bird's body, not its feet")
	bird.velocity = Vector3(10, 0, 0)
	check(combat._lock_velocity(bird).is_equal_approx(Vector3(10, 0, 0)), "Lock-on reads the target's velocity to lead the shot")
	bird.deactivate()
	check(not combat._lockable(bird), "A recycled bird is no longer a lock target")
	check(not combat._lockable(null), "No target is not lockable")
	combat.free()
	bird.queue_free()
