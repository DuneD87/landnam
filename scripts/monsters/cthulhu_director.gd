class_name CthulhuDirector
extends Node

## Cuándo y dónde aparece Cthulhu. Mientras el jugador anda cerca del mar (agua honda a menos de
## SEA_PROBE, en la costa o navegando) hay de media un encuentro cada MEAN_INTERVAL segundos de juego;
## después, COOLDOWN_DAYS días del calendario sin otro. Primero llega su tormenta (el evento de clima
## "abyss", forzado) y OMEN_TIME s después sale de lo hondo a 1,3–1,7 km, rumbo a un punto de mar a unos
## cientos de metros del jugador, para que pase cerca. Se hunde y se va cuando se aleja, cuando ha
## pasado ENCOUNTER_TIME o un rato después de mirar al jugador; con él se va la tormenta.
##
## Los presagios (la ventana para esconderse bajo cubierta, bucear o alejarse de la costa): la fauna se
## va y el mar se queda en silencio (AmbientFaunaSpawner.hush), retumba el fondo cada vez más fuerte,
## el mar hierve a borbotones alrededor del jugador y, CALL_LEAD s antes de salir, se le oye llamar
## desde donde va a salir.
##
## Lo crea PlanetLoader. Guarda solo la espera (get_save_data): un encuentro a medias no se guarda.

const MEAN_INTERVAL := 36000.0
const COOLDOWN_DAYS := 5.0
const OMEN_TIME := 60.0
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
## Presagios: el silencio (s hasta que la fauna se va entera y hasta que vuelve), el aviso escrito,
## desde qué parte del aviso hierve el mar, y cuánto antes de salir se le oye.
const HUSH_RISE := 15.0
const HUSH_FALL := 90.0
const SILENCE_NOTICE_AT := 10.0
const BOIL_FROM := 0.3
const CALL_LEAD := 14.0
## Manchas de mar que hierve: distancia al jugador (m), radio (m) y vida (s).
const BOIL_DISTANCE := Vector2(25.0, 200.0)
const BOIL_RADIUS := Vector2(3.0, 9.0)
const BOIL_LIFE := Vector2(2.0, 4.5)
## Esbirros sueltos cuando ya no está él: cada cuánto se miran (s), y se quitan los que no cazan a nadie
## y no se ven a más de MINION_FORGET m, o cualquiera a más de MINION_KEEP.
const MINION_CHECK := 2.0
const MINION_FORGET := 60.0
const MINION_KEEP := 1500.0
const RUMBLE_STREAM := "res://audio/monsters/cthulhu/rumble_loop.ogg"
const BUBBLES_EVENT := &"cthulhu_bubbles"

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
var _hush := 0.0
var _spray: AbyssSpray
var _rumble: AudioStreamPlayer
var _rumble_level := 0.0
var _minion_check := 0.0
var _boils: Array[Dictionary] = []
var _boil_timer := 0.0
var _told_silence := false
## Dónde saldrá, elegido al llamar (vacío si aún no).
var _pending: Dictionary = {}


func setup(terrain: VoxelLodTerrain, ocean: OceanSystem, world_map: PlanetWorldMap,
		weather: WeatherController, player: PlayerController) -> void:
	_terrain = terrain
	_player = player
	_weather = weather
	_habitat = WaterFaunaHabitat.new()
	_habitat.setup(terrain, ocean, world_map)
	_rng.randomize()
	_rumble = AudioStreamPlayer.new()
	_rumble.name = "AbyssRumble"
	var stream := load(RUMBLE_STREAM) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_rumble.stream = stream
	_rumble.bus = &"SFX"
	_rumble.volume_db = -80.0
	add_child(_rumble)


func _exit_tree() -> void:
	AmbientFaunaSpawner.hush = 0.0


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
			return "presente a %.0f m (%s)%s; esbirros encima: %d, sueltos: %d" % [
				cthulhu.global_position.distance_to(_player.global_position), Cthulhu.State.keys()[cthulhu.state],
				", ya ha mirado" if cthulhu.gazed else "", cthulhu.brood.perched() if cthulhu.brood != null else 0,
				get_tree().get_nodes_in_group(Minion.MINION_GROUP).size()]
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
	_update_hush(delta)
	_update_rumble(delta)
	_update_boils(delta)
	_cleanup_minions(delta)
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
			_omens(delta)
			if _timer >= _omen_length:
				if not _spawn_pending() and not _spawn_far():
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
	_told_silence = false
	_pending = {}
	_boil_timer = 0.0
	_begin_weather()
	# Las aves posadas cerca echan a volar ya; el resto se va con el silencio.
	AmbientAnimal.startle_near(get_tree(), _player.global_position, 150.0)


# --- Presagios ------------------------------------------------------------------------------------

func _omens(delta: float) -> void:
	var progress := _timer / maxf(_omen_length, 0.01)
	if not _told_silence and _timer >= minf(SILENCE_NOTICE_AT, _omen_length * 0.3):
		_told_silence = true
		if _player.hotbar != null:
			_player.hotbar.notify(tr("ABYSS_OMEN_SILENCE"))
	if progress >= BOIL_FROM:
		_boil_timer -= delta
		if _boil_timer <= 0.0:
			_boil_timer = lerpf(3.5, 0.7, progress) * _rng.randf_range(0.6, 1.4)
			_start_boil(progress)
	if _pending.is_empty() and _timer >= _omen_length - CALL_LEAD:
		var pick := _pick_far()
		if not pick.is_empty():
			# Relativo al centro del planeta: el origen flotante puede moverse antes de que salga.
			_pending = {"offset": (pick["spot"] as Vector3) - _habitat.center()}
			var event := AudioManager.get_event(Cthulhu.ROAR_EVENT)
			if event != null:
				# Aún bajo el agua: apagado.
				AudioManager.play_event_3d(event, pick["spot"], {"volume_offset_db": -4.0, "pitch": 0.85})


## La fauna se va con la tormenta y vuelve despacio cuando se va él.
func _update_hush(delta: float) -> void:
	var target := 1.0 if phase != Phase.NONE else 0.0
	var rate := 1.0 / (HUSH_RISE if target > _hush else HUSH_FALL)
	var next := move_toward(_hush, target, delta * rate)
	if next != _hush or AmbientFaunaSpawner.hush != next:
		_hush = next
		AmbientFaunaSpawner.hush = _hush


## El retumbar del fondo: sube durante el aviso y se apaga cuando él ya está (lleva el suyo).
func _update_rumble(delta: float) -> void:
	var level := 0.0
	if phase == Phase.OMEN:
		level = smoothstep(0.1, 1.0, _timer / maxf(_omen_length, 0.01))
	_rumble_level = move_toward(_rumble_level, level, delta / (2.0 if level > _rumble_level else 12.0))
	if _rumble_level < 0.005:
		if _rumble.playing:
			_rumble.stop()
		return
	_rumble.volume_db = linear_to_db(_rumble_level) - 3.0
	if not _rumble.playing:
		_rumble.play(_rng.randf() * 10.0)


## Una mancha de mar que hierve, mejor delante de la cámara y sin barco encima.
func _start_boil(progress: float) -> void:
	var center := _habitat.center()
	var here := _player.global_position
	var up := (here - center).normalized()
	var view := -_player.camera.global_basis.z
	view = view.slide(up).normalized() if view.slide(up).length_squared() > 0.01 else up.cross(Vector3.RIGHT).normalized()
	for attempt in 6:
		var direction := view.rotated(up, _rng.randf_range(-1.2, 1.2) if _rng.randf() < 0.75 else _rng.randf() * TAU)
		var spot := _on_sphere(here + direction * _rng.randf_range(BOIL_DISTANCE.x, BOIL_DISTANCE.y))
		if not _deep(spot, 4.0) or _under_hull(spot):
			continue
		var radius := _rng.randf_range(BOIL_RADIUS.x, BOIL_RADIUS.y) * lerpf(0.7, 1.3, progress)
		_boils.append({"offset": spot - center, "age": 0.0, "life": _rng.randf_range(BOIL_LIFE.x, BOIL_LIFE.y),
			"radius": radius, "strength": progress, "emit": 0.0})
		HullWaves.wave_ring(spot, 0.25 + 0.35 * progress, radius * 0.5, 3.0, 7.0)
		var event := AudioManager.get_event(BUBBLES_EVENT)
		if event != null:
			AudioManager.play_event_3d(event, spot, {"volume_offset_db": lerpf(-6.0, 2.0, progress)})
		return


func _update_boils(delta: float) -> void:
	if _boils.is_empty():
		return
	var center := _habitat.center()
	if _spray == null or not is_instance_valid(_spray):
		_spray = AbyssSpray.new()
		_spray.name = "AbyssOmenSpray"
		_terrain.add_child(_spray)
	_spray.follow(_on_sphere(_player.global_position), center)
	for i in range(_boils.size() - 1, -1, -1):
		var boil := _boils[i]
		boil["age"] = float(boil["age"]) + delta
		if boil["age"] >= boil["life"]:
			_boils.remove_at(i)
			continue
		# Un borbotón cada ~0,12 s, más flojo al final.
		boil["emit"] = float(boil["emit"]) - delta
		if boil["emit"] > 0.0:
			continue
		boil["emit"] = 0.12
		var spot: Vector3 = center + (boil["offset"] as Vector3)
		var fade := 1.0 - smoothstep(0.6, 1.0, float(boil["age"]) / float(boil["life"]))
		_spray.boil(spot, (spot - center).normalized(), boil["radius"], float(boil["strength"]) * fade)


## Consola: que salten ya los esbirros que lleva encima.
func launch_minions() -> String:
	if phase != Phase.PRESENT or not is_instance_valid(cthulhu) or cthulhu.brood == null:
		return "no está"
	cthulhu.brood.launch()
	return "saltan %d" % cthulhu.brood.perched()


## Ido él, los esbirros que no cazan a nadie se van (se quitan sin que se vea).
func _cleanup_minions(delta: float) -> void:
	_minion_check -= delta
	if _minion_check > 0.0:
		return
	_minion_check = MINION_CHECK
	for node in get_tree().get_nodes_in_group(Minion.MINION_GROUP):
		var minion := node as Minion
		if minion == null or minion.is_dead or minion.leaping:
			continue
		var distance := minion.global_position.distance_to(_player.global_position)
		var idle := minion.ai_controller.target == null and not minion.is_feeding()
		if distance > MINION_KEEP or (phase != Phase.PRESENT and idle and distance > MINION_FORGET
				and not AnimationLod.in_view(minion, 2.0)):
			minion.queue_free()


## Hay un casco justo encima del punto: ahí no se ve hervir.
func _under_hull(point: Vector3) -> bool:
	var space := _terrain.get_world_3d().direct_space_state
	var up := (point - _habitat.center()).normalized()
	var query := PhysicsRayQueryParameters3D.create(point + up * 30.0, point - up * 1.0, PhysicsLayers.BODIES)
	return not space.intersect_ray(query).is_empty()


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
	_pending = {}
	_boils.clear()
	if cooldown:
		_cooldown_hours = COOLDOWN_DAYS * 24.0
	if _weather != null:
		if _weather_was_forced and _weather_before != WEATHER_EVENT:
			_weather.force_weather(_weather_before)
		else:
			_weather.clear_force()


func _spawn_far() -> bool:
	var pick := _pick_far()
	if pick.is_empty():
		return false
	_spawn(pick["spot"], pick["heading"], pick["pass"], false)
	return true


## Sale donde se le oyó llamar, si sigue teniendo sentido (el jugador no se ha ido lejos).
func _spawn_pending() -> bool:
	if _pending.is_empty():
		return false
	var spot: Vector3 = _habitat.center() + (_pending["offset"] as Vector3)
	var distance := spot.distance_to(_player.global_position)
	if distance > SPAWN_DISTANCE.y * 1.5 or distance < SPAWN_DISTANCE.x * 0.5:
		return false
	var pass_point := _pass_point(spot)
	if pass_point == Vector3.ZERO:
		return false
	var up := (spot - _habitat.center()).normalized()
	_spawn(spot, (pass_point - spot).slide(up).normalized(), pass_point, false)
	return true


## Sitio de salida a SPAWN_DISTANCE, con fondo, y su punto de paso; vacío si no hay.
func _pick_far() -> Dictionary:
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
		return {"spot": spot, "heading": heading, "pass": pass_point}
	return {}


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
