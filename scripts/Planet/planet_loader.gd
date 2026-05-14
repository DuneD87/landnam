@tool
extends Node

enum Action { NONE, SELECT_CONFIG }

@export_group("Planet")
@export var sun_path : DirectionalLight3D
@export var config_file_path: String = ""
@export var sun_dir: Vector3
@export var gravity_strength: float = 9.8
@export var players: Array[CharacterBody3D]
@onready var atmosphere_node: Node3D = $VoxelLodTerrain/PlanetAthmosphere
@onready var voxel_terrain: VoxelLodTerrain = $VoxelLodTerrain

@export var water_sphere: OceanSystem
@export var global_pos: Vector3
@export var planet: Planet
@export var entity_id: String = ""

var _config_action: Action = Action.NONE
var water_material : ShaderMaterial

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
	planet.atmosphere_radius = planet_parser.atmosphere_radius
	print("Atmosphere radius: ", planet.atmosphere_radius)
	planet.atmosphere_density = planet_parser.atmosphere_density
	planet.atmosphere_height = planet_parser.atmosphere_height
	planet.atmosphere_scattering = planet_parser.atmosphere_scattering
	planet.atmosphere_modulate = planet_parser.atmosphere_modulate
	planet.has_clouds = planet_parser.has_clouds
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
	add_child(planet)
	global_pos = planet.global_position
	#setup_voxel_stream()
	if planet_parser.has_water:
		water_sphere = OceanSystem.new()
		add_child(water_sphere)
		water_sphere.subdivision_factor = 2.5
		water_sphere.max_lod = 7
		water_sphere.sub_divisions = 32
		#water_sphere.enable_wireframe = true
		water_sphere.radius = planet.radius - planet_parser.water_level
		water_sphere.player = players[0]
		water_sphere.quadtree_material = load("res://data/resources/WaterSphere_material.tres")
		var water_shader: ShaderMaterial = water_sphere.quadtree_material as ShaderMaterial
		water_shader.set_shader_parameter("planet_center", voxel_terrain.global_position)
		print(voxel_terrain.global_position)
		water_sphere.wireframe_material = load("res://data/resources/WaterSphere_wireframe_material.tres")
		
		water_sphere.load_watersphere(planet)

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
	return {
		"config_file_path": config_file_path,
		"sun_dir": {
			"x": sun_dir.x,
			"y": sun_dir.y,
			"z": sun_dir.z
		},
		"gravity_strength": gravity_strength,
		"global_pos": {
			"x": global_pos.x,
			"y": global_pos.y,
			"z": global_pos.z
		}
	}


func restore_save_data(data: Dictionary) -> void:
	config_file_path = data.config_file_path
	gravity_strength = data.gravity_strength
	sun_dir = Vector3(data.sun_dir.x, data.sun_dir.y, data.sun_dir.z)
	global_pos = Vector3(data.global_pos.x, data.global_pos.y, data.global_pos.z)
	
	# Recargar planeta desde config
	if config_file_path != "":
		_load_planet()
		
func _process(_delta: float) -> void:
	if planet != null:
		planet.sun_dir = sun_dir
		planet._update_planet()
		if planet.has_water:
			water_sphere.sun_dir = sun_dir
#		water_material.set_shader_parameter("light_direction", sun_dir)
	pass
