class_name PlanetParser extends Node3D

## Lee el JSON sin cambiar su formato. Biomas, materiales y generación se escriben directamente
## en la PlanetDefinition que conservará el planeta; el resto configura sus nodos asociados.

@export var definition: PlanetDefinition = PlanetDefinition.new()

@export_group("Terrain Settings")
@export var radius: float
@export var terrain_material: ShaderMaterial
@export var has_water: bool
@export var water_level: float

@export_group("Biome Settings")
## Rutas a los GroundFaunaProfile de las especies de superficie de este planeta.
@export var ground_fauna: Array[String] = []


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
	
	definition.vegetation = data
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
	
	definition.terrain_generator_path = config.terrain_settings.terrain_generator
	print("DEBUG: Terrain generator readed: ", definition.terrain_generator_path)
	print("DEBUG: Loaded radius: ", radius)
	_load_vegetation_settings(config.get("vegetation_settings", {}))
	var biome_settings = config.get("biome_settings", {})
	if not biome_settings.has_all(["biome_count", "textures_per_biome", "biome_latitude_ranges", 
			"biome_transition_smoothness", "max_heights", "biome_texture_indices", 
			"textures", "normal_textures", "roughness_textures", "ao_textures", "height_textures",
			"slope_texture", "slope_normal_texture", "slope_roughness_texture", "slope_ao_texture", "slope_height_texture"]):
		push_error("DEBUG: Invalid biome settings in config.")
		return
	
	definition.biome_count = biome_settings.biome_count
	print(biome_settings.textures_per_biome)

	definition.textures_per_biome = biome_settings.textures_per_biome
	
	definition.biome_latitude_ranges = []
	for value in biome_settings.biome_latitude_ranges:
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			definition.biome_latitude_ranges.append(float(value))
		else:
			push_error("DEBUG: Invalid value in biome_latitude_ranges: " + str(value))
			return
	
	definition.biome_transition_smoothness = biome_settings.biome_transition_smoothness
	# Opcionales: el umbral se compara contra 1 - dot(normal, up), no contra el angulo.
	definition.slope_threshold = float(biome_settings.get("slope_threshold", definition.slope_threshold))
	definition.slope_smoothness = float(biome_settings.get("slope_smoothness", definition.slope_smoothness))
	definition.slope_height_blend_strength = float(biome_settings.get("slope_height_blend_strength", definition.slope_height_blend_strength))
	definition.slope_height_blend_sharpness = float(biome_settings.get("slope_height_blend_sharpness", definition.slope_height_blend_sharpness))
	definition.slope_breakup_scale = float(biome_settings.get("slope_breakup_scale", definition.slope_breakup_scale))
	definition.slope_breakup_strength = float(biome_settings.get("slope_breakup_strength", definition.slope_breakup_strength))
	definition.slope_breakup_anisotropy = float(biome_settings.get("slope_breakup_anisotropy", definition.slope_breakup_anisotropy))
	definition.slope_strata_thickness = float(biome_settings.get("slope_strata_thickness", definition.slope_strata_thickness))
	definition.slope_strata_strength = float(biome_settings.get("slope_strata_strength", definition.slope_strata_strength))
	definition.slope_strata_warp = float(biome_settings.get("slope_strata_warp", definition.slope_strata_warp))
	definition.parallax_enabled = bool(biome_settings.get("parallax_enabled", definition.parallax_enabled))
	definition.parallax_strength = float(biome_settings.get("parallax_strength", definition.parallax_strength))
	definition.transition_smoothness = float(biome_settings.get("transition_smoothness", definition.transition_smoothness))
	definition.height_transition_noise_scale = float(biome_settings.get("height_transition_noise_scale", definition.height_transition_noise_scale))
	definition.height_transition_noise_strength = float(biome_settings.get("height_transition_noise_strength", definition.height_transition_noise_strength))
	definition.macro_variation_scale = float(biome_settings.get("macro_variation_scale", definition.macro_variation_scale))
	definition.macro_variation_strength = float(biome_settings.get("macro_variation_strength", definition.macro_variation_strength))
	definition.texture_albedo_adjust = PackedVector4Array()
	for entry in biome_settings.get("texture_albedo", []):
		definition.texture_albedo_adjust.append(parse_albedo_adjust(entry))
	definition.slope_albedo_adjust = parse_albedo_adjust(biome_settings.get("slope_albedo", {}))
	definition.slope_sound_material = StringName(biome_settings.get("slope_sound_material", definition.slope_sound_material))

	definition.sound_materials = []
	for value in biome_settings.get("sound_materials", []):
		definition.sound_materials.append(StringName(value))

	definition.max_heights = []
	for value in biome_settings.max_heights:
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			definition.max_heights.append(float(value))
		else:
			push_error("DEBUG: Invalid value in max_heights: " + str(value))
			return
	
	definition.biome_texture_indices = []
	for value in biome_settings.biome_texture_indices:
		definition.biome_texture_indices.append(int(value))

	_load_biome_noise_texture_overrides(biome_settings)

	ground_fauna.clear()
	for profile_path in biome_settings.get("ground_fauna", []):
		ground_fauna.append(str(profile_path))

	definition.ore_settings.clear()
	for ore_data in config.get("ore_settings", []):
		definition.ore_settings.append(ore_data)

	print("DEBUG: Loaded biome settings: count=", definition.biome_count, ", textures_per_biome=", definition.textures_per_biome)
	
	# Los campos nuevos son opcionales: los JSON anteriores mantienen sus mapas separados.
	definition.packed_materials = biome_settings.has("packed_material_textures")
	if definition.packed_materials:
		if biome_settings.packed_material_textures.size() != biome_settings.textures.size() or not biome_settings.has("slope_packed_material_texture"):
			push_error("PlanetParser: mapas empaquetados incompletos")
			return
	if not _load_biome_textures(biome_settings):
		return

	atmosphere_settings = config.get("atmosphere_settings", {})
	atmosphere_enabled = bool(atmosphere_settings.get("enabled", false))
	atmosphere_height = float(atmosphere_settings.get("atmosphere_height", 0.0))
	print("DEBUG: Loaded atmosphere settings: enabled=", atmosphere_enabled, ", height=", atmosphere_height)

	weather_settings = config.get("weather_settings", {})
	print("DEBUG: Loaded weather settings: ", weather_settings)

	definition.river_settings = _parse_river_settings(config.get("river_settings", {}))
	definition.reef_settings = config.get("reef_settings", {})
	definition.climate_settings = config.get("climate_settings", {})


## Carga las capas y los mapas de pendiente por la misma ruta, tanto con mapas separados
## como con los tres canales empaquetados. Los arrays mantienen su tipo para el shader.
func _load_biome_textures(settings: Dictionary) -> bool:
	var packed := definition.packed_materials
	definition.roughness_textures.clear()
	definition.ao_textures.clear()
	definition.slope_roughness_texture = null
	definition.slope_ao_texture = null
	var layers := {
		"textures": settings.textures,
		"normal_textures": settings.normal_textures,
		"height_textures": settings.packed_material_textures if packed else settings.height_textures,
	}
	var slopes := {
		"slope_texture": settings.slope_texture,
		"slope_normal_texture": settings.slope_normal_texture,
		"slope_height_texture": settings.slope_packed_material_texture if packed else settings.slope_height_texture,
	}
	if not packed:
		layers["roughness_textures"] = settings.roughness_textures
		layers["ao_textures"] = settings.ao_textures
		slopes["slope_roughness_texture"] = settings.slope_roughness_texture
		slopes["slope_ao_texture"] = settings.slope_ao_texture
	for key in layers:
		var textures: Array[Texture2D] = []
		for path in layers[key]:
			var texture := load(path) as Texture2D
			if texture == null:
				push_error("PlanetParser: no se pudo cargar %s: %s" % [key, path])
				return false
			textures.append(texture)
		definition.set(key, textures)
	for key in slopes:
		var texture := load(slopes[key]) as Texture2D
		if texture == null:
			push_error("PlanetParser: no se pudo cargar %s: %s" % [key, slopes[key]])
			return false
		definition.set(key, texture)
	return true


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
	definition.biome_noise_enabled = []
	definition.biome_noise_source_texture_indices = []
	definition.biome_noise_target_texture_indices = []
	definition.biome_noise_scales = []
	definition.biome_noise_thresholds = []
	definition.biome_noise_smoothness = []
	definition.biome_noise_seeds = []
	definition.biome_noise_invert = []
	definition.biome_noise_abs_latitude_mins = []
	definition.biome_noise_abs_latitude_maxs = []
	definition.biome_noise_latitude_smoothness = []

	for i in definition.biome_count:
		definition.biome_noise_enabled.append(0)
		definition.biome_noise_source_texture_indices.append(0)
		definition.biome_noise_target_texture_indices.append(0)
		definition.biome_noise_scales.append(0.001)
		definition.biome_noise_thresholds.append(0.5)
		definition.biome_noise_smoothness.append(0.15)
		definition.biome_noise_seeds.append(1337.0)
		definition.biome_noise_invert.append(0)
		definition.biome_noise_abs_latitude_mins.append(0.0)
		definition.biome_noise_abs_latitude_maxs.append(90.0)
		definition.biome_noise_latitude_smoothness.append(1.0)

	if not biome_settings.has("biome_noise_texture_overrides"):
		return

	for override_config in biome_settings.biome_noise_texture_overrides:
		if not override_config.has("biome"):
			push_warning("DEBUG: Ignoring biome noise texture override without biome index.")
			continue

		var biome_index := int(override_config.biome)
		if biome_index < 0 or biome_index >= definition.biome_count:
			push_warning("DEBUG: Ignoring biome noise texture override with invalid biome index: " + str(biome_index))
			continue

		definition.biome_noise_enabled[biome_index] = 1
		definition.biome_noise_source_texture_indices[biome_index] = int(override_config.get("source_texture", 0))
		definition.biome_noise_target_texture_indices[biome_index] = int(override_config.get("target_texture", 0))
		if override_config.has("period"):
			var period : float = max(float(override_config.period), 0.0001)
			definition.biome_noise_scales[biome_index] = 1.0 / period
		else:
			definition.biome_noise_scales[biome_index] = float(override_config.get("scale", 0.001))
		definition.biome_noise_thresholds[biome_index] = float(override_config.get("threshold", 0.5))
		definition.biome_noise_smoothness[biome_index] = float(override_config.get("smoothness", 0.15))
		definition.biome_noise_seeds[biome_index] = float(override_config.get("seed", 1337.0))
		definition.biome_noise_invert[biome_index] = 1 if override_config.get("invert", false) else 0
		definition.biome_noise_abs_latitude_mins[biome_index] = float(override_config.get("abs_latitude_min", 0.0))
		definition.biome_noise_abs_latitude_maxs[biome_index] = float(override_config.get("abs_latitude_max", 90.0))
		definition.biome_noise_latitude_smoothness[biome_index] = float(override_config.get("latitude_smoothness", 1.0))
