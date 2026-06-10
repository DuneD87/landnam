extends VoxelGeneratorScript
class_name OreVoxelGenerator

# El ore se guarda EN el voxel usando el sistema de texturing 4-blend de godot_voxel
# (canales INDICES/WEIGHTS). El mesher los pasa al shader vía CUSTOM1, y el minado los
# lee del mismo voxel. Fuente única de verdad: el noise se evalúa solo aquí, una vez.
# Slot 0 = terreno base (bioma procedural), slot 1 = ore. El índice de ore guardado es
# el type_id (1=iron, 2=gold...).
const ORE_SLOT := 1

var _base_generator: VoxelGenerator
var _ore_configs: Array[Dictionary] = []
# Dos octavas por mineral (n1 a freq, n2 a freq*2.1 / seed+7) para patches orgánicos.
var _ore_noise_a: Array[FastNoiseLite] = []
var _ore_noise_b: Array[FastNoiseLite] = []

func setup(base_generator: VoxelGenerator, ore_configs: Array[Dictionary]) -> void:
	_base_generator = base_generator
	_ore_configs = ore_configs
	_ore_noise_a.clear()
	_ore_noise_b.clear()
	for ore in _ore_configs:
		var ore_seed := int(ore.get("noise_seed", 0))
		var freq := float(ore.get("noise_scale", 0.03))

		var noise_a := FastNoiseLite.new()
		noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise_a.seed = ore_seed
		noise_a.frequency = freq
		_ore_noise_a.append(noise_a)

		var noise_b := FastNoiseLite.new()
		noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise_b.seed = ore_seed + 7
		noise_b.frequency = freq * 2.1
		_ore_noise_b.append(noise_b)

func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) \
		| (1 << VoxelBuffer.CHANNEL_INDICES) \
		| (1 << VoxelBuffer.CHANNEL_WEIGHTS)

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	_base_generator.generate_block(out_buffer, origin_in_voxels, lod)
	if _ore_configs.is_empty() or lod > 2:
		return
	_generate_ores(out_buffer, origin_in_voxels)

func get_ore_drop(type_id: int) -> Dictionary:
	for ore in _ore_configs:
		if int(ore.get("type_id", -1)) == type_id:
			return {
				"item_id": StringName(ore.get("drop_item", "stone_01")),
				"min_count": int(ore.get("drop_count_min", 1)),
				"max_count": int(ore.get("drop_count_max", 1))
			}
	return {"item_id": &"stone_01", "min_count": 1, "max_count": 2}

func _generate_ores(buffer: VoxelBuffer, origin: Vector3i) -> void:
	var size := buffer.get_size()

	for z in size.z:
		for y in size.y:
			for x in size.x:
				var sdf := buffer.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
				if sdf >= 0.0:
					continue

				var world_pos := Vector3(origin + Vector3i(x, y, z))

				# Varios minerales pueden solaparse: nos quedamos con el de mayor peso.
				var chosen_type := 0
				var chosen_weight := 0.0
				for i in _ore_configs.size():
					var ore := _ore_configs[i]
					if absf(sdf) > float(ore.get("surface_depth", 10.0)):
						continue

					var n1 := _ore_noise_a[i].get_noise_3dv(world_pos)
					var n2 := _ore_noise_b[i].get_noise_3dv(world_pos) * 0.35
					var ore_n := ((n1 + n2) * (1.0 / 1.35)) * 0.5 + 0.5

					var thr := float(ore.get("threshold", 0.65))
					var smooth: float = maxf(float(ore.get("threshold_smoothness", 0.05)), 0.005)
					var ore_w := smoothstep(thr - smooth, thr + smooth, ore_n)
					if ore_w > chosen_weight:
						chosen_weight = ore_w
						chosen_type = int(ore.get("type_id", 1))

				if chosen_type > 0 and chosen_weight > 0.05:
					var indices := Vector4i(0, 0, 0, 0)
					indices[ORE_SLOT] = chosen_type
					var weights := Color(0.0, 0.0, 0.0, 0.0)
					weights[ORE_SLOT] = chosen_weight
					buffer.set_voxel(VoxelTool.vec4i_to_u16_indices(indices), x, y, z, VoxelBuffer.CHANNEL_INDICES)
					buffer.set_voxel(VoxelTool.color_to_u16_weights(weights), x, y, z, VoxelBuffer.CHANNEL_WEIGHTS)
