@tool
extends Node3D
@export_group("Terrain Settings")
@export var radius : float = 5000

@export_group("Biome Settings")
@export var biome_count : int = 5
@export var textures_per_biome : int = 3
@export var biome_latitude_ranges : Array[float] = [-90.0, -80.0, -60.0, -30.0, 30.0, 60.0, 90.0] # Latitude boundaries

var shader_material : ShaderMaterial
var trans_smooth := 1.5
@onready var voxel_terrain : VoxelLodTerrain = $VoxelLodTerrain

func set_shader_parameters() -> void:
	shader_material = voxel_terrain.material as ShaderMaterial
	shader_material.set_shader_parameter("transition_smoothness", 30)
	shader_material.set_shader_parameter("center", position)
	shader_material.set_shader_parameter("radius", radius)
	
	# Define height thresholds for each biome (flattened array)
	var max_heights = [
		-30, 70, 200,   # Biome 1: Polar (-90 to -80)
		-20, 50, 150,   # Biome 2: Temperate (-80 to -60)
		-10, 30, 100,   # Biome 3: Tropical (-60 to -30)
		-20, 50, 150,   # Biome 4: Temperate (-30 to 30)
		-30, 70, 200    # Biome 5: Polar (60 to 90)
	]
	
	shader_material.set_shader_parameter("max_heights", max_heights)
	shader_material.set_shader_parameter("biome_count", biome_count)
	shader_material.set_shader_parameter("textures_per_biome", textures_per_biome)
	shader_material.set_shader_parameter("biome_latitude_ranges", biome_latitude_ranges)
	
	# Define the three unique textures
	var texture_ice: Texture2D = load("res://textures/crusted_snow/Crusted_snow2_Base_Color.png")
	var texture_ice_normal: Texture2D = load("res://textures/crusted_snow/Crusted_snow2_Normal-ogl.png")
	var texture_ice_roughness: Texture2D = load("res://textures/crusted_snow/Crusted_snow2_Roughness.png")
	
	var texture_grass: Texture2D = load("res://textures/whispy-grass-meadow-bl/wispy-grass-meadow_albedo.png")
	var texture_grass_normal: Texture2D = load("res://textures/whispy-grass-meadow-bl/wispy-grass-meadow_normal-ogl.png")
	var texture_grass_roughness: Texture2D = load("res://textures/whispy-grass-meadow-bl/wispy-grass-meadow_roughness.png")
	
	var texture_sand: Texture2D = load("res://textures/wavy-sand-bl/wavy-sand_albedo.png")
	var texture_sand_normal: Texture2D = load("res://textures/wavy-sand-bl/wavy-sand_normal-ogl.png")
	var texture_sand_roughness: Texture2D = load("res://textures/wavy-sand-bl/wavy-sand_roughness.png")
	
	# Texture arrays (only three textures)
	var textures = [texture_sand, texture_grass, texture_ice ]
	var normal_textures = [texture_sand_normal, texture_grass_normal, texture_ice_normal ]
	var roughness_textures = [texture_sand_roughness,texture_grass_roughness, texture_ice_roughness]
	
	shader_material.set_shader_parameter("textures", textures)
	shader_material.set_shader_parameter("normal_textures", normal_textures)
	shader_material.set_shader_parameter("roughness_textures", roughness_textures)
	
	# Define texture indices for each biome (0 = ice, 1 = grass, 2 = sand)
	var biome_texture_indices = [
		[0, 0, 0], # Biome 1: Polar (ice, ice, ice)
		[2, 1, 0], # Biome 2: Temperate (sand, grass, ice)
		[2, 2, 2], # Biome 3: Tropical (sand, sand, sand)
		[2, 1, 0], # Biome 4: Temperate (sand, grass, ice)
		[0, 0, 0]  # Biome 5: Polar (ice, ice, ice)
	]
	
	shader_material.set_shader_parameter("biome_texture_indices", biome_texture_indices)
	
	# Slope texture (global)
	var texture_slope: Texture2D = load("res://textures/bumpy-worn-ground-bl/bumpy_worn_ground_albedo.png")
	var texture_slope_normals: Texture2D = load("res://textures/bumpy-worn-ground-bl/bumpy_worn_ground_normal-ogl.png")
	var texture_slope_roughness: Texture2D = load("res://textures/bumpy-worn-ground-bl/bumpy_worn_ground_roughness.png")
	
	shader_material.set_shader_parameter("slope_texture", texture_slope)
	shader_material.set_shader_parameter("slope_normal_texture", texture_slope_normals)
	shader_material.set_shader_parameter("slope_roughness_texture", texture_slope_roughness)

func _ready() -> void:
	set_shader_parameters()
	var graph_generator : VoxelGeneratorGraph = voxel_terrain.generator
	if !graph_generator is VoxelGeneratorGraph:
		return
	
	var graph_generator_function : VoxelGraphFunction = graph_generator.get_main_function()
	for node_id in graph_generator_function.get_node_ids():
		var node_type = graph_generator_function.get_node_type_id(node_id)
		var node_data = graph_generator_function.get_node_type_info(node_type)
		var radius_pos : int = 0
		var radius_found : bool = false
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
			shader_material.set_shader_parameter("radius", radius)

func _process(delta: float) -> void:
	pass
