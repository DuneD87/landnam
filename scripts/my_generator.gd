extends VoxelGeneratorScript

const channel : int = VoxelBuffer.CHANNEL_SDF

# Instancias de FastNoiseLite
var noise = FastNoiseLite.new()
var fine_noise = FastNoiseLite.new()

func _init():
	# Configuración del ruido principal (Perlin, para colinas grandes)
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = 42
	noise.frequency = 0.002  # Más baja para características más amplias
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 6  # Más octavas para mayor detalle
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	
	# Configuración del ruido fino (para detalles pequeños)
	fine_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	fine_noise.seed = 43  # Diferente semilla para variedad
	fine_noise.frequency = 0.02  # Más alta para detalles pequeños
	fine_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	fine_noise.fractal_octaves = 3
	fine_noise.fractal_gain = 0.4
	fine_noise.fractal_lacunarity = 2.2

func _get_used_channels_mask() -> int:
	return 1 << channel
	
func _generate_block(out_buffer : VoxelBuffer, origin_in_voxels : Vector3i, lod : int) -> void:
	var sphere_center := Vector3(0, 0, -1500)
	var radius := 1000.0
	var noise_amplitude := 80.0  # Mayor amplitud para colinas más pronunciadas
	var fine_amplitude := 10.0  # Menor amplitud para detalles sutiles
	var max_noise_amplitude := 90.0

	var block_size := out_buffer.get_size()
	var min_corner := Vector3(origin_in_voxels)
	var max_corner := min_corner + Vector3(block_size * (1 << lod))
	var min_dist := sphere_center.distance_to(min_corner)
	var max_dist := sphere_center.distance_to(max_corner)
			
	if min_dist > radius + max_noise_amplitude:
		out_buffer.fill_f(1000.0, channel)
		return
	if max_dist < radius - max_noise_amplitude:
		out_buffer.fill_f(-1000.0, channel)
		return
	if max_dist < radius - max_noise_amplitude:
		out_buffer.fill_f(-1000.0, channel)
		return
	for rz in out_buffer.get_size().z:
		for rx in out_buffer.get_size().x:
			for ry in out_buffer.get_size().y:
				var pos_world := Vector3(origin_in_voxels) + Vector3(rx << lod, ry << lod, rz << lod)
				var distance_to_center := pos_world.distance_to(sphere_center)
				
				# Ruido principal (colinas grandes)
				var noise_value := noise.get_noise_3dv(pos_world)
				var main_offset := noise_value * noise_amplitude
				
				# Ruido fino (detalles pequeños)
				var fine_noise_value := fine_noise.get_noise_3dv(pos_world)
				var fine_offset := fine_noise_value * fine_amplitude

				var total_offset := main_offset + fine_offset
				
				var signed_distance := distance_to_center - (radius + total_offset)
				out_buffer.set_voxel_f(signed_distance, rx, ry, rz, channel)
