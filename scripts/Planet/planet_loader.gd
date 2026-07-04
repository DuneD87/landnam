@tool
extends Node

## Carga un planeta desde su JSON (vía PlanetParser), lo instancia con su terreno, agua, clima y
## spawners de NPC, y expone el guardado/carga y los ajustes de godrays y anti-tiling.

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

@export_group("Underwater Godray Settings")
@export var godray_intensity: float = 1.9
@export var godray_decay: float = 0.88
@export var godray_exposure: float = 0.4
@export var godray_samples: int = 10
@export var godray_max_depth: float = 35.0
@export var godray_fade_start: float = 10.0
@export var godray_density: float = 0.12
@export var godray_surface_scale: float = 0.1
@export var godray_surface_speed: float = 0.12
@export var godray_surface_contrast: float = 3.0
@export var godray_light_absorption: float = 0.08
@export var godray_view_absorption: float = 0.025
@export var godray_forward_scatter_power: float = 3.0
@export var godray_min_phase: float = 0.15

var _config_action: Action = Action.NONE
var water_material : ShaderMaterial
var weather_controller: WeatherController
var _pending_weather_data: Dictionary = {}

func _apply_godray_settings_to_water_sphere() -> void:
	if not water_sphere:
		return
	water_sphere.godray_intensity = godray_intensity
	water_sphere.godray_decay = godray_decay
	water_sphere.godray_exposure = godray_exposure
	water_sphere.godray_samples = godray_samples
	water_sphere.godray_max_depth = godray_max_depth
	water_sphere.godray_fade_start = godray_fade_start
	water_sphere.godray_density = godray_density
	water_sphere.godray_surface_scale = godray_surface_scale
	water_sphere.godray_surface_speed = godray_surface_speed
	water_sphere.godray_surface_contrast = godray_surface_contrast
	water_sphere.godray_light_absorption = godray_light_absorption
	water_sphere.godray_view_absorption = godray_view_absorption
	water_sphere.godray_forward_scatter_power = godray_forward_scatter_power
	water_sphere.godray_min_phase = godray_min_phase

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

@export_range(0.0, 1.0, 0.1) var texture_scale: float = 0.5:
	set(value):
		if planet == null:
			return
		texture_scale = value
		planet.voxel_terrain.material.set_shader_parameter("texture_scale", texture_scale)

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
	planet.biome_noise_enabled = planet_parser.biome_noise_enabled
	planet.biome_noise_source_texture_indices = planet_parser.biome_noise_source_texture_indices
	planet.biome_noise_target_texture_indices = planet_parser.biome_noise_target_texture_indices
	planet.biome_noise_scales = planet_parser.biome_noise_scales
	planet.biome_noise_thresholds = planet_parser.biome_noise_thresholds
	planet.biome_noise_smoothness = planet_parser.biome_noise_smoothness
	planet.biome_noise_strengths = planet_parser.biome_noise_strengths
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
	planet.has_water = planet_parser.has_water
	planet.water_radius = planet_parser.water_level
	planet.ore_settings = planet_parser.ore_settings
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
		_apply_godray_settings_to_water_sphere()
		
		water_sphere.load_watersphere(planet)

	if not Engine.is_editor_hint():
		_setup_weather(planet_parser)

	_setup_npc_spawners(planet_parser)


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
			_apply_godray_settings_to_water_sphere()
	pass
