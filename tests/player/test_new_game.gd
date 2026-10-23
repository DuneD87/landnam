extends Node

## godot --headless --path . res://tests/player/test_new_game.tscn
## Añade -- --integration para recorrer también el arranque de la escena principal.
## Con render real, -- --capture guarda imágenes de órbita, descenso y aterrizaje en build/.
const Landing := preload("res://scripts/player/new_game_landing.gd")
var failures := 0


func _enter_tree() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)
		get_window().size = Vector2i(1280, 720)


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var parser := PlanetParser.new(null)
	parser.load_config("res://data/planet/planet_earth.json")
	var terrain := VoxelLodTerrain.new()
	var world := Node3D.new()
	world.add_child(terrain)
	var core := Planet.new(terrain)
	core.definition = parser.definition
	core.radius = parser.radius
	core.has_water = parser.has_water
	core.water_radius = parser.water_level
	core.entity_id = "planet_earth"
	core.setup_voxel_generator()
	var map_owner := PlanetWorldMap.new()
	var key := map_owner._build_cache_key(core, Vector2i(2048, 1024), 2000.0)
	var map := WorldMapData.load_from("user://maps/planet_earth.map", key)
	if map == null:
		map = WorldMapBaker.bake_heights(terrain.generator, Vector2i(256, 128),
			core.radius, core.radius - core.water_radius, true, 2000.0)
		WorldMapBaker.classify_water(map)
	var finder := Landing.new()
	var rng := RandomNumberGenerator.new()
	var distinct := {}
	for i in 32:
		rng.seed = i + 1
		# Distintas horas y estaciones: ningún destino puede caer en la cara nocturna.
		var declination := deg_to_rad([-23.44, 0.0, 23.44][i % 3])
		var azimuth := TAU * (i % 4) / 4.0
		var sunlight := Vector3(cos(declination) * cos(azimuth), sin(declination),
			cos(declination) * sin(azimuth))
		# También debe funcionar mientras el mapa todavía está clasificándose.
		var result: Variant = finder.find_landing(core, map if i % 2 == 0 else null, rng, sunlight)
		check(result != null, "Tierra segura para la semilla %d" % rng.seed)
		if result == null:
			continue
		var point: Vector3 = result.origin
		var up := point.normalized()
		var latitude := WorldMapData.dir_to_latlon(up).x
		check(latitude >= Landing.MIN_LATITUDE_DEGREES - 0.001 \
				and latitude <= Landing.MAX_LATITUDE_DEGREES + 0.001,
			"Aterrizaje dentro de la franja de latitud, fuera del desierto")
		check(up.dot(sunlight) >= sin(deg_to_rad(Landing.MIN_SUN_ELEVATION_DEGREES)) - 0.0001,
			"El sol está alto sobre el horizonte del destino")
		check(point.length() > core.radius - core.water_radius + Landing.WATER_MARGIN,
			"Los pies quedan en tierra por encima del agua")
		check(finder._sdf(point) > 0.0 and finder._sdf(point - up * 1.2) < 0.0,
			"Suelo real bajo los pies, incluyendo cuevas y ríos")
		check((result.basis.y as Vector3).dot(up) > 0.999, "Cuerpo alineado con la gravedad")
		if map != null:
			check(not map.is_water_at_dir(up), "El mapa tampoco etiqueta el aterrizaje como océano")
		distinct[Vector2i(WorldMapData.dir_to_latlon(up))] = true
	check(distinct.size() >= 24, "La nueva partida no reutiliza un punto fijo")
	check(finder.find_landing(core, map, rng, Vector3.DOWN) == null,
		"Con toda la franja a oscuras no hay fallback nocturno")
	check(finder.find_landing(core, map, rng, Vector3.ZERO) == null,
		"Sin dirección solar no se acepta un destino sin comprobar la luz")
	# Un planeta inundado no debe devolver como fallback un punto bajo el océano.
	core.water_radius = -10000.0
	check(finder.find_landing(core, null, rng, Vector3.UP) == null,
		"Sin tierra segura no hay fallback submarino")
	map_owner.free()
	parser.free()
	core.free()
	world.free()
	if "--integration" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args():
		await _test_cinematic()
	print("NEW GAME: %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func _test_cinematic() -> void:
	var scene: Node3D = load("res://scenes/maps/sun.tscn").instantiate()
	for loader in scene.get_node("Planets").get_children():
		loader.ambient_fauna_enabled = false
	# Un alcance menor basta para probar las colisiones del destino.
	var capture := "--capture" in OS.get_cmdline_user_args()
	(scene.get_node("Player/CameraPivot/PitchPivot/Camera3D/VoxelViewer") as VoxelViewer).view_distance = 60000 if capture else 4096
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	var player: PlayerController = scene.get_node("Player")
	player.cinematic_duration = 16.0 if capture else 2.0
	var marker: Marker3D = scene.get_node("SpawnPoint")
	# Simula un marcador que Continuar/Guardar había movido a la Luna.
	marker.global_position = scene.get_node("Planets/Moon").global_position + Vector3.UP * 9000.0
	GameManager.begin_character_creation()
	GameManager.start_game(CharacterData.new())
	check(GameManager.current_state == GameManager.State.CINEMATIC, "Crear personaje inicia la cinemática")
	check(player.camera.is_visible_in_tree() and not player.player_model.visible,
		"La cámara sigue visible durante el vuelo aunque se oculte el personaje")
	check(player.planet == scene.get_node("Planets/Earth"), "Nueva partida elige la Tierra aunque el save estuviera en la Luna")
	var start := player.global_position
	var target := marker.global_position
	var terrain: VoxelLodTerrain = player.planet.voxel_terrain
	var sun: DirectionalLight3D = player.planet.planet.sun
	var target_up := (target - terrain.global_position).normalized()
	check(target_up.dot(sun.global_basis.z) >= sin(deg_to_rad(Landing.MIN_SUN_ELEVATION_DEGREES)) - 0.0001,
		"La nueva partida busca un destino iluminado por el sol real de la escena")
	var camera := player.camera
	var initial_camera := camera.global_position
	if capture:
		await get_tree().create_timer(1.0).timeout
		await _capture("orbit")
	await get_tree().create_timer(player.cinematic_duration * 0.4).timeout
	check(GameManager.current_state == GameManager.State.CINEMATIC, "El descenso tiene duración visible")
	check(player.global_position.distance_to(target) < start.distance_to(target) - 100.0, "El jugador desciende hacia el terreno")
	check(camera.global_position.distance_to(initial_camera) > 100.0, "La cámara acompaña el descenso")
	check(camera.global_position.distance_to(player.global_position) < 20.0, "La cámara sigue cerca del jugador")
	check(camera.get_global_transform_interpolated().origin.distance_to(camera.global_position) < 500.0,
		"La cámara interpolada del render también avanza durante el descenso")
	check(camera.global_basis.y.dot(player.up_direction) > 0.1, "El horizonte usa el arriba del destino")
	var view := (-camera.global_basis.z).slide(player.up_direction).normalized()
	check(view.dot(-player.global_basis.z) > 0.99, "El encuadre mantiene el rumbo al pasar a la cámara normal")
	check(not player.input_enabled and player.collision_model.disabled, "No hay movimiento ni colisiones durante el vuelo")
	if capture:
		await _capture("descent")
	await get_tree().create_timer(player.cinematic_duration * 0.6 + 0.3).timeout
	check(GameManager.current_state == GameManager.State.PLAYING, "La cinemática termina en PLAYING")
	check(player.camera_controller.first_person == player.start_first_person, "Se respeta la vista inicial al aterrizar")
	# La primera física de PLAYING rebasa el origen. Compara con el centro vivo del planeta.
	var local := terrain.to_local(player.global_position)
	var latitude := WorldMapData.dir_to_latlon(local).x
	check(latitude >= Landing.MIN_LATITUDE_DEGREES and latitude <= Landing.MAX_LATITUDE_DEGREES,
		"El origen flotante conserva la latitud del aterrizaje")
	check(player.up_direction.dot(sun.global_basis.z) > 0.0, "Sigue siendo de día al aterrizar")
	check(marker.global_position.distance_to(player.global_position) < 2.0,
		"El marcador y su viewer acompañan el rebase del origen flotante")
	var waited := 0.0
	while not player.input_enabled and waited < 18.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	check(player.input_enabled, "Se devuelven los controles al aterrizar")
	check(player.is_ground_ready(), "Las colisiones del terreno están cargadas al devolver el control")
	check(player.inventory.get_item_count(ItemCatalog.get_item(&"stone_pickaxe_01")) == 1,
		"Una partida nueva entrega un solo pico inicial")
	print("CINEMATIC: lat=%.2f, ground=%s, control wait=%.1fs" % [latitude, player.is_ground_ready(), waited])
	if capture:
		await _capture("landed")
	scene.queue_free()
	await get_tree().process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build")
	var error := get_viewport().get_texture().get_image().save_png("res://build/new_game_%s.png" % label)
	check(error == OK, "Captura del encuadre: " + label)
