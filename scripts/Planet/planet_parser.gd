class_name PlanetParser extends Node3D

## Lee un JSON de planeta (terreno, biomas, atmósfera, agua, clima) a campos tipados que
## consume el PlanetLoader.

@export_group("Terrain Settings")
@export var radius: float
@export var vegetation : Dictionary
@export var terrain_material: ShaderMaterial
@export var terrain_generator_path: String
@export var has_water: bool
@export var water_level: float

@export_group("Biome Settings")
@export var npc_spawners: Array[Dictionary] = []
@export var ore_settings: Array[Dictionary] = []
@export var biome_count: int
@export var textures_per_biome: int
@export var biome_latitude_ranges: Array[float] = []
@export var biome_transition_smoothness: float
@export var max_heights: Array[float] = []

@export var biome_texture_indices: Array[int] = []
@export var biome_noise_enabled: Array[int] = []
@export var biome_noise_source_texture_indices: Array[int] = []
@export var biome_noise_target_texture_indices: Array[int] = []
@export var biome_noise_scales: Array[float] = []
@export var biome_noise_thresholds: Array[float] = []
@export var biome_noise_smoothness: Array[float] = []
@export var biome_noise_strengths: Array[float] = []
@export var biome_noise_seeds: Array[float] = []
@export var biome_noise_invert: Array[int] = []
@export var biome_noise_abs_latitude_mins: Array[float] = []
@export var biome_noise_abs_latitude_maxs: Array[float] = []
@export var biome_noise_latitude_smoothness: Array[float] = []
@export var textures: Array[Texture2D] = []
@export var normal_textures: Array[Texture2D] = []
@export var roughness_textures: Array[Texture2D] = []
@export var ao_textures: Array[Texture2D] = []
@export var height_textures: Array[Texture2D] = []

@export var slope_texture: Texture2D
@export var slope_normal_texture: Texture2D
@export var slope_roughness_texture: Texture2D
@export var slope_ao_texture: Texture2D
@export var slope_height_texture: Texture2D
@export var slope_threshold: float = 0.35
@export var slope_smoothness: float = 0.18
@export var slope_height_blend_strength: float = 0.0
@export var slope_height_blend_sharpness: float = 0.2
@export var macro_variation_scale: float = 0.006
@export var macro_variation_strength: float = 0.18

@export_group("Atmosphere Settings")
@export var atmosphere_radius: float
@export var atmosphere_height: float
@export var atmosphere_density: float
@export var atmosphere_scattering: Vector3
@export var atmosphere_modulate: Vector3
@export var sun: DirectionalLight3D
@export var sun_dir: Vector3
@export var wind_direction: Vector3 = Vector3.ZERO
@export var has_clouds: bool = true

@export_group("Weather Settings")
## Bloque opcional "weather_settings" del JSON. Vacío = el WeatherController usa sus defaults.
@export var weather_settings: Dictionary = {}

@export_group("Underwater settings")
@export var fog_density: float = 0.5
@export var fog_color: Color = Color(0.3, 0.2, 0.8, 1.0)
@export var absorption: float = 0.3
@export var scattering: float = 0.2
@export var noise_scale: float = 2.0
@export var noise_speed: float = 0.1
@export var scale_modifier: float = 1.0
@export var max_steps: int = 0
@export var step_size: float = 0

@export_group("Water settings")
@export var player: CharacterBody3D
@export var sub_divisions: int = 32
@export var subdivision_factor: float = 2.0
@export var max_lod: int = 5
@export var enable_wireframe: bool = false
@export var use_gpu_compute: bool = true
@export var camera: Camera3D
@export var debug: bool = false
@export var quadtree_material: Material
@export var wireframe_material: Material
@export var show_stats: bool = true

func _init(_sun: DirectionalLight3D) -> void:
	print("Planet parser initialized")

	sun = _sun
	
	
func _load_vegetation_settings(data:Dictionary) -> void:
	if data.is_empty():
			return
	
	vegetation = data
	wind_direction.x = data.wind_direction[0]
	wind_direction.y = data.wind_direction[1]
	wind_direction.z = data.wind_direction[2]
	

func load_config(config_path: String):
	print("DEBUG: Loading config: " + config_path)
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		push_error("DEBUG: Failed to open config file: " + config_path)
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("DEBUG: Failed to parse JSON: " + json.get_error_message())
		return
	
	var config = json.get_data()

	if not config.has("terrain_settings") or not config.terrain_settings.has("radius"):
		push_error("DEBUG: Invalid terrain settings in config.")
		return
	radius = config.terrain_settings.radius
	
	if not config.has("terrain_settings") or not config.terrain_settings.has("has_water"):
		push_error("DEBUG: Invalid terrain settings in config.")
		return
	has_water = config.terrain_settings.has_water
	
	if not config.has("terrain_settings") or not config.terrain_settings.has("water_level"):
		push_error("DEBUG: Invalid terrain settings in config.")
		return
	water_level = config.terrain_settings.water_level
	
	terrain_generator_path = config.terrain_settings.terrain_generator
	print("DEBUG: Terrain generator readed: ", terrain_generator_path)
	print("DEBUG: Loaded radius: ", radius)
	_load_vegetation_settings(config.get("vegetation_settings", {}))
	var biome_settings = config.get("biome_settings", {})
	if not biome_settings.has_all(["biome_count", "textures_per_biome", "biome_latitude_ranges", 
			"biome_transition_smoothness", "max_heights", "biome_texture_indices", 
			"textures", "normal_textures", "roughness_textures", "ao_textures", "height_textures",
			"slope_texture", "slope_normal_texture", "slope_roughness_texture", "slope_ao_texture", "slope_height_texture"]):
		push_error("DEBUG: Invalid biome settings in config.")
		return
	
	biome_count = biome_settings.biome_count
	print(biome_settings.textures_per_biome)

	textures_per_biome = biome_settings.textures_per_biome
	
	biome_latitude_ranges = []
	for value in biome_settings.biome_latitude_ranges:
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			biome_latitude_ranges.append(float(value))
		else:
			push_error("DEBUG: Invalid value in biome_latitude_ranges: " + str(value))
			return
	
	biome_transition_smoothness = biome_settings.biome_transition_smoothness
	# Opcionales: el umbral se compara contra 1 - dot(normal, up), no contra el angulo.
	slope_threshold = float(biome_settings.get("slope_threshold", slope_threshold))
	slope_smoothness = float(biome_settings.get("slope_smoothness", slope_smoothness))
	slope_height_blend_strength = float(biome_settings.get("slope_height_blend_strength", slope_height_blend_strength))
	slope_height_blend_sharpness = float(biome_settings.get("slope_height_blend_sharpness", slope_height_blend_sharpness))
	macro_variation_scale = float(biome_settings.get("macro_variation_scale", macro_variation_scale))
	macro_variation_strength = float(biome_settings.get("macro_variation_strength", macro_variation_strength))

	max_heights = []
	for value in biome_settings.max_heights:
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			max_heights.append(float(value))
		else:
			push_error("DEBUG: Invalid value in max_heights: " + str(value))
			return
	
	biome_texture_indices = []
	for value in biome_settings.biome_texture_indices:
		biome_texture_indices.append(int(value))

	_load_biome_noise_texture_overrides(biome_settings)

	npc_spawners.clear()
	for spawner_data in biome_settings.get("npc_spawners", []):
		npc_spawners.append(spawner_data)

	ore_settings.clear()
	for ore_data in config.get("ore_settings", []):
		ore_settings.append(ore_data)

	print("DEBUG: Loaded biome settings: count=", biome_count, ", textures_per_biome=", textures_per_biome)
	
	textures = []
	for path in biome_settings.textures:
		var texture = load(path) as Texture2D
		if texture:
			textures.append(texture)
			print("DEBUG: Loaded texture: " + path)
		else:
			push_error("DEBUG: Failed to load texture: " + path)
			return

	normal_textures = []
	for path in biome_settings.normal_textures:
		var texture = load(path) as Texture2D
		if texture:
			normal_textures.append(texture)
			print("DEBUG: Loaded normal texture: " + path)
		else:
			push_error("DEBUG: Failed to load normal texture: " + path)
			return
	
	roughness_textures = []
	for path in biome_settings.roughness_textures:
		var texture = load(path) as Texture2D
		if texture:
			roughness_textures.append(texture)
			print("DEBUG: Loaded roughness texture: " + path)
		else:
			push_error("DEBUG: Failed to load roughness texture: " + path)
			return
	ao_textures = []
	for path in biome_settings.ao_textures:
		var texture = load(path) as Texture2D
		if texture:
			ao_textures.append(texture)
			print("DEBUG: Loaded ambient oclussion texture: " + path)
		else:
			push_error("DEBUG: Failed to load ambient oclussion texture: " + path)
			return
	height_textures = []
	for path in biome_settings.height_textures:
		var texture = load(path) as Texture2D
		if texture:
			height_textures.append(texture)
			print("DEBUG: Loaded height texture: " + path)
		else:
			push_error("DEBUG: Failed to load height texture: " + path)
			return
	slope_texture = load(biome_settings.slope_texture) as Texture2D
	if not slope_texture:
		push_error("DEBUG: Failed to load slope texture: " + biome_settings.slope_texture)
		return
	print("DEBUG: Loaded slope texture: " + biome_settings.slope_texture)
	
	slope_normal_texture = load(biome_settings.slope_normal_texture) as Texture2D
	if not slope_normal_texture:
		push_error("DEBUG: Failed to load slope normal texture: " + biome_settings.slope_normal_texture)
		return
	print("DEBUG: Loaded slope normal texture: " + biome_settings.slope_normal_texture)
	
	slope_roughness_texture = load(biome_settings.slope_roughness_texture) as Texture2D
	if not slope_roughness_texture:
		push_error("DEBUG: Failed to load slope roughness texture: " + biome_settings.slope_roughness_texture)
		return
	print("DEBUG: Loaded slope roughness texture: " + biome_settings.slope_roughness_texture)
	
	slope_ao_texture = load(biome_settings.slope_ao_texture) as Texture2D
	if not slope_ao_texture:
		push_error("DEBUG: Failed to load slope ao texture: " + biome_settings.slope_ao_texture)
		return
	print("DEBUG: Loaded slope ao texture: " + biome_settings.slope_ao_texture)
	
	slope_height_texture = load(biome_settings.slope_height_texture) as Texture2D
	if not slope_height_texture:
		push_error("DEBUG: Failed to load slope height texture: " + biome_settings.slope_height_texture)
		return
	print("DEBUG: Loaded slope height texture: " + biome_settings.slope_height_texture)
	
	var atmosphere_settings = config.get("atmosphere_settings", {})
	print(atmosphere_settings)
	if not atmosphere_settings.has_all(["atmosphere_height", "atmosphere_density"]):
		push_error("DEBUG: Invalid atmosphere settings in config.")
		return
	
	atmosphere_height = atmosphere_settings.atmosphere_height
	atmosphere_density = atmosphere_settings.atmosphere_density
	
	atmosphere_scattering.x = atmosphere_settings.scattering_wavelength[0]
	atmosphere_scattering.y = atmosphere_settings.scattering_wavelength[1]
	atmosphere_scattering.z = atmosphere_settings.scattering_wavelength[2]
	
	atmosphere_modulate.x = atmosphere_settings.atmosphere_modulate[0]
	atmosphere_modulate.y = atmosphere_settings.atmosphere_modulate[1]
	atmosphere_modulate.z = atmosphere_settings.atmosphere_modulate[2]
	
	has_clouds = atmosphere_settings.has_clouds

	print("DEBUG: Loaded atmosphere settings: height=", atmosphere_height, ", density=", atmosphere_density)
	
	if atmosphere_settings.has("sun_path") and atmosphere_settings.sun_path:
		sun = get_node_or_null(atmosphere_settings.sun_path) as DirectionalLight3D
		if not sun:
			push_warning("DEBUG: Sun node not found at path: " + atmosphere_settings.sun_path)
		else:
			print("DEBUG: Loaded sun node at path: " + atmosphere_settings.sun_path)
	
	if atmosphere_settings.has("sun_dir") and atmosphere_settings.sun_dir.size() == 3:
		sun_dir = Vector3(
			atmosphere_settings.sun_dir[0],
			atmosphere_settings.sun_dir[1],
			atmosphere_settings.sun_dir[2]
		)
		print("DEBUG: Loaded sun_dir: ", sun_dir)

	weather_settings = config.get("weather_settings", {})
	print("DEBUG: Loaded weather settings: ", weather_settings)


func _load_biome_noise_texture_overrides(biome_settings: Dictionary) -> void:
	biome_noise_enabled = []
	biome_noise_source_texture_indices = []
	biome_noise_target_texture_indices = []
	biome_noise_scales = []
	biome_noise_thresholds = []
	biome_noise_smoothness = []
	biome_noise_strengths = []
	biome_noise_seeds = []
	biome_noise_invert = []
	biome_noise_abs_latitude_mins = []
	biome_noise_abs_latitude_maxs = []
	biome_noise_latitude_smoothness = []

	for i in biome_count:
		biome_noise_enabled.append(0)
		biome_noise_source_texture_indices.append(0)
		biome_noise_target_texture_indices.append(0)
		biome_noise_scales.append(0.001)
		biome_noise_thresholds.append(0.5)
		biome_noise_smoothness.append(0.15)
		biome_noise_strengths.append(1.0)
		biome_noise_seeds.append(1337.0)
		biome_noise_invert.append(0)
		biome_noise_abs_latitude_mins.append(0.0)
		biome_noise_abs_latitude_maxs.append(90.0)
		biome_noise_latitude_smoothness.append(1.0)

	if not biome_settings.has("biome_noise_texture_overrides"):
		return

	for override_config in biome_settings.biome_noise_texture_overrides:
		if not override_config.has("biome"):
			push_warning("DEBUG: Ignoring biome noise texture override without biome index.")
			continue

		var biome_index := int(override_config.biome)
		if biome_index < 0 or biome_index >= biome_count:
			push_warning("DEBUG: Ignoring biome noise texture override with invalid biome index: " + str(biome_index))
			continue

		biome_noise_enabled[biome_index] = 1
		biome_noise_source_texture_indices[biome_index] = int(override_config.get("source_texture", 0))
		biome_noise_target_texture_indices[biome_index] = int(override_config.get("target_texture", 0))
		if override_config.has("period"):
			var period : float = max(float(override_config.period), 0.0001)
			biome_noise_scales[biome_index] = 1.0 / period
		else:
			biome_noise_scales[biome_index] = float(override_config.get("scale", 0.001))
		biome_noise_thresholds[biome_index] = float(override_config.get("threshold", 0.5))
		biome_noise_smoothness[biome_index] = float(override_config.get("smoothness", 0.15))
		biome_noise_strengths[biome_index] = float(override_config.get("strength", 1.0))
		biome_noise_seeds[biome_index] = float(override_config.get("seed", 1337.0))
		biome_noise_invert[biome_index] = 1 if override_config.get("invert", false) else 0
		biome_noise_abs_latitude_mins[biome_index] = float(override_config.get("abs_latitude_min", 0.0))
		biome_noise_abs_latitude_maxs[biome_index] = float(override_config.get("abs_latitude_max", 90.0))
		biome_noise_latitude_smoothness[biome_index] = float(override_config.get("latitude_smoothness", 1.0))
