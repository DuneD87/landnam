@tool
extends Node

@export_group("Config Selection")
@export_enum("None") var selected_config: String = "None":
	set(value):
		print(value)
		selected_config = value
		if value != "None" and Engine.is_editor_hint():
			load_config("res://data/planet/" + value)
		notify_property_list_changed()

# Dummy property to force editor refresh
@export var refresh_dropdown: bool = false:
	set(value):
		refresh_dropdown = value
		notify_property_list_changed()

@export_group("Terrain Settings")
@export var radius: float

@export_group("Biome Settings")
@export var biome_count: int
@export var textures_per_biome: int
@export var biome_latitude_ranges: Array[float] = []
@export var biome_transition_smoothness: float
@export var max_heights: Array[float] = []

@export var biome_texture_indices: Array[int] = []

@export var textures: Array[CompressedTexture2D] = []

@export var normal_textures: Array[CompressedTexture2D] = []

@export var roughness_textures: Array[CompressedTexture2D] = []

@export var slope_texture: CompressedTexture2D
@export var slope_normal_texture: CompressedTexture2D
@export var slope_roughness_texture: CompressedTexture2D

@export_group("Atmosphere Settings")
@export var atmosphere_radius: float
@export var atmosphere_height: float
@export var atmosphere_density: float
@export var sun: DirectionalLight3D
@export var sun_dir: Vector3

@onready var voxel_terrain: VoxelLodTerrain = $VoxelLodTerrain
@onready var atmosphere_node: Node3D = $VoxelLodTerrain/PlanetAthmosphere

func _get_property_list() -> Array:
	var properties = []
	var config_files = ["None"]
	var dir_path = "res://data/planet"

	# Open directory
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				config_files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	properties.append({
		"name": "selected_config",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(config_files)
	})
	print(properties)
	return properties

func load_config(config_path: String) -> void:
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
	
	# Validate and load terrain settings
	if not config.has("terrain_settings") or not config.terrain_settings.has("radius"):
		push_error("DEBUG: Invalid terrain settings in config.")
		return
	radius = config.terrain_settings.radius
	print("DEBUG: Loaded radius: ", radius)
	
	# Validate and load biome settings
	var biome_settings = config.get("biome_settings", {})
	if not biome_settings.has_all(["biome_count", "textures_per_biome", "biome_latitude_ranges", 
			"biome_transition_smoothness", "max_heights", "biome_texture_indices", 
			"textures", "normal_textures", "roughness_textures", 
			"slope_texture", "slope_normal_texture", "slope_roughness_texture"]):
		push_error("DEBUG: Invalid biome settings in config.")
		return
	
	biome_count = biome_settings.biome_count
	textures_per_biome = biome_settings.textures_per_biome
	biome_latitude_ranges = biome_settings.biome_latitude_ranges
	biome_transition_smoothness = biome_settings.biome_transition_smoothness
	max_heights = biome_settings.max_heights
	biome_texture_indices = biome_settings.biome_texture_indices
	print("DEBUG: Loaded biome settings: count=", biome_count, ", textures_per_biome=", textures_per_biome)
	
	textures = []
	for path in biome_settings.textures:
		var texture = load(path) as CompressedTexture2D
		if texture:
			textures.append(texture)
			print("DEBUG: Loaded texture: " + path)
		else:
			push_error("DEBUG: Failed to load texture: " + path)
			return
	
	normal_textures = []
	for path in biome_settings.normal_textures:
		var texture = load(path) as CompressedTexture2D
		if texture:
			normal_textures.append(texture)
			print("DEBUG: Loaded normal texture: " + path)
		else:
			push_error("DEBUG: Failed to load normal texture: " + path)
			return
	
	roughness_textures = []
	for path in biome_settings.roughness_textures:
		var texture = load(path) as CompressedTexture2D
		if texture:
			roughness_textures.append(texture)
			print("DEBUG: Loaded roughness texture: " + path)
		else:
			push_error("DEBUG: Failed to load roughness texture: " + path)
			return
	
	slope_texture = load(biome_settings.slope_texture) as CompressedTexture2D
	if not slope_texture:
		push_error("DEBUG: Failed to load slope texture: " + biome_settings.slope_texture)
		return
	print("DEBUG: Loaded slope texture: " + biome_settings.slope_texture)
	
	slope_normal_texture = load(biome_settings.slope_normal_texture) as CompressedTexture2D
	if not slope_normal_texture:
		push_error("DEBUG: Failed to load slope normal texture: " + biome_settings.slope_normal_texture)
		return
	print("DEBUG: Loaded slope normal texture: " + biome_settings.slope_normal_texture)
	
	slope_roughness_texture = load(biome_settings.slope_roughness_texture) as CompressedTexture2D
	if not slope_roughness_texture:
		push_error("DEBUG: Failed to load slope roughness texture: " + biome_settings.slope_roughness_texture)
		return
	print("DEBUG: Loaded slope roughness texture: " + biome_settings.slope_roughness_texture)
	
	# Validate and load atmosphere settings
	var atmosphere_settings = config.get("atmosphere_settings", {})
	if not atmosphere_settings.has_all(["atmosphere_radius", "atmosphere_height", "atmosphere_density"]):
		push_error("DEBUG: Invalid atmosphere settings in config.")
		return
	
	atmosphere_radius = atmosphere_settings.atmosphere_radius
	atmosphere_height = atmosphere_settings.atmosphere_height
	atmosphere_density = atmosphere_settings.atmosphere_density
	print("DEBUG: Loaded atmosphere settings: radius=", atmosphere_radius, ", height=", atmosphere_height, ", density=", atmosphere_density)
	
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

func _ready() -> void:
	# Create Atmosphere instance
	var atmosphere = Atmosphere.new(
		radius,
		atmosphere_radius,
		atmosphere_density,
		atmosphere_height,
		sun,
		atmosphere_node
	)
	
	# Create Planet instance
	var planet = Planet.new(
		radius,
		biome_count,
		textures_per_biome,
		biome_latitude_ranges,
		biome_transition_smoothness,
		max_heights,
		biome_texture_indices,
		textures,
		normal_textures,
		roughness_textures,
		slope_texture,
		slope_normal_texture,
		slope_roughness_texture,
		voxel_terrain,
		atmosphere_node
	)
	
	# Set up planet and atmosphere
	planet.setup_shader_parameters()
	planet.setup_voxel_generator()
	
	atmosphere.setup_shader_parameters()
