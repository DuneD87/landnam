
@tool
extends Node3D

@export_group("Terrain Settings")
@export var radius : float = 5000

@export_group("Biome Settings")
@export var biome_count : int = 5  # Cambiado a 6 biomas
@export var textures_per_biome : int = 3
var biome_latitude_ranges : Array[float] = [-90, -45, -10, 10, 45, 90]  # 7 valores para 6 intervalos
@export var biome_transition_smoothness = 1.0
@export_group("Atmosphere settings")
@export var atmosphere_radius : float = 2000.0
@export var atmosphere_density : float = 0.05
@export var sun : DirectionalLight3D
@export var sun_dir : Vector3

var shader_material : ShaderMaterial
var trans_smooth := 1.5
@onready var voxel_terrain : VoxelLodTerrain = $VoxelLodTerrain
@onready var atmosphere : Node3D = $VoxelLodTerrain/PlanetAthmosphere

func set_shader_parameters() -> void:
	shader_material = voxel_terrain.material as ShaderMaterial
	shader_material.set_shader_parameter("transition_smoothness", 30)
	shader_material.set_shader_parameter("biome_transition_smoothness", biome_transition_smoothness)
	atmosphere.sun_path = sun.get_path()
	
	atmosphere.planet_radius = radius
	atmosphere.set_atmosphere_height(atmosphere_radius)
	atmosphere.set_shader_parameter("u_density", atmosphere_density)
	
	shader_material.set_shader_parameter("center", position)
	shader_material.set_shader_parameter("radius", radius)
	
	# Alturas máximas para cada bioma (6 biomas x 3 alturas)
	var max_heights = [
		-30, 70, 200,   # Bioma 1: Polo Sur (hielo)
		-20, 50, 150,   # Bioma 2: Templado Sur (arena, hierba, hielo)
		-5, 20, 150,     # Bioma 4: Tropical (arena)
		-20, 50, 150,   # Bioma 5: Templado Norte (arena, hierba, hielo) - "bioma verde"
		-30, 70, 200    # Bioma 6: Polo Norte (hielo)
	]
	
	shader_material.set_shader_parameter("max_heights", max_heights)
	shader_material.set_shader_parameter("biome_count", biome_count)
	shader_material.set_shader_parameter("textures_per_biome", textures_per_biome)
	shader_material.set_shader_parameter("biome_latitude_ranges", biome_latitude_ranges)
	
	# Cargar texturas
	var texture_ice: Texture2D = load("res://textures/terrain/crusted_snow/Crusted_snow2_Base_Color.png")
	var texture_ice_normal: Texture2D = load("res://textures/terrain/crusted_snow/Crusted_snow2_Normal-ogl.png")
	var texture_ice_roughness: Texture2D = load("res://textures/terrain/crusted_snow/Crusted_snow2_Roughness.png")
	
	var texture_grass: Texture2D = load("res://textures/terrain/whispy-grass-meadow-bl/wispy-grass-meadow_albedo.png")
	var texture_grass_normal: Texture2D = load("res://textures/terrain/whispy-grass-meadow-bl/wispy-grass-meadow_normal-ogl.png")
	var texture_grass_roughness: Texture2D = load("res://textures/terrain/whispy-grass-meadow-bl/wispy-grass-meadow_roughness.png")
	
	var texture_sand: Texture2D = load("res://textures/terrain/wavy-sand-bl/wavy-sand_albedo.png")
	var texture_sand_normal: Texture2D = load("res://textures/terrain/wavy-sand-bl/wavy-sand_normal-ogl.png")
	var texture_sand_roughness: Texture2D = load("res://textures/terrain/wavy-sand-bl/wavy-sand_roughness.png")
	
	# Arreglos de texturas (índices: 0=hielo, 1=hierba, 2=arena)
	var textures = [texture_sand, texture_grass, texture_ice]
	var normal_textures = [texture_sand_normal, texture_grass_normal, texture_ice_normal]
	var roughness_textures = [texture_sand_roughness, texture_grass_roughness, texture_ice_roughness]
	
	shader_material.set_shader_parameter("textures", textures)
	shader_material.set_shader_parameter("normal_textures", normal_textures)
	shader_material.set_shader_parameter("roughness_textures", roughness_textures)
	
	# Índices de texturas por bioma
	var biome_texture_indices = [
		[2, 2, 2], # Bioma 1: Polo Sur (hielo)
		[0, 1, 2], # Bioma 2: Templado Sur (arena, hierba, hielo)
		[0, 0, 0], # Bioma 4: Tropical (arena)
		[0, 1, 2], # Bioma 5: Templado Norte (arena, hierba, hielo) - "bioma verde"
		[2, 2, 2]  # Bioma 6: Polo Norte (hielo)
	]
	
	# Aplanar biome_texture_indices
	var flattened_biome_texture_indices = []
	for biome in biome_texture_indices:
		for index in biome:
			flattened_biome_texture_indices.append(index)
	shader_material.set_shader_parameter("biome_texture_indices", flattened_biome_texture_indices)
	
	# Textura de pendientes (slope)
	var texture_slope: Texture2D = load("res://textures/terrain/bumpy-worn-ground-bl/bumpy_worn_ground_albedo.png")
	var texture_slope_normals: Texture2D = load("res://textures/terrain/bumpy-worn-ground-bl/bumpy_worn_ground_normal-ogl.png")
	var texture_slope_roughness: Texture2D = load("res://textures/terrain/bumpy-worn-ground-bl/bumpy_worn_ground_roughness.png")
	
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
