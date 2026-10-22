extends Node

## Frío con el clima real de la Tierra, sin cargar terreno ni personajes: lluvia, nieve,
## transiciones, refugio, altitud, hielo, ropa, fuego y daño a la vida.
##   godot --headless --path . res://tests/survival/test_cold_exposure.tscn

class PlanetBody extends Node3D:
	var planet: Planet


class LocalWeather extends WeatherController:
	var sheltered := false
	var cloud_envelope := 1.0

	func is_sheltered() -> bool:
		return sheltered

	func _local_cloud_coverage(st: WeatherState) -> float:
		return st.cloud_coverage * cloud_envelope


var failures := 0
var checks := 0
var _body: PlanetBody
var _player: PlayerController
var _needs: SurvivalNeeds
var _health: HealthComponent
var _weather: LocalWeather
var _events: Dictionary


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	_events = JSON.parse_string(FileAccess.get_file_as_string(WeatherController.DEFAULT_EVENTS_FILE)).events
	_body = PlanetBody.new()
	add_child(_body)
	var terrain := VoxelLodTerrain.new()
	_body.add_child(terrain)
	_body.planet = Planet.new(terrain)
	_body.add_child(_body.planet)
	_body.planet.radius = config.terrain_settings.radius
	_body.planet.climate = ClimateField.new(config.climate_settings, _body.planet.radius)
	Seasons.enabled = false

	# El cuerpo ya está listo al ponerle el script: solo se montan los componentes necesarios,
	# sin ejecutar el arranque de una partida, los modelos ni las ventanas del jugador.
	var body := CharacterBody3D.new()
	add_child(body)
	body.set_script(PlayerController)
	_player = body as PlayerController
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.planet = _body
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
	_weather = LocalWeather.new()
	_weather._planet = _body.planet
	_weather._player = _player
	add_child(_weather)
	_weather.add_to_group("weather")
	_weather.set_process(false)

	_test_precipitation()
	_test_exposure()
	_test_protection()
	_test_damage_rules()
	_player.free()
	_weather.free()
	_body.free()
	await get_tree().process_frame
	print("COLD EXPOSURE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _reset(lat := 30.0, altitude := 0.0, event := "clear") -> void:
	_needs.refill()
	_needs.paused = false
	_needs.rate = 1.0
	_needs._climate_timer = 0.0
	_health.revive()
	_player.free_flight_enabled = false
	_player.visible = true
	_player.movement.is_swimming = false
	_weather.enabled = true
	_weather.sheltered = false
	_weather.cloud_envelope = 1.0
	_weather._camera_submerged = false
	_place(lat, altitude)
	_set_weather(event)


func _place(lat: float, altitude: float) -> void:
	var angle := deg_to_rad(lat)
	_player.global_position = _body.global_position + Vector3(cos(angle), sin(angle), 0.0) * (_body.planet.radius + altitude)
	_needs._climate_timer = 0.0


func _set_weather(event: String) -> void:
	var st := WeatherState.new()
	st.apply_overrides(_events[event])
	_weather._resolved = st
	_weather._current = event
	_needs._climate_timer = 0.0


func _step(seconds: int) -> void:
	for tick in seconds:
		_needs._physics_process(1.0)


func _test_precipitation() -> void:
	_reset(25.0, 0.0, "storm")
	var rain := _weather.get_local_precipitation()
	check(rain.x > 0.9 and rain.y < 0.1, "el temporal cae como lluvia en tierra templada")
	_step(60)
	check(_needs.wetness > 0.95, "la lluvia real empapa en un minuto")
	_weather._camera_submerged = true
	check(_weather.get_local_precipitation().is_equal_approx(rain), "sumergir la cámara no cambia lo que cae sobre el jugador")
	_reset(25.0, 0.0, "storm")
	_weather.cloud_envelope = 0.5
	_step(60)
	check(is_zero_approx(_needs.wetness), "un claro entre nubes no moja aunque el evento sea temporal")
	_reset(25.0, 0.0, "storm")
	_weather._resolved = WeatherState.blend(_state("clear"), _state("storm"), 0.25)
	_step(30)
	check(is_zero_approx(_needs.wetness), "la transición no moja antes de que llegue la precipitación")
	_weather._resolved = WeatherState.blend(_state("clear"), _state("storm"), 0.9)
	_step(30)
	check(_needs.wetness > 0.0 and _needs.wetness < 0.5, "la lluvia de la transición moja en proporción a su intensidad")
	_reset(25.0, 1200.0, "storm")
	_step(60)
	check(is_zero_approx(_needs.wetness), "por encima de las nubes no llueve sobre el jugador")
	_reset(70.0, 0.0, "storm")
	var snow := _weather.get_local_precipitation()
	check(is_zero_approx(snow.x) and snow.y > 0.9, "en el casquete la lluvia del temporal se convierte en nieve")
	_step(60)
	check(_needs.wetness > 0.2 and _needs.wetness < 0.3, "el temporal convertido a nieve moja más despacio que la lluvia")
	_reset(30.0, 0.0, "snow")
	_step(60)
	check(_needs.wetness > 0.0, "la nevada también moja")
	_reset(30.0, 0.0, "storm")
	_weather.enabled = false
	_step(60)
	check(is_zero_approx(_needs.wetness), "el sistema meteorológico desactivado no moja")


func _test_exposure() -> void:
	_reset()
	_step(360)
	check(is_equal_approx(_health.health, _health.max_health), "sin exposición el personaje conserva la vida")
	_reset(30.0, 0.0, "storm")
	_step(360)
	check(_needs.warmth <= -SurvivalNeeds.COLD_EXPOSURE_START and _health.health < _health.max_health,
		"mojarse bajo la lluvia acaba causando frío y pérdida de vida")
	_reset(30.0, 0.0, "snow")
	_step(360)
	check(_needs.warmth <= -SurvivalNeeds.COLD_EXPOSURE_START and _health.health < _health.max_health,
		"la nevada acaba causando frío y pérdida de vida")
	_reset(25.0, 700.0)
	_step(300)
	check(_needs.wetness == 0.0 and _health.health < _health.max_health,
		"la alta montaña quita vida por frío incluso en seco y con cielo despejado")
	_reset(70.0)
	_step(300)
	var local := _player.global_position - _body.global_position
	check(_body.planet.climate.snow_cover(_body.planet.climate.snow_coldness(local)) > 0.9
		and _body.planet.climate.sea_ice(local) > 0.9 and _health.health < _health.max_health,
		"el frío de una zona con nieve y mar helado quita vida sin que esté nevando")
	var felt := _needs.felt_temperature
	var shift := Vector3(25000.0, -8000.0, 9000.0)
	_body.position += shift
	_player.position += shift
	_weather.set_planet_center(_body.global_position)
	_needs._climate_timer = 0.0
	_step(1)
	check(absf(_needs.felt_temperature - felt) < 0.05, "el frío sigue siendo el mismo tras un cambio de origen")
	_body.position = Vector3.ZERO
	_weather.set_planet_center(Vector3.ZERO)


func _test_protection() -> void:
	_reset(30.0, 0.0, "storm")
	_weather.sheltered = true
	_step(300)
	check(is_zero_approx(_needs.wetness) and is_equal_approx(_health.health, _health.max_health),
		"un techo evita mojarse y sufrir el frío de la lluvia")
	_needs.wetness = 1.0
	_needs._climate_timer = 0.0
	_step(1)
	check(_needs.wetness > 0.9 and _needs.wetness < 1.0, "entrar bajo techo empieza a secar sin borrar la humedad de golpe")
	_reset(45.0)
	_step(1)
	var naked := _needs.felt_temperature
	# La ropa usa los mismos objetos y ranuras que el inventario; basta una ventana sin abrir.
	var window := CharacterWindow.new()
	var slot := EquipmentSlot.new()
	var clothes := ItemData.new()
	var insulation := InsulationTrait.new()
	insulation.warmth = 9.0
	clothes.traits.append(insulation)
	slot.equipped_item = InventoryItem.new(clothes)
	window.equipment_slots[ItemData.ArmorSlot.CHEST] = slot
	_player.character_window = window
	_needs._climate_timer = 0.0
	_step(1)
	check(_needs.felt_temperature > naked + 8.9, "la ropa puesta suma su abrigo a la temperatura sentida")
	_needs.wetness = 1.0
	_needs._climate_timer = 0.0
	_step(1)
	check(_needs.felt_temperature < naked, "empapado, la ropa pierde abrigo y el cuerpo se enfría")
	_player.character_window = null
	slot.free()
	window.free()
	# Sin el montaje visual ni el consumo de combustible: se usa el calor real de Campfire.
	var node := Node3D.new()
	add_child(node)
	node.set_script(Campfire)
	var fire := node as Campfire
	fire.process_mode = Node.PROCESS_MODE_DISABLED
	fire.add_child(fire.inventory)
	fire.add_to_group(Campfire.GROUP)
	fire.position = _player.position
	fire.lit = true
	_weather.sheltered = true
	_needs.warmth = -0.7
	_needs._climate_timer = 0.0
	_step(300)
	check(is_zero_approx(_needs.wetness) and _needs.warmth > -SurvivalNeeds.COLD_EXPOSURE_START,
		"la hoguera seca y permite recuperar calor hasta salir del estado dañino")
	var health := _health.health
	_step(30)
	check(is_equal_approx(_health.health, health), "recuperado el calor, deja de bajar la vida")
	fire.free()


func _test_damage_rules() -> void:
	_reset()
	_needs.warmth = -SurvivalNeeds.COLD_EXPOSURE_START
	_needs._hurt(15.0, _health)
	check(_health.health < _health.max_health and _needs.is_critical("warmth"), "desde «Frío» baja la vida y avisa el medallón")
	var cold_damage := _health.max_health - _health.health
	_needs.refill()
	_health.revive()
	_needs.warmth = -1.0
	_needs._hurt(15.0, _health)
	check(_health.max_health - _health.health > cold_damage, "helado se pierde más vida que con frío moderado")
	_needs.refill()
	_health.revive()
	_needs.warmth = -0.2
	_needs._hurt(60.0, _health)
	check(_health.health == _health.max_health, "el estado «Fresco» todavía no daña")
	_needs.warmth = -1.0
	_health.invincible = true
	_needs._hurt(30.0, _health)
	check(_health.health == _health.max_health, "el modo dios evita el daño por frío")
	_health.invincible = false
	_needs.wetness = 0.7
	var saved := _needs.save_data()
	_needs.refill()
	_needs.load_data(saved)
	check(_needs.warmth == -1.0 and is_equal_approx(_needs.wetness, 0.7), "temperatura y humedad sobreviven al guardado")
	_reset(70.0)
	_needs.paused = true
	_step(300)
	check(is_zero_approx(_needs.warmth) and _health.health == _health.max_health, "la pausa de necesidades detiene frío y daño")
	_needs.paused = false
	_player.free_flight_enabled = true
	_step(300)
	check(is_zero_approx(_needs.warmth) and _health.health == _health.max_health, "el vuelo libre detiene frío y daño")


func _state(event: String) -> WeatherState:
	var st := WeatherState.new()
	st.apply_overrides(_events[event])
	return st


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
