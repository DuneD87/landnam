@tool
class_name Planet extends Node3D

@export_group("Terrain Settings")
@export var radius: float

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
@export var vegetation: Dictionary
@export var wind_direction : Vector3

@export var item_transparent_materials : Array[Dictionary]
@export var shader_material: ShaderMaterial

@export var multi_mesh_array: Array[Dictionary] = []

@export_group("Atmosphere settings")
@export var atmosphere_radius: float
@export var atmosphere_density: float
@export var atmosphere_height: float
@export var atmosphere_scattering: Vector3
@export var atmosphere_modulate: Vector3
@export var has_clouds: bool

@export var sun_dir: Vector3
@export var planet_position: Vector3
@export var voxel_terrain: VoxelLodTerrain
@export var atmosphere_node: Node3D
@export var voxel_instancer: VoxelInstancer
@export var sun : DirectionalLight3D

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

func _load_vegetation():
	var generators = vegetation.generators
	var graph_functions =  vegetation.hemisphere_graph_function
	voxel_instancer.library.clear()
	var i = 0
	for item in vegetation.items:
		
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
		multi_mesh_item.lod_index = 16
		var scene = load(item.scene)
		multi_mesh_item.scene = scene
		voxel_instancer.library.add_item(i, multi_mesh_item)
		i += 1
		var multi_mesh_elem = {
			"mesh_item": multi_mesh_item,
			"wind_speed": item.wind_speed if item.has("wind_speed") else 0.0,
		}
		
		multi_mesh_array.append(multi_mesh_elem)
		var scene_mesh : MeshInstance3D = scene.instantiate().get_child(0)
		var surface_count = scene_mesh.mesh.get_surface_count()
		for surface_idx in surface_count:
			var shader_material = scene_mesh.mesh.surface_get_material(surface_idx)
			if shader_material is ShaderMaterial:
				item_transparent_materials.append(
					{
						"shader": shader_material as ShaderMaterial,
						"wind_speed": item.wind_speed
					}
				)
		
func _init(_voxel_terrain: VoxelLodTerrain, _atmosphere_node: Node3D) -> void:
	voxel_terrain = _voxel_terrain
	voxel_terrain.lod_distance = 1024
	atmosphere_node = _atmosphere_node
	voxel_instancer = VoxelInstancer.new()
	voxel_instancer.library = VoxelInstanceLibrary.new()
	voxel_instancer.up_mode = VoxelInstancer.UP_MODE_SPHERE
	voxel_terrain.add_child(voxel_instancer)
	shader_material = ShaderMaterial.new()
	shader_material.shader = load("res://shaders/terrain/terrain_no_biomes.gdshader")
	
func setup_shader_parameters() -> void:
	voxel_terrain.material = shader_material
	shader_material.set_shader_parameter("transition_smoothness", 30)
	shader_material.set_shader_parameter("biome_transition_smoothness", biome_transition_smoothness)
	planet_position = voxel_terrain.get_parent().position
	shader_material.set_shader_parameter("center", planet_position)
	print(planet_position)
	shader_material.set_shader_parameter("radius", radius)
	
	shader_material.set_shader_parameter("max_heights", max_heights)
	shader_material.set_shader_parameter("biome_count", biome_count)
	shader_material.set_shader_parameter("textures_per_biome", textures_per_biome)
	shader_material.set_shader_parameter("biome_latitude_ranges", biome_latitude_ranges)
	
	shader_material.set_shader_parameter("textures", textures)
	shader_material.set_shader_parameter("normal_textures", normal_textures)
	shader_material.set_shader_parameter("roughness_textures", roughness_textures)
	
	shader_material.set_shader_parameter("biome_texture_indices", biome_texture_indices)
	
	shader_material.set_shader_parameter("slope_texture", slope_texture)
	shader_material.set_shader_parameter("slope_normal_texture", slope_normal_texture)
	shader_material.set_shader_parameter("slope_roughness_texture", slope_roughness_texture)
	
	if !has_clouds:
		atmosphere_node.custom_shader = preload("res://addons/zylann.atmosphere/shaders/planet_atmosphere_no_clouds.gdshader")
	else:
		atmosphere_node.custom_shader = preload("res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds.gdshader")
	atmosphere_node.planet_radius = radius
	atmosphere_node.sun_path = sun.get_path()
	atmosphere_node.set_shader_parameter("u_density", atmosphere_density)
	atmosphere_node.set_shader_parameter("u_scattering_wavelengths", atmosphere_scattering)
	atmosphere_node.set_shader_parameter("u_atmosphere_modulate", atmosphere_modulate)

	atmosphere_node.set_atmosphere_height(atmosphere_height)

func setup_voxel_generator() -> void:
	voxel_terrain.generator = voxel_terrain.generator.duplicate()
	var graph_generator: VoxelGeneratorGraph = voxel_terrain.generator
	var graph_function: VoxelGraphFunction = graph_generator.get_main_function()
	if not graph_generator is VoxelGeneratorGraph:
		return
	
	var graph_generator_function: VoxelGraphFunction = graph_generator.get_main_function()
	for node_id in graph_generator_function.get_node_ids():
		var node_type = graph_generator_function.get_node_type_id(node_id)
		var node_data = graph_generator_function.get_node_type_info(node_type)
		var radius_pos: int = 0
		var radius_found: bool = false
		for key in node_data:
			if key == "params":
				var value = node_data[key]
				for params in value:
					for param in params:
						if params[param] is String && params[param] == "radius":
							radius_pos += 1
							radius_found = true
							break
						else:
							radius_pos += 1
		if radius_found:
			graph_generator_function.set_node_param(node_id, radius_pos - 1, radius)
			var success = graph_generator.compile()

func _ready() -> void:
	pass

func _update_planet() -> void:
	for mat_struct in item_transparent_materials:
		var mat = mat_struct.shader as ShaderMaterial
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet_position)
		mat.set_shader_parameter("wind_direction", wind_direction)
		mat.set_shader_parameter("wind_speed", mat_struct.wind_speed)
