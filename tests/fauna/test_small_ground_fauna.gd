extends Node3D

var _failures: int = 0
var _terrain: Node3D
var _ground: StaticBody3D
var _habitat: SmallGroundFaunaHabitat
var _observer: Node3D


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _run() -> void:
	GameManager.current_state = GameManager.State.PLAYING
	_terrain = Node3D.new()
	add_child(_terrain)
	_ground = StaticBody3D.new()
	_ground.position.y = 999.5
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collider.shape = box
	_ground.add_child(collider)
	_terrain.add_child(_ground)
	_observer = Node3D.new()
	_observer.position = Vector3(0, 1001, 0)
	_terrain.add_child(_observer)
	_habitat = SmallGroundFaunaHabitat.new()
	_habitat.setup(_terrain, self, 1000, 100, [])
	_habitat.observer = _observer
	await get_tree().physics_frame
	await get_tree().physics_frame
	for name in ["rabbits", "foxes", "mice", "arctic_hares", "arctic_foxes", "lemmings"]:
		await _test_species(name)
	_test_animation_clock()
	await _test_skinned_model()
	await _test_steep_and_sunk()
	await _test_radial_ground()
	await _test_habitat()
	await _test_pool()
	print("SMALL GROUND FAUNA TESTS: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _settings(name: String) -> SmallGroundFaunaProfile:
	var settings := load("res://data/fauna/%s.tres" % name).duplicate() as SmallGroundFaunaProfile
	settings.biomes = []
	settings.animal_scene = load(settings.scene_path)
	return settings


func _test_species(name: String) -> void:
	var settings := _settings(name)
	var animal := settings.animal_scene.instantiate() as AmbientSmallGroundAnimal
	_terrain.add_child(animal)
	animal.profile = settings
	var rng := RandomNumberGenerator.new()
	rng.seed = 67
	animal.activate(Vector3(12, 1001, 0), _habitat, rng)
	_check(animal.active and not animal._collision.disabled, name + ": se activa con colisión")
	_check(animal.global_basis.y.dot(_habitat.up_at(animal.global_position)) > 0.999,
		name + ": se alinea con la gravedad radial")
	# Animated mesh vertices must fit the spawn envelope at maximum random scale.
	var model := animal._model
	var contained := true
	if model is SkinnedFaunaModel:
		# Con esqueleto: los huesos (hasta las puntas de orejas y patas) más un margen de piel, al
		# tamaño máximo del individuo, en las poses de huir.
		var skinned := model as SkinnedFaunaModel
		var widest := 0.0
		for phase in 12:
			skinned.animate(phase * 0.19, settings.flee_speed)
			var to_model := skinned.global_transform.affine_inverse() * skinned.skeleton.global_transform
			for bone in skinned.skeleton.get_bone_count():
				widest = maxf(widest, (to_model * skinned.skeleton.get_bone_global_pose(bone).origin).length())
		contained = (widest + 0.04) * settings.largest_size() <= settings.clearance
		_check(contained, name + ": el modelo animado cabe en el despeje de spawn (%.2f m de %.2f)"
			% [(widest + 0.04) * settings.largest_size(), settings.clearance])
	else:
		for phase in 12:
			model.animate(phase * 0.19, settings.flee_speed)
			for part in model.get_children():
				for vertex in (part.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					# GPU skin deformation is bounded in addition to the rest-pose geometry.
					if ((part.transform * vertex).length() + SimpleSmallAnimalModel.MAX_ANIMATION_DISPLACEMENT[settings.species]) * settings.largest_size() > settings.clearance:
						contained = false
		_check(contained, name + ": el modelo animado cabe en el despeje de spawn")
	for frame in 100:
		await get_tree().physics_frame
	_check(animal.active and animal.global_position.y >= 999.98 and animal.global_position.y < 1000.8,
		name + ": se apoya en suelo tras caer")
	_observer.global_position = animal.global_position + Vector3(0, 0, 1.0)
	var before := animal.global_position
	var hopped := false
	for frame in 35:
		await get_tree().physics_frame
		hopped = hopped or animal.velocity.dot(animal.up_direction) > 1.0
	if model is SkinnedFaunaModel:
		var gaits := settings.model.gait_clips
		_check((model as SkinnedFaunaModel).current_clip in gaits and not hopped,
			name + ": huye con su clip de marcha (%s), sin saltos físicos" % (model as SkinnedFaunaModel).current_clip)
	elif settings.species == 0:
		_check(hopped, "El conejo salta físicamente durante la huida")
	_check(animal.active and animal.state == AmbientSmallGroundAnimal.State.FLEE,
		name + ": huye del observador próximo")
	_check(animal.global_position.distance_to(_observer.global_position) > before.distance_to(_observer.global_position) + 0.3,
		name + ": la huida aumenta la separación")
	# Both pool nodes and destinations move once with their terrain parent.
	var old_goal := _terrain.to_global(animal._goal_local)
	var old_position := animal.global_position
	var shift := Vector3(2500, -750, 1200)
	_terrain.position += shift
	_check(animal.global_position.is_equal_approx(old_position + shift)
		and _terrain.to_global(animal._goal_local).is_equal_approx(old_goal + shift),
		name + ": posición y destino siguen el origen flotante")
	_terrain.position -= shift
	animal.deactivate()
	_check(not animal.active and animal._collision.disabled and not animal.is_in_group(AmbientAnimal.GROUP),
		name + ": el pool retira colisión y grupo de impactos")
	animal.activate(Vector3(-12, 1000.2, 0), _habitat, rng)
	_check(animal.state == AmbientSmallGroundAnimal.State.IDLE and animal.velocity.is_zero_approx(),
		name + ": reactivar limpia la huida y la velocidad")
	_observer.position = Vector3(0, 1001, 0)
	animal.queue_free()
	await get_tree().process_frame


func _test_radial_ground() -> void:
	var settings := _settings("foxes")
	var animal := settings.animal_scene.instantiate() as AmbientSmallGroundAnimal
	_terrain.add_child(animal)
	animal.profile = settings
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	for angle in [PI * 0.5, PI]:
		_terrain.rotation.z = angle
		await get_tree().physics_frame
		await get_tree().physics_frame
		animal.activate(_terrain.to_global(Vector3(12, 1000.7, 0)), _habitat, rng)
		for frame in 40:
			await get_tree().physics_frame
		_check(animal.active and animal.global_basis.y.dot(_habitat.up_at(animal.global_position)) > 0.999
			and animal.position.y >= 999.98 and animal.position.y < 1000.1,
			"Camina con gravedad radial al girar el terreno %.0f grados" % rad_to_deg(angle))
		animal.deactivate()
	_terrain.rotation = Vector3.ZERO
	animal.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_animation_clock() -> void:
	var model := SimpleSmallAnimalModel.new()
	add_child(model)
	model.set_species(1)
	for frame in 60:
		model.advance(1.0 / 60.0, 0.0)
	_check(is_zero_approx(model._phase) and model._clock > 0.99,
		"En reposo continúa la respiración sin avanzar el ciclo de pasos")
	for frame in 20:
		model.advance(1.0 / 60.0, 1.4)
	_check(float(model.body.get_instance_shader_parameter("movement")) > 0.9 and model._phase > 0.1,
		"La velocidad real activa la marcha y su cadencia")
	for frame in 90:
		model.advance(1.0 / 60.0, 0.0)
	_check(float(model.body.get_instance_shader_parameter("movement")) < 0.001,
		"Al detenerse las patas vuelven suavemente al reposo")
	model.set_species(0)
	model.advance(0.1, 2.0, false, 1.8)
	_check(float(model.body.get_instance_shader_parameter("airborne")) > 0.9
		and float(model.body.get_instance_shader_parameter("vertical_speed")) > 1.0,
		"La postura del conejo recibe la fase del salto físico")
	model.advance(0.02, 2.0, true, 0.0)
	_check(float(model.body.get_instance_shader_parameter("landing")) > 0.5,
		"El contacto con el suelo activa la amortiguación de aterrizaje")
	model.set_species(0)
	_check(is_zero_approx(model._phase) and is_zero_approx(model._air) and is_zero_approx(model._landing)
		and is_zero_approx(float(model.body.get_instance_shader_parameter("movement"))),
		"Reutilizar el modelo borra la marcha y el salto anteriores")
	model.queue_free()


## El modelo de un pack: el clip va con la velocidad del cuerpo, a su ritmo; quieto, a ratos pasta;
## y su cadáver se queda en la pose en que murió.
func _test_skinned_model() -> void:
	var data := load("res://data/fauna/models/rabbit.tres") as FaunaModelData
	var model := SkinnedFaunaModel.new()
	add_child(model)
	model.set_data(data, 3)
	_check(model.current_clip == data.idle_clip and model.player.is_playing(), "Sale quieto (%s)" % model.current_clip)
	for frame in 40:
		model.advance(1.0 / 60.0, 0.55)
	var walk_rate := 0.55 / (data.gait_speeds[0] * data.scale)
	_check(model.current_clip == data.gait_clips[0] and absf(model.player.speed_scale - clampf(walk_rate, 0.5, 2.0)) < 0.02,
		"Al paso, su clip lento al ritmo del cuerpo (%s ×%.2f)" % [model.current_clip, model.player.speed_scale])
	for frame in 40:
		model.advance(1.0 / 60.0, 5.0)
	_check(model.current_clip == data.gait_clips[2] and model.player.speed_scale > 0.5 and model.player.speed_scale < 1.2,
		"Huyendo, el de correr a fondo (%s ×%.2f)" % [model.current_clip, model.player.speed_scale])
	var rested := false
	for attempt in 12:
		model.set_data(data, attempt)
		for frame in 30:
			model.advance(1.0 / 60.0, 0.0)
		if model.current_clip == data.rest_clips[0]:
			rested = true
			model.player.advance(model.player.current_animation_length)
			model.advance(1.0 / 60.0, 0.0)
			_check(model.current_clip == data.rest_clips[1], "Tras agacharse, sigue pastando en bucle (%s)" % model.current_clip)
			break
	_check(rested, "Quieto, a ratos se pone a pastar")
	# Cadáver: una copia del esqueleto en la pose de ahora, sin animación.
	for frame in 20:
		model.advance(1.0 / 60.0, 5.0)
	# Ya corriendo (pasado el fundido desde el idle, que es el conejo sentado). En pasos como los del
	# juego: un fundido que acaba dentro de un solo paso no se ve hasta el siguiente.
	for frame in 30:
		model.player.advance(1.0 / 60.0)
	var bone := model.skeleton.find_bone("LegBLAnkle")
	var corpse := FaunaCorpse.spawn(self, model, Vector3.ZERO, Vector3.DOWN * 9.8, 1)
	var copies := corpse.find_children("*", "Skeleton3D", true, false) if corpse != null else []
	_check(copies.size() == 1 and corpse.find_children("*", "AnimationPlayer", true, false).is_empty()
		and (copies[0] as Skeleton3D).get_bone_pose(bone).is_equal_approx(model.skeleton.get_bone_pose(bone)),
		"El cadáver se queda en la pose en que murió")
	if corpse != null:
		corpse.queue_free()
	# Con animación de muerte, el cadáver la hace y no rueda: acaba tumbado, con la pelvis abajo.
	var dying := FaunaCorpse.spawn(self, model, Vector3.ZERO, Vector3.DOWN * 9.8, 1, data.death)
	var death_player := dying.find_child("Death", true, false) as AnimationPlayer if dying != null else null
	_check(death_player != null and death_player.current_animation == &"Death" and dying.lock_rotation,
		"Al morir, el cadáver hace su animación de muerte sin rodar")
	if death_player != null:
		var posed := death_player.get_parent() as Skeleton3D
		var pelvis := posed.find_bone("Pelvis")
		var height := func() -> float:
			return (posed.global_transform * posed.get_bone_global_pose(pelvis).origin - model.global_position).y
		death_player.advance(0.0)
		var standing: float = height.call()
		for frame in ceili((data.death.length + 0.5) * 30.0):
			death_player.advance(1.0 / 30.0)
		var lying: float = height.call()
		_check(lying < standing * 0.5 and lying > 0.0, "Y acaba tumbado en el suelo (pelvis de %.2f a %.2f m)" % [standing, lying])
	if dying != null:
		dying.queue_free()
	# Otro muere cuando los anteriores ya se han ido: la lista de cadáveres no se atraganta con ellos.
	await get_tree().process_frame
	var next := FaunaCorpse.spawn(self, model, Vector3.ZERO, Vector3.DOWN * 9.8, 1)
	_check(next != null and next.is_inside_tree(), "Otro cadáver sale cuando los anteriores ya se han ido")
	if next != null:
		next.queue_free()
	model.queue_free()
	await get_tree().process_frame


## En una ladera más empinada que su pendiente máxima no desaparece (antes se retiraba al pisar un
## triángulo empinado); y si se cuela bajo una malla de terreno (sin dentro, como la del voxel),
## vuelve encima.
func _test_steep_and_sunk() -> void:
	var settings := _settings("rabbits")
	var animal := settings.animal_scene.instantiate() as AmbientSmallGroundAnimal
	_terrain.add_child(animal)
	animal.profile = settings
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_ground.rotation.z = deg_to_rad(45)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var surface := _habitat.terrain_under(Vector3(0, 1003, 0), 0.0, 6.0)
	animal.activate((surface.position as Vector3) + Vector3.UP * 0.05, _habitat, rng)
	for frame in 40:
		await get_tree().physics_frame
	_check(animal.active, "En una ladera de 45° no desaparece")
	animal.deactivate()
	_ground.rotation = Vector3.ZERO
	# Terreno de malla: dos triángulos a 1000 m, sin la caja debajo.
	_ground.get_child(0).disabled = true
	var mesh_ground := StaticBody3D.new()
	var mesh_shape := CollisionShape3D.new()
	var faces := ConcavePolygonShape3D.new()
	faces.set_faces(PackedVector3Array([Vector3(-10, 1000, -10), Vector3(10, 1000, -10), Vector3(10, 1000, 10),
		Vector3(-10, 1000, -10), Vector3(10, 1000, 10), Vector3(-10, 1000, 10)]))
	mesh_shape.shape = faces
	mesh_ground.add_child(mesh_shape)
	_terrain.add_child(mesh_ground)
	await get_tree().physics_frame
	await get_tree().physics_frame
	animal.activate(Vector3(0, 1000.1, 0), _habitat, rng)
	await get_tree().physics_frame
	animal.global_position = Vector3(0, 999.75, 0)
	for frame in 20:
		await get_tree().physics_frame
	_check(animal.active and animal.global_position.y > 999.97 and animal.global_position.y < 1000.2,
		"Hundido bajo la malla del terreno, vuelve encima (%.2f)" % animal.global_position.y)
	animal.queue_free()
	mesh_ground.queue_free()
	_ground.get_child(0).disabled = false
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_habitat() -> void:
	var settings := _settings("rabbits")
	_check(not _habitat.ground_at(Vector3(0, 1000.1, 0), 0.6, settings).is_empty(), "Sondeo encuentra suelo llano")
	_check(not _habitat.can_step(Vector3(49.8, 1000.1, 0), Vector3(50.8, 1000.1, 0), settings), "No avanza sobre un precipicio")
	_habitat.sea_radius = 1001
	_check(_habitat.ground_at(Vector3(0, 1000.1, 0), 0.6, settings).is_empty(), "Rechaza suelo sumergido incluso sin mapa horneado")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	_check(_habitat.sample_spawn(_observer.global_position, settings, rng) == null, "El spawn también rechaza agua")
	_habitat.sea_radius = 0
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.1)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1001, -1)
	_terrain.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _habitat.can_step(Vector3(0, 1000.1, 0), Vector3(0, 1000.1, -2), settings), "El sondeo frontal bloquea paredes")
	wall.queue_free()
	# Tilt the floor around its centre; keep a loaded surface under the test point.
	_ground.rotation.z = deg_to_rad(55)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_habitat.ground_at(Vector3(0, 1000.5, 0), 2, settings).is_empty(), "Pendiente excesiva no es transitable")
	_ground.rotation = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_pool() -> void:
	var settings := _settings("mice")
	settings.population = 5
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(settings, _habitat, _observer)
	_terrain.add_child(spawner)
	spawner.set_physics_process(false)
	for i in 10:
		spawner.update_population()
	_check(spawner._pool.size() == 5, "El spawner real alcanza el límite de población")
	var ids: Array[int] = []
	for animal in spawner._pool:
		ids.append(animal.get_instance_id())
		animal.deactivate()
	for i in 10:
		spawner.update_population()
	var reused := spawner._pool.size() == 5
	for animal in spawner._pool:
		reused = reused and animal.get_instance_id() in ids and animal.active
	_check(reused, "El spawner reutiliza los mismos cinco animales")
	_ground.process_mode = Node.PROCESS_MODE_DISABLED
	_ground.get_child(0).disabled = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	for frame in 15:
		await get_tree().physics_frame
	var retired := true
	for animal in spawner._pool:
		retired = retired and not animal.active
	_check(retired, "Al descargar el suelo los animales se retiran sin caer al vacío")
	spawner.queue_free()
	await get_tree().process_frame
