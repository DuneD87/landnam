@tool
extends VoxelStreamScript

var planet_radius := 500.0
var noise_scale := 50.0
var noise := FastNoiseLite.new()

func _init():
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = randi()
	noise.frequency = 0.005

func _load_voxel_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> int:
	# Tamaño del bloque voxel (ej: 16x16x16 si LOD=0)
	var block_size := out_buffer.get_size()
	var channel := VoxelBuffer.CHANNEL_SDF  # Canal de densidad (SDF)
	
	# Itera sobre cada posición en el bloque
	for z in block_size.z:
		for x in block_size.x:
			for y in block_size.y:
				# Posición mundial del voxel
				var world_pos := origin + Vector3i(x, y, z)
				# Calcula densidad
				var density := calculate_density(world_pos)
				# Asigna el valor al buffer
				out_buffer.set_voxel_f(density, x, y, z, channel)
	return 0

func calculate_density(pos: Vector3) -> float:
	var distance_to_center := pos.length()
	var noise_value := noise.get_noise_3dv(pos) * noise_scale
	return planet_radius + noise_value - distance_to_center
