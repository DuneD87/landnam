extends Node

class OpenHabitat extends AmbientFaunaHabitat:
	func sample_spawn(anchor: Vector3, settings: AmbientFaunaProfile, rng: RandomNumberGenerator) -> Variant:
		var angle := rng.randf_range(0, TAU)
		return anchor + Vector3(cos(angle), 0, sin(angle)) * settings.sample_spawn_distance(rng)
	func is_spawn_valid(_point: Vector3, _clearance: float) -> bool:
		return true

class ProjectedHabitat extends AmbientFaunaHabitat:
	var offset := Vector3.ZERO
	var validations := 0
	func sample_spawn(anchor: Vector3, _settings: AmbientFaunaProfile, _rng: RandomNumberGenerator) -> Variant:
		return anchor + offset
	func is_spawn_valid(_point: Vector3, _clearance: float) -> bool:
		validations += 1
		return true

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func _run() -> void:
	var world := Node3D.new()
	add_child(world)
	var observer := Node3D.new()
	world.add_child(observer)
	observer.position = Vector3(0, 1000, 0)
	var settings := load("res://data/fauna/forest_birds.tres").duplicate() as AmbientFaunaProfile
	var bird := AmbientAnimal.new()
	settings.animal_scene = PackedScene.new()
	settings.animal_scene.pack(bird)
	bird.free()
	# Check the real forest sampler, including its altitude adjustment, using a
	# registered tree so no streamed world or physics timing affects the histogram.
	var forest := ForestBirdHabitat.new()
	forest.setup(world, observer)
	var tree := Node3D.new()
	world.add_child(tree)
	forest.register_tree(tree, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 49187
	var bands := [0, 0, 0, 0]
	var bounded := true
	for sample in 12000:
		var point: Vector3 = forest.sample_spawn(observer.global_position, settings, rng)
		var distance := point.distance_to(observer.global_position)
		bounded = bounded and distance >= settings.spawn_min_distance and distance <= settings.spawn_radius
		var area := inverse_lerp(settings.spawn_min_distance ** 2, settings.spawn_radius ** 2, distance ** 2)
		bands[mini(3, int(area * 4))] += 1
	check(bounded, "Forest samples respect the complete 3D distance interval")
	check(bands.all(func(count: int) -> bool: return count > 2800 and count < 3200), "Equal-area rings receive comparable populations: " + str(bands))
	for seed_value in [71, 284, 1991]:
		var spawner := AmbientFaunaSpawner.new()
		spawner.setup(settings, OpenHabitat.new(), observer)
		world.add_child(spawner)
		spawner.set_physics_process(false)
		spawner._rng.seed = seed_value
		for tick in 160:
			spawner.update_population()
		var separated := true
		var nearby := 0
		var quadrants := [0, 0, 0, 0]
		for i in spawner._pool.size():
			var animal := spawner._pool[i]
			var offset := animal.global_position - observer.global_position
			if offset.length() < 30.0:
				nearby += 1
			quadrants[(2 if offset.x < 0 else 0) + (1 if offset.z < 0 else 0)] += 1
			for j in i:
				separated = separated and animal.global_position.distance_to(spawner._pool[j].global_position) >= settings.min_spacing
		check(spawner._pool.size() == settings.population, "Dispersal can fill the existing population cap, seed " + str(seed_value))
		check(separated and nearby < settings.population / 3 and quadrants.min() >= 5, "Population is separated and spread around the annulus, seed " + str(seed_value))
		var occupied := spawner._pool[0].global_position
		world.position += Vector3(-10000, 3000, 7000)
		check(spawner._crowded(occupied + Vector3(-10000, 3000, 7000)), "Spacing survives a floating-origin rebase")
		world.position = Vector3.ZERO
		spawner.free()
	var projected := ProjectedHabitat.new()
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(settings, projected, observer)
	world.add_child(spawner)
	spawner.set_physics_process(false)
	for distance in [2.0, settings.spawn_radius + 1.0]:
		projected.offset = Vector3(distance, 0, 0)
		spawner.update_population()
	check(spawner._pool.is_empty() and projected.validations == 0, "Projected positions outside either spawn bound are rejected before collision checks")
	projected.offset = Vector3(settings.spawn_min_distance + 1.0, 0, 0)
	spawner.update_population()
	check(spawner._pool.size() == 1 and projected.validations == 1, "A valid position spawns once; repeated crowded candidates are cheap to reject")
	for id in ["forest_birds", "coastal_gulls", "river_ducks", "coastal_fish", "rabbits", "mice", "foxes", "deer", "bear", "lion", "buffalo", "shark", "whale", "orca", "turtle"]:
		var profile := load("res://data/fauna/%s.tres" % id) as AmbientFaunaProfile
		check(profile.min_spacing > 0 and profile.spawn_min_distance >= 18 and profile.spawn_radius > profile.spawn_min_distance and profile.recycle_distance >= profile.spawn_radius + 5,
			id + ": configured for separated spawns and a wider retention radius")
	world.free()
	print("FAUNA DISTRIBUTION TESTS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
