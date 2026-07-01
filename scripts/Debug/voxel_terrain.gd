@tool
extends VoxelGeneratorScript

@export var plane_size: Vector2 = Vector2(32, 32):
	set(new_value):
		plane_size = new_value
		_notify_terrain_changed()

@export var plane_height: float = 0.0:
	set(new_value):
		plane_height = new_value
		_notify_terrain_changed()


signal terrain_changed

func _ready():
	if Engine.is_editor_hint():
		if has_method("restart_stream"):
			call_deferred("restart_stream")
			print("VoxelTerrain: stream reiniciado en _ready() del editor.")
		elif has_method("rebuild_all_blocks"):
			call_deferred("rebuild_all_blocks",0) 
			print("VoxelTerrain: reconstrucción solicitada en _ready() del editor.")

func _notify_terrain_changed():
	if Engine.is_editor_hint():
		emit_signal("terrain_changed")


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod_index: int):

	assert(out_buffer.get_channel_depth(VoxelBuffer.CHANNEL_SDF) == VoxelBuffer.DEPTH_32_BIT)

	var block_size_voxels: Vector3i = out_buffer.get_size()

	for y_in_block in range(block_size_voxels.y):
		for z_in_block in range(block_size_voxels.z):
			for x_in_block in range(block_size_voxels.x):
				var global_voxel_pos: Vector3 = Vector3(
					float(origin_in_voxels.x + x_in_block),
					float(origin_in_voxels.y + y_in_block),
					float(origin_in_voxels.z + z_in_block)
				)

				var sdf_value: float

				var half_size_x: float = plane_size.x / 2.0
				var half_size_z: float = plane_size.y / 2.0

				if abs(global_voxel_pos.x) <= half_size_x and abs(global_voxel_pos.z) <= half_size_z:
					sdf_value = global_voxel_pos.y - plane_height
				else:
					sdf_value = 100.0 

				out_buffer.set_voxel_f(sdf_value, x_in_block, y_in_block, z_in_block, VoxelBuffer.CHANNEL_SDF)
