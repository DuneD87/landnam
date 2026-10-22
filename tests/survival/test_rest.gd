extends Node

## Jornada, sueño y reloj compartido sin cargar una partida.
## godot --headless --path . res://tests/survival/test_rest.tscn
const Sun = preload("res://scripts/planet/sun_controller.gd")

var failures := 0
var checks := 0
var _sun: Node3D
var _player: PlayerController
var _needs: SurvivalNeeds
var _rest: RestController
var _health: HealthComponent
var _bed: Bedroll


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	WorldTime.reset()
	# Se montan solo los componentes usados, sobre nodos ya listos, sin el arranque de una partida.
	_sun = Node3D.new()
	add_child(_sun)
	_sun.set_script(Sun)
	_sun.set_process(false)
	_sun.add_to_group("sun_controller")
	var body := CharacterBody3D.new()
	add_child(body)
	body.set_script(PlayerController)
	_player = body as PlayerController
	_player.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.input_enabled = true
	_player.free_flight_enabled = false
	_player.movement = Movement.new()
	_player.add_child(_player.movement)
	_player.inventory = Inventory.new()
	_player.add_child(_player.inventory)
	_health = HealthComponent.new()
	_player.add_child(_health)
	_player.health_component = _health
	_needs = SurvivalNeeds.new()
	_player.add_child(_needs)
	_player.needs = _needs
	_needs.setup(_player)
	_player.player_model = Node3D.new()
	_player.add_child(_player.player_model)
	_rest = RestController.new()
	_player.add_child(_rest)
	_player.resting = _rest
	_rest.setup(_player)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 1.0
	_player.add_child(shape)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	_bed = load("res://scenes/world/bedroll.tscn").instantiate()
	_bed.position.x = 1.5
	add_child(_bed)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.velocity = Vector3.DOWN
	_player.move_and_slide()
	check(_player.is_on_floor(), "el personaje de prueba está sobre suelo seco")
	_test_clock()
	_test_fatigue()
	_test_sleep()
	_test_interruptions()
	_test_world_systems()
	await _test_bedroll()
	await _test_save_load()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await _capture(arg.trim_prefix("--capture="))
	_rest.close(false)
	WorldTime.reset()
	_player.free()
	_bed.free()
	_sun.free()
	floor_body.free()
	await get_tree().process_frame
	print("REST: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _reset() -> void:
	_rest.close(false)
	WorldTime.reset()
	_sun.rotation_speed_deg = 0.1
	_sun.auto_rotate = true
	_player.input_enabled = true
	_player.free_flight_enabled = false
	_player.movement.is_swimming = false
	_needs.paused = false
	_needs.rate = 1.0
	_needs.refill()
	_health.revive()
	_health.invincible = false


func _test_clock() -> void:
	_reset()
	check(is_equal_approx(WorldTime.day_seconds(), 3600.0), "la vuelta actual del sol dura una hora real")
	WorldTime.set_speed(60.0)
	check(is_equal_approx(WorldTime.hours_elapsed(20.0), 8.0), "a ×60 pasan ocho horas de juego en veinte segundos")
	var azimuth: float = _sun.sun_azimuth_deg
	var day: float = _sun.day_of_year
	_sun._process(1.0)
	check(is_equal_approx(angle_difference(deg_to_rad(azimuth), deg_to_rad(_sun.sun_azimuth_deg)), deg_to_rad(6.0)),
		"la aceleración mueve el sol al mismo ritmo que las horas")
	check(is_equal_approx(_sun.day_of_year - day, 1.0 / 60.0), "el calendario avanza junto al sol")
	check(is_equal_approx(Engine.time_scale, 1.0), "la aceleración conserva el ritmo normal de la física")
	WorldTime.request_speed(_rest, 90.0)
	WorldTime.release_speed(_rest)
	check(WorldTime.speed == 60.0, "retirar una aceleración temporal conserva el ritmo anterior")
	Console._cmd_time(PackedStringArray(["speed", "12"]))
	check(WorldTime.speed == 12.0, "la consola permite reutilizar la aceleración sin dormir")
	Console._cmd_time(PackedStringArray(["speed", "-1"]))
	check(WorldTime.speed == 12.0, "la consola rechaza ritmos inválidos")


func _test_fatigue() -> void:
	_reset()
	_health.invincible = true
	for i in 2400:
		_needs._physics_process(1.0)
	check(_needs.rest < 0.001, "una jornada de dieciséis horas despierto agota el descanso")
	_needs.refill()
	_sun.rotation_speed_deg = 0.2
	for i in 600:
		_needs._physics_process(1.0)
	check(absf(_needs.rest - 0.5) < 0.001, "si el día dura la mitad, el cansancio sigue las horas del juego")
	var before := _needs.rest
	_sun.auto_rotate = false
	_needs._physics_process(100.0)
	check(is_equal_approx(_needs.rest, before), "con el reloj detenido no pasan horas de cansancio")


func _test_sleep() -> void:
	_reset()
	_needs.rest = 0.0
	_sun.sun_azimuth_deg = -180.0
	var before_day: float = _sun.day_of_year
	_rest.open(_bed)
	check(_rest.is_open() and not _rest._sleep_button.disabled, "E sobre un lecho ofrece dormir")
	check(_rest.start_sleep() and _needs.sleeping and WorldTime.speed == 60.0, "dormir activa el descanso y acelera el mundo")
	check(_rest.start_sleep(), "repetir la orden de dormir conserva el sueño ya iniciado")
	check(_player.player_model.global_position.distance_to(_bed.global_position) < 1.0
		and absf(_player.player_model.global_basis.y.dot(_bed.global_basis.z)) > 0.99,
		"el personaje queda tumbado sobre el lecho")
	var slept := 0
	while _rest.is_sleeping() and slept < 30:
		_needs._physics_process(1.0)
		_sun._process(1.0)
		_rest._physics_process(1.0)
		slept += 1
	check(slept == 20 and not _rest.is_open(), "tras ocho horas termina el sueño y se cierra el panel")
	check(_needs.rest > 0.999 and not _needs.sleeping, "una noche completa recupera todo el descanso")
	check(_player.player_model.transform.is_equal_approx(Transform3D.IDENTITY), "al despertar se recupera la postura del personaje")
	check(WorldTime.speed == 1.0, "al despertar el reloj vuelve a su ritmo normal")
	check(absf(_sun.day_of_year - before_day - 1.0 / 3.0) < 0.0001
		and absf(_sun.sun_azimuth_deg - (-60.0)) < 0.0001, "la noche ha avanzado ocho horas reales del calendario")
	check(_needs.hunger < 1.0 and _needs.thirst < 1.0, "dormir consume alimento y agua durante las horas transcurridas")
	check(_health.health == _health.max_health, "dormir abrigado y sin necesidades críticas no quita vida")


func _test_interruptions() -> void:
	_reset()
	WorldTime.set_speed(3.0)
	_rest.open(_bed)
	check(_rest.start_sleep(), "se inicia un sueño que se puede cancelar")
	_rest.close()
	check(not _needs.sleeping and WorldTime.speed == 3.0, "despertarse antes restaura el ritmo que había antes de dormir")
	WorldTime.reset()
	_rest.open(_bed)
	check(_rest.start_sleep(), "se inicia un sueño antes de recibir daño")
	_health.take_damage(2.0)
	check(not _rest.is_sleeping() and WorldTime.speed == 1.0, "recibir daño despierta y retira la aceleración")
	_rest.open(_bed)
	check(_rest.start_sleep(), "se inicia un sueño antes de sufrir frío")
	_needs.warmth = -1.0
	_needs._hurt(10.0, _health)
	check(not _rest.is_sleeping(), "el daño por frío también interrumpe el sueño")
	_rest.open(_bed)
	check(_rest.start_sleep(), "se inicia un sueño antes de entrar en agua")
	_player.movement.is_swimming = true
	_rest._physics_process(0.1)
	check(not _rest.is_sleeping() and WorldTime.speed == 1.0, "entrar en agua interrumpe el sueño")
	_player.movement.is_swimming = false
	_rest.open(_bed)
	check(_rest.start_sleep(), "se inicia un sueño antes de salir de la partida")
	_rest._on_state_changed(GameManager.State.MENU)
	check(not _rest.is_open() and WorldTime.speed == 1.0, "salir de la partida cancela el descanso y su aceleración")
	_sun.auto_rotate = false
	_rest.open(_bed)
	check(not _rest.start_sleep() and not _needs.sleeping, "con el ciclo solar detenido no se inicia un sueño que no pueda terminar")
	_rest.close()
	_sun.auto_rotate = true
	_player.movement.is_swimming = true
	_rest.open(_bed)
	check(not _rest.start_sleep(), "no se puede empezar a dormir nadando")
	_player.movement.is_swimming = false
	_rest.close()
	_rest.open(_bed)
	check(_rest.start_sleep(), "se inicia un sueño antes de morir")
	_health.take_damage(_health.max_health)
	check(not _rest.is_sleeping() and WorldTime.speed == 1.0, "morir retira la aceleración del sueño")
	_health.revive()


func _test_world_systems() -> void:
	_reset()
	var fire := Campfire.new()
	add_child(fire)
	fire.set_process(false)
	fire.inventory.items[0] = InventoryItem.new(ItemCatalog.get_item(&"branch_01"), 3)
	fire.inventory.items[1] = InventoryItem.new(ItemCatalog.get_item(&"raw_meat"))
	fire.ignite()
	WorldTime.set_speed(60.0)
	fire._process(2.0)
	check(absf(fire.burn_seconds_left() - 60.0) < 0.001, "a ×60 la hoguera consume dos minutos de combustible en dos segundos")
	check(fire.inventory.items[1].data.id == &"cooked_meat", "durante el tiempo acelerado también se cocina la comida")
	fire.advance(300.0)
	check(not fire.lit and fire.burn_seconds_left() == 0.0, "una espera larga consume todo el combustible y apaga el fuego")
	fire.free()
	var effects := StatusEffects.new()
	add_child(effects)
	effects.apply(&"recovering", &"", 0.5, 90.0)
	effects._physics_process(1.0)
	check(absf(effects.get_effect(&"recovering").remaining - 30.0) < 0.001, "los estados duraderos cuentan el mismo tiempo acelerado")
	effects._physics_process(1.0)
	check(effects.get_effect(&"recovering") == null, "la recuperación termina cuando pasa su tiempo del mundo")
	effects.free()
	var weather := WeatherController.new()
	add_child(weather)
	weather.set_process(false)
	weather._to = WeatherState.new()
	weather._resolved = weather._to
	weather._ready_to_run = true
	weather._forced = true
	weather._process(1.0)
	check(is_equal_approx(weather._elapsed, 60.0), "los eventos meteorológicos cuentan el mismo tiempo acelerado")
	weather.free()
	WorldTime.reset()


func _test_bedroll() -> void:
	var data: ItemData = ItemCatalog.get_item(&"bedroll")
	check(data != null and data.icon != null and data.get_trait(GroundPlaceableTrait) != null,
		"el lecho tiene objeto, icono y vista previa para plantarlo")
	var ground := data.get_trait(GroundPlaceableTrait) as GroundPlaceableTrait
	var preview := ground.preview_scene.instantiate()
	add_child(preview)
	check(not preview.find_children("*", "GeometryInstance3D", true, false).is_empty(),
		"la vista previa permite colorear el lecho al validar dónde se planta")
	preview.free()
	var recipes := Recipes.all().filter(func(recipe: RecipeData) -> bool: return recipe.result == &"bedroll")
	check(recipes.size() == 1 and recipes[0].station == Recipes.HAND, "el lecho se fabrica a mano")
	var saved := _bed.get_save_data()
	var original := _bed.transform
	_bed.position += Vector3(12, 4, -3)
	_bed.restore_save_data(saved)
	check(_bed.transform.is_equal_approx(original), "el lecho conserva su posición al guardar y cargar")
	_needs.rest = 0.37
	_needs.sleeping = true
	var needs_saved := _needs.save_data()
	_needs.refill()
	_needs.load_data(needs_saved)
	check(is_equal_approx(_needs.rest, 0.37) and not _needs.sleeping, "se guarda el descanso recuperado y se carga despierto")
	var temporary: Bedroll = load("res://scenes/world/bedroll.tscn").instantiate()
	add_child(temporary)
	_rest.open(temporary)
	check(_rest.start_sleep(), "se puede dormir en un lecho recién plantado")
	temporary.free()
	_rest._physics_process(0.1)
	check(not _rest.is_sleeping() and WorldTime.speed == 1.0, "retirar el lecho despierta sin dejar el tiempo acelerado")
	_rest.open(_bed)
	_rest._pickup()
	check(_player.inventory.get_item_count(data) == 1 and not _rest.is_open(), "recoger el lecho lo devuelve al inventario")
	_player.inventory.remove_item(data, 1)
	await get_tree().process_frame
	_bed = load("res://scenes/world/bedroll.tscn").instantiate()
	_bed.position.x = 1.5
	add_child(_bed)


func _test_save_load() -> void:
	var slot := "test_rest_%d" % Time.get_ticks_usec()
	var id := _bed.entity_id
	var position := _bed.position
	check(await GameManager.save_game(slot), "se guarda una partida con el lecho plantado")
	_bed.free()
	WorldTime.set_speed(120.0)
	check(GameManager.load_game(slot), "se carga la partida guardada")
	_bed = Bedroll.nearest(get_tree(), position)
	check(_bed != null and _bed.entity_id == id and _bed.position.is_equal_approx(position),
		"la carga vuelve a crear el lecho con la identidad y posición guardadas")
	check(WorldTime.speed == 1.0, "cargar una partida restablece el tiempo normal")
	GameManager.delete_save(slot)


func _capture(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	_reset()
	_rest.open(_bed)
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path.path_join("rest_menu.png"))
	_rest.start_sleep()
	_needs.rest = 0.35
	_rest._hours = 2.0
	_rest._refresh()
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path.path_join("sleeping.png"))


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
