@tool
extends Node

enum Action { NONE, SELECT_CONFIG }

@export_group("Config Planet")
@export var sun_path : DirectionalLight3D
@export var config_file_path: String = ""
@export var sun_dir: Vector3

@onready var atmosphere_node: Node3D = $VoxelLodTerrain/PlanetAthmosphere
@onready var voxel_terrain: VoxelLodTerrain = $VoxelLodTerrain

var _config_action: Action = Action.NONE

@export var planet: Planet

@export var config_action: Action:
	get:		
		return _config_action
	set(value):
		if value == Action.SELECT_CONFIG && Engine.is_editor_hint() && sun_path:
			_open_file_dialog()
			_config_action = Action.NONE      # resetea la opción
			notify_property_list_changed()    # refresca el Inspector
		else:
			_config_action = value
			if sun_path == null:
				push_error("sun_path is null! Aborting")

var _editor_file_dialog: EditorFileDialog

func _copy_parsed_data(planet_parser: PlanetParser) -> void:
	planet.radius = planet_parser.radius
	planet.biome_count = planet_parser.biome_count
	planet.textures_per_biome = planet_parser.textures_per_biome
	planet.biome_latitude_ranges = planet_parser.biome_latitude_ranges
	planet.biome_transition_smoothness = planet_parser.biome_transition_smoothness
	planet.max_heights = planet_parser.max_heights
	planet.biome_texture_indices = planet_parser.biome_texture_indices
	planet.textures = planet_parser.textures
	planet.normal_textures = planet_parser.normal_textures
	planet.roughness_textures = planet_parser.roughness_textures
	planet.slope_texture = planet_parser.slope_texture
	planet.slope_normal_texture = planet_parser.slope_normal_texture
	planet.slope_roughness_texture = planet_parser.slope_roughness_texture
	
	planet.atmosphere_radius = planet_parser.atmosphere_radius
	print("Atmosphere radius: ", planet.atmosphere_radius)
	planet.atmosphere_density = planet_parser.atmosphere_density
	planet.atmosphere_height = planet_parser.atmosphere_height
	planet.atmosphere_scattering = planet_parser.atmosphere_scattering
	planet.atmosphere_modulate = planet_parser.atmosphere_modulate
	planet.has_clouds = planet_parser.has_clouds
	
	var shader_material = ShaderMaterial.new()
	shader_material.shader = load("res://shaders/terrain/terrain_no_biomes.gdshader").duplicate(true)
	planet.shader_material = shader_material

	planet.vegetation = planet_parser.vegetation
	planet.wind_direction = planet_parser.wind_direction
	planet.sun = sun_path


func _load_planet() -> void:
	var planet_parser: PlanetParser = PlanetParser.new(sun_path)
	planet_parser.load_config(config_file_path)
	planet = Planet.new(voxel_terrain, atmosphere_node)
	_copy_parsed_data(planet_parser)
	planet.setup_shader_parameters()
	planet.setup_voxel_generator()
	planet._load_vegetation()
	
func _on_file_selected(path: String) -> void:
	config_file_path = path
	_load_planet()
	notify_property_list_changed()

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


func _ready() -> void:
	if config_file_path != "res://data/planet/default.json":
		_load_planet()
		
	
func _process(delta: float) -> void:
	if planet != null:
		planet.sun_dir = sun_dir
		planet._update_planet()
	pass
