class_name WeatherController
extends Node

## Cerebro del sistema meteorológico: elige un evento climático según el bioma y la altitud
## del jugador, interpola entre eventos y difunde el estado resuelto a atmósfera, sol,
## vegetación, agua y terreno. Los eventos son data-driven (data/weather/weather_events.json);
## añade partículas de precipitación (WeatherFX) y destellos de rayo (WeatherLightning).

## Se emite el frame en que arranca una descarga de rayo (gancho para el trueno o gameplay).
signal lightning_struck

const DEFAULT_EVENTS_FILE := "res://data/weather/weather_events.json"

# Perfiles por defecto por carácter de bioma (probabilidad 0..1, suman 1.0); usados si el JSON no define uno.
const PROFILE_SNOWY := [["snow", 0.5], ["storm", 0.17], ["fog", 0.17], ["clear", 0.16]]
const PROFILE_TEMPERATE := [["clear", 0.33], ["storm", 0.33], ["wind", 0.17], ["fog", 0.17]]
const PROFILE_TROPICAL := [["clear", 0.5], ["wind", 0.33], ["storm", 0.17]]
const PROFILE_FALLBACK := [["clear", 0.5], ["storm", 0.2], ["wind", 0.15], ["fog", 0.15]]
# Perfil de picos (>= snow_altitude): nieve dominante. Fallback si falta 'peaks_profile' en el JSON.
const DEFAULT_PEAKS_PROFILE := [["snow", 0.7], ["fog", 0.2], ["storm", 0.1]]
# Refuerzo de frío (cold_altitude..snow_altitude): probabilidad extra sumada. Fallback si falta 'cold_boost' en el JSON.
const DEFAULT_COLD_BOOST := {"snow": 0.4, "fog": 0.2}
# Multiplicadores de cada evento por estación, en la del jugador (Seasons). Fallback si falta
# 'season_weights' en el JSON. La nieve de invierno no sale de aquí sino del frío de la estación,
# que lleva la taiga y su refuerzo de nieve hacia el ecuador.
const DEFAULT_SEASON_WEIGHTS := {
	"spring": {"clear": 1.0, "storm": 1.2, "wind": 1.2, "fog": 0.8},
	"summer": {"clear": 1.8, "storm": 0.8, "wind": 0.8, "fog": 0.4, "snow": 0.5},
	"autumn": {"clear": 0.7, "storm": 1.6, "wind": 1.4, "fog": 1.8},
	"winter": {"clear": 0.8, "storm": 1.2, "fog": 1.5, "snow": 1.6},
}
# Transición mínima entre eventos con el calendario acelerado (s): por debajo, el cielo salta.
const MIN_TRANSITION_TIME := 2.0
# Velocidad del suavizado del oscurecimiento local (1/s): ~4 s para entrar o salir de la celda.
const SHADE_SMOOTH_RATE := 0.7

@export var enabled: bool = true
@export var min_duration: float = 60.0
@export var max_duration: float = 180.0
@export var transition_time: float = 30.0
## Umbrales de latitud para elegir el perfil por defecto de un bioma (solo biomas sin perfil propio).
@export var snowy_latitude: float = 55.0
@export var tropical_latitude: float = 25.0
## Altitudes donde el clima se enfría (más nieve/niebla) y donde la nieve domina como en un pico.
@export var cold_altitude: float = 400.0
@export var snow_altitude: float = 500.0

@export var lightning_enabled: bool = true
## Energía pico del destello del rayo (luz auxiliar dedicada, radial hacia abajo, con sombras).
@export var lightning_flash_strength: float = 2.5

## La precipitación arranca cuando cloud_coverage supera precip_cloud_start y llega a plena en precip_cloud_full.
@export var precip_cloud_start: float = 0.8
@export var precip_cloud_full: float = 1.0

## Si la niebla se descarta dentro de cuevas muestreando la rejilla de oclusión del WeatherFX.
@export var fog_cave_occlusion_enabled: bool = true

var _planet: Planet
var _ocean: OceanSystem
var _atmosphere: PlanetAtmosphere
var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _player: Node3D
var _planet_center: Vector3

var _fx: WeatherFX

var _lightning: WeatherLightning
var _aux_light: DirectionalLight3D

## Actualiza el centro del planeta y reinicia las partículas del FX (viven en mundo).
func set_planet_center(c: Vector3) -> void:
	_planet_center = c
	if _fx != null:
		_fx.on_origin_shift(c)

var _biome_count: int = 0
var _biome_latitude_ranges: Array = []
var _profiles_by_biome: Dictionary = {}

var _peaks_profile: Array = DEFAULT_PEAKS_PROFILE
var _cold_boost: Dictionary = DEFAULT_COLD_BOOST
var _season_weights: Dictionary = DEFAULT_SEASON_WEIGHTS
## Calendario (sun_controller.gd): su season_speed acelera también la sucesión de eventos.
var _calendar: Node

var _base_sun_energy: float = 1.0
var _base_ambient_energy: float = 1.0
var _base_wave_amplitude: float = 4.0
var _base_wave_speed: float = 1.2
var _base_wave_length: float = 50.0
var _base_foam_crest: float = 1.1
var _base_wave_steepness: float = 0.5
## Rompiente autorada en el material. Los eventos la multiplican; ver _apply_state.
var _base_shore_amplitude: float = 2.0
var _base_shore_steepness: float = 0.5
var _base_shore_speed: float = 1.2
var _base_shore_length: float = 60.0
## Mar más tranquilo del catálogo: a esto vuelve el agua fuera de mar abierto. Ver _compute_calm_sea.
var _calm_wave_amplitude: float = 2.5
var _calm_wave_steepness: float = 0.5
var _water_mat: ShaderMaterial

# Sumersión de la cámara: bajo el agua se apagan precipitación y niebla (ver _update_submersion).
var _water_sampler: WaterHeightSampler
var _base_water_radius: float = 0.0
var _camera_submerged: bool = false

var _events: Dictionary = {}
var _from: WeatherState
var _to: WeatherState
var _blend: float = 1.0
var _elapsed: float = 0.0
var _duration: float = 120.0
## Estado ya interpolado que se esta aplicando. Lo que quiera reaccionar al clima debe leer
## esto y no _to, que es el destino de la transicion y llega antes que el mundo.
var _resolved: WeatherState
## Lecho sonoro del clima. Cuelga de aqui porque todo lo que necesita —estado resuelto,
## oclusion y la senal de rayo— sale de este nodo.
var ambience: WeatherAmbience
var _current: String = "clear"
var _current_biome: int = 0
var _ready_to_run: bool = false
var _forced: bool = false

var _active_fog_density: float = 0.0

# Oscurecimiento local del sol/ambiente, suavizado en el tiempo. -1 = sin inicializar (se engancha al valor exacto).
var _shade: float = -1.0
## Iluminación día/noche de la escena, si la hay: recibe las escalas del clima en vez de que el
## clima escriba las luces a mano.
var _sky_lighting: SkyLighting


## Inyecta dependencias y arranca el sistema. Lo llama planet_loader tras cargar el planeta.
func setup(
	planet: Planet,
	ocean: OceanSystem,
	atmosphere: PlanetAtmosphere,
	sun: DirectionalLight3D,
	world_env: WorldEnvironment,
	player: Node3D,
	planet_center: Vector3,
	config: Dictionary
) -> void:
	_planet = planet
	_ocean = ocean
	_atmosphere = atmosphere
	_sun = sun
	_world_env = world_env
	_player = player
	_planet_center = planet_center
	_biome_count = planet.biome_count
	_biome_latitude_ranges = planet.biome_latitude_ranges

	_apply_config(config)
	_read_base_values()
	_build_events(config)
	_compute_calm_sea()
	_build_biome_profiles(config)
	_setup_fx()
	_lightning = WeatherLightning.new()
	_setup_lightning_light()

	ambience = WeatherAmbience.new()
	ambience.name = "WeatherAmbience"
	add_child(ambience)
	ambience.setup(self)
	_current = _choose_from(_active_profile(), "")
	_to = _events.get(_current, _fallback_state())
	_from = _to
	_blend = 1.0
	_elapsed = 0.0
	_duration = randf_range(min_duration, max_duration)

	_ready_to_run = enabled
	if enabled:
		_apply_state(_to)
		_update_sky_light(0.0, _to)
	set_process(_ready_to_run)


func _apply_config(config: Dictionary) -> void:
	enabled = bool(config.get("enabled", enabled))
	min_duration = float(config.get("min_duration", min_duration))
	max_duration = float(config.get("max_duration", max_duration))
	transition_time = float(config.get("transition_time", transition_time))
	snowy_latitude = float(config.get("snowy_latitude", snowy_latitude))
	tropical_latitude = float(config.get("tropical_latitude", tropical_latitude))
	cold_altitude = float(config.get("cold_altitude", cold_altitude))
	snow_altitude = float(config.get("snow_altitude", snow_altitude))
	lightning_enabled = bool(config.get("lightning_enabled", lightning_enabled))
	lightning_flash_strength = float(config.get("lightning_flash_strength", lightning_flash_strength))
	precip_cloud_start = float(config.get("precip_cloud_start", precip_cloud_start))
	precip_cloud_full = float(config.get("precip_cloud_full", precip_cloud_full))

	var peaks := _parse_profile(config.get("peaks_profile", []))
	if peaks.is_empty():
		push_warning("WeatherController: falta 'peaks_profile' en weather_settings; uso el fallback %s. Defínelo en el JSON del planeta." % str(DEFAULT_PEAKS_PROFILE))
	else:
		_peaks_profile = peaks
	if config.has("cold_boost") and config["cold_boost"] is Dictionary:
		_cold_boost = config["cold_boost"]
	else:
		push_warning("WeatherController: falta 'cold_boost' en weather_settings; uso el fallback %s. Defínelo en el JSON del planeta." % str(DEFAULT_COLD_BOOST))
	if config.get("season_weights") is Dictionary:
		_season_weights = config["season_weights"]


func _read_base_values() -> void:
	if _sun:
		_base_sun_energy = _sun.light_energy
	if _world_env and _world_env.environment:
		_base_ambient_energy = _world_env.environment.ambient_light_energy
	if _ocean and _ocean.quadtree_material is ShaderMaterial:
		_water_mat = _ocean.quadtree_material as ShaderMaterial
		var wa: Variant = _water_mat.get_shader_parameter("wave_amplitude")
		var ws: Variant = _water_mat.get_shader_parameter("wave_speed")
		var wl: Variant = _water_mat.get_shader_parameter("wave_base_length")
		var fc: Variant = _water_mat.get_shader_parameter("foam_crest_amount")
		var st: Variant = _water_mat.get_shader_parameter("wave_steepness")
		if wa != null: _base_wave_amplitude = wa
		if ws != null: _base_wave_speed = ws
		if wl != null: _base_wave_length = wl
		if fc != null: _base_foam_crest = fc
		if st != null: _base_wave_steepness = st
		# La rompiente sí sale de _param: shore_* son ajustes finos y el .tres puede no traerlos
		# todos, en cuyo caso el valor bueno es el default que declara el shader, no un cero.
		var sa: Variant = WaterHeightSampler._param(_water_mat, &"shore_amplitude")
		var ss: Variant = WaterHeightSampler._param(_water_mat, &"shore_steepness")
		var sp: Variant = WaterHeightSampler._param(_water_mat, &"shore_speed")
		var sl: Variant = WaterHeightSampler._param(_water_mat, &"shore_length")
		if sa != null: _base_shore_amplitude = sa
		if ss != null: _base_shore_steepness = ss
		if sp != null: _base_shore_speed = sp
		if sl != null: _base_shore_length = sl
		_setup_water_sampler()


## Estado de mar más tranquilo del catálogo: es al que vuelve el agua donde la máscara de temporal
## no aplica. No sirve el valor autorado del material, que no es el mar en calma sino la referencia
## desde la que multiplican los eventos, y sale más movido que el océano en día despejado.
func _compute_calm_sea() -> void:
	var min_multiplier := INF
	var min_steepness := INF
	for event_name in _events:
		var st: WeatherState = _events[event_name]
		min_multiplier = minf(min_multiplier, st.water_wave_multiplier)
		min_steepness = minf(min_steepness, st.water_steepness)

	if is_inf(min_multiplier):
		min_multiplier = 1.0
		min_steepness = _base_wave_steepness
	_calm_wave_amplitude = _base_wave_amplitude * min_multiplier
	_calm_wave_steepness = min_steepness


## Le pasa el mapa del planeta al sampler de submersión. Llega tarde a propósito: el mapa se hornea
## después del clima, y sin él la cámara se daría por sumergida con olas de temporal que en un lago
## o en la orilla no existen.
func set_world_map(map: PlanetWorldMap) -> void:
	if _water_sampler != null:
		_water_sampler.world_map = map


## Réplica CPU de las olas para saber si la cámara está bajo la superficie (con oleaje, no el radio base).
func _setup_water_sampler() -> void:
	if _planet == null or not _planet.has_water or _water_mat == null:
		return
	_base_water_radius = _planet.radius - _planet.water_radius
	_water_sampler = WaterHeightSampler.new()
	add_child(_water_sampler)
	_water_sampler.setup(_water_mat)


## Crea el gestor de partículas de precipitación, que sigue al jugador.
func _setup_fx() -> void:
	if _player == null:
		return
	_fx = WeatherFX.new()
	_fx.name = "WeatherFX"
	add_child(_fx)
	_fx.setup(_player, _planet_center, _sun)


## Crea la luz auxiliar del destello: DirectionalLight3D radial hacia abajo, con sombras, apagada por defecto.
func _setup_lightning_light() -> void:
	_aux_light = DirectionalLight3D.new()
	_aux_light.name = "LightningFlashLight"
	_aux_light.visible = false
	_aux_light.light_energy = 0.0
	_aux_light.light_color = Color(0.9, 0.95, 1.0)
	_aux_light.shadow_enabled = true
	if _sun != null:
		_aux_light.shadow_opacity = _sun.shadow_opacity
	add_child(_aux_light)


func _process(delta: float) -> void:
	if not _ready_to_run:
		return

	# Con el calendario acelerado los eventos duran proporcionalmente menos: el tiempo sigue a la
	# estación. La transición se acorta igual, sin bajar de MIN_TRANSITION_TIME.
	var speed := _calendar_speed()
	_elapsed += delta * speed
	# Antes de aplicar nada: el estado sumergido apaga precipitación y niebla de este frame.
	_update_submersion()
	var st: WeatherState = _to
	_resolved = st
	if _blend < 1.0:
		var transition := maxf(transition_time / speed, minf(transition_time, MIN_TRANSITION_TIME))
		_blend = minf(1.0, _blend + delta / maxf(transition, 0.01))
		st = WeatherState.blend(_from, _to, smoothstep(0.0, 1.0, _blend))
		_resolved = st
		_apply_state(st)
	else:
		_apply_precipitation(_to)

	_update_sky_light(delta, st)
	_update_lightning(delta, st)
	_update_fog_occlusion()

	if _forced:
		return

	if _blend >= 1.0:
		var profile := _active_profile()
		if _elapsed >= _duration or not _profile_has(profile, _current):
			_transition_to(_choose_from(profile, _current))


## Velocidad del calendario (1 = normal). Más lento que el normal no frena el tiempo.
func _calendar_speed() -> float:
	if _calendar == null or not is_instance_valid(_calendar):
		_calendar = get_tree().get_first_node_in_group("sun_controller")
	if _calendar == null:
		return 1.0
	return maxf(float(_calendar.get("season_speed")), 1.0)


## Vuelve a sortear el evento con la estación de ahora (tras un salto del calendario). No toca un
## evento forzado.
func reroll() -> void:
	if not _ready_to_run or _forced:
		return
	_transition_to(_choose_from(_active_profile(), ""))


## Fuerza un evento por nombre (para testeo o eventos de juego).
func set_weather(event_name: String) -> void:
	if not _events.has(event_name):
		push_warning("WeatherController: evento desconocido '%s'" % event_name)
		return
	_transition_to(event_name)


## Fuerza un evento y bloquea la máquina de estados (no auto-transiciona) hasta clear_force().
func force_weather(event_name: String) -> void:
	if not _events.has(event_name):
		push_warning("WeatherController: evento forzado desconocido '%s'" % event_name)
		return
	if not _ready_to_run:
		push_warning("WeatherController: no se puede forzar clima con el sistema deshabilitado.")
		return
	_forced = true
	_transition_to(event_name)


## Suelta el override y devuelve el control al sistema automático.
func clear_force() -> void:
	if not _forced:
		return
	_forced = false
	_elapsed = _duration


func is_forced() -> bool:
	return _forced


## Altitud del jugador sobre el radio del planeta. La usa el audio para que en una cima sople
## viento aunque el parte este tendido.
func get_player_altitude() -> float:
	return _current_altitude()


## Clima aplicado ahora mismo, con la transicion ya resuelta.
func get_resolved_state() -> WeatherState:
	return _resolved if _resolved != null else _to


## True con techo encima (cueva, voladizo, interior). Sale del mismo barrido de oclusion que
## decide si te caen gotas encima.
func is_sheltered() -> bool:
	if _fx == null or not is_instance_valid(_fx):
		return false
	var field := _fx.get_occlusion_field()
	return field != null and field.player_occluded


func get_current_weather_name() -> String:
	return _current


func get_current_biome() -> int:
	return _current_biome


func get_event_names() -> Array:
	return _events.keys()


## Serializa el estado climático actual para el guardado de partida.
func get_save_data() -> Dictionary:
	return {
		"current": _current,
		"elapsed": _elapsed,
		"duration": _duration,
		"forced": _forced,
	}


## Restablece un estado climático guardado saltando directo al evento, sin transición.
func restore_save_data(data: Dictionary) -> void:
	if not _ready_to_run:
		return
	var event_name := str(data.get("current", _current))
	if not _events.has(event_name):
		push_warning("WeatherController: evento guardado desconocido '%s'; conservo el actual." % event_name)
		return
	_current = event_name
	_forced = bool(data.get("forced", false))
	_to = _events[event_name]
	_from = _to
	_blend = 1.0
	_elapsed = float(data.get("elapsed", _elapsed))
	_duration = float(data.get("duration", _duration))
	_apply_state(_to)


func _transition_to(event_name: String) -> void:
	_from = _to
	_to = _events.get(event_name, _fallback_state())
	print("[WEATHER]: Transitioning to [", event_name, "]")
	_current = event_name
	_blend = 0.0
	_elapsed = 0.0
	_duration = randf_range(min_duration, max_duration)


func _current_latitude() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var up := _player.global_position - _planet_center
	if up.length_squared() < 0.0001:
		return 0.0
	up = up.normalized()
	return rad_to_deg(asin(clampf(up.y, -1.0, 1.0)))


func _current_altitude() -> float:
	if _player == null or not is_instance_valid(_player) or _planet == null:
		return 0.0
	return (_player.global_position - _planet_center).length() - _planet.radius


## Cobertura de nubes EFECTIVA sobre el jugador: la global del evento modulada por la
## envolvente de agrupación (la MISMA Image que muestrea el shader, vía consulta CPU sin
## readback). Con cloud_group_strength = 0 la envolvente es 1 → cobertura global clásica.
func _local_cloud_coverage(st: WeatherState) -> float:
	var cov := st.cloud_coverage
	if _atmosphere != null and _player != null and is_instance_valid(_player):
		cov *= _atmosphere.get_cloud_group_envelope(_player.global_position)
	return cov


## Factor 0..1 de precipitación por altitud: 1 bajo la base de nubes, 0 por encima de su cima.
func _below_clouds_factor(st: WeatherState) -> float:
	var top := maxf(st.cloud_max_height, st.cloud_min_height + 1.0)
	return 1.0 - smoothstep(st.cloud_min_height, top, _current_altitude())


## Mapea la latitud al índice de bioma usando biome_latitude_ranges.
func _biome_for_latitude(lat: float) -> int:
	if _biome_count <= 0 or _biome_latitude_ranges.size() < _biome_count + 1:
		return 0
	for i in _biome_count:
		if lat >= _biome_latitude_ranges[i] and lat <= _biome_latitude_ranges[i + 1]:
			return i
	return 0 if lat < float(_biome_latitude_ranges[0]) else _biome_count - 1


## Perfil de eventos activo: el del sitio (_place_profile) con los pesos de la estación.
func _active_profile() -> Array:
	return _seasonal(_place_profile())


## Perfil de eventos según bioma y altitud (frío al subir, nieve en picos). Con clima frío manda el
## campo de frío del planeta, con el de la estación: la taiga refuerza la nieve y la niebla, y la
## tundra y el casquete (polos y cumbres) usan el perfil de picos. En invierno ese frío llega más
## cerca del ecuador.
func _place_profile() -> Array:
	_current_biome = _biome_for_latitude(_current_latitude())
	var base: Array = _profile_for_biome(_current_biome)
	var alt := _current_altitude()
	if alt >= snow_altitude:
		return _peaks_profile
	if _planet != null and _planet.climate.enabled and _player != null and is_instance_valid(_player):
		var climate: ClimateField = _planet.climate
		match climate.zone(climate.snow_coldness(_player.global_position - _planet_center)):
			ClimateField.Zone.TUNDRA, ClimateField.Zone.ICE:
				return _peaks_profile
			ClimateField.Zone.TAIGA:
				return _boost_cold(base)
	if alt >= cold_altitude:
		return _boost_cold(base)
	return base


## 0..1: cuánto de la precipitación cae como nieve sobre el jugador (0 en tierra templada).
func _cold_precipitation() -> float:
	if _planet == null or not _planet.climate.enabled or _player == null or not is_instance_valid(_player):
		return 0.0
	var climate: ClimateField = _planet.climate
	var cold := climate.snow_coldness(_player.global_position - _planet_center)
	return smoothstep(climate.snow_start - 3.0, climate.snow_start + 3.0, cold)


## Copia del perfil con los pesos de la estación del jugador, entre las dos estaciones más cercanas.
## En el ecuador (sin estaciones) no cambia.
func _seasonal(profile: Array) -> Array:
	if not Seasons.enabled or _player == null or not is_instance_valid(_player):
		return profile
	var local := _player.global_position - _planet_center
	var strength := Seasons.strength(local)
	if strength <= 0.0:
		return profile
	var blend: Array = Seasons.blend(local)
	var first: Dictionary = _season_weights.get(Seasons.KEYS[blend[0]], {})
	var second: Dictionary = _season_weights.get(Seasons.KEYS[blend[1]], {})
	var result: Array = []
	for entry in profile:
		var factor := lerpf(float(first.get(entry[0], 1.0)), float(second.get(entry[0], 1.0)), blend[2])
		result.append([entry[0], float(entry[1]) * lerpf(1.0, factor, strength)])
	return result


## Copia del perfil con los eventos de _cold_boost reforzados para zonas altas frías.
func _boost_cold(base: Array) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for entry in base:
		var ev_name: String = entry[0]
		var weight: float = float(entry[1])
		if _cold_boost.has(ev_name):
			weight += float(_cold_boost[ev_name])
		result.append([ev_name, weight])
		seen[ev_name] = true
	for ev_name in _cold_boost:
		if not seen.has(ev_name):
			result.append([ev_name, float(_cold_boost[ev_name])])
	return result


func _profile_for_biome(biome_idx: int) -> Array:
	return _profiles_by_biome.get(biome_idx, PROFILE_FALLBACK)


func _profile_has(profile: Array, event_name: String) -> bool:
	for entry in profile:
		if entry[0] == event_name and _events.has(event_name) and float(entry[1]) > 0.0:
			return true
	return false


## Sorteo por probabilidad dentro de un perfil (normaliza por el total), evitando 'exclude' si puede.
func _choose_from(profile: Array, exclude: String) -> String:
	var valid: Array = []
	for entry in profile:
		if _events.has(entry[0]) and float(entry[1]) > 0.0:
			valid.append(entry)
	if valid.is_empty():
		return _fallback_event()

	var pool: Array = valid
	if exclude != "":
		var filtered := valid.filter(func(e): return e[0] != exclude)
		if not filtered.is_empty():
			pool = filtered

	var total := 0.0
	for entry in pool:
		total += float(entry[1])
	var r := randf() * total
	for entry in pool:
		r -= float(entry[1])
		if r <= 0.0:
			return entry[0]
	return pool[0][0]


func _fallback_event() -> String:
	if _events.has("clear"):
		return "clear"
	if not _events.is_empty():
		return _events.keys()[0]
	return "clear"


func _fallback_state() -> WeatherState:
	if not _events.is_empty():
		return _events[_fallback_event()]
	return WeatherState.new()


## Difunde un WeatherState a atmósfera, sol/ambiente, vegetación, terreno y agua.
func _apply_state(st: WeatherState) -> void:
	if _atmosphere:
		_atmosphere.clouds_enabled = true
		_atmosphere.cloud_coverage = st.cloud_coverage
		_atmosphere.cloud_density = st.cloud_density
		_atmosphere.cloud_absorption = clampf(st.cloud_absorption, 0.01, 1.0)
		_atmosphere.cloud_shadow_strength = st.cloud_shadow
		_atmosphere.cloud_albedo = clampf(st.cloud_albedo, 0.0, 1.0)
		_atmosphere.atmosphere_scatter = clampf(st.atmosphere_scatter, 0.0, 1.0)
		_atmosphere.set_god_ray_weather(st.god_ray_strength, st.god_ray_reach)
		_atmosphere.cloud_min_height = st.cloud_min_height
		_atmosphere.cloud_max_height = maxf(st.cloud_max_height, st.cloud_min_height + 1.0)
		_atmosphere.cloud_wind_speed = st.cloud_wind_speed
		_active_fog_density = st.fog_density
		_atmosphere.fog_density = st.fog_density
		_atmosphere.fog_coverage = st.fog_coverage
		_atmosphere.fog_group_strength = clampf(st.fog_group, 0.0, 1.0)
		_atmosphere.fog_wind_speed = st.fog_wind_speed
		_atmosphere.fog_floor_height = st.fog_floor_height
		_atmosphere.fog_top_height = maxf(st.fog_top_height, st.fog_floor_height + 1.0)

	if _planet:
		_planet.weather_wind_multiplier = st.wind_multiplier
		# Nieve reciente: la nevada, y en tierra fría también la precipitación del temporal, que
		# allí cae como nieve. Baja la cota de nieve del suelo, los árboles y las rocas.
		_planet.climate.set_fresh_snow(maxf(st.snow_coverage, _cold_precipitation() * clampf(st.rain_rate, 0.0, 1.0)))

	if _water_mat:
		_water_mat.set_shader_parameter("wave_amplitude", _base_wave_amplitude * st.water_wave_multiplier)
		_water_mat.set_shader_parameter("wave_speed", _base_wave_speed * st.water_speed_multiplier)
		_water_mat.set_shader_parameter("wave_base_length", _base_wave_length * st.water_wave_length_mult)
		_water_mat.set_shader_parameter("foam_crest_amount", _base_foam_crest * st.water_foam_multiplier)
		_water_mat.set_shader_parameter("wave_steepness", st.water_steepness)
		# Estado de calma al que vuelve el agua fuera de mar abierto. La máscara de temporal
		# (gerstner_waves.gdshaderinc) mezcla entre este y el de arriba según dónde esté cada punto,
		# así un lago o la orilla no reciben el oleaje del temporal.
		_water_mat.set_shader_parameter("wave_calm_amplitude", _calm_wave_amplitude)
		_water_mat.set_shader_parameter("wave_calm_steepness", _calm_wave_steepness)
		# Rompiente. Va sin máscara, igual que wave_speed y wave_base_length: son los parámetros que
		# NO pueden variar por posición sin rajar la malla (cambian la fase entre vértices vecinos),
		# así que el temporal levanta la orilla de todo el planeta y no solo la del evento.
		# La amplitud efectiva la acota igual el límite de rompiente (H/L) del shader: por eso el
		# temporal sube también la longitud de onda, que es lo que sube ese techo.
		_water_mat.set_shader_parameter("shore_amplitude",
			_base_shore_amplitude * st.water_shore_multiplier)
		_water_mat.set_shader_parameter("shore_length",
			_base_shore_length * st.water_shore_length_mult)
		_water_mat.set_shader_parameter("shore_speed",
			_base_shore_speed * st.water_shore_speed_mult)
		# Por encima de 1 la ola de Gerstner se auto-interseca (Q·k·A > 1) y la cresta se pliega.
		_water_mat.set_shader_parameter("shore_steepness",
			clampf(_base_shore_steepness * st.water_shore_steepness_mult, 0.0, 0.95))

	_apply_precipitation(st)


## Oscurece sol y ambiente SOLO bajo la celda de nubes: el sol es una luz global, así que aplicar
## sun_energy/ambient_energy del evento tal cual pintaba de sombra el planeta entero, también en
## los claros de la agrupación. Mismo gate que lluvia y rayos, suavizado para que no salte al
## cruzar el borde de la celda. La sombra que de verdad proyecta cada nube la pone el compute.
func _update_sky_light(delta: float, st: WeatherState) -> void:
	var target := smoothstep(precip_cloud_start, precip_cloud_full, _local_cloud_coverage(st))
	if _shade < 0.0:
		_shade = target
	else:
		_shade = lerpf(_shade, target, 1.0 - exp(-delta * SHADE_SMOOTH_RATE))

	var sun_scale := lerpf(1.0, st.sun_energy, _shade)
	var ambient_scale := lerpf(1.0, st.ambient_energy, _shade)
	# Con SkyLighting las luces las gobierna él (hora, luna, exposición): el clima solo le pasa sus
	# escalas, y él las aplica también a los uniforms globales que leen el agua y los impostores.
	if _sky_lighting == null or not is_instance_valid(_sky_lighting):
		_sky_lighting = get_tree().get_first_node_in_group(SkyLighting.GROUP) as SkyLighting
	if _sky_lighting != null:
		_sky_lighting.set_weather_scales(sun_scale, ambient_scale, _shade, get_parent())
		return
	if _sun:
		_sun.light_energy = _base_sun_energy * sun_scale
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_energy = _base_ambient_energy * ambient_scale


## Marca si la CÁMARA (no el jugador: en tercera persona se sumergen por separado) está bajo la
## superficie del agua, olas incluidas. Ni la lluvia ni la niebla del compute se recortan solas
## contra el agua, así que este es el interruptor que las apaga buceando.
func _update_submersion() -> void:
	if _water_sampler == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return
	var pos := cam.global_position
	var wave_time := WaterHeightSampler.get_water_time(_water_mat)
	var surface_r := _base_water_radius + _water_sampler.get_height_at(pos, wave_time, _planet_center)
	_camera_submerged = pos.distance_to(_planet_center) < surface_r


## Ajusta la intensidad de lluvia/nieve según sus rates, la altitud y la cobertura de nubes.
func _apply_precipitation(st: WeatherState) -> void:
	if _fx == null:
		return
	_fx.set_submerged(_camera_submerged)
	var below := _below_clouds_factor(st)
	# Cobertura LOCAL: en una celda despejada de la agrupación no llueve aunque el evento
	# global sea una tormenta; el umbral precip_cloud_start/full ya hace el resto.
	var cloud_factor := smoothstep(precip_cloud_start, precip_cloud_full, _local_cloud_coverage(st))
	var gate := below * cloud_factor
	# En tierra fría la lluvia del temporal cae como nieve.
	var cold := _cold_precipitation()
	_fx.set_intensity("rain", st.rain_rate * gate * (1.0 - cold))
	_fx.set_intensity("snow", maxf(st.snow_rate, st.rain_rate * cold) * gate)


## Avanza el generador de rayos y aplica el destello del frame; emite lightning_struck al iniciar la descarga.
func _update_lightning(delta: float, st: WeatherState) -> void:
	if _lightning == null or not lightning_enabled:
		return
	# Mismo gate que la precipitación: en una celda despejada de la agrupación no arrancan
	# rayos nuevos (un destello ya en curso se extingue solo por su envolvente).
	var cloud_factor := smoothstep(precip_cloud_start, precip_cloud_full, _local_cloud_coverage(st))
	var flash := _lightning.update(delta, st.lightning_frequency * cloud_factor, _below_clouds_factor(st))
	if _lightning.strike_started:
		lightning_struck.emit()
	_apply_flash(flash)


## Aplica el destello del rayo a la luz auxiliar (superficies de escena) y a las nubes del compute (uniform).
func _apply_flash(flash: float) -> void:
	if _aux_light != null:
		if _aux_light.visible != (flash > 0.0):
			DebugStats.report_event(&"clima:rayo_on" if flash > 0.0 else &"clima:rayo_off")
		if flash > 0.0:
			if _aux_light.shadow_enabled:
				DebugStats.report_event(&"clima:rayo_sombras")
			if _player != null and is_instance_valid(_player):
				var up := _player.global_position - _planet_center
				up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
				var ref := Vector3.FORWARD
				if absf(up.dot(ref)) > 0.99:
					ref = Vector3.RIGHT
				var x := ref.cross(up).normalized()
				var y := up.cross(x).normalized()
				_aux_light.global_transform = Transform3D(Basis(x, y, up), _player.global_position)
			_aux_light.light_energy = flash * lightning_flash_strength
			_aux_light.visible = true
		else:
			_aux_light.visible = false

	if _atmosphere != null:
		_atmosphere.lightning_flash = flash


## Empuja al shader de atmósfera la rejilla de oclusión para que la niebla no entre en cuevas.
func _update_fog_occlusion() -> void:
	if _fx == null:
		return
	var fog_on := fog_cave_occlusion_enabled and _active_fog_density > 0.001 and not _camera_submerged
	_fx.field_force_active = fog_on
	if _atmosphere == null:
		return
	# Bajo el agua la niebla se apaga entera: el compute es POST_TRANSPARENT y la pintaría encima
	# de la vista submarina (la profundidad que escribe el quad de agua no la recorta).
	_atmosphere.fog_density = 0.0 if _camera_submerged else _active_fog_density
	var field := _fx.get_occlusion_field()
	if field == null:
		return
	_atmosphere.set_fog_occlusion(
		fog_on,
		field.center, field.x_axis, field.z_axis, field.up,
		field.half_size(), field.span(), field.probe_below,
		field.get_height_texture())


## Construye _events: eventos internos por defecto + catálogo JSON + overrides del planeta.
func _build_events(config: Dictionary) -> void:
	_events = _builtin_events()

	var path := str(config.get("events_file", DEFAULT_EVENTS_FILE))
	_merge_event_dict(_load_events_catalog(path))

	var presets: Dictionary = config.get("presets", {})
	if presets is Dictionary:
		_merge_event_dict(presets)


## Mezcla un diccionario {nombre: {campos}} en _events, actualizando existentes y creando nuevos.
func _merge_event_dict(events: Dictionary) -> void:
	for ev_name in events:
		if not (events[ev_name] is Dictionary):
			continue
		var s: WeatherState = _events.get(ev_name, WeatherState.new())
		s.apply_overrides(events[ev_name])
		_events[ev_name] = s


func _load_events_catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("WeatherController: catálogo de eventos no encontrado en '%s'; uso los internos." % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary and data.has("events") and data["events"] is Dictionary:
		return data["events"]
	if data is Dictionary:
		return data
	push_warning("WeatherController: catálogo de eventos con formato inválido en '%s'." % path)
	return {}


## Construye _profiles_by_biome: un perfil por bioma, sobrescribible desde weather_settings.biome_profiles.
func _build_biome_profiles(config: Dictionary) -> void:
	_profiles_by_biome.clear()
	for i in maxi(_biome_count, 1):
		_profiles_by_biome[i] = _default_profile_for_biome(i)

	var overrides: Dictionary = config.get("biome_profiles", {})
	for key in overrides:
		var idx := int(str(key))
		var parsed := _parse_profile(overrides[key])
		if not parsed.is_empty():
			_profiles_by_biome[idx] = parsed

	for idx in _profiles_by_biome:
		_warn_if_not_1(idx, _profiles_by_biome[idx])


## Avisa si las probabilidades de un perfil no suman ~1.0.
func _warn_if_not_1(idx, profile: Array) -> void:
	var total := 0.0
	for entry in profile:
		total += float(entry[1])
	if absf(total - 1.0) > 0.01:
		push_warning("WeatherController: las probabilidades del bioma %s suman %.2f, no 1.0 (se normalizan igual, pero revisa)." % [str(idx), total])


## Perfil por defecto de un bioma según la latitud central de su banda.
func _default_profile_for_biome(i: int) -> Array:
	if _biome_latitude_ranges.size() < i + 2:
		return PROFILE_TEMPERATE
	var center: float = (float(_biome_latitude_ranges[i]) + float(_biome_latitude_ranges[i + 1])) * 0.5
	var a := absf(center)
	if a >= snowy_latitude:
		return PROFILE_SNOWY
	if a <= tropical_latitude:
		return PROFILE_TROPICAL
	return PROFILE_TEMPERATE


## Convierte una lista del JSON en perfil [[nombre, probabilidad], ...]. Acepta las claves chance/percent/weight.
func _parse_profile(raw) -> Array:
	var profile: Array = []
	if not (raw is Array):
		return profile
	for entry in raw:
		var name := ""
		var chance := 1.0
		if entry is Dictionary:
			name = str(entry.get("weather", entry.get("event", "")))
			chance = float(entry.get("chance", entry.get("percent", entry.get("weight", 1.0))))
		elif entry is Array and entry.size() >= 1:
			name = str(entry[0])
			chance = float(entry[1]) if entry.size() >= 2 else 1.0
		if name != "" and chance > 0.0:
			profile.append([name, chance])
	return profile


## Eventos climáticos internos por defecto (fallback si falta el catálogo JSON).
func _builtin_events() -> Dictionary:
	return {
		"clear": _state({
			"cloud_coverage": 0.25, "cloud_density": 0.35, "cloud_absorption": 0.12,
			"cloud_shadow": 0.5, "cloud_min_height": 600.0, "cloud_max_height": 900.0,
			"cloud_wind_speed": 0.025, "sun_energy": 1.0, "ambient_energy": 1.0,
			"wind_multiplier": 0.6, "water_wave_multiplier": 0.4,
			"water_speed_multiplier": 0.8, "water_foam_multiplier": 0.4,
			"water_steepness": 0.25, "water_wave_length_mult": 1.0,
		}),
		"storm": _state({
			"cloud_coverage": 0.9, "cloud_density": 1.6, "cloud_absorption": 0.4,
			"cloud_albedo": 0.35,
			"cloud_shadow": 1.0, "cloud_min_height": 300.0, "cloud_max_height": 800.0,
			"cloud_wind_speed": 0.06, "sun_energy": 0.3, "ambient_energy": 0.5,
			"atmosphere_scatter": 0.15,
			"god_ray_strength": 1.2, "god_ray_reach": 0.4,
			"wind_multiplier": 2.4, "water_wave_multiplier": 2.2,
			"water_speed_multiplier": 1.7, "water_foam_multiplier": 2.5,
			"water_steepness": 0.9, "water_wave_length_mult": 1.6,
			"rain_rate": 1.0, "lightning_frequency": 0.15,
			"fog_density": 0.5, "fog_coverage": 0.45, "fog_group": 1.0, "fog_wind_speed": 0.05,
			"fog_floor_height": 0.0, "fog_top_height": 90.0,
		}),
		"snow": _state({
			"cloud_coverage": 0.75, "cloud_density": 0.9, "cloud_absorption": 0.28,
			"cloud_albedo": 0.7,
			"cloud_shadow": 0.8, "cloud_min_height": 350.0, "cloud_max_height": 700.0,
			"cloud_wind_speed": 0.04, "sun_energy": 0.7, "ambient_energy": 0.8,
			"atmosphere_scatter": 0.5,
			"god_ray_strength": 1.6, "god_ray_reach": 0.5,
			"wind_multiplier": 1.3, "snow_coverage": 1.0, "snow_rate": 1.0,
			"water_wave_multiplier": 0.5, "water_speed_multiplier": 0.8,
			"water_foam_multiplier": 0.5, "water_steepness": 0.3, "water_wave_length_mult": 1.0,
			"fog_density": 0.6, "fog_coverage": 0.5, "fog_wind_speed": 0.03,
			"fog_floor_height": 0.0, "fog_top_height": 120.0,
		}),
		"wind": _state({
			"cloud_coverage": 0.45, "cloud_density": 0.5, "cloud_absorption": 0.14,
			"cloud_shadow": 0.6, "cloud_min_height": 500.0, "cloud_max_height": 850.0,
			"cloud_wind_speed": 0.1, "sun_energy": 0.9, "ambient_energy": 0.95,
			"god_ray_strength": 0.85, "god_ray_reach": 1.25,
			"wind_multiplier": 3.2, "water_wave_multiplier": 1.6,
			"water_speed_multiplier": 1.7, "water_foam_multiplier": 1.7,
			"water_steepness": 0.7, "water_wave_length_mult": 1.3,
		}),
		"fog": _state({
			"cloud_coverage": 0.35, "cloud_density": 0.4, "cloud_absorption": 0.16,
			"cloud_albedo": 0.8,
			"cloud_shadow": 0.3, "cloud_min_height": 500.0, "cloud_max_height": 800.0,
			"cloud_wind_speed": 0.03, "sun_energy": 0.6, "ambient_energy": 0.8,
			"atmosphere_scatter": 0.5,
			"god_ray_strength": 2.4, "god_ray_reach": 0.25,
			"wind_multiplier": 0.5, "water_wave_multiplier": 0.3,
			"water_speed_multiplier": 0.6, "water_foam_multiplier": 0.3,
			"water_steepness": 0.2, "water_wave_length_mult": 0.9,
			"fog_density": 1.0, "fog_coverage": 0.62, "fog_wind_speed": 0.025,
			"fog_floor_height": 0.0, "fog_top_height": 160.0,
		}),
	}


func _state(fields: Dictionary) -> WeatherState:
	var s := WeatherState.new()
	s.apply_overrides(fields)
	return s
