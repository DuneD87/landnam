extends "WorldCommon.gd"

onready var terrain = $VoxelTerrain

const MATERIAL = preload("res://fps_demo/materials/grass-rock2.material")

	
func _input(event):
	if event is InputEventKey and Input.is_key_pressed(KEY_N):
		randomize_terrain()
	

func randomize_terrain():	
	get_tree().call_group("bullets", "free")
	terrain.free()
	terrain = VoxelLodTerrain.new()
	terrain.name = "VoxelTerrain"
	
	terrain.stream = VoxelGeneratorNoise.new()
	terrain.stream.noise = OpenSimplexNoise.new()
	terrain.stream.noise.seed = randi()								# Int (0): 		0 to 2147483647
	terrain.stream.noise.octaves = 1+randi()%5						# Int (3): 		1 - 6 
	terrain.stream.noise.period = rand_range(0.1, 256)				# Float (64): 	0.1 - 256.0 
	terrain.stream.noise.persistence = randf()						# Float (0.5): 	0.0 - 1.0
	terrain.stream.noise.lacunarity = rand_range(0.1, 4)			# Float (2): 	0.1 - 4.0
	print("Seed: ", String(terrain.stream.noise.seed))
	print("Octaves: ", String(terrain.stream.noise.octaves))
	print("Period: ", String(terrain.stream.noise.period).substr(0,4))
	print("Persistence: ", String(terrain.stream.noise.persistence).substr(0,4))
	print("Lacunarity: ", String(terrain.stream.noise.lacunarity).substr(0,4))
		
	terrain.lod_count = 8
	terrain.lod_split_scale = 3
	terrain.viewer_path = "/root/World/Player"
	terrain.set_material(MATERIAL)
	add_child(terrain)


