@tool
extends Node

## Carga un planeta desde su JSON (vía PlanetParser), lo instancia con su terreno, agua, clima y
## spawners de NPC, y expone el guardado/carga y los ajustes de anti-tiling.

enum Action { NONE, SELECT_CONFIG }

@export_group("Planet")
@export var sun_path : DirectionalLight3D
@export var config_file_path: String = ""
@export var sun_dir: Vector3
@export var gravity_strength: float = 9.8
@export var players: Array[CharacterBody3D]
@onready var voxel_terrain: VoxelLodTerrain = $VoxelLodTerrain

@export var water_sphere: OceanSystem
@export var global_pos: Vector3
@export var planet: Planet
@export var entity_id: String = ""
var save_category: String = "planet"

@export_group("Underwater Fog")
@export var fog_density: float = 1.0
@export var fog_color: Color = Color("00526e")
@export var deep_fog_color: Color = Color(0.1, 0.2, 0.3, 1.0)
@export var abyss_fog_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var deep_transition_depth: float = 100.0
@export var abyss_transition_depth: float = 250.0
@export var distance_depth_gain: float = 0.7
@export var distance_depth_max: float = 120.0
@export var sun_glow_intensity: float = 0.35
@export var sun_glow_power: float = 8.0

@export_group("Underwater Godrays")
@export var godray_intensity: float = 3.0
@export var godray_samples: int = 12
@export var godray_max_distance: float = 40.0
@export var godray_pattern_scale: float = 0.01
@export var godray_pattern_speed: float = 0.01
@export var godray_sharpness: float = 2.5
@export var godray_phase_power: float = 6.0
@export var godray_min_phase: float = 0.15

# Mismos nombres que los exports de Underwater: se copian tal cual cada frame.
# (absorption_coefficients queda fuera a propósito: se hereda del .tres del agua
# para que el color buceando converja con el visto desde fuera.)
const _UNDERWATER_PARAMS: Array[StringName] = [
	&"fog_density", &"fog_color", &"deep_fog_color", &"abyss_fog_color",
	&"deep_transition_depth", &"abyss_transition_depth",
	&"distance_depth_gain", &"distance_depth_max",
	&"sun_glow_intensity", &"sun_glow_power",
	&"godray_intensity", &"godray_samples", &"godray_max_distance",
	&"godray_pattern_scale", &"godray_pattern_speed", &"godray_sharpness",
	&"godray_phase_power", &"godray_min_phase",
]

var _config_action: Action = Action.NONE
var water_material : ShaderMaterial
var weather_controller: WeatherController
var _pending_weather_data: Dictionary = {}

func get_gravity_direction(_global_position: Vector3) -> Vector3:
	var gravity_center = voxel_terrain.global_position
	return (gravity_center - _global_position).normalized()
	

@export var config_action: Action:
	get:		
		return _config_action
	set(value):
		if value == Action.SELECT_CONFIG && Engine.is_editor_hint() && sun_path:
			_open_file_dialog()
			_config_action = Action.NONE
			notify_property_list_changed()
		else:
			_config_action = value
			if sun_path == null:
				push_error("sun_path is null! Aborting")

@export_group("Weather Override")
## Si está activo, fuerza el clima a 'forced_weather' y bloquea el cambio automático.
@export var force_weather: bool = false:
	set(value):
		force_weather = value
		_apply_weather_override()
## Evento a forzar. Coincide con los nombres del catálogo data/weather/weather_events.json.
@export_enum("clear", "storm", "snow", "wind", "fog") var forced_weather: String = "storm":
	set(value):
		forced_weather = value
		_apply_weather_override()

@export_group("Impostor (planeta lejano)")

## Sustituye el terreno voxel por una esfera analítica cuando el planeta se ve de lejos.
## Pensado para cuerpos donde el terreno ES el planeta (lunas, asteroides): en uno con agua y
## atmósfera la esfera del impostor queda por fuera del océano y lo taparía, así que ahí mejor off.
@export var impostor_enabled: bool = true
## Radios (desde el centro) a partir de los cuales solo se ve el impostor.
@export var impostor_show_factor: float = 3.0
## Radios por debajo de los cuales solo se ve el terreno real; entre ambos hay crossfade.
@export var impostor_hide_factor: float = 2.0
## Resolución del equirect que se hornea del terreno real (ver planet_impostor_baker.gd).
@export var impostor_map_size: Vector2i = Vector2i(1024, 512)
## Semirrango de búsqueda del SDF alrededor del radio: la superficie debe caer dentro.
@export var impostor_height_range: float = 600.0
## Color plano mientras el bake, que corre en un hilo, no ha terminado.
@export var impostor_fallback_color: Color = Color(0.55, 0.53, 0.5)
## Ganancia del relieve sobre la pendiente real del mapa horneado. 1 = tal cual.
@export_range(0.0, 4.0, 0.05) var impostor_relief_strength: float = 1.0
@export_range(0.005, 0.5, 0.005) var impostor_terminator_softness: float = 0.03
@export_range(0.0, 1.0, 0.01) var impostor_night_light: float = 0.03
## Halo atmosférico en el limbo iluminado. 0 en cuerpos sin atmósfera.
@export_range(0.0, 3.0, 0.01) var impostor_rim_strength: float = 0.0
@export var impostor_rim_color: Color = Color(0.35, 0.55, 1.0)
## Diagnóstico: 0 normal, 1 albedo crudo, 2 altura, 3 normal, 4 verde=hay mapa / magenta=no.
@export_range(0, 4, 1) var impostor_debug_mode: int = 0

# Mismos nombres que los exports de arriba sin el prefijo: se copian tal cual cada frame.
const _IMPOSTOR_PARAMS: Array[StringName] = [
	&"show_factor", &"hide_factor", &"fallback_color",
	&"relief_strength", &"terminator_softness", &"night_light",
	&"rim_strength", &"rim_color", &"debug_mode",
]

var impostor: PlanetImpostor

@export_group("Mapa mundial")

## Mapa equirect precomputado del planeta: lo dibuja la UI de la tecla M y responde las consultas
## de "¿qué hay bajo esta posición?" (tierra/agua, qué cuerpo de agua, qué profundidad).
@export var world_map_enabled: bool = true
## Resolución del equirect. A 2048x1024 un téxel son ~92 m de ecuador en un planeta de radio 30000;
## los cuerpos de agua más pequeños que un téxel no se detectan.
@export var world_map_size: Vector2i = Vector2i(2048, 1024)
## Semirrango de búsqueda del SDF alrededor del radio: la superficie debe caer dentro. Si el mapa
## sale con mesetas planas, el bake avisa por consola de que hay que subirlo. Con 1200 la Tierra
## saturaba un 0.9% (fosas profundas), así que va holgado. Forma parte de la clave del caché.
@export var world_map_height_range: float = 2000.0

var world_map: PlanetWorldMap

@export_group("Anti-tiling (de-repetición de texturas)")

@export var antitiling_enabled: bool = false:
	set(value):
		antitiling_enabled = value
		_apply_antitiling_settings()

@export_range(0.005, 2.5, 0.001) var antitiling_variation_scale: float = 2.5:
	set(value):
		antitiling_variation_scale = value
		_apply_antitiling_settings()

@export_range(0.005, 2.5, 0.01) var antitiling_blend_softness: float = 2.5:
	set(value):
		antitiling_blend_softness = value
		_apply_antitiling_settings()

@export_range(0.0, 1.0, 0.01) var antitiling_rotation_strength: float = 0.7:
	set(value):
		antitiling_rotation_strength = value
		_apply_antitiling_settings()

@export_range(0.0, 1.0, 0.005) var antitiling_fade_start: float = 0.10:
	set(value):
		antitiling_fade_start = value
		_apply_antitiling_settings()
@export_range(0.0, 1.5, 0.005) var antitiling_fade_end: float = 0.40:
	set(value):
		antitiling_fade_end = value
		_apply_antitiling_settings()

## Escala de las UV triplanares del terreno: es lo que fija cada cuánto se repite la textura.
@export_range(0.0, 1.0, 0.1) var texture_scale: float = 0.5:
	set(value):
		# El valor se guarda SIEMPRE. Antes salía antes de asignarlo cuando 'planet' era null,
		# que es el caso al cargar la escena (los exports se aplican antes de _ready), así que
		# lo puesto en el inspector se perdía y todos los planetas acababan con el default.
		texture_scale = value
		_apply_texture_scale()

var _editor_file_dialog: EditorFileDialog

func _copy_parsed_data(planet_parser: PlanetParser) -> void:
	planet.radius = planet_parser.radius
	planet.terrain_generator_path = planet_parser.terrain_generator_path
	planet.biome_count = planet_parser.biome_count
	planet.textures_per_biome = planet_parser.textures_per_biome
	planet.biome_latitude_ranges = planet_parser.biome_latitude_ranges
	planet.biome_transition_smoothness = planet_parser.biome_transition_smoothness
	planet.max_heights = planet_parser.max_heights
	planet.biome_texture_indices = planet_parser.biome_texture_indices
	planet.sound_materials = planet_parser.sound_materials
	planet.slope_sound_material = planet_parser.slope_sound_material
	planet.biome_noise_enabled = planet_parser.biome_noise_enabled
	planet.biome_noise_source_texture_indices = planet_parser.biome_noise_source_texture_indices
	planet.biome_noise_target_texture_indices = planet_parser.biome_noise_target_texture_indices
	planet.biome_noise_scales = planet_parser.biome_noise_scales
	planet.biome_noise_thresholds = planet_parser.biome_noise_thresholds
	planet.biome_noise_smoothness = planet_parser.biome_noise_smoothness
	planet.biome_noise_seeds = planet_parser.biome_noise_seeds
	planet.biome_noise_invert = planet_parser.biome_noise_invert
	planet.biome_noise_abs_latitude_mins = planet_parser.biome_noise_abs_latitude_mins
	planet.biome_noise_abs_latitude_maxs = planet_parser.biome_noise_abs_latitude_maxs
	planet.biome_noise_latitude_smoothness = planet_parser.biome_noise_latitude_smoothness
	planet.textures = planet_parser.textures
	planet.normal_textures = planet_parser.normal_textures
	planet.roughness_textures = planet_parser.roughness_textures
	planet.ao_textures = planet_parser.ao_textures
	planet.height_textures = planet_parser.height_textures
	planet.slope_texture = planet_parser.slope_texture
	planet.slope_normal_texture = planet_parser.slope_normal_texture
	planet.slope_roughness_texture = planet_parser.slope_roughness_texture
	planet.slope_ao_texture = planet_parser.slope_ao_texture
	planet.slope_height_texture = planet_parser.slope_height_texture
	planet.slope_threshold = planet_parser.slope_threshold
	planet.slope_smoothness = planet_parser.slope_smoothness
	planet.slope_height_blend_strength = planet_parser.slope_height_blend_strength
	planet.slope_height_blend_sharpness = planet_parser.slope_height_blend_sharpness
	planet.slope_breakup_scale = planet_parser.slope_breakup_scale
	planet.slope_breakup_strength = planet_parser.slope_breakup_strength
	planet.slope_breakup_anisotropy = planet_parser.slope_breakup_anisotropy
	planet.slope_strata_thickness = planet_parser.slope_strata_thickness
	planet.slope_strata_strength = planet_parser.slope_strata_strength
	planet.slope_strata_warp = planet_parser.slope_strata_warp
	planet.parallax_enabled = planet_parser.parallax_enabled
	planet.parallax_strength = planet_parser.parallax_strength
	planet.transition_smoothness = planet_parser.transition_smoothness
	planet.height_transition_noise_scale = planet_parser.height_transition_noise_scale
	planet.height_transition_noise_strength = planet_parser.height_transition_noise_strength
	planet.macro_variation_scale = planet_parser.macro_variation_scale
	planet.macro_variation_strength = planet_parser.macro_variation_strength
	planet.has_water = planet_parser.has_water
	planet.water_radius = planet_parser.water_level
	planet.ore_settings = planet_parser.ore_settings
	planet.river_settings = planet_parser.river_settings
	planet.entity_id = entity_id
	planet.vegetation = planet_parser.vegetation
	planet.wind_direction = planet_parser.wind_direction
	planet.sun = sun_path


func _load_planet() -> void:
	if is_instance_valid(planet):
		return
	var planet_parser: PlanetParser = PlanetParser.new(sun_path)
	planet_parser.load_config(config_file_path)
	voxel_terrain.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	planet = Planet.new(voxel_terrain)
	_copy_parsed_data(planet_parser)
	planet.setup_shader_parameters()
	_apply_antitiling_settings()
	_apply_texture_scale()
	planet.setup_voxel_generator()
	planet._load_vegetation()
	add_child(planet)
	global_pos = planet.global_position
	if planet_parser.has_water:
		water_sphere = OceanSystem.new()
		add_child(water_sphere)
		water_sphere.subdivision_factor = 1.5
		water_sphere.max_lod = 10
		water_sphere.sub_divisions = 32
		water_sphere.radius = planet.radius - planet_parser.water_level
		water_sphere.player = players[0]
		water_sphere.quadtree_material = load("res://data/resources/WaterSphere_material.tres")
		var water_shader: ShaderMaterial = water_sphere.quadtree_material as ShaderMaterial
		water_shader.set_shader_parameter("planet_center", voxel_terrain.global_position)
		print(voxel_terrain.global_position)
		water_sphere.wireframe_material = load("res://data/resources/WaterSphere_wireframe_material.tres")
		water_sphere.load_watersphere(planet)

	if not Engine.is_editor_hint():
		_setup_weather(planet_parser)

	_setup_npc_spawners(planet_parser)

	if world_map_enabled and not Engine.is_editor_hint():
		_setup_world_map()

	if impostor_enabled:
		_setup_impostor()


## Crea el mapa precomputado del planeta. Se hornea al cargar, y no la primera vez que se abre la
## UI, porque también es la fuente de las consultas de agua del gameplay: tiene que estar listo
## antes de que alguien pregunte. El etiquetado va en un hilo, así que no bloquea la carga.
func _setup_world_map() -> void:
	if world_map != null or planet == null:
		return
	world_map = PlanetWorldMap.new()
	world_map.name = "WorldMap"
	add_child(world_map)
	# Conectado ANTES de setup(): con caché válido, map_ready se emite dentro de la propia llamada.
	world_map.map_ready.connect(_push_world_map_to_water)
	world_map.setup(planet, entity_id, world_map_size, world_map_height_range)


## Empuja el mapa horneado al material del agua. De él salen dos cosas: la máscara que decide dónde
## puede la tormenta levantar oleaje (sin ella el clima sube las olas por igual en mar abierto,
## dentro de un lago y en la rompiente, porque todo el planeta comparte un único material) y el
## campo de litoral del que las olas de orilla sacan su fase.
func _push_world_map_to_water(map: WorldMapData) -> void:
	if water_sphere == null or not map.has_water:
		return
	var mat := water_sphere.quadtree_material as ShaderMaterial
	if mat == null:
		return

	mat.set_shader_parameter("storm_height_map", map.height_texture())
	mat.set_shader_parameter("storm_body_map", map.body_texture())
	mat.set_shader_parameter("storm_height_min", map.height_min)
	mat.set_shader_parameter("storm_height_range", map.height_span)
	mat.set_shader_parameter("storm_sea_height", map.sea_level_radius - map.radius)
	mat.set_shader_parameter("storm_depth_start", PlanetWorldMap.STORM_DEPTH_START)
	mat.set_shader_parameter("storm_depth_full", PlanetWorldMap.STORM_DEPTH_FULL)

	var ids := world_map.storm_body_ids()
	mat.set_shader_parameter("storm_body_ids", ids)
	mat.set_shader_parameter("storm_body_count", ids.size())

	# Semilla de la calma con lo que hay ahora en el material. Si este planeta tiene clima, el
	# WeatherController la reescribe cada frame con los valores base de verdad.
	if mat.get_shader_parameter("wave_calm_amplitude") == null:
		mat.set_shader_parameter("wave_calm_amplitude", mat.get_shader_parameter("wave_amplitude"))
		mat.set_shader_parameter("wave_calm_steepness", mat.get_shader_parameter("wave_steepness"))

	mat.set_shader_parameter("storm_mask_enabled", true)

	# Olas de orilla: el mismo mapa, pero lo que consumen es el campo de litoral horneado. Si no hay
	# campo (planeta sin mares abiertos) el agua se queda con el oleaje de siempre.
	if map.has_shore_field():
		mat.set_shader_parameter("shore_offset_map", map.shore_texture())
		mat.set_shader_parameter("shore_range", map.shore_range)
		mat.set_shader_parameter("shore_waves_enabled", true)

	water_sphere.world_map = world_map
	if weather_controller != null:
		weather_controller.set_world_map(world_map)


## Crea el impostor analítico del planeta y le dice qué nodos apagar cuando esté a pleno.
## El centro se lee del VoxelLodTerrain, así el origen flotante lo arrastra sin más.
func _setup_impostor() -> void:
	if impostor != null or planet == null:
		return
	# Solo el terreno: el agua y la atmósfera siguen por su cuenta. El impostor sustituye la
	# malla voxel, no el planeta entero.
	var body: Array[Node3D] = [voxel_terrain]

	impostor = PlanetImpostor.new()
	impostor.name = "PlanetImpostor"
	# Ambos se leen al hornear, dentro de setup(): hay que fijarlos antes.
	impostor.map_size = impostor_map_size
	impostor.height_range = impostor_height_range
	add_child(impostor)
	_apply_impostor_settings()
	impostor.setup(planet, body, self)
	print("[impostor] creado en '%s' (radio %.0f, centro %s)" % [
		name, planet.radius, voxel_terrain.global_position])


## Copia los exports de aspecto al impostor; este los reaplica al shader cada frame.
func _apply_impostor_settings() -> void:
	if impostor == null:
		return
	for param in _IMPOSTOR_PARAMS:
		impostor.set(param, get("impostor_" + param))


## Crea el sistema meteorológico si este planeta tiene atmósfera (controlador presente).
func _setup_weather(planet_parser: PlanetParser) -> void:
	var atmo_ctrl: PlanetAtmosphereController = get_node_or_null("PlanetAtmosphereController")
	if atmo_ctrl == null or atmo_ctrl.effect == null:
		return

	weather_controller = WeatherController.new()
	weather_controller.name = "WeatherController"
	weather_controller.add_to_group("weather")
	add_child(weather_controller)
	weather_controller.setup(
		planet,
		water_sphere if planet.has_water else null,
		atmo_ctrl.effect,
		sun_path,
		get_node_or_null("../../WorldEnvironment") as WorldEnvironment,
		players[0] if players.size() > 0 else null,
		voxel_terrain.global_position,
		planet_parser.weather_settings
	)
	_apply_weather_override()

## Empuja la escala de textura al material del terreno. Igual que el anti-tiling, hay que
## llamarla también al cargar: el setter no puede hacerlo porque el material aún no existe.
func _apply_texture_scale() -> void:
	if planet == null:
		return
	var vt_mat := planet.voxel_terrain.material as ShaderMaterial
	if vt_mat != null:
		vt_mat.set_shader_parameter("texture_scale", texture_scale)


## Empuja los parámetros de anti-tiling al material del terreno (afecta a los bloques que se remallen).
func _apply_antitiling_settings() -> void:
	if planet == null:
		return
	var vt_mat := planet.voxel_terrain.material as ShaderMaterial
	if vt_mat == null:
		return
	vt_mat.set_shader_parameter("antitiling_enabled", antitiling_enabled)
	vt_mat.set_shader_parameter("antitiling_variation_scale", antitiling_variation_scale)
	vt_mat.set_shader_parameter("antitiling_blend_softness", antitiling_blend_softness)
	vt_mat.set_shader_parameter("antitiling_rotation_strength", antitiling_rotation_strength)
	vt_mat.set_shader_parameter("antitiling_fade_start", antitiling_fade_start)
	vt_mat.set_shader_parameter("antitiling_fade_end", antitiling_fade_end)

func refresh_world_anchors() -> void:
	if planet == null:
		return
	global_pos = voxel_terrain.global_position
	planet.update_world_center()
	if planet.has_water and water_sphere != null:
		var wmat := water_sphere.quadtree_material as ShaderMaterial
		if wmat != null:
			wmat.set_shader_parameter("planet_center", voxel_terrain.global_position)
	if weather_controller != null:
		weather_controller.set_planet_center(voxel_terrain.global_position)
	for child in get_children():
		if child is NPCSpawner:
			child.set_planet_center(voxel_terrain.global_position)

## Aplica (o suelta) el override de clima en el controlador. No-op si aún no existe (en
## editor o antes de cargar el planeta); _setup_weather lo vuelve a llamar al final.
func _apply_weather_override() -> void:
	if weather_controller == null:
		return
	if force_weather:
		weather_controller.force_weather(forced_weather)
	else:
		weather_controller.clear_force()

func _setup_npc_spawners(planet_parser: PlanetParser) -> void:
	var planet_center := voxel_terrain.global_position
	for spawner_config in planet_parser.npc_spawners:
		var spawner := NPCSpawner.new()
		spawner.setup(
			spawner_config,
			planet_parser.radius,
			planet_parser.atmosphere_height,
			planet_center,
			planet_parser.biome_latitude_ranges,
			players,
			get_parent()
		)
		add_child(spawner)

func _on_file_selected(path: String) -> void:
	config_file_path = path
	_load_planet()
	notify_property_list_changed()

func _open_file_dialog() -> void:
	if not Engine.is_editor_hint():
		return
	
	if not _editor_file_dialog:
		_editor_file_dialog = EditorFileDialog.new()
		_editor_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_editor_file_dialog.add_filter("*.json", "JSON Files")
		_editor_file_dialog.current_dir = "res://data/planet/"
		_editor_file_dialog.size = Vector2i(800, 600)
		_editor_file_dialog.title = "Select Planet Config JSON"
		_editor_file_dialog.file_selected.connect(_on_file_selected)
		
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			var main_control = editor_interface.get_base_control()
			if main_control:
				main_control.add_child(_editor_file_dialog)
			else:
				push_error("DEBUG: Failed to get editor main control to add EditorFileDialog")
				return
		else:
			push_error("DEBUG: EditorInterface singleton not found")
			return
			
	_editor_file_dialog.popup_centered()
	print("DEBUG: EditorFileDialog opened at res://data/planet/")

func _ready() -> void:
	if voxel_terrain.generator:
		voxel_terrain.generator = voxel_terrain.generator.duplicate()
	if voxel_terrain.stream:
		voxel_terrain.stream = voxel_terrain.stream.duplicate()
	
	entity_id = "planet_%s" % name.to_lower()
	voxel_terrain.stream.database_path = "user://saves/%s.sqlite" % [entity_id]
	add_to_group(GameManager.SAVEABLE_GROUP)
	if config_file_path != "res://data/planet/default.json":
		_load_planet()
		
func save_voxel_data() -> VoxelSaveCompletionTracker:
	if voxel_terrain and voxel_terrain.stream:
		return voxel_terrain.save_modified_blocks()
	return null

func get_save_data() -> Dictionary:
	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	var save_pos: Vector3 = fo.to_canonical(global_pos) if fo != null else global_pos
	return {
		"config_file_path": config_file_path,
		"sun_dir": {
			"x": sun_dir.x,
			"y": sun_dir.y,
			"z": sun_dir.z
		},
		"gravity_strength": gravity_strength,
		"global_pos": {
			"x": save_pos.x,
			"y": save_pos.y,
			"z": save_pos.z
		},
		"weather": weather_controller.get_save_data() if weather_controller != null else {}
	}


func restore_save_data(data: Dictionary) -> void:
	config_file_path = data.config_file_path
	gravity_strength = data.gravity_strength
	sun_dir = Vector3(data.sun_dir.x, data.sun_dir.y, data.sun_dir.z)
	global_pos = Vector3(data.global_pos.x, data.global_pos.y, data.global_pos.z)
	_pending_weather_data = data.get("weather", {})

	if config_file_path != "":
		_load_planet()


## Restaura el clima guardado tras la carga, cuando el jugador ya está posicionado
## (el estado se aplica muestreando su altitud), sobrescribiendo el override de escena.
func post_restore() -> void:
	if weather_controller != null and not _pending_weather_data.is_empty():
		weather_controller.restore_save_data(_pending_weather_data)
	_pending_weather_data = {}

func _process(_delta: float) -> void:
	if planet != null:
		planet.sun_dir = sun_dir
		planet._update_planet()
		if planet.has_water:
			water_sphere.sun_dir = sun_dir
			_apply_underwater_settings()
		_apply_impostor_settings()

## Copia los exports de niebla/godrays al nodo Underwater; este los reaplica al material,
## así cualquier cambio en el inspector se ve en el mismo frame.
func _apply_underwater_settings() -> void:
	if water_sphere == null or water_sphere.underwater == null:
		return
	for param in _UNDERWATER_PARAMS:
		water_sphere.underwater.set(param, get(param))
