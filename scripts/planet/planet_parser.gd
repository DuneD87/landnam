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
## Rutas a los GroundFaunaProfile de las especies de superficie de este planeta.
@export var ground_fauna: Array[String] = []
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
## Si está activo, height_textures contiene los mapas R=roughness/G=AO/B=height.
var packed_materials: bool = false

## Familia de sonido de cada textura de terreno, en el mismo orden que "textures". La usan
## las pisadas (ver SurfaceAudio): sin ella, todo el planeta suena a la familia por defecto.
@export var sound_materials: Array[StringName] = []
## Familia de sonido de la textura de pendiente.
@export var slope_sound_material: StringName = &"rock"

@export var slope_texture: Texture2D
@export var slope_normal_texture: Texture2D
@export var slope_roughness_texture: Texture2D
@export var slope_ao_texture: Texture2D
@export var slope_height_texture: Texture2D
@export var slope_threshold: float = 0.35
@export var slope_smoothness: float = 0.18
@export var slope_height_blend_strength: float = 0.0
@export var slope_height_blend_sharpness: float = 0.2
@export var slope_breakup_scale: float = 0.025
@export var slope_breakup_strength: float = 0.0
@export var slope_breakup_anisotropy: float = 2.5
@export var slope_strata_thickness: float = 18.0
@export var slope_strata_strength: float = 0.0
@export var slope_strata_warp: float = 0.35
@export var parallax_enabled: bool = false
@export var parallax_strength: float = 0.09
@export var transition_smoothness: float = 10.0
@export var height_transition_noise_scale: float = 0.015
@export var height_transition_noise_strength: float = 12.0
@export var macro_variation_scale: float = 0.006
@export var macro_variation_strength: float = 0.18
## Calibración del albedo de cada textura, en el orden de "textures" (ver parse_albedo_adjust).
@export var texture_albedo_adjust: PackedVector4Array = PackedVector4Array()
@export var slope_albedo_adjust: Vector4 = Vector4.ONE

@export_group("Atmosphere Settings")
## Sección "atmosphere_settings" del JSON: "enabled", "atmosphere_height" (grosor del aire sobre
## la superficie) y los grupos de propiedades del PlanetAtmosphere (ver apply_settings).
@export var atmosphere_enabled: bool = false
@export var atmosphere_height: float
@export var atmosphere_settings: Dictionary = {}
@export var sun: DirectionalLight3D
@export var wind_direction: Vector3 = Vector3.ZERO

@export_group("Weather Settings")
## Bloque opcional "weather_settings" del JSON. Vacío = el WeatherController usa sus defaults.
@export var weather_settings: Dictionary = {}

@export_group("River Settings")
## Bloque opcional "river_settings" del JSON. Vacío = planeta sin ríos.
@export var river_settings: Dictionary = {}
## Bloque opcional "reef_settings" del JSON: los escollos de la franja costera. Vacío = los valores
## que trae coastal_reefs.tres.
@export var reef_settings: Dictionary = {}

@export_group("Climate Settings")
## Bloque opcional "climate_settings" del JSON: el campo de frío (nieve, taiga, tundra, hielo
## marino). Vacío = planeta sin clima frío (ver ClimateField).
@export var climate_settings: Dictionary = {}

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
	slope_breakup_scale = float(biome_settings.get("slope_breakup_scale", slope_breakup_scale))
	slope_breakup_strength = float(biome_settings.get("slope_breakup_strength", slope_breakup_strength))
	slope_breakup_anisotropy = float(biome_settings.get("slope_breakup_anisotropy", slope_breakup_anisotropy))
	slope_strata_thickness = float(biome_settings.get("slope_strata_thickness", slope_strata_thickness))
	slope_strata_strength = float(biome_settings.get("slope_strata_strength", slope_strata_strength))
	slope_strata_warp = float(biome_settings.get("slope_strata_warp", slope_strata_warp))
	parallax_enabled = bool(biome_settings.get("parallax_enabled", parallax_enabled))
	parallax_strength = float(biome_settings.get("parallax_strength", parallax_strength))
	transition_smoothness = float(biome_settings.get("transition_smoothness", transition_smoothness))
	height_transition_noise_scale = float(biome_settings.get("height_transition_noise_scale", height_transition_noise_scale))
	height_transition_noise_strength = float(biome_settings.get("height_transition_noise_strength", height_transition_noise_strength))
	macro_variation_scale = float(biome_settings.get("macro_variation_scale", macro_variation_scale))
	macro_variation_strength = float(biome_settings.get("macro_variation_strength", macro_variation_strength))
	texture_albedo_adjust = PackedVector4Array()
	for entry in biome_settings.get("texture_albedo", []):
		texture_albedo_adjust.append(parse_albedo_adjust(entry))
	slope_albedo_adjust = parse_albedo_adjust(biome_settings.get("slope_albedo", {}))
	slope_sound_material = StringName(biome_settings.get("slope_sound_material", slope_sound_material))

	sound_materials = []
	for value in biome_settings.get("sound_materials", []):
		sound_materials.append(StringName(value))

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

	ground_fauna.clear()
	for profile_path in biome_settings.get("ground_fauna", []):
		ground_fauna.append(str(profile_path))

	ore_settings.clear()
	for ore_data in config.get("ore_settings", []):
		ore_settings.append(ore_data)

	print("DEBUG: Loaded biome settings: count=", biome_count, ", textures_per_biome=", textures_per_biome)
	
	# Los campos nuevos son opcionales: los JSON anteriores mantienen sus mapas separados.
	packed_materials = biome_settings.has("packed_material_textures")
	if packed_materials:
		if biome_settings.packed_material_textures.size() != biome_settings.textures.size() or not biome_settings.has("slope_packed_material_texture"):
			push_error("PlanetParser: mapas empaquetados incompletos")
			return
	roughness_textures.clear()
	ao_textures.clear()
	slope_roughness_texture = null
	slope_ao_texture = null

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
	
	if not packed_materials:
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
	var height_paths: Array = biome_settings.packed_material_textures if packed_materials else biome_settings.height_textures
	for path in height_paths:
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
	
	if not packed_materials:
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
	
	var slope_height_path: String = biome_settings.slope_packed_material_texture if packed_materials else biome_settings.slope_height_texture
	slope_height_texture = load(slope_height_path) as Texture2D
	if not slope_height_texture:
		push_error("DEBUG: Failed to load slope height texture: " + slope_height_path)
		return
	print("DEBUG: Loaded slope height texture: " + slope_height_path)
	
	atmosphere_settings = config.get("atmosphere_settings", {})
	atmosphere_enabled = bool(atmosphere_settings.get("enabled", false))
	atmosphere_height = float(atmosphere_settings.get("atmosphere_height", 0.0))
	print("DEBUG: Loaded atmosphere settings: enabled=", atmosphere_enabled, ", height=", atmosphere_height)

	weather_settings = config.get("weather_settings", {})
	print("DEBUG: Loaded weather settings: ", weather_settings)

	river_settings = _parse_river_settings(config.get("river_settings", {}))
	reef_settings = config.get("reef_settings", {})
	climate_settings = config.get("climate_settings", {})


## Normaliza el bloque de ríos: los tamaños llegan como pares [ancho, alto] desde el JSON y el resto
## del pipeline los quiere como Vector2i.
func _parse_river_settings(cfg: Dictionary) -> Dictionary:
	if cfg.is_empty():
		return {}
	var out := cfg.duplicate(true)
	for key in ["hydrology_size", "dist_size", "bed_size"]:
		if out.has(key) and out[key] is Array and out[key].size() == 2:
			out[key] = Vector2i(int(out[key][0]), int(out[key][1]))
	return out


## Una entrada de "texture_albedo"/"slope_albedo": {"gain": 1.0, "tint": [r, g, b], "saturation": 1.0},
## todas opcionales. Devuelve xyz = gain * tint (multiplicador lineal) y w = saturación, que es lo
## que espera planet_biomes.gdshader. Lo que no sea un diccionario cuenta como textura sin calibrar.
static func parse_albedo_adjust(entry: Variant) -> Vector4:
	if not entry is Dictionary:
		return Vector4.ONE
	var gain := float(entry.get("gain", 1.0))
	var tint: Array = entry.get("tint", [1.0, 1.0, 1.0])
	return Vector4(gain * float(tint[0]), gain * float(tint[1]), gain * float(tint[2]),
		float(entry.get("saturation", 1.0)))


func _load_biome_noise_texture_overrides(biome_settings: Dictionary) -> void:
	biome_noise_enabled = []
	biome_noise_source_texture_indices = []
	biome_noise_target_texture_indices = []
	biome_noise_scales = []
	biome_noise_thresholds = []
	biome_noise_smoothness = []
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
		biome_noise_seeds[biome_index] = float(override_config.get("seed", 1337.0))
		biome_noise_invert[biome_index] = 1 if override_config.get("invert", false) else 0
		biome_noise_abs_latitude_mins[biome_index] = float(override_config.get("abs_latitude_min", 0.0))
		biome_noise_abs_latitude_maxs[biome_index] = float(override_config.get("abs_latitude_max", 90.0))
		biome_noise_latitude_smoothness[biome_index] = float(override_config.get("latitude_smoothness", 1.0))
