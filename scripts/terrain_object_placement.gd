extends VoxelInstancer
var function_north_hemi : VoxelGraphFunction = load("res://graph_functions/earth_terrain_green_hemisphere.tres")
var tree_generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var grass_generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var bushes_generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var large_rocks_generator_03 : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var large_rocks_generator_02 : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var planet : Node3D
var sun_dir : Vector3

var grass_scene : PackedScene = load("res://scenes/grass_01.tscn")
var tree01_scene : PackedScene = load("res://scenes/tree01.tscn")
var tree02_scene : PackedScene = load("res://scenes/tree_02.tscn")
var bush01_scene : PackedScene = load("res://scenes/bush_01.tscn")
var flowers02_scene : PackedScene = load("res://scenes/flowers_02.tscn")

var grass_materials : Array
var tree01_materials : Array
var tree02_materials : Array
var bush01_materials : Array
var flowers02_materials : Array

var wind_direction = Vector3(2.0, 0.0, 0.01)
var wind_speed = 0.3

func set_generators() -> void:
	
	tree_generator.density = 0.01
	tree_generator.max_height = 10050
	tree_generator.min_height = 9975
	tree_generator.max_slope_degrees = 25
	tree_generator.min_scale = 1.5
	tree_generator.max_scale = 2
	tree_generator.noise_graph = function_north_hemi	

	
	grass_generator.emit_mode = VoxelInstanceGenerator.EMIT_ONE_PER_TRIANGLE
	grass_generator.max_height = 10050
	grass_generator.min_height = 9975
	grass_generator.max_slope_degrees = 35
	grass_generator.noise_graph = function_north_hemi
	
	bushes_generator.density = 0.05
	bushes_generator.max_height = 10050
	bushes_generator.min_height = 9975
	bushes_generator.max_slope_degrees = 25
	bushes_generator.min_scale = 1.5
	bushes_generator.max_scale = 2
	bushes_generator.noise_graph = function_north_hemi
	
	large_rocks_generator_03.density = 0.01
	large_rocks_generator_03.offset_along_normal = -1.5
	large_rocks_generator_03.max_height = 10050
	large_rocks_generator_03.min_height = 9975
	large_rocks_generator_03.max_slope_degrees = 45
	large_rocks_generator_03.vertical_alignment = 0
	large_rocks_generator_03.min_scale = 1.25
	large_rocks_generator_03.max_scale = 1.75
	large_rocks_generator_03.noise_graph = function_north_hemi
	
	large_rocks_generator_02.density = 0.01
	large_rocks_generator_02.offset_along_normal = -1
	large_rocks_generator_02.max_height = 10050
	large_rocks_generator_02.min_height = 9975
	large_rocks_generator_02.max_slope_degrees = 45
	large_rocks_generator_02.vertical_alignment = 0
	large_rocks_generator_02.min_scale = 1.25
	large_rocks_generator_02.max_scale = 1.75
	large_rocks_generator_02.noise_graph = function_north_hemi
	
func add_vegatation() -> Array:
	
	var vegetation_array : Array

	var tree_item_01 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	tree_item_01.scene = tree01_scene
	tree_item_01.generator = tree_generator
	vegetation_array.append(tree_item_01)
	
	var tree_item_02 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	tree_item_02.scene = tree02_scene
	tree_item_02.generator = tree_generator
	vegetation_array.append(tree_item_02)
	
	var grass_item_01 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	grass_item_01.scene = grass_scene
	grass_item_01.generator = grass_generator
	vegetation_array.append(grass_item_01)
	
	var bush_01 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	bush_01.scene = bush01_scene
	bush_01.generator = bushes_generator
	vegetation_array.append(bush_01)
	
	var flowers_02 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	flowers_02.scene = flowers02_scene
	flowers_02.generator = bushes_generator
	vegetation_array.append(flowers_02)
	'''
	var tree_006_ico : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	tree_006_ico.scene = load("res://models/low-poly-forest/tree2_icosphere_006.tscn")
	tree_006_ico.generator = tree_generator
	vegetation_array.append(tree_006_ico)
	'''
	
	return vegetation_array
	
func add_rocks() -> Array:
	var rocks_array : Array
	
	var large_rock_03 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	large_rock_03.scene = load("res://models/rocks/large_rock_03_glb.tscn")
	large_rock_03.generator = large_rocks_generator_03
	rocks_array.append(large_rock_03)
	
	var large_rock_02 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	large_rock_02.scene = load("res://models/rocks/large_rock_02.tscn")
	large_rock_02.generator = large_rocks_generator_02
	rocks_array.append(large_rock_02)
	
	return rocks_array

func fill_object_materials() -> void:
	var grass_mesh : MeshInstance3D = grass_scene.instantiate().get_child(0)
	var grass_material_01 : ShaderMaterial = grass_mesh.mesh.surface_get_material(0)
	var grass_material_02 : ShaderMaterial = grass_mesh.mesh.surface_get_material(1)
	grass_materials.append(grass_material_01)
	grass_materials.append(grass_material_02)
	
	var tree01_mesh : MeshInstance3D = tree01_scene.instantiate().get_child(0)
	var tree01_material_01 : ShaderMaterial = tree01_mesh.mesh.surface_get_material(1)
	var tree01_material_02 : ShaderMaterial = tree01_mesh.mesh.surface_get_material(2)
	tree01_materials.append(tree01_material_01)
	tree01_materials.append(tree01_material_02)
	
	var tree02_mesh : MeshInstance3D = tree02_scene.instantiate().get_child(0)
	var tree02_material_01 : ShaderMaterial = tree02_mesh.mesh.surface_get_material(1)
	var tree02_material_02 : ShaderMaterial = tree02_mesh.mesh.surface_get_material(2)
	tree02_materials.append(tree02_material_01)
	tree02_materials.append(tree02_material_02)
	
	var bush01_mesh : MeshInstance3D = bush01_scene.instantiate().get_child(0)
	var bush01_material_01 : ShaderMaterial = bush01_mesh.mesh.surface_get_material(0)
	var bush01_material_02 : ShaderMaterial = bush01_mesh.mesh.surface_get_material(1)
	bush01_materials.append(bush01_material_01)
	bush01_materials.append(bush01_material_02)
	
	var flowers02_mesh : MeshInstance3D = flowers02_scene.instantiate().get_child(0)
	var flowers02_material_01 : ShaderMaterial = flowers02_mesh.mesh.surface_get_material(0)
	var flowers02_material_02 : ShaderMaterial = flowers02_mesh.mesh.surface_get_material(1)
	var flowers02_material_03 : ShaderMaterial = flowers02_mesh.mesh.surface_get_material(2)
	var flowers02_material_04 : ShaderMaterial = flowers02_mesh.mesh.surface_get_material(3)
	flowers02_materials.append(flowers02_material_01)
	flowers02_materials.append(flowers02_material_02)
	flowers02_materials.append(flowers02_material_03)
	flowers02_materials.append(flowers02_material_04)
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_generators()
	fill_object_materials()
	planet = get_parent().get_parent()
		
	var vegetation_array = add_vegatation()
	var i = 0

	for vegetation in vegetation_array:
		library.add_item(i, vegetation)
		i += 1

	var rocks_array = add_rocks()
	for rock in rocks_array:
		library.add_item(i, rock)
		i+=1

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	sun_dir = planet.sun_dir
	for mat in grass_materials:
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet.position)
		mat.set_shader_parameter("wind_direction", wind_direction / 2.0)
		mat.set_shader_parameter("wind_speed", wind_speed / 2.0)
		
	for mat in tree01_materials:
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet.position)
		mat.set_shader_parameter("wind_direction", wind_direction)
		mat.set_shader_parameter("wind_speed", wind_speed)

	for mat in tree02_materials:
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet.position)
		mat.set_shader_parameter("wind_direction", wind_direction)
		mat.set_shader_parameter("wind_speed", wind_speed)
	
	for mat in bush01_materials:
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet.position)
		mat.set_shader_parameter("wind_direction", wind_direction / 2.0)
		mat.set_shader_parameter("wind_speed", wind_speed / 2.0)
		
	for mat in flowers02_materials:
		mat.set_shader_parameter("light_direction", sun_dir)
		mat.set_shader_parameter("planet_position", planet.position)
		mat.set_shader_parameter("wind_direction", wind_direction / 2.0)
		mat.set_shader_parameter("wind_speed", wind_speed / 2.0)


	
