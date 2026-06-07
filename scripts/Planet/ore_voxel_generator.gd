extends VoxelGeneratorScript
class_name OreVoxelGenerator

var _base_generator: VoxelGenerator
var _ore_configs: Array[Dictionary] = []
var _ore_noises: Array[FastNoiseLite] = []

func setup(base_generator: VoxelGenerator, ore_configs: Array[Dictionary]) -> void:
	_base_generator = base_generator
	_ore_configs = ore_configs
	_ore_noises.clear()
	for ore in _ore_configs:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.seed = int(ore.get("noise_seed", 0))
		noise.frequency = float(ore.get("noise_scale", 0.03))
		_ore_noises.append(noise)

func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_DATA5)

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	_base_generator.generate_block(out_buffer, origin_in_voxels, lod)
	if _ore_configs.is_empty() or lod > 0:
		return
	_generate_ores(out_buffer, origin_in_voxels)

func _generate_ores(buffer: VoxelBuffer, origin: Vector3i) -> void:
	var size := buffer.get_size()

	for z in size.z:
		for y in size.y:
			for x in size.x:
				var sdf := buffer.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
				if sdf >= 0.0:
					continue

				var world_pos := Vector3(origin + Vector3i(x, y, z))

				for i in _ore_noises.size():
					var ore := _ore_configs[i]
					var surface_depth: float = float(ore.get("surface_depth", 10.0))
					if absf(sdf) > surface_depth:
						continue

					var n := (_ore_noises[i].get_noise_3dv(world_pos) + 1.0) * 0.5
					if n <= float(ore.get("threshold", 0.65)):
						continue

					buffer.set_voxel(int(ore.get("type_id", 1)), x, y, z, VoxelBuffer.CHANNEL_DATA5)
					break
