class_name Planet extends Node3D

@export_group("Terrain Settings")
@export var radius: float

@export_group("Biome Settings")
@export var biome_count: int 
@export var textures_per_biome: int
@export var biome_latitude_ranges: Array[float] = []
@export var biome_transition_smoothness: float
@export var max_heights: Array[float] = []
@export var biome_texture_indices: Array[int] = [
]
@export var textures: Array[Texture2D] = []
@export var normal_textures: Array[Texture2D] = []
@export var roughness_textures: Array[Texture2D] = []
@export var slope_texture: Texture2D
@export var slope_normal_texture: Texture2D
@export var slope_roughness_texture: Texture2D

var shader_material: ShaderMaterial
var voxel_terrain: VoxelLodTerrain
var atmosphere: Node3D

func _init(
	_radius: float,
	_biome_count: int,
	_textures_per_biome: int,
	_biome_latitude_ranges: Array[float],
	_biome_transition_smoothness: float,
	_max_heights: Array[float],
	_biome_texture_indices: Array[int],
	_textures: Array[Texture2D],
	_normal_textures: Array[Texture2D],
	_roughness_textures: Array[Texture2D],
	_slope_texture: Texture2D,
	_slope_normal_texture: Texture2D,
	_slope_roughness_texture: Texture2D,
	_voxel_terrain: VoxelLodTerrain,
	_shader_material: ShaderMaterial,
	_atmosphere: Node3D
) -> void:
	radius = _radius
	biome_count = _biome_count
	textures_per_biome = _textures_per_biome
	biome_latitude_ranges = _biome_latitude_ranges
	biome_transition_smoothness = _biome_transition_smoothness
	max_heights = _max_heights
	biome_texture_indices = _biome_texture_indices
	textures = _textures
	normal_textures = _normal_textures
	roughness_textures = _roughness_textures
	slope_texture = _slope_texture
	slope_normal_texture = _slope_normal_texture
	slope_roughness_texture = _slope_roughness_texture
	voxel_terrain = _voxel_terrain
	shader_material = _shader_material
	voxel_terrain.material = shader_material

func setup_shader_parameters() -> void:
	shader_material.set_shader_parameter("transition_smoothness", 30)
	shader_material.set_shader_parameter("biome_transition_smoothness", biome_transition_smoothness)
	print(voxel_terrain.get_parent().position)
	shader_material.set_shader_parameter("center", voxel_terrain.get_parent().position)
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

func setup_voxel_generator() -> void:
	voxel_terrain.generator = voxel_terrain.generator.duplicate()
	var graph_generator: VoxelGeneratorGraph = voxel_terrain.generator
	var graph_function: VoxelGraphFunction = graph_generator.get_main_function()
	print(graph_function)
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
