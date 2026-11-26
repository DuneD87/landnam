class_name CthulhuDirector
extends Node

## Cuándo y dónde aparece Cthulhu. Mientras el jugador anda cerca del mar (agua honda a menos de
## SEA_PROBE, en la costa o navegando) hay de media un encuentro cada MEAN_INTERVAL segundos de juego;
## después, COOLDOWN_DAYS días del calendario sin otro. Primero llega su tormenta (el evento de clima
## "abyss", forzado) y OMEN_TIME s después sale de lo hondo a 1,3–1,7 km, rumbo a un punto de mar a unos
## cientos de metros del jugador, para que pase cerca. Se hunde y se va cuando se aleja, cuando ha
## pasado ENCOUNTER_TIME o un rato después de mirar al jugador; con él se va la tormenta.
##
## Lo crea PlanetLoader. Guarda solo la espera (get_save_data): un encuentro a medias no se guarda.

const MEAN_INTERVAL := 36000.0
const COOLDOWN_DAYS := 5.0
const OMEN_TIME := 45.0
const SPAWN_DISTANCE := Vector2(1300.0, 1700.0)
## Distancia lateral al jugador del punto por el que pasa.
const PASS_OFFSET := Vector2(200.0, 420.0)
const LEAVE_DISTANCE := 2600.0
## Más lejos que esto (teletransporte, muerte lejos) se quita de golpe.
const VANISH_DISTANCE := 5000.0
const ENCOUNTER_TIME := 540.0
## Tras mirar al jugador, lo que tarda en irse.
const AFTER_GAZE := 75.0
## Agua honda a menos de esto (m) del jugador: está cerca del mar.
const SEA_PROBE := 700.0
## Fondo que necesita donde aparece.
const SPAWN_DEPTH := 30.0
const CHECK_EVERY := 1.0
const WEATHER_EVENT := "abyss"

enum Phase { NONE, OMEN, PRESENT }

var phase: Phase = Phase.NONE
var cthulhu: Cthulhu

var _terrain: Node3D
var _player: PlayerController
var _weather: WeatherController
var _habitat: WaterFaunaHabitat
## Horas de calendario que faltan para poder volver.
var _cooldown_hours := 0.0
var _timer := 0.0
var _check := 0.0
var _gaze_time := -1.0
var _omen_length := OMEN_TIME
var _weather_was_forced := false
var _weather_before := ""
var _rng := RandomNumberGenerator.new()


func setup(terrain: VoxelLodTerrain, ocean: OceanSystem, world_map: PlanetWorldMap,
		weather: WeatherController, player: PlayerController) -> void:
	_terrain = terrain
	_player = player
	_weather = weather
	_habitat = WaterFaunaHabitat.new()
	_habitat.setup(terrain, ocean, world_map)
	_rng.randomize()


func get_save_data() -> Dictionary:
	return {"cooldown_hours": _cooldown_hours}


func restore_save_data(data: Dictionary) -> void:
	_cooldown_hours = float(data.get("cooldown_hours", 0.0))


## Estado legible para la consola.
func describe() -> String:
	match phase:
		Phase.OMEN:
			return "tormenta: sale en %.0f s" % maxf(0.0, _omen_length - _timer)
		Phase.PRESENT:
			if not is_instance_valid(cthulhu):
				return "presente"
			return "presente a %.0f m (%s)%s" % [cthulhu.global_position.distance_to(_player.global_position),
				Cthulhu.State.keys()[cthulhu.state], ", ya ha mirado" if cthulhu.gazed else ""]
	return "ausente; espera %.1f h de calendario; cerca del mar: %s" % [_cooldown_hours,
		"sí" if _near_sea() else "no"]


## Consola: trae la tormenta y lo saca en [omen] s, a la distancia normal.
func summon(omen: float = 6.0) -> bool:
	if phase != Phase.NONE:
		return false
	_start_omen(omen)
	return true


## Consola: lo planta ya fuera del agua a [distance] m delante del jugador, mirándolo.
func summon_facing(distance: float = 420.0) -> String:
	if phase == Phase.PRESENT:
		dismiss(true)
	var center := _habitat.center()
	var up := (_player.global_position - center).normalized()
	var view := -_player.camera.global_basis.z
	view = view.slide(up).normalized() if view.slide(up).length_squared() > 0.01 else up.cross(Vector3.RIGHT).normalized()
	var spot := Vector3.ZERO
	for attempt in 24:
		var direction := view.rotated(up, deg_to_rad(15.0) * ceili(attempt / 2.0) * (1.0 if attempt % 2 == 0 else -1.0))
		var candidate := _on_sphere(_player.global_position + direction * distance)
		if _deep(candidate, Cthulhu.MIN_DEPTH):
			spot = candidate
			break
	if spot == Vector3.ZERO:
		return "no hay mar hondo delante a %.0f m" % distance
	if phase == Phase.NONE:
		_begin_weather()
	var heading := (_player.global_position - spot).slide(up).normalized()
	_spawn(spot, heading, spot + heading.rotated(up, PI * 0.5) * 900.0, true)
	cthulhu.face(_player.global_position)
	return "aparece a %.0f m" % distance


## Lo hunde ([now]: lo quita sin más) y se lleva la tormenta.
func dismiss(now: bool = false) -> void:
	if phase == Phase.OMEN:
		_end()
		return
	if phase != Phase.PRESENT:
		return
	if now or not is_instance_valid(cthulhu):
		if is_instance_valid(cthulhu):
			cthulhu.queue_free()
		_end(false)
		return
	cthulhu.submerge()


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.State.PLAYING or _player == null:
		return
	if phase == Phase.NONE and _cooldown_hours > 0.0:
		_cooldown_hours = maxf(0.0, _cooldown_hours - WorldTime.hours_elapsed(delta))
	match phase:
		Phase.NONE:
			_check -= delta
			if _check > 0.0:
				return
			_check = CHECK_EVERY
			if _cooldown_hours > 0.0 or _player.combat.is_dead() or not _near_sea():
				return
			if _rng.randf() < 1.0 - exp(-CHECK_EVERY / MEAN_INTERVAL):
				_start_omen(OMEN_TIME)
		Phase.OMEN:
			_timer += delta
			if _timer >= _omen_length:
				if not _spawn_far():
					# Sin sitio todavía (el mapa, el jugador en tierra adentro): lo reintenta un rato.
					if _timer > _omen_length + 30.0:
						_end(false)
		Phase.PRESENT:
			_timer += delta
			if not is_instance_valid(cthulhu):
				_end()
				return
			var distance := cthulhu.global_position.distance_to(_player.global_position)
			if distance > VANISH_DISTANCE:
				# Reapareció lejos o se fue de un salto: el encuentro cuenta igual para la espera.
				cthulhu.queue_free()
				_end()
				return
			if cthulhu.gazed and _gaze_time < 0.0:
				_gaze_time = _timer
			var after_gaze := _gaze_time >= 0.0 and _timer - _gaze_time > AFTER_GAZE
			if distance > LEAVE_DISTANCE or _timer > ENCOUNTER_TIME or after_gaze:
				cthulhu.submerge()


func _start_omen(length: float) -> void:
	phase = Phase.OMEN
	_timer = 0.0
	_omen_length = length
	_begin_weather()


func _begin_weather() -> void:
	if _weather == null:
		return
	_weather_was_forced = _weather._forced
	_weather_before = _weather.get_current_weather_name()
	_weather.force_weather(WEATHER_EVENT)


func _end(cooldown: bool = true) -> void:
	phase = Phase.NONE
	cthulhu = null
	_timer = 0.0
	_gaze_time = -1.0
	if cooldown:
		_cooldown_hours = COOLDOWN_DAYS * 24.0
	if _weather != null:
		if _weather_was_forced and _weather_before != WEATHER_EVENT:
			_weather.force_weather(_weather_before)
		else:
			_weather.clear_force()


func _spawn_far() -> bool:
	var center := _habitat.center()
	var here := _player.global_position
	var up := (here - center).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := up.cross(right)
	for attempt in 32:
		var angle := _rng.randf_range(0.0, TAU)
		var flat := right * cos(angle) + forward * sin(angle)
		var spot := _on_sphere(here + flat * _rng.randf_range(SPAWN_DISTANCE.x, SPAWN_DISTANCE.y))
		if not _deep(spot, SPAWN_DEPTH):
			continue
		var pass_point := _pass_point(spot)
		if pass_point == Vector3.ZERO:
			continue
		var heading := (pass_point - spot).slide((spot - center).normalized()).normalized()
		_spawn(spot, heading, pass_point, false)
		return true
	return false


## Punto de mar a PASS_OFFSET del jugador, de costado respecto a la llegada; si a los lados es tierra,
## el primer punto con fondo yendo del jugador hacia donde sale.
func _pass_point(spot: Vector3) -> Vector3:
	var here := _player.global_position
	var up := (here - _habitat.center()).normalized()
	var toward := (spot - here).slide(up).normalized()
	var side := up.cross(toward)
	var first := 1.0 if _rng.randf() < 0.5 else -1.0
	for flip in [first, -first]:
		var candidate := _on_sphere(here + side * flip * _rng.randf_range(PASS_OFFSET.x, PASS_OFFSET.y))
		if _deep(candidate, Cthulhu.MIN_DEPTH + 4.0):
			return candidate
	var span := here.distance_to(spot)
	var step := 80.0
	var d := PASS_OFFSET.x
	while d < span - 300.0:
		var candidate := _on_sphere(here + toward * d)
		if _deep(candidate, Cthulhu.MIN_DEPTH + 4.0):
			return candidate
		d += step
	return Vector3.ZERO


func _spawn(spot: Vector3, heading: Vector3, destination: Vector3, emerged: bool) -> void:
	cthulhu = Cthulhu.new()
	cthulhu.name = "Cthulhu"
	_terrain.add_child(cthulhu)
	cthulhu.setup(_player, _habitat, spot, heading, destination, emerged)
	phase = Phase.PRESENT
	_timer = 0.0
	_gaze_time = -1.0


## Cerca del mar: agua de mar honda bajo el jugador o en un anillo a su alrededor.
func _near_sea() -> bool:
	var map := _habitat.world_map
	if map == null or not map.is_ready():
		return false
	var here := _player.global_position
	if _deep(here, SPAWN_DEPTH):
		return true
	var up := (here - _habitat.center()).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	for reach in [SEA_PROBE * 0.5, SEA_PROBE]:
		for i in 8:
			var flat := right.rotated(up, TAU * i / 8.0)
			if _deep(_on_sphere(here + flat * reach), SPAWN_DEPTH):
				return true
	return false


func _deep(point: Vector3, depth: float) -> bool:
	var map := _habitat.world_map
	if map == null or not map.is_ready():
		return false
	var water := map.get_water_type_at(point)
	if water != WorldMapData.WaterType.OCEAN and water != WorldMapData.WaterType.SEA:
		return false
	return map.get_water_depth_at(point) >= depth


## [point] llevado a la superficie del mar (misma vertical).
func _on_sphere(point: Vector3) -> Vector3:
	var center := _habitat.center()
	return center + (point - center).normalized() * _habitat.ocean.radius
