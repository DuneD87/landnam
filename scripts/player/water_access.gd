class_name WaterAccess
extends RefCounted

## Consulta de gameplay: el terreno vivo decide si hay agua al alcance; el mapa solo aporta su
## tipo. Una celda de ~92 m no puede decidir si se llega a una orilla que está a 2,5 m.

const DRINK_REACH := 2.5
const RIVER_REACH := 6.0


static func kind_at(world_pos: Vector3, terrain: VoxelLodTerrain, map: WorldMapData,
		rivers: Dictionary, sea_radius: float) -> StringName:
	if terrain == null or sea_radius <= 0.0:
		return &""
	var center := terrain.global_position
	var radial := world_pos - center
	if radial.length() - sea_radius > DRINK_REACH:
		return &""
	var up := radial.normalized()
	var tool := terrain.get_voxel_tool() as VoxelToolLodTerrain
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var channel := RiverField.nearby_channel_at(rivers, up, RIVER_REACH)
	if not channel.is_empty():
		var river_point: Vector3 = center + (channel.direction as Vector3) * sea_radius
		if _has_water(terrain, tool, river_point):
			return &"fresh"
	if map == null or not map.is_valid() or not map.has_water:
		return &""
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var forward := up.cross(right)
	var salt := false
	for offset: Vector3 in [Vector3.ZERO, right, -right, forward, -forward,
			(right + forward) * 0.7, (right - forward) * 0.7,
			(forward - right) * 0.7, -(right + forward) * 0.7]:
		var direction := (radial + offset * DRINK_REACH).normalized()
		var water_point := center + direction * sea_radius
		if not _has_water(terrain, tool, water_point):
			continue
		var body := map.nearby_water_body_at_dir(direction)
		# Una charca menor que un téxel puede no tener etiqueta. Con agua real y sin ningún
		# cuerpo vecino se trata como agua interior.
		if body.is_empty() or int(body.type) >= WorldMapData.WaterType.LAKE:
			return &"fresh"
		salt = true
	return &"salt" if salt else &""


static func _has_water(terrain: VoxelLodTerrain, tool: VoxelToolLodTerrain,
		water_point: Vector3) -> bool:
	var local := terrain.to_local(water_point)
	# Los vóxeles ausentes pueden leerse como aire: nunca tomarlos por agua.
	if not tool.is_area_editable(AABB(local - Vector3.ONE, Vector3.ONE * 2.0)):
		return false
	return tool.get_voxel_f_interpolated(local) > 0.0
