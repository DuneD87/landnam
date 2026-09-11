extends Node3D

var failures := 0
var forest: ForestBirdHabitat
var ground: Node3D
var observer: Node3D
var trees: Array[Node3D] = []
var birds: Array[AmbientBird] = []
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
	rng.seed = 246
	ground = Node3D.new()
	add_child(ground)
	observer = Node3D.new()
	observer.position = Vector3(0, 1001, 15)
	ground.add_child(observer)
	forest = ForestBirdHabitat.new()
	forest.setup(ground, observer)
	for i in 2:
		var name := "pine_01" if i == 0 else "olive_01"
		var source: Node3D = load("res://scenes/planet/planet_items/vegetation/trees/%s.tscn" % name).instantiate()
		var meshes: Array = source.get_child(0).bake_lods()
		var data := TreePerchBaker.bake(meshes[0])
		check(data.perches.size() > 4, name + " has automatically extracted branch anchors")
		var tree := Node3D.new()
		tree.position = Vector3(-4 if i == 0 else 4, 1000, 0)
		tree.rotation.y = 0.4 + i
		tree.scale = Vector3.ONE * (0.6 if i == 0 else 2.0)
		ground.add_child(tree)
		trees.append(tree)
		forest.register_tree(tree, data)
		var anchor := forest._anchor(tree.get_instance_id(), 0)
		var expected: Vector3 = tree.global_transform * (data.perches[0].point as Vector3)
		check((anchor.point as Vector3).distance_to(expected) < 0.006, name + " anchor follows instance scale and rotation")
		check((anchor.basis as Basis).get_scale().is_equal_approx(Vector3.ONE), name + " tree scale does not enlarge the bird")
		var visual := MeshInstance3D.new()
		visual.mesh = meshes[0].duplicate()
		for surface in visual.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("765b3e") if surface == 0 else Color("527945")
			mat.roughness = 1.0
			if surface > 0:
				var old := meshes[0].surface_get_material(surface) as ShaderMaterial
				if old != null:
					mat.albedo_texture = old.get_shader_parameter("texture_albedo")
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			visual.set_surface_override_material(surface, mat)
		tree.add_child(visual)
		source.free()
	await get_tree().physics_frame
	var owner_a := Node.new()
	var owner_b := Node.new()
	add_child(owner_a)
	add_child(owner_b)
	var perch_a := forest.reserve(owner_a.get_instance_id(), Vector3(0, 1003, 0), rng)
	var perch_b := forest.reserve(owner_b.get_instance_id(), Vector3(0, 1003, 0), rng)
	check(not perch_a.is_empty() and not perch_b.is_empty(), "Real branches provide headroom and support for both feet")
	if not perch_a.is_empty() and not perch_b.is_empty():
		check(perch_a.key != perch_b.key, "Two birds cannot reserve the same perch")
		_test_short_spawn_radius(perch_a)
		var reassigned: Node3D = forest._trees[perch_a.tree].body.get_ref()
		var original := reassigned.transform
		reassigned.position.x += 1.0
		check(forest.resolve(perch_a).is_empty(), "Reassigned instance transforms invalidate old branch reservations")
		reassigned.transform = original
	forest.release(owner_a.get_instance_id())
	forest.release(owner_b.get_instance_id())
	check(forest._reservations.is_empty(), "Released perches become available again")
	owner_a.queue_free()
	owner_b.queue_free()
	var profile: AmbientFaunaProfile = load("res://data/fauna/forest_birds.tres")
	# Keep the general landing fixture independent of the user's tuning.
	profile = profile.duplicate()
	profile.spawn_radius = 55.0
	for i in 6:
		var point: Variant = forest.sample_spawn(observer.global_position, profile, rng)
		if not point is Vector3:
			continue
		var bird: AmbientBird = profile.animal_scene.instantiate()
		ground.add_child(bird)
		bird.bird_type = i % 3
		bird.profile = profile
		bird.activate(point, forest, rng)
		birds.append(bird)
	check(birds.size() > 0, "Forest habitat supplies nearby birds using the shared population profile")
	var landed: Dictionary = {}
	for frame in 900:
		await get_tree().physics_frame
		for bird in birds:
			if bird.state == AmbientBird.State.PERCHED:
				landed[bird.get_instance_id()] = true
		if landed.size() >= 1:
			break
	print("LANDED birds=", landed.size(), "/", birds.size())
	check(landed.size() > 0, "Birds autonomously approach and land on real tree branches")
	var resting: AmbientBird
	for bird in birds:
		if bird.state == AmbientBird.State.PERCHED:
			resting = bird
			break
	if resting != null:
		var before := resting.global_position
		ground.position += Vector3(-4000, 0, 3000)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(resting.global_position.distance_to(before + Vector3(-4000, 0, 3000)) < 0.02, "Origin rebase keeps the perched feet attached")
		var anchor := resting._perch.duplicate()
		var observer_before := observer.position
		observer.global_position = resting.global_position + Vector3(0, 0, 1)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(resting.state == AmbientBird.State.TAKEOFF and resting._perch.is_empty(), "Nearby player scares a resting bird and releases its perch")
		observer.position = observer_before
		# Restore this known supported anchor to isolate the removal behavior.
		resting._perch = anchor
		resting.state = AmbientBird.State.PERCHED
		resting._timer = 10.0
		var body: Node3D = forest._trees[anchor.tree].body.get_ref()
		body.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(resting.state != AmbientBird.State.PERCHED and resting._perch.is_empty(), "Removing a tree makes its bird release the perch and take off")
	for bird in birds:
		bird.deactivate()
	check(forest._reservations.is_empty(), "Recycling birds releases every reservation")
	ground.queue_free()
	await get_tree().process_frame
	await _test_high_branches()
	await _test_instancer()
	print("BIRD TESTS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func _test_short_spawn_radius(perch: Dictionary) -> void:
	var profile: AmbientFaunaProfile = load("res://data/fauna/forest_birds.tres").duplicate()
	profile.spawn_min_distance = 8.0
	profile.spawn_radius = 10.0
	var origin: Vector3 = perch.point + perch.up * 2.0 + (perch.basis as Basis).z * 9.0
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = 845
	var accepted := 0
	var outside := 0
	for attempt in 100:
		var point: Variant = forest.sample_spawn(origin, profile, local_rng)
		if point is Vector3:
			var distance := origin.distance_to(point)
			if distance < 8.0 or distance > 10.0:
				outside += 1
			if forest.is_spawn_valid(point, profile.clearance):
				accepted += 1
	check(accepted > 0, "An 8-10 m spawn annulus supplies unobstructed birds around real branches")
	check(outside == 0, "Flight offsets never place spawn candidates outside the configured annulus")
	print("SHORT RADIUS accepted=", accepted, "/100")


func _test_high_branches() -> void:
	var floor_root := Node3D.new()
	add_child(floor_root)
	var player := Node3D.new()
	player.position = Vector3(0, 1001, 0)
	floor_root.add_child(player)
	var camera := Camera3D.new()
	player.add_child(camera)
	camera.current = true
	var habitat := ForestBirdHabitat.new()
	habitat.setup(floor_root, player)
	var profile: AmbientFaunaProfile = load("res://data/fauna/forest_birds.tres").duplicate()
	profile.population = 1
	profile.spawn_min_distance = 8.0
	profile.spawn_radius = 10.0
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = 754
	check(habitat.sample_spawn(player.global_position, profile, local_rng) == null, "Forest birds still require nearby trees")
	# A trunk with its ONLY landing branch 24 m above the ground.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.height = 24.0
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.4
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 12, 0)))
	var branch := BoxMesh.new()
	branch.size = Vector3(6, 0.2, 1)
	st.append_from(branch, 0, Transform3D(Basis.IDENTITY, Vector3(2, 24, 0)))
	var tree := MeshInstance3D.new()
	tree.mesh = st.commit()
	tree.position = Vector3(0, 1000, 0)
	floor_root.add_child(tree)
	var data := TreePerchBaker.bake(tree.mesh, [Vector3(2, 24.1, 0)])
	data.perches = data.perches.slice(0, 1)
	habitat.register_tree(tree, data)
	check(habitat._available(player.global_position, 14.0).is_empty(), "Tall-tree fixture has no branches within or near the spawn radius")
	var reserved := habitat.reserve(get_instance_id(), player.global_position, local_rng)
	check(not reserved.is_empty(), "A high branch remains a valid landing destination")
	var point: Variant = habitat.sample_spawn(player.global_position, profile, local_rng)
	check(point is Vector3 and habitat.is_spawn_valid(point, profile.clearance), "Birds can spawn near the player even when every branch is high and reserved")
	habitat.release(get_instance_id())
	profile.flight_speed_min = 10.0
	profile.flight_speed_max = 10.0
	profile.perch_time_min = 0.6
	profile.perch_time_max = 0.6
	# Use the known original clip for the automatic-start measurement.
	profile.ambient_sound = profile.ambient_sound.duplicate()
	var flight_clips: Array[AudioStream] = [load("res://audio/effects/birds_01.wav")]
	profile.ambient_sound.streams = flight_clips
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(profile, habitat, player)
	spawner._rng.seed = 123
	floor_root.add_child(spawner)
	spawner.set_physics_process(false)
	spawner.update_population()
	var bird: AmbientBird = spawner._pool[0] if not spawner._pool.is_empty() else null
	check(bird != null and bird.active and bird.global_position.distance_to(player.global_position) <= 10.0,
		"Shared spawner activates a bird within 10 m below the high canopy")
	if bird != null:
		check(is_equal_approx(bird._speed, 10.0), "Spawner passes the bird profile's configured flight speed to the actor")
		var sang_in_flight := false
		var audio_peak := -200.0
		var ambient_bus := AudioServer.get_bus_index("Ambient")
		for frame in 900:
			await get_tree().physics_frame
			if bird.state != AmbientBird.State.PERCHED and is_instance_valid(bird._audio_player) and bird._audio_player.playing:
				sang_in_flight = true
				audio_peak = maxf(audio_peak, maxf(AudioServer.get_bus_peak_volume_left_db(ambient_bus, 0), AudioServer.get_bus_peak_volume_right_db(ambient_bus, 0)))
			if bird.state == AmbientBird.State.PERCHED:
				break
		check(sang_in_flight, "Bird automatically sings during flight before reaching any branch")
		check(audio_peak > -45.0, "Bird recording produces audible output on the Ambient bus near the player")
		print("BIRD AUDIO peak_db=", audio_peak)
		check(bird.state == AmbientBird.State.PERCHED and bird.global_position.y > 1024.0,
			"Bird autonomously flies from player height to the branch 24 m up")
		print("HIGH CANOPY state=", bird.state, " height=", bird.global_position.y - 1000.0)
		await get_tree().create_timer(0.25).timeout
		check(bird.state == AmbientBird.State.PERCHED, "Bird stays on the branch before the configured rest time elapses")
		await get_tree().create_timer(0.5).timeout
		check(bird.state != AmbientBird.State.PERCHED and bird._perch.is_empty(),
			"Configured rest duration triggers takeoff and releases the branch")
		await _test_bird_audio(bird, profile)
		bird.deactivate()
		profile.flight_speed_min = 16.0
		profile.flight_speed_max = 16.0
		bird.activate(point, habitat, local_rng)
		check(is_equal_approx(bird._speed, 16.0), "Recycled birds read the updated flight speed from their profile")
	floor_root.queue_free()
	await get_tree().process_frame


func _test_bird_audio(bird: AmbientBird, profile: AmbientFaunaProfile) -> void:
	var settings := profile as AmbientBirdProfile
	var sound := load("res://data/audio/events/forest_birds.tres").duplicate() as SoundEvent
	sound.event_id = &"bird_audio_test"
	sound.max_voices = 1
	sound.cooldown = 0.0
	settings.ambient_sound = sound
	settings.ambient_only_perched = false
	settings.ambient_interval_min = 0.2
	settings.ambient_interval_max = 0.2
	bird.set_physics_process(false)
	bird._stop_ambient_audio()
	bird._audio_timer = 0.0
	bird._update_ambient_audio(0.1)
	var voice := bird._audio_player
	check(voice != null and voice.playing and sound.streams.has(voice.stream) and voice.bus == "Ambient",
		"Bird plays the configured recording through the Ambient bus")
	check(is_equal_approx(bird._audio_timer, 0.2), "Bird uses the configured interval between calls")
	check(AudioManager.play_event_3d(sound, bird.global_position) == null,
		"Bird ambience respects the simultaneous voice budget")
	if voice != null:
		bird.position.x += 1.0
		bird._update_ambient_audio(0.0)
		check(voice.global_position.is_equal_approx(bird.global_position), "A bird's sound follows its position")
		settings.ambient_audio_enabled = false
		bird._update_ambient_audio(0.0)
		check(not voice.playing and AudioManager._active_voices[sound.event_id] == 0,
			"Disabling bird ambience stops playback and releases its budget")
		settings.ambient_audio_enabled = true
		bird._audio_timer = 0.0
		bird._update_ambient_audio(0.0)
		voice = bird._audio_player
		bird.deactivate()
		check(voice != null and not voice.playing and AudioManager._active_voices[sound.event_id] == 0,
			"Recycling a bird stops its sound immediately")
		var next_voice := AudioManager.play_event_3d(sound, bird.global_position, {"source_id": 987654})
		AudioManager.stop_source_voice(next_voice, bird.get_instance_id())
		check(next_voice != null and next_voice.playing, "An old owner cannot stop a reassigned audio voice")
		await get_tree().create_timer(next_voice.stream.get_length() / next_voice.pitch_scale + 0.2).timeout
		check(next_voice != null and not next_voice.playing and AudioManager._active_voices[sound.event_id] == 0,
			"Finishing the recording returns the voice to the shared pool")
		var clips := sound.streams.duplicate()
		var listener := AudioManager._get_listener()
		var bus := AudioServer.get_bus_index("Ambient")
		for clip in clips:
			# finished is dispatched after the mixer clears playing; allow the pool
			# callback to release its budget before requesting the next clip.
			await get_tree().create_timer(0.05).timeout
			var selected: Array[AudioStream] = [clip]
			sound.streams = selected
			var measured_voice := AudioManager.play_event_3d(sound, listener.global_position + Vector3(0, 0, 20))
			var peak := -200.0
			if measured_voice != null:
				while measured_voice.playing:
					await get_tree().physics_frame
					peak = maxf(peak, maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0)))
			check(peak > -45.0, "Configured bird clip is audible at 20 m: " + clip.resource_path)
			print("CLIP AUDIO ", clip.resource_path, " peak_db=", peak)


func _test_instancer() -> void:
	var terrain := VoxelLodTerrain.new()
	var flat := VoxelGeneratorFlat.new()
	flat.height = 1000.0
	terrain.generator = flat
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 3
	terrain.view_distance = 96
	terrain.streaming_system = VoxelLodTerrain.STREAMING_SYSTEM_CLIPBOX
	add_child(terrain)
	var world := Planet.new(terrain)
	add_child(world)
	var item := {"scene": "res://scenes/planet/planet_items/vegetation/trees/olive_01.tscn", "wind_speed": 0.0,
		"instance_as_scene": true, "collision_distance_m": 128.0, "mesh_lod_ratios": [0.1, 0.3, 0.6, 1.0]}
	var data := world._build_item_shared_data(0, item)
	var generator := VoxelInstanceGenerator.new()
	generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	generator.density = 0.015
	generator.min_scale = 1.3
	generator.max_scale = 2.1
	world._register_multi_mesh_item(0, item, data, generator, 0)
	check(world.tree_perch_catalog.size() == 1, "Planet registration keeps the shared branch catalog for a real library item")
	var viewer := VoxelViewer.new()
	viewer.position = Vector3(0, 1003, 0)
	viewer.view_distance = 96
	add_child(viewer)
	# The instancer's collision distance uses the camera, not the voxel viewer.
	var camera := Camera3D.new()
	viewer.add_child(camera)
	camera.current = true
	var habitat := ForestBirdHabitat.new()
	habitat.setup(terrain, viewer, world)
	for attempt in 80:
		await get_tree().create_timer(0.05).timeout
		habitat._refresh_at = 0
		habitat.refresh()
		if not habitat._trees.is_empty():
			break
	check(not habitat._trees.is_empty(), "Habitat discovers trees created by the real VoxelInstancer")
	var found_scale := false
	for entry in habitat._trees.values():
		var body: Node3D = entry.body.get_ref()
		var anchor := habitat._anchor(body.get_instance_id(), 0)
		var expected: Vector3 = body.global_transform * (entry.data.perches[0].point as Vector3)
		if not anchor.is_empty() and body.global_basis.get_scale().x > 1.2:
			found_scale = (anchor.point as Vector3).distance_to(expected) < 0.006
			break
	check(found_scale, "Instanced tree bodies preserve the random render scale used for branch anchors")
	var profile: AmbientFaunaProfile = load("res://data/fauna/forest_birds.tres")
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(profile, habitat, viewer)
	spawner._rng.seed = 123
	terrain.add_child(spawner)
	for step in 35:
		await get_tree().create_timer(0.05).timeout
		spawner.update_population()
	var active := spawner._pool.filter(func(bird: AmbientAnimal) -> bool: return bird.active).size()
	check(active > 0, "Shared spawner populates an actually streamed forest with birds")
	print("INSTANCER trees=", habitat._trees.size(), " active birds=", active)
	terrain.queue_free()
	viewer.queue_free()
	for node in world.planet_item_scenes.values():
		if is_instance_valid(node):
			node.free()
	world.queue_free()
	await get_tree().process_frame
