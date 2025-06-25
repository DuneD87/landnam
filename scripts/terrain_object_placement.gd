extends VoxelInstancer
var function_north_hemi : VoxelGraphFunction = load("res://graph_functions/earth_terrain_green_hemisphere.tres")
var tree_generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var grass_generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var bushes_generator : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var large_rocks_generator_03 : VoxelInstanceGenerator = VoxelInstanceGenerator.new()
var large_rocks_generator_02 : VoxelInstanceGenerator = VoxelInstanceGenerator.new()

func set_generators() -> void:
	tree_generator.density = 0.01
	tree_generator.vertical_alignment = 0.5
	tree_generator.max_height = 10050
	tree_generator.min_height = 9975
	tree_generator.max_slope_degrees = 25
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
	tree_item_01.scene = load("res://scenes/tree01.tscn")
	tree_item_01.generator = tree_generator
	vegetation_array.append(tree_item_01)
	
	var tree_item_02 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	tree_item_02.scene = load("res://scenes/tree_02.tscn")
	tree_item_02.generator = tree_generator
	vegetation_array.append(tree_item_02)
	
	var grass_item_01 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	grass_item_01.scene = load("res://scenes/grass_01.tscn")
	grass_item_01.generator = grass_generator
	vegetation_array.append(grass_item_01)
	
	var bush_01 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	bush_01.scene = load("res://scenes/bush_01.tscn")
	bush_01.generator = bushes_generator
	vegetation_array.append(bush_01)
	
	var flowers_02 : VoxelInstanceLibraryMultiMeshItem = VoxelInstanceLibraryMultiMeshItem.new()
	flowers_02.scene = load("res://scenes/flowers_02.tscn")
	flowers_02.generator = bushes_generator
	vegetation_array.append(flowers_02)
	
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

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_generators()
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
	pass
