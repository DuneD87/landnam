class_name AmbientFaunaSpawner extends Node3D

## Bounded, reusable population around an observer. No water/flight/ground logic here.
## Parent this under the planet so origin rebases move the entire pool exactly once.
var profile: AmbientFaunaProfile
var habitat: AmbientFaunaHabitat
var observer: Node3D
var _pool: Array[AmbientAnimal] = []
var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0

## Presupuesto COMPARTIDO por todas las especies y por todos los ticks de recuperación de
## un frame. Una consulta/alta individual no se puede interrumpir; se deja de iniciar trabajo
## nuevo al agotarlo. Evita sumar los 6–8 intentos de cada especie en una misma tanda.
const FRAME_BUDGET_USEC := 2000
static var _budget_frame: int = -1
static var _budget_spent_usec: int = 0

## Grupo de todos los spawners en juego, para los informes de la consola.
const GROUP := &"fauna_spawner"


func setup(settings: AmbientFaunaProfile, environment: AmbientFaunaHabitat,
		player: Node3D) -> void:
	profile = settings
	habitat = environment
	observer = player
	_rng.randomize()
	# Las especies se crean juntas al cargar el planeta; no deben vencer todas a la vez.
	_elapsed = -float(get_instance_id() % 17) / 17.0 * maxf(profile.update_interval, 0.05)
	add_to_group(GROUP)


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
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_spent_usec = 0
	if _budget_spent_usec >= FRAME_BUDGET_USEC:
		return # Sigue vencido y reintenta en el siguiente frame.
	_elapsed = 0.0
	var start := Time.get_ticks_usec()
	update_population(start + FRAME_BUDGET_USEC - _budget_spent_usec)
	var elapsed := Time.get_ticks_usec() - start
	_budget_spent_usec += elapsed
	DebugStats.report_cost(&"fauna:spawner", elapsed)


func update_population(deadline_usec: int = 0) -> void:
	if profile.animal_scene == null:
		return
	# Reducing the configured population also releases the surplus pool nodes.
	while _pool.size() > profile.population:
		_pool.pop_back().queue_free()
	var count := 0
	var recycle := maxf(profile.recycle_distance, profile.spawn_radius + 5.0)
	for animal in _pool:
		if not animal.in_play():
			continue
		var distance := observer.global_position.distance_to(animal.global_position)
		if distance > recycle and (distance > recycle * 1.5 or not _in_view(animal.global_position)):
			animal.deactivate()
		else:
			animal.set_detail(distance)
			count += 1
	var activated := 0
	for _attempt in profile.attempts_per_update:
		if count >= profile.population or activated >= profile.activations_per_update:
			break
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			break
		var sample_start := Time.get_ticks_usec()
		var candidate: Variant = habitat.sample_spawn(observer.global_position, profile, _rng)
		DebugStats.report_cost(&"fauna:spawner/muestreo", Time.get_ticks_usec() - sample_start)
		if not candidate is Vector3:
			continue
		var point: Vector3 = candidate
		if point.distance_to(observer.global_position) > profile.spawn_radius:
			continue
		if _in_view(point):
			continue
		var check_start := Time.get_ticks_usec()
		var valid := habitat.is_spawn_valid(point, profile.clearance)
		DebugStats.report_cost(&"fauna:spawner/validacion", Time.get_ticks_usec() - check_start)
		if not valid:
			continue
		var activation_start := Time.get_ticks_usec()
		var animal := _get_available_animal()
		var instance_end := Time.get_ticks_usec()
		DebugStats.report_cost(&"fauna:spawner/instancia", instance_end - activation_start)
		if animal == null:
			break
		animal.profile = profile
		animal.activate(point, habitat, _rng)
		DebugStats.report_cost(StringName("fauna:activar/" + name), Time.get_ticks_usec() - instance_end)
		DebugStats.report_cost(&"fauna:spawner/alta", Time.get_ticks_usec() - activation_start)
		count += 1
		activated += 1


func _get_available_animal() -> AmbientAnimal:
	for animal in _pool:
		if not animal.in_play():
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
