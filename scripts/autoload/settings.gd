class_name SettingsManager
extends Node

## Ajustes del jugador (autoload "Settings"): pantalla, gráficos, audio y controles, guardados en
## user://settings.cfg. Cada ajuste se aplica en cuanto cambia, salvo los de RESTART_KEYS, que el
## planeta lee al cargarse (terreno y vegetación) y valen desde el siguiente arranque.
## Los valores viven en estáticos para que esos sistemas los lean sin depender del autoload; en el
## editor devuelven siempre los valores por defecto, así los @tool no dependen de la partida.

signal changed(key: String)

const PATH := "user://settings.cfg"

enum WindowMode {WINDOWED, FULLSCREEN, EXCLUSIVE}
enum Upscaler {BILINEAR, FSR1, FSR2}
enum Antialiasing {OFF, FXAA, MSAA_2X, MSAA_4X, TAA}
enum Preset {LOW, MEDIUM, HIGH, ULTRA}
const PRESET_CUSTOM := -1
## Sangre y mutilaciones ("game/gore"): nada de sangre, sangre sin cercenar, o todo.
const GORE_OFF := 0
const GORE_BLOOD := 1
const GORE_FULL := 2

const AUDIO_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Ambient", &"UI", &"Voice"]

## Valores de cada preset [Bajo, Medio, Alto, Ultra]. Alto es como estaba el juego antes de las
## opciones y es el valor por defecto.
const PRESETS := {
	"graphics/render_scale": [0.75, 0.85, 1.0, 1.0],
	"graphics/upscaler": [Upscaler.FSR1, Upscaler.FSR1, Upscaler.BILINEAR, Upscaler.BILINEAR],
	"graphics/antialiasing": [Antialiasing.FXAA, Antialiasing.FXAA, Antialiasing.MSAA_2X, Antialiasing.MSAA_4X],
	"graphics/shadow_quality": [1, 2, 3, 4],
	"graphics/shadow_distance": [0, 1, 2, 2],
	"graphics/vegetation_shadows": [0, 1, 2, 2],
	"graphics/clouds": [1, 2, 3, 3],
	"graphics/atmosphere_quality": [0, 1, 1, 2],
	"graphics/god_rays": [false, true, true, true],
	"graphics/glow": [false, true, true, true],
	"graphics/ssao": [false, false, false, true],
	"graphics/weather_particles": [0, 1, 2, 2],
	"graphics/fauna": [0, 1, 2, 2],
	"graphics/terrain_detail": [0, 1, 2, 3],
	"graphics/terrain_normalmaps": [false, true, true, true],
	"graphics/terrain_material": [0, 1, 2, 2],
	"graphics/grass_density": [0, 1, 2, 2],
	"graphics/grass_distance": [1, 2, 2, 2],
	"graphics/forest_distance": [1, 1, 2, 2],
}

const DEFAULTS := {
	"display/window_mode": WindowMode.WINDOWED,
	## Solo en ventana. Vector2i.ZERO = el tamaño con que arranca el proyecto.
	"display/resolution": Vector2i.ZERO,
	"display/vsync": DisplayServer.VSYNC_DISABLED,
	"display/max_fps": 0,
	"audio/Master": 1.0,
	"audio/Music": 1.0,
	"audio/SFX": 1.0,
	"audio/Ambient": 1.0,
	"audio/UI": 1.0,
	"audio/Voice": 1.0,
	"game/gore": GORE_FULL,
	"controls/mouse_sensitivity": 1.0,
	"controls/invert_y": false,
	## Acción -> eventos serializados, solo de las acciones que el jugador ha cambiado.
	"controls/bindings": {},
}

## Ajustes que se leen al cargar el planeta: cambiarlos con el mundo cargado no tiene efecto
## hasta reiniciar.
const RESTART_KEYS: Array[String] = [
	"graphics/vegetation_shadows", "graphics/terrain_detail", "graphics/terrain_normalmaps",
	"graphics/terrain_material",
	"graphics/grass_density", "graphics/grass_distance", "graphics/forest_distance",
]

## Índice de cada opción -> valor del motor. Índice 0 de sombras = sin sombras.
const SHADOW_ATLAS_SIZE := [0, 2048, 4096, 4096, 8192]
const SHADOW_FILTER := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
	RenderingServer.SHADOW_QUALITY_SOFT_ULTRA]
## Fracción de la distancia de sombra de cada luz tal como viene en la escena.
const SHADOW_DISTANCE_SCALE := [0.35, 0.6, 1.0]
## Primer corte de cascada con dos cascadas (calidad baja): con las cuatro de la escena el
## primero cubre solo el 2 % y con dos quedaría la sombra cercana borrosa o cortada.
const LOW_SHADOW_SPLIT := 0.12
## Pasos de nubes y niebla respecto a los del PlanetAtmosphere. 0 = sin nubes.
const CLOUD_STEP_SCALE := [0.0, 0.6, 0.8, 1.0]
const WEATHER_PARTICLE_SCALE := [0.3, 0.6, 1.0]
const FAUNA_SCALE := [0.4, 0.7, 1.0]
## Escala del secondary_lod_distance de la escena (32): alcance de los LOD lejanos del terreno.
## lod_distance no se toca: la vegetación calcula sus relevos con él.
const TERRAIN_DETAIL_SCALE := [0.75, 0.875, 1.0, 1.25]
const GRASS_DENSITY_SCALE := [0.5, 0.75, 1.0]
## Última banda del instancer con hierba y sotobosque: 0 hasta ~40 m, 1 hasta ~90 m, 2 todas.
const GRASS_MAX_BAND := [0, 1, 99]

const MIN_MOUSE_SENSITIVITY := 0.2
const MAX_MOUSE_SENSITIVITY := 3.0

## Acciones que se pueden reasignar, por grupo, con su nombre en la pantalla de opciones.
const REBINDABLE_ACTIONS := [
	["Movimiento", [
		[&"move_forward", "Avanzar"], [&"move_back", "Retroceder"], [&"move_left", "Izquierda"],
		[&"move_right", "Derecha"], [&"jump", "Saltar"], [&"Sprint", "Correr"],
		[&"walk_toggle", "Andar / correr"], [&"dodge", "Esquivar"],
		[&"toggle_free_flight", "Vuelo libre"]]],
	["Combate", [
		[&"attack_1", "Ataque principal"], [&"attack_2", "Ataque secundario"], [&"lock_on", "Fijar objetivo"]]],
	["Interfaz", [
		[&"action", "Usar / interactuar"], [&"inventory", "Inventario"], [&"character_window", "Personaje"],
		[&"world_map", "Mapa del mundo"], [&"toggle_console", "Consola"]]],
	["Construcción", [
		[&"open_build_menu", "Menú de construcción"], [&"switch_build_modes", "Cambiar modo"],
		[&"toggle_symmetry_mode", "Simetría"], [&"switch_symmetry_plane", "Plano de simetría"],
		[&"rotate_block_x", "Rotar bloque en X"], [&"rotate_block_y", "Rotar bloque en Y"],
		[&"rotate_block_z", "Rotar bloque en Z"], [&"convert_dynamic", "Convertir en dinámica"],
		[&"open_ship_menu", "Menú de naves"], [&"open_grid_menu", "Menú de estructura"]]],
	["Cámara", [
		[&"camera_zoom_in", "Acercar cámara"], [&"camera_zoom_out", "Alejar cámara"]]],
]

## Sensibilidad del ratón (multiplicador) e inversión del eje Y, leídas por las cámaras en cada
## movimiento.
static var mouse_scale := 1.0
static var invert_y := false

static var _values: Dictionary = {}
static var _loaded := false
## Valores de RESTART_KEYS con que ha arrancado el juego.
static var _boot: Dictionary = {}

var _default_events: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_loaded()
	for group in REBINDABLE_ACTIONS:
		for entry in group[1]:
			if InputMap.has_action(entry[0]):
				_default_events[entry[0]] = InputMap.action_get_events(entry[0])
	get_tree().node_added.connect(_on_node_added)
	apply_all()


# --- Lectura -----------------------------------------------------------------------------------

static func default_value(key: String) -> Variant:
	if PRESETS.has(key):
		return PRESETS[key][Preset.HIGH]
	var fallback: Variant = DEFAULTS.get(key)
	return fallback.duplicate(true) if fallback is Dictionary else fallback


static func has_key(key: String) -> bool:
	return PRESETS.has(key) or DEFAULTS.has(key)


static func value(key: String) -> Variant:
	if Engine.is_editor_hint():
		return default_value(key)
	_ensure_loaded()
	return _values.get(key, default_value(key))


## Índice de una opción por niveles, acotado a los que tiene su tabla.
static func level(key: String, count: int) -> int:
	return clampi(int(value(key)), 0, count - 1)


## Cuánto gore se ve (GORE_OFF, GORE_BLOOD o GORE_FULL).
static func gore_level() -> int:
	return level("game/gore", 3)


static func grass_density_scale() -> float:
	return GRASS_DENSITY_SCALE[level("graphics/grass_density", GRASS_DENSITY_SCALE.size())]


static func grass_max_band() -> int:
	return GRASS_MAX_BAND[level("graphics/grass_distance", GRASS_MAX_BAND.size())]


## Bandas de impostores lejanos de un bosque: las que pide el planeta, recortadas por el ajuste.
static func forest_far_bands(authored: int) -> int:
	return mini(authored, level("graphics/forest_distance", 3))


## 0 = sin sombras de vegetación, 1 = solo los árboles cercanos, 2 = todas.
static func vegetation_shadows() -> int:
	return level("graphics/vegetation_shadows", 3)


## Aplica al terreno los ajustes que solo valen antes de que empiece a mallar.
static func apply_terrain(terrain: VoxelLodTerrain) -> void:
	if Engine.is_editor_hint() or terrain == null:
		return
	if not terrain.has_meta(&"settings_base_secondary_lod"):
		terrain.set_meta(&"settings_base_secondary_lod", terrain.secondary_lod_distance)
	var base: float = terrain.get_meta(&"settings_base_secondary_lod")
	terrain.secondary_lod_distance = base * TERRAIN_DETAIL_SCALE[level("graphics/terrain_detail", TERRAIN_DETAIL_SCALE.size())]
	terrain.normalmap_enabled = bool(value("graphics/terrain_normalmaps"))


## Se aplica después de los parámetros del planeta y antes del primer mallado:
## los bloques de VoxelLodTerrain guardan copias del material.
static func apply_terrain_material(material: ShaderMaterial) -> void:
	if Engine.is_editor_hint() or material == null:
		return
	var quality := level("graphics/terrain_material", 3)
	if quality < 2:
		material.set_shader_parameter("detail_blend_enabled", false)
		material.set_shader_parameter("parallax_enabled", false)
	if quality == 0:
		material.set_shader_parameter("antitiling_enabled", false)


## Preset con el que coinciden todos los ajustes gráficos, o PRESET_CUSTOM.
static func current_preset() -> int:
	for preset in Preset.values():
		var matches := true
		for key in PRESETS:
			if not _same(value(key), PRESETS[key][preset]):
				matches = false
				break
		if matches:
			return preset
	return PRESET_CUSTOM


## Hay ajustes de RESTART_KEYS distintos de los del arranque.
static func needs_restart() -> bool:
	for key in RESTART_KEYS:
		if not _same(value(key), _boot.get(key, value(key))):
			return true
	return false


## Los sliders devuelven 0.8500000001: los float se comparan con tolerancia.
static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for section in cfg.get_sections():
			for entry in cfg.get_section_keys(section):
				var key := "%s/%s" % [section, entry]
				if has_key(key):
					_values[key] = _sanitize(key, cfg.get_value(section, entry))
	for key in RESTART_KEYS:
		_boot[key] = value(key)


## Descarta valores de otro tipo (fichero editado a mano o de una versión anterior).
static func _sanitize(key: String, raw: Variant) -> Variant:
	var fallback: Variant = default_value(key)
	if typeof(fallback) == TYPE_FLOAT and typeof(raw) == TYPE_INT:
		return float(raw)
	if typeof(raw) != typeof(fallback):
		return fallback
	return raw


# --- Escritura ---------------------------------------------------------------------------------

func set_value(key: String, new_value: Variant) -> void:
	if not has_key(key):
		push_error("Settings: ajuste desconocido '%s'" % key)
		return
	_ensure_loaded()
	_values[key] = _sanitize(key, new_value)
	_apply(key)
	changed.emit(key)


func apply_preset(preset: int) -> void:
	for key in PRESETS:
		set_value(key, PRESETS[key][preset])


## Vuelve a los valores por defecto las claves que empiezan por `prefix` ("graphics/"...).
func reset_section(prefix: String) -> void:
	for key in PRESETS.keys() + DEFAULTS.keys():
		if key.begins_with(prefix):
			set_value(key, default_value(key))


func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in _values:
		var slash := key.find("/")
		cfg.set_value(key.substr(0, slash), key.substr(slash + 1), _values[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_error("Settings: no se pudo guardar %s (%s)" % [PATH, error_string(err)])


## Copia de los valores actuales, para deshacer los cambios de la pantalla de opciones.
func snapshot() -> Dictionary:
	_ensure_loaded()
	return _values.duplicate(true)


func restore(saved: Dictionary) -> void:
	var touched: Array = saved.keys()
	for key in _values:
		if not saved.has(key):
			touched.append(key)
	_values = saved.duplicate(true)
	for key in touched:
		_apply(key)
		changed.emit(key)


# --- Controles ---------------------------------------------------------------------------------

func get_default_events(action: StringName) -> Array:
	return _default_events.get(action, [])


## Asigna los eventos de una acción (hasta dos: principal y secundario) y los guarda como
## cambiados solo si difieren de los del proyecto.
func set_action_events(action: StringName, events: Array) -> void:
	var bindings: Dictionary = value("controls/bindings")
	var serialized := []
	for event in events:
		var data := event_to_dict(event)
		if not data.is_empty():
			serialized.append(data)
	var defaults := []
	for event in get_default_events(action):
		var data := event_to_dict(event)
		if not data.is_empty():
			defaults.append(data)
	if serialized == defaults:
		bindings.erase(String(action))
	else:
		bindings[String(action)] = serialized
	set_value("controls/bindings", bindings)


static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return {"key": code}
	if event is InputEventMouseButton:
		return {"mouse": event.button_index}
	return {}


static func dict_to_event(data: Dictionary) -> InputEvent:
	if data.has("key"):
		var key := InputEventKey.new()
		key.device = -1
		key.physical_keycode = int(data.key)
		return key
	if data.has("mouse"):
		var button := InputEventMouseButton.new()
		button.device = -1
		button.button_index = int(data.mouse)
		return button
	return null


static func same_event(a: InputEvent, b: InputEvent) -> bool:
	return a != null and b != null and event_to_dict(a) == event_to_dict(b) and not event_to_dict(a).is_empty()


static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var layout_key := DisplayServer.keyboard_get_keycode_from_physical(code)
		return OS.get_keycode_string(layout_key if layout_key != KEY_NONE else code)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "Clic izquierdo"
			MOUSE_BUTTON_RIGHT: return "Clic derecho"
			MOUSE_BUTTON_MIDDLE: return "Clic central"
			MOUSE_BUTTON_WHEEL_UP: return "Rueda arriba"
			MOUSE_BUTTON_WHEEL_DOWN: return "Rueda abajo"
			MOUSE_BUTTON_XBUTTON1: return "Botón lateral 1"
			MOUSE_BUTTON_XBUTTON2: return "Botón lateral 2"
		return "Botón %d" % event.button_index
	return "—"


# --- Aplicación --------------------------------------------------------------------------------

func apply_all() -> void:
	for key in PRESETS.keys() + DEFAULTS.keys():
		_apply(key)


func _apply(key: String) -> void:
	match key:
		"display/window_mode", "display/resolution":
			_apply_window()
		"display/vsync":
			DisplayServer.window_set_vsync_mode(int(value(key)))
		"display/max_fps":
			Engine.max_fps = maxi(int(value(key)), 0)
		"graphics/render_scale", "graphics/upscaler":
			_apply_scaling()
		"graphics/antialiasing":
			_apply_antialiasing()
		"graphics/shadow_quality":
			_apply_shadow_atlas()
			_apply_to_lights()
		"graphics/shadow_distance":
			_apply_to_lights()
		"graphics/clouds", "graphics/atmosphere_quality", "graphics/god_rays", "graphics/glow", "graphics/ssao":
			_apply_to_environments()
		"graphics/weather_particles":
			WeatherParticles.amount_scale = WEATHER_PARTICLE_SCALE[level(key, WEATHER_PARTICLE_SCALE.size())]
			for node in get_tree().root.find_children("*", "GPUParticles3D", true, false):
				if node is WeatherParticles:
					node.refresh_amount()
		"graphics/fauna":
			AmbientFaunaSpawner.population_scale = FAUNA_SCALE[level(key, FAUNA_SCALE.size())]
		"controls/mouse_sensitivity":
			mouse_scale = clampf(float(value(key)), MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
		"controls/invert_y":
			invert_y = bool(value(key))
		"controls/bindings":
			_apply_bindings()
		_:
			if key.begins_with("audio/"):
				AudioManager.set_bus_volume(StringName(key.substr(6)), clampf(float(value(key)), 0.0, 1.0))


## Solo toca la ventana si el jugador ha elegido algo distinto de lo que trae el proyecto, para
## no pelearse con la ventana del editor al lanzar el juego desde él.
func _apply_window() -> void:
	var mode := level("display/window_mode", 3)
	var resolution: Vector2i = value("display/resolution")
	match mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			var current := DisplayServer.window_get_mode()
			if current == DisplayServer.WINDOW_MODE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if resolution.x > 0 and resolution.y > 0 and DisplayServer.window_get_size() != resolution:
				DisplayServer.window_set_size(resolution)
				var screen := DisplayServer.window_get_current_screen()
				var origin := DisplayServer.screen_get_position(screen)
				var free := DisplayServer.screen_get_size(screen) - resolution
				DisplayServer.window_set_position(origin + Vector2i(maxi(free.x, 0), maxi(free.y, 0)) / 2)


func _apply_scaling() -> void:
	var viewport := get_tree().root
	var upscaler := level("graphics/upscaler", 3)
	viewport.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR,
		Viewport.SCALING_3D_MODE_FSR2][upscaler]
	viewport.scaling_3d_scale = clampf(float(value("graphics/render_scale")), 0.5, 1.0)


func _apply_antialiasing() -> void:
	var viewport := get_tree().root
	var aa := level("graphics/antialiasing", 5)
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	match aa:
		Antialiasing.FXAA: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		Antialiasing.MSAA_2X: viewport.msaa_3d = Viewport.MSAA_2X
		Antialiasing.MSAA_4X: viewport.msaa_3d = Viewport.MSAA_4X
		Antialiasing.TAA: viewport.use_taa = true


func _apply_shadow_atlas() -> void:
	var quality := level("graphics/shadow_quality", SHADOW_ATLAS_SIZE.size())
	if quality == 0:
		return
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZE[quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER[quality])
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTER[quality])


func _apply_to_lights() -> void:
	for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_apply_light(light)


## Guarda en metadatos cómo viene la luz de su escena y aplica calidad y distancia encima. La luna
## no se enciende aquí: SkyLighting le pasa las sombras cuando el sol se pone, y solo si el sol
## las tiene.
func _apply_light(light: DirectionalLight3D) -> void:
	if not light.has_meta(&"settings_base_shadow"):
		light.set_meta(&"settings_base_shadow", {
			"enabled": light.shadow_enabled,
			"distance": light.directional_shadow_max_distance,
			"mode": light.directional_shadow_mode,
			"split_1": light.directional_shadow_split_1,
		})
	var base: Dictionary = light.get_meta(&"settings_base_shadow")
	var quality := level("graphics/shadow_quality", SHADOW_ATLAS_SIZE.size())
	light.shadow_enabled = base.enabled and quality > 0
	light.directional_shadow_max_distance = base.distance \
		* SHADOW_DISTANCE_SCALE[level("graphics/shadow_distance", SHADOW_DISTANCE_SCALE.size())]
	if quality == 1:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		light.directional_shadow_split_1 = LOW_SHADOW_SPLIT
	else:
		light.directional_shadow_mode = base.mode
		light.directional_shadow_split_1 = base.split_1


func _apply_to_environments() -> void:
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_world_environment(node)


func _apply_world_environment(world: WorldEnvironment) -> void:
	var env := world.environment
	if env != null:
		if not env.has_meta(&"settings_base_glow"):
			env.set_meta(&"settings_base_glow", env.glow_enabled)
		env.glow_enabled = env.get_meta(&"settings_base_glow") and bool(value("graphics/glow"))
		env.ssao_enabled = bool(value("graphics/ssao"))
	if world.compositor == null:
		return
	var step_scale: float = CLOUD_STEP_SCALE[level("graphics/clouds", CLOUD_STEP_SCALE.size())]
	for effect in world.compositor.compositor_effects:
		if effect is PlanetAtmosphere:
			effect.set_quality(step_scale, bool(value("graphics/god_rays")),
				[4, 2, 1][level("graphics/atmosphere_quality", 3)])


func _apply_bindings() -> void:
	var bindings: Dictionary = value("controls/bindings")
	for action: StringName in _default_events:
		InputMap.action_erase_events(action)
		var events: Array = []
		if bindings.has(String(action)):
			for data in bindings[String(action)]:
				if data is Dictionary:
					var event := dict_to_event(data)
					if event != null:
						events.append(event)
		else:
			events = _default_events[action]
		for event in events:
			InputMap.action_add_event(action, event)


func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D:
		_apply_light(node)
	elif node is WorldEnvironment:
		_apply_world_environment(node)
