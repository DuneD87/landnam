@tool
extends Node

@export_group("Config Selection")
@export var select_config_file: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_open_file_dialog()
		select_config_file = false # Reset to allow repeated clicks

@export_group("Terrain Settings")
@export var radius: float
@export var vegetation : Array[Dictionary]

@export_group("Biome Settings")
@export var biome_count: int
@export var textures_per_biome: int
@export var biome_latitude_ranges: Array[float] = []
@export var biome_transition_smoothness: float
@export var max_heights: Array[float] = []

@export var biome_texture_indices: Array[int] = []

@export var textures: Array[Texture2D] = []

@export var normal_textures: Array[Texture2D] = []

@export var roughness_textures: Array[Texture2D] = []

@export var slope_texture: Texture2D
@export var slope_normal_texture: Texture2D
@export var slope_roughness_texture: Texture2D

@export_group("Atmosphere Settings")
@export var atmosphere_radius: float
@export var atmosphere_height: float
@export var atmosphere_density: float
@export var atmosphere_scattering: Vector3
@export var atmosphere_modulate: Vector3
@export var sun: DirectionalLight3D
@export var sun_dir: Vector3
@export var wind_direction: Vector3 = Vector3.ZERO

@onready var voxel_terrain: VoxelLodTerrain = $VoxelLodTerrain
@onready var atmosphere_node: Node3D = $VoxelLodTerrain/PlanetAthmosphere
@onready var voxel_instancer : VoxelInstancer = $VoxelLodTerrain/VoxelInstancer

var _editor_file_dialog: EditorFileDialog
var sun_node : Node3D

func _open_file_dialog() -> void:
	if not Engine.is_editor_hint():
		return
	
	# Create EditorFileDialog if not already created
	if not _editor_file_dialog:
		_editor_file_dialog = EditorFileDialog.new()
		_editor_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_editor_file_dialog.add_filter("*.json", "JSON Files")
		_editor_file_dialog.current_dir = "res://data/planet/"
		_editor_file_dialog.size = Vector2i(800, 600)
		_editor_file_dialog.title = "Select Planet Config JSON"
		_editor_file_dialog.file_selected.connect(_on_file_selected)
		
		# Add EditorFileDialog to the editor's main control
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
	
	# Show the dialog
	_editor_file_dialog.popup_centered()
	print("DEBUG: EditorFileDialog opened at res://data/planet/")

func _on_file_selected(path: String) -> void:
	print("DEBUG: Selected file: " + path)
	load_config(path)
	notify_property_list_changed()
	
func _build_generator(generator_config: Dictionary, graph_functions: Array) -> VoxelInstanceGenerator:
	var generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
	
	if generator_config.emit_mode == "EMIT_FROM_VERTICES":
		generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_VERTICES
		generator.density = generator_config.density
	elif generator_config.emit_mode == "EMIT_ONE_PER_TRIANGLE":
		generator.emit_mode = VoxelInstanceGenerator.EMIT_ONE_PER_TRIANGLE
		
	if generator_config.has("offset_along_normal"):
		generator.offset_along_normal = generator_config.offset_along_normal
	if generator_config.has("max_height"):
		generator.max_height = generator_config.max_height
	if generator_config.has("min_height"):
		generator.min_height = generator_config.min_height
	if generator_config.has("max_slope_degrees"):
		generator.max_slope_degrees = generator_config.max_slope_degrees
	if generator_config.has("vertical_alignment"):
		generator.vertical_alignment = generator_config.vertical_alignment
	if generator_config.has("min_scale"):
		generator.min_scale = generator_config.min_scale
	if generator_config.has("max_scale"):
		generator.max_scale = generator_config.max_scale
	if generator_config.has("noise_graph"):
		for graph_func in graph_functions:
			if graph_func.name == generator_config.noise_graph:
				generator.noise_graph = load(graph_func.path)
	return generator
	
func _load_vegetation_settings(data:Dictionary) -> void:
	if data.is_empty():
			return
	var multi_mesh_array : Array[Dictionary]
	var generators = data.generators
	var graph_functions =  data.hemisphere_graph_function
	
	for item in data.items:
		
		var generator : VoxelInstanceGenerator
		var generator_found = false
		for generator_config in generators:
			if generator_config.name == item.generator:
				generator = _build_generator(generator_config, graph_functions)
				generator_found = true
				break
		if !generator_found:
			push_error("Error parsing vegetation, generator with name %s not found.", item.generator)
			
		var multi_mesh_item : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
		multi_mesh_item.generator = generator
		var multi_mesh_elem = {
			"mesh_item": multi_mesh_item,
			"wind_speed": item.wind_speed if item.has("wind_speed") else 0.0,
			"scene_path": item.scene
		}
		
		multi_mesh_array.append(multi_mesh_elem)

	vegetation = multi_mesh_array
	voxel_instancer._set_mesh_items(vegetation)
	wind_direction.x = data.wind_direction[0]
	wind_direction.y = data.wind_direction[1]
	wind_direction.z = data.wind_direction[2]
	

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
	_load_vegetation_settings(config.get("vegetation_settings", {}))
	# Validate and load biome settings
	var biome_settings = config.get("biome_settings", {})
	if not biome_settings.has_all(["biome_count", "textures_per_biome", "biome_latitude_ranges", 
			"biome_transition_smoothness", "max_heights", "biome_texture_indices", 
			"textures", "normal_textures", "roughness_textures", 
			"slope_texture", "slope_normal_texture", "slope_roughness_texture"]):
		push_error("DEBUG: Invalid biome settings in config.")
		return
	
	biome_count = biome_settings.biome_count
	print(biome_settings.textures_per_biome)

	textures_per_biome = biome_settings.textures_per_biome
	
	# Convert biome_latitude_ranges to Array[float]
	biome_latitude_ranges = []
	for value in biome_settings.biome_latitude_ranges:
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			biome_latitude_ranges.append(float(value))
		else:
			push_error("DEBUG: Invalid value in biome_latitude_ranges: " + str(value))
			return
	
	biome_transition_smoothness = biome_settings.biome_transition_smoothness
	
	# Convert max_heights to Array[float]
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
	
	# Validate and load atmosphere settings
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

func _ready() -> void:
	# Create Atmosphere instance
	var atmosphere = Atmosphere.new(
		radius,
		atmosphere_radius,
		atmosphere_density,
		atmosphere_height,
		atmosphere_scattering,
		atmosphere_modulate,
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
	
	sun_node = get_parent()
	# Set up planet and atmosphere
	planet.setup_shader_parameters()
	planet.setup_voxel_generator()
	
	atmosphere.setup_shader_parameters()
