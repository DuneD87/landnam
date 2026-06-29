class_name WeatherController
extends Node

## Cerebro del sistema meteorológico (Fase 1).
##
## Los EVENTOS climáticos son data-driven: se definen por nombre en un catálogo JSON
## compartido (data/weather/weather_events.json) y no hay enum fijo. Puedes inventar
## eventos nuevos ('blizzard', 'heatwave'...) solo en JSON y referenciarlos por nombre
## en los biome_profiles del planeta, sin tocar código. Si el catálogo falta, se usan
## los eventos internos por defecto (_builtin_events) como red de seguridad.
##
## El controlador elige el evento según el BIOMA en el que está el jugador (la latitud
## se mapea a un índice de bioma con biome_latitude_ranges, igual que el shader de
## terreno) y según su ALTITUD (zonas altas se enfrían; los picos se cubren de nieve).
## Cada bioma tiene un perfil de eventos permitidos con pesos, configurable en el JSON
## del planeta. Interpola suavemente entre el evento actual y el siguiente, y cada frame
## difunde el estado resuelto a:
##   - la atmósfera (nubes: cobertura/densidad/sombra/altura; niebla: capa baja dedicada),
##   - el sol y el ambiente (oscurecimiento),
##   - la vegetación (multiplicador de viento),
##   - el agua (oleaje y espuma),
##   - el terreno (nieve por fragmento, vía uniforms del shader planet_biomes).
##
## La niebla es una capa volumétrica baja propia (fog_density/fog_coverage en el shader
## de atmósfera): pegada al suelo y modulada por ruido de gran escala advectado por el
## viento, de modo que el banco "llega de lejos" en vez de verse bajar las nubes.
##
## Fase 2: partículas de lluvia/nieve con gravedad radial (WeatherFX, alimentado por
## rain_rate/snow_rate). Pendiente aún: flashes de rayo + trueno (lightning_frequency).

const DEFAULT_EVENTS_FILE := "res://data/weather/weather_events.json"

# Perfiles por defecto (lista de [nombre_evento, peso]) según el carácter del bioma. Se
# usan cuando el JSON del planeta no define un perfil para ese índice de bioma. La
# asignación se deriva de la latitud central de la banda del bioma, sobrescribible por
# índice desde weather_settings.biome_profiles.
const PROFILE_SNOWY := [["snow", 3.0], ["storm", 1.0], ["fog", 1.0], ["clear", 1.0]]
const PROFILE_TEMPERATE := [["clear", 2.0], ["storm", 2.0], ["wind", 1.0], ["fog", 1.0]]
const PROFILE_TROPICAL := [["clear", 3.0], ["wind", 2.0], ["storm", 1.0]]
const PROFILE_FALLBACK := [["clear", 3.0], ["storm", 1.0], ["wind", 1.0], ["fog", 1.0]]
# Perfil de alta montaña (>= snow_altitude): la nieve domina sea cual sea el bioma.
const DEFAULT_PEAKS_PROFILE := [["snow", 4.0], ["fog", 1.5], ["storm", 1.0]]
# Refuerzo de frío (entre cold_altitude y snow_altitude): peso extra a estos eventos.
const DEFAULT_COLD_BOOST := {"snow": 2.0, "fog": 1.0}

@export var enabled: bool = true
@export var min_duration: float = 60.0
@export var max_duration: float = 180.0
@export var transition_time: float = 30.0
## Umbrales (latitud absoluta del centro del bioma) para elegir el perfil POR DEFECTO
## de cada bioma. Solo afectan a biomas sin perfil propio en el JSON.
@export var snowy_latitude: float = 55.0
@export var tropical_latitude: float = 25.0
## Altitud (m sobre el nivel base del terreno) a partir de la cual el clima se enfría
## (más nieve/niebla) y, por encima de snow_altitude, la nieve domina como en un pico.
@export var cold_altitude: float = 1500.0
@export var snow_altitude: float = 3500.0

## --- Oclusión de niebla en cuevas ---
## La niebla no se rellena dentro de las cuevas: el shader de atmósfera muestrea la rejilla de
## oclusión del WeatherFX (R = altura del techo) por punto de marcha y descarta la niebla bajo
## techo. Es espacialmente exacto (a diferencia de un fundido global), así que las bocas de cueva
## quedan limpias. El coste es mantener la rejilla viva durante la niebla (raycasts del WeatherFX).
@export var fog_cave_occlusion_enabled: bool = true

# --- Refs a subsistemas (inyectadas por setup) ---
var _planet: Planet
var _ocean: OceanSystem
var _atmosphere: PlanetAtmosphere
var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _player: Node3D
var _planet_center: Vector3

# --- Efectos de precipitación (lluvia/nieve, partículas) ---
var _fx: WeatherFX

func set_planet_center(c: Vector3) -> void:
	_planet_center = c
	if _fx != null:
		# on_origin_shift refresca el centro del FX y reinicia las partículas (viven en mundo,
		# así que tras un rebase las ya emitidas quedarían desplazadas).
		_fx.on_origin_shift(c)

# --- Datos de biomas (copiados del planeta) ---
var _biome_count: int = 0
var _biome_latitude_ranges: Array = []
var _profiles_by_biome: Dictionary = {}   # biome_index:int -> Array[[nombre, peso]]

# --- Reglas de altitud (configurables; defaults arriba) ---
var _peaks_profile: Array = DEFAULT_PEAKS_PROFILE
var _cold_boost: Dictionary = DEFAULT_COLD_BOOST

# --- Valores base leídos al iniciar (las modulaciones son relativas a estos) ---
var _base_sun_energy: float = 1.0
var _base_ambient_energy: float = 1.0
var _base_wave_amplitude: float = 4.0
var _base_wave_speed: float = 1.2
var _base_foam_crest: float = 1.1
var _water_mat: ShaderMaterial

# --- Catálogo de eventos y máquina de estados ---
var _events: Dictionary = {}           # nombre:String -> WeatherState
var _from: WeatherState
var _to: WeatherState
var _blend: float = 1.0
var _elapsed: float = 0.0
var _duration: float = 120.0
var _current: String = "clear"
var _current_biome: int = 0
var _ready_to_run: bool = false
var _forced: bool = false   # override de depuración: clima fijo, sin auto-transiciones

# --- Oclusión de niebla en cuevas ---
var _active_fog_density: float = 0.0 # densidad de niebla del estado actual (para saber si hay niebla)


## Inyecta dependencias y arranca. Llamado por planet_loader tras cargar el planeta.
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
	_build_biome_profiles(config)
	_push_snow_line_params()
	_setup_fx()

	# Estado inicial coherente con el bioma y la altitud actuales del jugador.
	_current = _choose_from(_active_profile(), "")
	_to = _events.get(_current, _fallback_state())
	_from = _to
	_blend = 1.0
	_elapsed = 0.0
	_duration = randf_range(min_duration, max_duration)

	_ready_to_run = enabled
	if enabled:
		_apply_state(_to)
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

	# Reglas de altitud configurables (qué eventos dominan en picos / se refuerzan en frío).
	var peaks := _parse_profile(config.get("peaks_profile", []))
	if not peaks.is_empty():
		_peaks_profile = peaks
	if config.has("cold_boost") and config["cold_boost"] is Dictionary:
		_cold_boost = config["cold_boost"]


func _read_base_values() -> void:
	if _sun:
		_base_sun_energy = _sun.light_energy
	if _world_env and _world_env.environment:
		_base_ambient_energy = _world_env.environment.ambient_light_energy
	if _ocean and _ocean.quadtree_material is ShaderMaterial:
		_water_mat = _ocean.quadtree_material as ShaderMaterial
		var wa: Variant = _water_mat.get_shader_parameter("wave_amplitude")
		var ws: Variant = _water_mat.get_shader_parameter("wave_speed")
		var fc: Variant = _water_mat.get_shader_parameter("foam_crest_amount")
		if wa != null: _base_wave_amplitude = wa
		if ws != null: _base_wave_speed = ws
		if fc != null: _base_foam_crest = fc


## Empuja (una sola vez) la línea de nieve del shader de terreno desde la misma config
## de clima, para que la nieve por fragmento cuaje en las latitudes/altitudes coherentes.
func _push_snow_line_params() -> void:
	if _planet == null or _planet.shader_material == null:
		return
	var sm := _planet.shader_material
	sm.set_shader_parameter("weather_snow_latitude_full", snowy_latitude)
	sm.set_shader_parameter("weather_snow_latitude_start", maxf(snowy_latitude - 20.0, 0.0))
	sm.set_shader_parameter("weather_snow_altitude_start", cold_altitude)
	sm.set_shader_parameter("weather_snow_altitude_full", snow_altitude)


## Crea el gestor de partículas de precipitación. Sigue al jugador y necesita el centro del
## planeta para que la "gravedad" de las gotas/copos apunte radialmente al suelo.
func _setup_fx() -> void:
	if _player == null:
		return
	_fx = WeatherFX.new()
	_fx.name = "WeatherFX"
	add_child(_fx)
	_fx.setup(_player, _planet_center, _sun)


func _process(delta: float) -> void:
	if not _ready_to_run:
		return

	_elapsed += delta
	if _blend < 1.0:
		# En transición: interpolar y empujar el estado COMPLETO (atmósfera/sol/agua/...) cada
		# frame, porque todos los campos se están moviendo.
		_blend = minf(1.0, _blend + delta / maxf(transition_time, 0.01))
		var st := WeatherState.blend(_from, _to, smoothstep(0.0, 1.0, _blend))
		_apply_state(st)
	else:
		# Estado estable: los uniforms de atmósfera/sol/agua/terreno ya quedaron fijados en el
		# último frame de la transición y no cambian. Solo la precipitación varía (depende de la
		# altitud del jugador), así que evitamos re-empujar ~25 uniforms y asignar un WeatherState.
		_apply_precipitation(_to)

	# La rejilla de oclusión sigue al jugador, así que su transform se empuja a la atmósfera cada
	# frame mientras haya niebla (independiente del estado de transición).
	_update_fog_occlusion()

	# Con un clima forzado (override de editor/depuración) no auto-transicionamos: el blend
	# hacia el evento forzado sigue corriendo, pero no se elige uno nuevo hasta soltarlo.
	if _forced:
		return

	# Solo decidimos un cambio cuando la transición anterior terminó.
	if _blend >= 1.0:
		var profile := _active_profile()
		# Cambiamos si se cumplió la duración, o si el jugador entró en una zona (bioma
		# + altitud) donde el evento actual ya no está permitido (p.ej. bajar de la
		# montaña nevada, o salir de un bioma frío).
		if _elapsed >= _duration or not _profile_has(profile, _current):
			_transition_to(_choose_from(profile, _current))


# ── API pública ───────────────────────────────────────────────────────────────

## Fuerza un evento concreto por nombre (para testeo o eventos de juego).
func set_weather(event_name: String) -> void:
	if not _events.has(event_name):
		push_warning("WeatherController: evento desconocido '%s'" % event_name)
		return
	_transition_to(event_name)


## Fuerza un evento Y BLOQUEA la máquina de estados (no auto-transiciona) hasta clear_force().
## Pensado para el override de depuración del inspector. Requiere el sistema activo (enabled).
func force_weather(event_name: String) -> void:
	if not _events.has(event_name):
		push_warning("WeatherController: evento forzado desconocido '%s'" % event_name)
		return
	if not _ready_to_run:
		push_warning("WeatherController: no se puede forzar clima con el sistema deshabilitado.")
		return
	_forced = true
	_transition_to(event_name)


## Suelta el override y devuelve el control al sistema automático (re-evalúa bioma/altitud).
func clear_force() -> void:
	if not _forced:
		return
	_forced = false
	_elapsed = _duration   # fuerza una reselección natural en el próximo frame


func is_forced() -> bool:
	return _forced


func get_current_weather_name() -> String:
	return _current


func get_current_biome() -> int:
	return _current_biome


func get_event_names() -> Array:
	return _events.keys()


# ── Máquina de estados ──────────────────────────────────────────────────────────

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


## Factor 0..1 de precipitación según la altitud del jugador respecto a la capa de nubes:
## 1 bajo la base (la lluvia/nieve cae sobre ti), se desvanece al ascender por la capa y 0
## por encima de la cima (estás sobre las nubes de donde nace la precipitación). Usa las
## alturas del estado interpolado para que coincida con las nubes que se están dibujando.
func _below_clouds_factor(st: WeatherState) -> float:
	var top := maxf(st.cloud_max_height, st.cloud_min_height + 1.0)
	return 1.0 - smoothstep(st.cloud_min_height, top, _current_altitude())


## Mapea la latitud al índice de bioma usando biome_latitude_ranges (n+1 entradas para
## n biomas: el bioma i abarca [ranges[i], ranges[i+1]]).
func _biome_for_latitude(lat: float) -> int:
	if _biome_count <= 0 or _biome_latitude_ranges.size() < _biome_count + 1:
		return 0
	for i in _biome_count:
		if lat >= _biome_latitude_ranges[i] and lat <= _biome_latitude_ranges[i + 1]:
			return i
	# Fuera de rango: el polo más cercano.
	return 0 if lat < float(_biome_latitude_ranges[0]) else _biome_count - 1


## Perfil de eventos activo según el bioma Y la altitud del jugador. A nivel del mar es
## el perfil del bioma; al subir se enfría (más nieve/niebla) y en los picos
## (>= snow_altitude) domina la nieve sea cual sea el bioma.
func _active_profile() -> Array:
	_current_biome = _biome_for_latitude(_current_latitude())
	var base: Array = _profile_for_biome(_current_biome)
	var alt := _current_altitude()
	if alt >= snow_altitude:
		return _peaks_profile
	if alt >= cold_altitude:
		return _boost_cold(base)
	return base


## Copia del perfil con los eventos de _cold_boost reforzados: las zonas altas (entre
## cold_altitude y snow_altitude) son frías aunque el bioma sea cálido.
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
		if entry[0] == event_name and _events.has(event_name):
			return true
	return false


## Random ponderado dentro de un perfil, ignorando eventos no definidos en el catálogo
## y evitando 'exclude' si hay alternativa.
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


# ── Aplicación del estado a los subsistemas ─────────────────────────────────────

func _apply_state(st: WeatherState) -> void:
	# Atmósfera / nubes. La niebla = capa de nubes casi a ras de suelo.
	if _atmosphere:
		_atmosphere.clouds_enabled = true
		_atmosphere.cloud_coverage = st.cloud_coverage
		_atmosphere.cloud_density = st.cloud_density
		_atmosphere.cloud_absorption = clampf(st.cloud_absorption, 0.01, 1.0)
		_atmosphere.cloud_shadow_strength = st.cloud_shadow
		_atmosphere.cloud_min_height = st.cloud_min_height
		_atmosphere.cloud_max_height = maxf(st.cloud_max_height, st.cloud_min_height + 1.0)
		_atmosphere.cloud_wind_speed = st.cloud_wind_speed
		# Niebla a ras de suelo: capa baja dedicada. Solo modulamos densidad/cobertura;
		# la altura es fija en el atmósfera, así la niebla nunca "baja del cielo". La oclusión en
		# cuevas la hace el shader por punto (no atenuamos aquí); guardamos la densidad para saber
		# si hay niebla activa y mantener viva la rejilla de oclusión.
		_active_fog_density = st.fog_density
		_atmosphere.fog_density = st.fog_density
		_atmosphere.fog_coverage = st.fog_coverage
		_atmosphere.fog_wind_speed = st.fog_wind_speed
		_atmosphere.fog_floor_height = st.fog_floor_height
		_atmosphere.fog_top_height = maxf(st.fog_top_height, st.fog_floor_height + 1.0)

	# Sol + ambiente: el oscurecimiento de la tormenta.
	if _sun:
		_sun.light_energy = _base_sun_energy * st.sun_energy
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_energy = _base_ambient_energy * st.ambient_energy

	# Vegetación (planet._update_planet aplica el multiplicador) + terreno (nieve).
	if _planet:
		_planet.weather_wind_multiplier = st.wind_multiplier
		if _planet.shader_material:
			_planet.shader_material.set_shader_parameter("weather_snow_coverage", st.snow_coverage)

	# Agua: mar más picado y con más espuma en tormenta/viento.
	if _water_mat:
		_water_mat.set_shader_parameter("wave_amplitude", _base_wave_amplitude * st.water_wave_multiplier)
		_water_mat.set_shader_parameter("wave_speed", _base_wave_speed * st.water_speed_multiplier)
		_water_mat.set_shader_parameter("foam_crest_amount", _base_foam_crest * st.water_foam_multiplier)

	_apply_precipitation(st)


## Precipitación: partículas de lluvia/nieve moduladas por sus rates y por la altitud (no
## llueve/nieva por encima de la capa de nubes). El "techo sólido" sobre el jugador lo gestiona
## aparte WeatherFX por colisión. Se actualiza cada frame (incluso en estado estable) porque el
## factor de altitud cambia al moverse el jugador.
func _apply_precipitation(st: WeatherState) -> void:
	if _fx == null:
		return
	var below := _below_clouds_factor(st)
	_fx.set_intensity("rain", st.rain_rate * below)
	_fx.set_intensity("snow", st.snow_rate * below)


## Empuja al shader de atmósfera la rejilla de oclusión (transform + textura) para que la niebla no
## se rellene dentro de las cuevas. Solo se activa cuando hay niebla; entonces además fuerza al
## WeatherFX a mantener la rejilla reconstruyéndose (la rejilla normalmente solo vive con lluvia/nieve).
func _update_fog_occlusion() -> void:
	if _fx == null:
		return
	var fog_on := fog_cave_occlusion_enabled and _active_fog_density > 0.001
	_fx.field_force_active = fog_on
	if _atmosphere == null:
		return
	var field := _fx.get_occlusion_field()
	if field == null:
		return
	_atmosphere.set_fog_occlusion(
		fog_on,
		field.center, field.x_axis, field.z_axis, field.up,
		field.half_size(), field.span(), field.probe_below,
		field.get_height_texture())


# ── Catálogo de eventos ──────────────────────────────────────────────────────────

## Construye _events: arranca con los eventos internos por defecto (red de seguridad) y
## los sobrescribe/extiende con el catálogo JSON y con overrides del planeta.
func _build_events(config: Dictionary) -> void:
	_events = _builtin_events()

	var path := str(config.get("events_file", DEFAULT_EVENTS_FILE))
	_merge_event_dict(_load_events_catalog(path))

	# Overrides por planeta (weather_settings.presets) — afinan el catálogo solo aquí.
	var presets: Dictionary = config.get("presets", {})
	if presets is Dictionary:
		_merge_event_dict(presets)


## Mezcla un diccionario {nombre: {campos}} en _events: actualiza los existentes y crea
## los nuevos (campos omitidos = default de WeatherState).
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


# ── Perfiles de eventos por bioma ────────────────────────────────────────────────

## Construye _profiles_by_biome: por cada bioma, un perfil por defecto derivado de la
## latitud central de su banda, sobrescribible por índice desde weather_settings.biome_profiles.
func _build_biome_profiles(config: Dictionary) -> void:
	_profiles_by_biome.clear()
	for i in maxi(_biome_count, 1):
		_profiles_by_biome[i] = _default_profile_for_biome(i)

	# Overrides por índice de bioma. En JSON las claves son strings ("0", "1", ...).
	var overrides: Dictionary = config.get("biome_profiles", {})
	for key in overrides:
		var idx := int(str(key))
		var parsed := _parse_profile(overrides[key])
		if not parsed.is_empty():
			_profiles_by_biome[idx] = parsed


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


## Convierte una lista del JSON en perfil [[nombre, peso], ...]. Acepta entradas como
## {"weather": "snow", "weight": 3}, {"event": "snow", "weight": 3} o ["snow", 3].
func _parse_profile(raw) -> Array:
	var profile: Array = []
	if not (raw is Array):
		return profile
	for entry in raw:
		var name := ""
		var weight := 1.0
		if entry is Dictionary:
			name = str(entry.get("weather", entry.get("event", "")))
			weight = float(entry.get("weight", 1.0))
		elif entry is Array and entry.size() >= 1:
			name = str(entry[0])
			weight = float(entry[1]) if entry.size() >= 2 else 1.0
		if name != "" and weight > 0.0:
			profile.append([name, weight])
	return profile


# ── Eventos internos por defecto (fallback si falta el catálogo JSON) ─────────────

func _builtin_events() -> Dictionary:
	return {
		"clear": _state({
			"cloud_coverage": 0.25, "cloud_density": 0.35, "cloud_absorption": 0.12,
			"cloud_shadow": 0.5, "cloud_min_height": 600.0, "cloud_max_height": 900.0,
			"cloud_wind_speed": 0.025, "sun_energy": 1.0, "ambient_energy": 1.0,
			"wind_multiplier": 0.6, "water_wave_multiplier": 0.7,
			"water_speed_multiplier": 0.8, "water_foam_multiplier": 0.6,
		}),
		"storm": _state({
			"cloud_coverage": 0.9, "cloud_density": 1.6, "cloud_absorption": 0.4,
			"cloud_shadow": 1.0, "cloud_min_height": 300.0, "cloud_max_height": 800.0,
			"cloud_wind_speed": 0.06, "sun_energy": 0.3, "ambient_energy": 0.5,
			"wind_multiplier": 2.4, "water_wave_multiplier": 2.0,
			"water_speed_multiplier": 1.6, "water_foam_multiplier": 2.5,
			"rain_rate": 1.0, "lightning_frequency": 0.15,
			"fog_density": 0.5, "fog_coverage": 0.45, "fog_wind_speed": 0.05,
			"fog_floor_height": 0.0, "fog_top_height": 90.0,
		}),
		"snow": _state({
			"cloud_coverage": 0.75, "cloud_density": 0.9, "cloud_absorption": 0.28,
			"cloud_shadow": 0.8, "cloud_min_height": 350.0, "cloud_max_height": 700.0,
			"cloud_wind_speed": 0.04, "sun_energy": 0.7, "ambient_energy": 0.8,
			"wind_multiplier": 1.3, "snow_coverage": 1.0, "snow_rate": 1.0,
			"fog_density": 0.6, "fog_coverage": 0.5, "fog_wind_speed": 0.03,
			"fog_floor_height": 0.0, "fog_top_height": 120.0,
		}),
		"wind": _state({
			"cloud_coverage": 0.45, "cloud_density": 0.5, "cloud_absorption": 0.14,
			"cloud_shadow": 0.6, "cloud_min_height": 500.0, "cloud_max_height": 850.0,
			"cloud_wind_speed": 0.1, "sun_energy": 0.9, "ambient_energy": 0.95,
			"wind_multiplier": 3.2, "water_wave_multiplier": 1.7,
			"water_speed_multiplier": 1.8, "water_foam_multiplier": 1.8,
		}),
		"fog": _state({
			# Las nubes se quedan ALTAS y discretas: la niebla la hace la capa baja dedicada
			# (fog_density/fog_coverage), no nubes que bajan. Un cielo encapotado tenue ayuda.
			"cloud_coverage": 0.35, "cloud_density": 0.4, "cloud_absorption": 0.16,
			"cloud_shadow": 0.3, "cloud_min_height": 500.0, "cloud_max_height": 800.0,
			"cloud_wind_speed": 0.03, "sun_energy": 0.6, "ambient_energy": 0.8,
			"wind_multiplier": 0.5, "water_wave_multiplier": 0.6,
			"water_speed_multiplier": 0.7, "water_foam_multiplier": 0.6,
			"fog_density": 1.0, "fog_coverage": 0.62, "fog_wind_speed": 0.025,
			"fog_floor_height": 0.0, "fog_top_height": 160.0,
		}),
	}


func _state(fields: Dictionary) -> WeatherState:
	var s := WeatherState.new()
	s.apply_overrides(fields)
	return s
