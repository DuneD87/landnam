class_name AmbientFaunaSpawner extends Node3D

## Bounded, reusable population around an observer. No water/flight/ground logic here.
## Parent this under the planet so origin rebases move the entire pool exactly once.
var profile: AmbientFaunaProfile
var habitat: AmbientFaunaHabitat
var observer: Node3D
var _pool: Array[AmbientAnimal] = []
var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0


func setup(settings: AmbientFaunaProfile, environment: AmbientFaunaHabitat,
		player: Node3D) -> void:
	profile = settings
	habitat = environment
	observer = player
	_rng.randomize()


func _physics_process(delta: float) -> void:
	if profile == null or habitat == null or not is_instance_valid(observer):
		return
	if GameManager.current_state != GameManager.State.PLAYING:
		for animal in _pool:
			if animal.active:
				animal.deactivate()
		return
	_elapsed += delta
	if _elapsed < maxf(profile.update_interval, 0.05):
		return
	_elapsed = 0.0
	var start := Time.get_ticks_usec()
	update_population()
	DebugStats.report_cost(&"fauna:spawner", Time.get_ticks_usec() - start)


func update_population() -> void:
	if profile.animal_scene == null:
		return
	# Reducing the configured population also releases the surplus pool nodes.
	while _pool.size() > profile.population:
		_pool.pop_back().queue_free()
	var count := 0
	var recycle := maxf(profile.recycle_distance, profile.spawn_radius + 5.0)
	for animal in _pool:
		if not animal.active:
			continue
		var distance := observer.global_position.distance_to(animal.global_position)
		if distance > recycle and (distance > recycle * 1.5 or not _in_view(animal.global_position)):
			animal.deactivate()
		else:
			count += 1
	var activated := 0
	for _attempt in profile.attempts_per_update:
		if count >= profile.population or activated >= profile.activations_per_update:
			break
		var candidate: Variant = habitat.sample_spawn(observer.global_position, profile, _rng)
		if not candidate is Vector3:
			continue
		var point: Vector3 = candidate
		if point.distance_to(observer.global_position) > profile.spawn_radius:
			continue
		if _in_view(point) or not habitat.is_spawn_valid(point, profile.clearance):
			continue
		var animal := _get_available_animal()
		if animal == null:
			break
		animal.profile = profile
		animal.activate(point, habitat, _rng)
		count += 1
		activated += 1


func _get_available_animal() -> AmbientAnimal:
	for animal in _pool:
		if not animal.active:
			return animal
	var node := profile.animal_scene.instantiate()
	var animal := node as AmbientAnimal
	if animal == null:
		push_error("Ambient fauna scenes must extend AmbientAnimal")
		node.free()
		return null
	add_child(animal)
	animal.deactivate()
	_pool.append(animal)
	return animal


func _in_view(point: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	# Include a margin so a tail cannot visibly pop in at the edge of the screen.
	for plane in camera.get_frustum():
		if plane.distance_to(point) > profile.clearance:
			return false
	return true
