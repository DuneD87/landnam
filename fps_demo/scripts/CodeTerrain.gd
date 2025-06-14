""" This file shows you how to create a Voxel Tools terrain from code """

extends "WorldCommon.gd"

const MyStream = preload("MyStream.gd")

const MATERIAL = preload("res://fps_demo/materials/color_grid.material")
const HEIGHT_MAP = preload("res://blocky_terrain/noise_distorted.png")

var terrain

func _ready() -> void:
	create_terrain()
	
func _input(event) -> void:
	
	if event is InputEventKey and Input.is_key_pressed(KEY_DELETE):
		terrain.free()
		
	if event is InputEventKey and Input.is_key_pressed(KEY_N):
		create_terrain()		

	
func create_terrain() -> void:
	
##### Folllow the instructions to use the various types of terrains available
	
##### 1. Choose VoxelTerrain or VoxelLodTerrain

## A. VoxelTerrain

#	terrain = VoxelTerrain.new()
#	terrain.view_distance = 256
#	terrain.set_material(0, MATERIAL)

## B. VoxelLodTerrain

	terrain = VoxelLodTerrain.new()
	terrain.view_distance = 2048
	terrain.lod_count = 6
	terrain.lod_split_scale = 3
	terrain.set_material(MATERIAL)
	

	
##### 2. Select one of the data streams:
	
## A. Custom GDScript stream 
## This generates a 3D sine wave with GDScript

	terrain.stream = MyStream.new()

## B. C++ Stream
## This generates a 3D sine wave from C++ and is considerably faster.

#	terrain.stream = VoxelGeneratorWaves.new()

## C. Image based stream

#	terrain.stream = VoxelGeneratorImage.new()
#	terrain.stream.image = HEIGHT_MAP
#	$Player.translate(Vector3(0,35,0))		# Not required, just aids the demo

## D. 3D Noise stream

#	terrain.stream = VoxelGeneratorNoise.new()
#	terrain.stream.noise = OpenSimplexNoise.new()
#	$Player.translate(Vector3(0,200,0))		# Not required, just aids the demo



##### 3. Select a blocky or smooth terrain type

## A. Blocky (TYPE)

#	terrain.stream.channel = VoxelBuffer.CHANNEL_TYPE

## B. Smooth (SDF). Note: VoxelLodTerrain only supports smooth.

	terrain.stream.channel = VoxelBuffer.CHANNEL_SDF


##### 4. Stop - Applicable to all

	terrain.generate_collisions = true
	terrain.viewer_path = "/root/World/Player"
	terrain.name = "VoxelTerrain"
	add_child(terrain)

