@tool
extends VoxelGeneratorScript

# Export variables to control the plane's properties in the editor
@export var plane_size: Vector2 = Vector2(32, 32):
	set(new_value):
		plane_size = new_value
		_notify_terrain_changed()

@export var plane_height: float = 0.0:
	set(new_value):
		plane_height = new_value
		_notify_terrain_changed()

# This is a placeholder for a reference to the VoxelTerrain node.
# VoxelGeneratorScript is a Resource, so it doesn't inherently know which node uses it.
# For live updates in the editor when these @export vars change, VoxelTerrain
# usually observes changes in its generator resource. If not, a manual "Rebuild"
# action on the VoxelTerrain node (in its inspector) might be needed.
# The _notify_terrain_changed function attempts to emit a signal that the VoxelTerrain could listen to if configured.

signal terrain_changed

func _ready():
	if Engine.is_editor_hint():
		# Esto es solo un ejemplo, los métodos exactos pueden variar.
		# Para VoxelLodTerrain, 'restart_stream()' es común.
		if has_method("restart_stream"):
			call_deferred("restart_stream") # call_deferred para esperar que todo esté listo
			print("VoxelTerrain: stream reiniciado en _ready() del editor.")
		elif has_method("rebuild_all_blocks"): # Otro método posible
			call_deferred("rebuild_all_blocks",0) 
			print("VoxelTerrain: reconstrucción solicitada en _ready() del editor.")
		# A veces, simplemente notificar que una propiedad ha cambiado puede ser suficiente
		# notify_property_list_changed()

func _notify_terrain_changed():
	if Engine.is_editor_hint():
		emit_signal("terrain_changed")
		# If VoxelTerrain doesn't automatically update, you might need to select it
		# and press its "Rebuild" button in the inspector.


func _get_used_channels_mask() -> int:
	# We will output Signed Distance Field (SDF) data.
	# This is suitable for smooth terrain meshers like VoxelMesherTransvoxel.
	return 1 << VoxelBuffer.CHANNEL_SDF


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod_index: int):
	# origin_in_voxels: The origin of the current chunk/block in voxel coordinates.
	# lod_index: Level of detail (0 is the highest). We'll ignore LOD for simplicity here.

	# Ensure the buffer is set up for 32-bit float SDF data.
	assert(out_buffer.get_channel_depth(VoxelBuffer.CHANNEL_SDF) == VoxelBuffer.DEPTH_32_BIT)

	var block_size_voxels: Vector3i = out_buffer.get_size()

	for y_in_block in range(block_size_voxels.y):
		for z_in_block in range(block_size_voxels.z):
			for x_in_block in range(block_size_voxels.x):
				# Calculate the global voxel coordinate for the current voxel
				# Note: VoxelTerrain's transform (scale, rotation, position) will further map this.
				# Here, we operate in the generator's local voxel space.
				var global_voxel_pos: Vector3 = Vector3(
					float(origin_in_voxels.x + x_in_block),
					float(origin_in_voxels.y + y_in_block),
					float(origin_in_voxels.z + z_in_block)
				)

				var sdf_value: float

				# Check if the current voxel is within the desired XZ plane dimensions
				# The plane is centered at (0, plane_height, 0) in this local voxel space.
				var half_size_x: float = plane_size.x / 2.0
				var half_size_z: float = plane_size.y / 2.0 # Assuming plane_size.y is depth (Z)

				if abs(global_voxel_pos.x) <= half_size_x and abs(global_voxel_pos.z) <= half_size_z:
					# Inside the defined plane area.
					# SDF is the signed distance to the surface (y = plane_height).
					# Negative inside (solid), positive outside (air), zero on surface.
					sdf_value = global_voxel_pos.y - plane_height
				else:
					# Outside the defined plane area, so it's air.
					# Use a large positive SDF value.
					sdf_value = 100.0 

				out_buffer.set_voxel_f(sdf_value, x_in_block, y_in_block, z_in_block, VoxelBuffer.CHANNEL_SDF)
