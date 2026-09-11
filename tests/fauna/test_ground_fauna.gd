extends Node

## Filtros de spawn de GroundFaunaHabitat sobre un planeta sintético: suelo con normal conocida,
## para fijar exactamente dónde está el corte de pendiente, altura y banda de latitud.

const RADIUS := 1000.0
## El rayo de sondeo arranca en radio + atmósfera, así que esto tiene que quedar por encima
## del terreno más alto del planeta o no hay suelo que encontrar.
const ATMOSPHERE := 900.0
const BANDS: Array[float] = [-90.0, -45.0, -10.0, 10.0, 45.0, 90.0]

var _failures: int = 0
var _world: Node3D
var _terrain: Node3D


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
	_terrain = Node3D.new()
	_world.add_child(_terrain)
	GameManager.current_state = GameManager.State.PLAYING

	await _test_flat_ground()
	await _test_slope_limit()
	await _test_height_band()
	await _test_biome_band()
	await _test_population()

	_world.queue_free()
	await get_tree().process_frame
	print("GROUND FAUNA TESTS: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


## Placa de suelo cuya cara superior queda a 'height' sobre el radio nominal, inclinada 'tilt'
## grados respecto a la radial. El observador está en el ecuador del eje +Z.
func _add_ground(height: float, tilt_degrees: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 400, 2)
	collider.shape = box
	body.add_child(collider)
	body.basis = Basis(Vector3.RIGHT, deg_to_rad(tilt_degrees))
	body.position = Vector3(0, 0, RADIUS + height - 1.0)
	_world.add_child(body)
	return body


func _habitat() -> GroundFaunaHabitat:
	var habitat := GroundFaunaHabitat.new()
	habitat.setup(_terrain, _world, RADIUS, ATMOSPHERE, BANDS)
	return habitat


func _profile(biomes: Array[int], min_height: float, max_height: float) -> GroundFaunaProfile:
	var settings := GroundFaunaProfile.new()
	settings.biomes = biomes
	settings.min_height = min_height
	settings.max_height = max_height
	settings.spawn_min_distance = 5.0
	settings.spawn_radius = 25.0
	settings.clearance = 1.0
	return settings


func _sample(habitat: GroundFaunaHabitat, settings: GroundFaunaProfile, tries: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var anchor := Vector3(0, 0, RADIUS)
	var accepted := 0
	for _try in tries:
		var candidate: Variant = habitat.sample_spawn(anchor, settings, rng)
		if candidate is Vector3 and habitat.is_spawn_valid(candidate, settings.clearance):
			accepted += 1
	return accepted


func _test_flat_ground() -> void:
	var ground := _add_ground(0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var habitat := _habitat()
	var settings := _profile([2], -50.0, 200.0)
	var accepted := _sample(habitat, settings, 40)
	_check(accepted > 30, "Suelo llano acepta casi todos los candidatos (%d/40)" % accepted)
	_check(habitat.accepted == accepted, "El contador de aceptados cuadra con lo devuelto")
	ground.queue_free()
	await get_tree().process_frame


## El corte tiene que estar en el floor_max_angle de los NPCs (70°), no antes: el filtro viejo
## cortaba en 49° y rechazaba suelo que el animal pisa de sobra.
func _test_slope_limit() -> void:
	for tilt in [30.0, 60.0, 80.0]:
		var ground := _add_ground(0.0, tilt)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var habitat := _habitat()
		var settings := _profile([2], -400.0, 400.0)
		var accepted := _sample(habitat, settings, 40)
		if tilt < GroundFaunaHabitat.MAX_SLOPE_DEGREES:
			_check(accepted > 0, "Pendiente de %.0f° admite spawn (%d/40)" % [tilt, accepted])
		else:
			_check(accepted == 0 and int(habitat.rejected.get(&"pendiente", 0)) > 0,
				"Pendiente de %.0f° se descarta por pendiente" % tilt)
		ground.queue_free()
		await get_tree().process_frame


func _test_height_band() -> void:
	var ground := _add_ground(500.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var habitat := _habitat()
	var settings := _profile([2], -50.0, 200.0)
	var accepted := _sample(habitat, settings, 20)
	_check(accepted == 0 and int(habitat.rejected.get(&"altura", 0)) > 0,
		"Suelo a 500 m queda fuera de la banda de altura y se descarta por altura")
	var wide := _profile([2], -50.0, 600.0)
	var open := _habitat()
	_check(_sample(open, wide, 20) > 0, "Ampliando la banda, ese mismo suelo sí vale")
	ground.queue_free()
	await get_tree().process_frame
	# Terreno por encima del techo de la atmósfera: el rayo sale por debajo y no ve nada.
	var too_high := _add_ground(ATMOSPHERE + 50.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blind := _habitat()
	_check(_sample(blind, _profile([2], -50.0, 2000.0), 10) == 0
		and int(blind.rejected.get(&"sin_suelo", 0)) > 0,
		"Suelo por encima de radio+atmósfera queda fuera del alcance del sondeo")
	too_high.queue_free()
	await get_tree().process_frame


func _test_biome_band() -> void:
	var ground := _add_ground(0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var polar := _habitat()
	var settings := _profile([0], -50.0, 200.0)
	_check(_sample(polar, settings, 20) == 0 and int(polar.rejected.get(&"bioma", 0)) > 0,
		"El ecuador se descarta para una especie de banda polar")
	var equator := _habitat()
	_check(_sample(equator, _profile([2], -50.0, 200.0), 20) > 0,
		"La misma posición vale para la especie de banda ecuatorial")
	var everywhere := _habitat()
	_check(_sample(everywhere, _profile([], -50.0, 200.0), 20) > 0,
		"Sin biomas declarados la especie vive en cualquier latitud")
	ground.queue_free()
	await get_tree().process_frame


## El pool compartido puebla y recicla sobre el hábitat de superficie igual que con peces.
func _test_population() -> void:
	var ground := _add_ground(0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var observer := Node3D.new()
	observer.position = Vector3(0, 0, RADIUS + 2.0)
	_world.add_child(observer)
	var settings := _profile([2], -50.0, 200.0)
	var template := AmbientAnimal.new()
	template.add_child(CollisionShape3D.new())
	settings.animal_scene = PackedScene.new()
	settings.animal_scene.pack(template)
	template.free()
	settings.population = 6
	settings.attempts_per_update = 8
	settings.activations_per_update = 6
	settings.recycle_distance = 40.0
	var spawner := AmbientFaunaSpawner.new()
	spawner.setup(settings, _habitat(), observer)
	_terrain.add_child(spawner)
	spawner.set_physics_process(false)
	for _step in 4:
		spawner.update_population()
	var alive := 0
	for animal in spawner._pool:
		if animal.active:
			alive += 1
	_check(alive == settings.population, "El pool de superficie llega a su tope (%d/%d)" % [alive, settings.population])
	var first: AmbientAnimal = spawner._pool[0]
	_check(first.global_position.distance_to(observer.global_position) <= settings.spawn_radius,
		"Los animales aparecen dentro del radio de spawn")
	_check(first.global_position.length() > RADIUS, "Aparecen sobre la superficie, no dentro de ella")
	observer.position = Vector3(0, 0, RADIUS + 500.0)
	spawner.update_population()
	var still_alive := 0
	for animal in spawner._pool:
		if animal.active:
			still_alive += 1
	_check(still_alive == 0, "Al alejarse el observador el pool entero se recicla")
	spawner.queue_free()
	ground.queue_free()
	await get_tree().process_frame
