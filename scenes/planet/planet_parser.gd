@tool
extends Node

@export var config_path: String = "res://data/planet_config.json"
@onready var planet_factory: Node = $PlanetFactory

func _ready() -> void:
	if planet_factory:
		push_error("PlanetFactory not assigned.")
		return
	
	var config = load_config()
	if config:
		create_planet_from_config(config)

func load_config() -> Dictionary:
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		push_error("Failed to open config file: " + config_path)
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("Failed to parse JSON: " + json.get_error_message())
		return {}
	
	return json.get_data()

func create_planet_from_config(config: Dictionary) -> void:
	# Validate terrain settings
	if not config.has("terrain_settings") or not config.terrain_settings.has("radius"):
		push_error("Invalid terrain settings in config.")
		return
	
	# Validate biome settings
	var biome_settings = config.get("biome_settings", {})
	if not biome_settings.has_all(["biome_count", "textures_per_biome", "biome_latitude_ranges", 
			"biome_transition_smoothness", "max_heights", "biome_texture_indices", 
			"textures", "normal_textures", "roughness_textures", 
			"slope_texture", "slope_normal_texture", "slope_roughness_texture"]):
		push_error("Invalid biome settings in config.")
		return
	
	# Validate atmosphere settings
	var atmosphere_settings = config.get("atmosphere_settings", {})
	if not atmosphere_settings.has_all(["atmosphere_radius", "atmosphere_density"]):
		push_error("Invalid atmosphere settings in config.")
		return
	
	# Load textures
	var textures: Array[CompressedTexture2D] = []
	for path in biome_settings.textures:
		var texture = load(path) as Texture2D
		if texture:
			textures.append(texture)
		else:
			push_error("Failed to load texture: " + path)
			return
	
	var normal_textures: Array[CompressedTexture2D] = []
	for path in biome_settings.normal_textures:
		var texture = load(path) as Texture2D
		if texture:
			normal_textures.append(texture)
		else:
			push_error("Failed to load normal texture: " + path)
			return
	
	var roughness_textures: Array[CompressedTexture2D] = []
	for path in biome_settings.roughness_textures:
		var texture = load(path) as Texture2D
		if texture:
			roughness_textures.append(texture)
		else:
			push_error("Failed to load roughness texture: " + path)
			return
	
	var slope_texture = load(biome_settings.slope_texture) as CompressedTexture2D
	if not slope_texture:
		push_error("Failed to load slope texture: " + biome_settings.slope_texture)
		return
	
	var slope_normal_texture = load(biome_settings.slope_normal_texture) as CompressedTexture2D
	if not slope_normal_texture:
		push_error("Failed to load slope normal texture: " + biome_settings.slope_normal_texture)
		return
	
	var slope_roughness_texture = load(biome_settings.slope_roughness_texture) as CompressedTexture2D
	if not slope_roughness_texture:
		push_error("Failed to load slope roughness texture: " + biome_settings.slope_roughness_texture)
		return
	
	# Load sun
	var sun: DirectionalLight3D = null
	if atmosphere_settings.sun_path:
		sun = get_node_or_null(atmosphere_settings.sun_path) as DirectionalLight3D
		if not sun:
			push_warning("Sun node not found at path: " + atmosphere_settings.sun_path)
	
	# Create planet via factory
	planet_factory.radius = config.terrain_settings.radius
	planet_factory.biome_count = biome_settings.biome_count
	planet_factory.textures_per_biome = biome_settings.textures_per_biome
	planet_factory.biome_latitude_ranges = biome_settings.biome_latitude_ranges
	planet_factory.biome_transition_smoothness = biome_settings.biome_transition_smoothness
	planet_factory.max_heights = biome_settings.max_heights
	planet_factory.biome_texture_indices = biome_settings.biome_texture_indices
	planet_factory.textures = textures
	planet_factory.normal_textures = normal_textures
	planet_factory.roughness_textures = roughness_textures
	planet_factory.slope_texture = slope_texture
	planet_factory.slope_normal_texture = slope_normal_texture
	planet_factory.slope_roughness_texture = slope_roughness_texture
	planet_factory.atmosphere_radius = atmosphere_settings.atmosphere_radius
	planet_factory.atmosphere_density = atmosphere_settings.atmosphere_density
	planet_factory.sun = sun
	planet_factory.sun_dir = Vector3(
		atmosphere_settings.sun_dir[0],
		atmosphere_settings.sun_dir[1],
		atmosphere_settings.sun_dir[2]
	)
	
	
	# Trigger factory to create planet
	planet_factory._ready()
