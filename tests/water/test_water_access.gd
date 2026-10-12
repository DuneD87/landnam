extends SceneTree

## Orillas reales con un mapa grueso y riberas cuya imagen de distancias no basta para E.
##   godot --headless --path . -s res://tests/water/test_water_access.gd

const Access = preload("res://scripts/player/water_access.gd")
const SEA_RADIUS := 1000.0

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _map() -> WorldMapData:
	var map := WorldMapData.new()
	map.size = Vector2i(64, 32)
	map.radius = SEA_RADIUS
	map.sea_level_radius = SEA_RADIUS
	map.has_water = true
	map.heights.resize(map.size.x * map.size.y)
	map.heights.fill(0.6)
	map.body_ids.resize(map.heights.size())
	map.body_ids.fill(-1)
	map.bodies = [{"type": WorldMapData.WaterType.LAKE}]
	return map


func _run() -> void:
	var map := _map()
	var cell := map.texel_of_dir(Vector3.RIGHT)
	map.body_ids[cell - 1] = 0
	check(map.water_body_at_dir(Vector3.RIGHT).is_empty(), "La orilla de regresión cae en una celda de tierra")
	check(map.nearby_water_body_at_dir(Vector3.RIGHT).get("type", -1) == WorldMapData.WaterType.LAKE,
		"El lago vecino aporta el tipo del agua en una orilla sin etiqueta")
	var seam := WorldMapData.uv_to_dir(Vector2(0.999, 0.5))
	map.body_ids.fill(-1)
	map.body_ids[16 * map.size.x] = 0
	check(not map.nearby_water_body_at_dir(seam).is_empty(), "La búsqueda de orillas envuelve la longitud")
	map.body_ids.fill(-1)
	map.body_ids[cell - 1] = 0

	var world := Node3D.new()
	root.add_child(world)
	var terrain := VoxelLodTerrain.new()
	var generator := VoxelGeneratorFlat.new()
	generator.height = 4.0
	terrain.generator = generator
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 3
	terrain.view_distance = 128
	terrain.streaming_system = VoxelLodTerrain.STREAMING_SYSTEM_CLIPBOX
	world.add_child(terrain)
	var viewer := VoxelViewer.new()
	viewer.position = Vector3(SEA_RADIUS, 1, 0)
	viewer.view_distance = 128
	terrain.add_child(viewer)
	var tool := terrain.get_voxel_tool() as VoxelToolLodTerrain
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var pool := Vector3.RIGHT * SEA_RADIUS
	for attempt in 100:
		if tool.is_area_editable(AABB(pool - Vector3.ONE * 45.0, Vector3.ONE * 90.0)):
			break
		await create_timer(0.05).timeout
	check(tool.is_area_editable(AABB(pool - Vector3.ONE * 45.0, Vector3.ONE * 90.0)),
		"El terreno de prueba está cargado a LOD 0")
	var feet := Vector3.RIGHT * (SEA_RADIUS + 1.0)
	check(Access.kind_at(feet, terrain, map, {}, SEA_RADIUS) == &"",
		"Una etiqueta de lago próxima no permite beber en terreno seco")
	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(pool, 8.0)
	check(Access.kind_at(feet, terrain, map, {}, SEA_RADIUS) == &"fresh",
		"Se bebe del lago real aunque la celda del jugador sea tierra")
	var bank := (pool + Vector3.FORWARD * 9.5).normalized() * (SEA_RADIUS + 1.0)
	check(Access.kind_at(bank, terrain, map, {}, SEA_RADIUS) == &"fresh",
		"Se alcanza el agua desde la orilla a menos de 2,5 m")
	var far_bank := (pool + Vector3.FORWARD * 14.0).normalized() * (SEA_RADIUS + 1.0)
	check(Access.kind_at(far_bank, terrain, map, {}, SEA_RADIUS) == &"",
		"El lago fuera de alcance no se puede recoger")
	map.bodies[0].type = WorldMapData.WaterType.OCEAN
	check(Access.kind_at(feet, terrain, map, {}, SEA_RADIUS) == &"salt",
		"La costa real de un océano sigue siendo agua salada")
	map.bodies[0].type = WorldMapData.WaterType.SEA
	check(Access.kind_at(feet, terrain, map, {}, SEA_RADIUS) == &"salt",
		"El mar sigue siendo agua salada")
	map.body_ids.fill(-1)
	check(Access.kind_at(feet, terrain, map, {}, SEA_RADIUS) == &"fresh",
		"Una charca real menor que un téxel permite recoger agua dulce")
	map.body_ids.fill(0)
	map.bodies[0].type = WorldMapData.WaterType.LAKE
	check(Access.kind_at(Vector3.RIGHT * (SEA_RADIUS + 10.0), terrain, map, {}, SEA_RADIUS) == &"",
		"No se bebe desde diez metros por encima del agua")
	var unloaded := pool.rotated(Vector3.UP, 0.75)
	check(Access.kind_at(unloaded, terrain, map, {}, SEA_RADIUS) == &"",
		"Los vóxeles sin cargar no se toman por agua")
	var shift := Vector3(25000, -8000, 9000)
	terrain.position = shift
	check(Access.kind_at(feet + shift, terrain, map, {}, SEA_RADIUS) == &"fresh",
		"La consulta usa el centro vivo después de un cambio de origen")
	terrain.position = Vector3.ZERO

	var image := Image.create(8, 4, false, Image.FORMAT_R8)
	image.fill(Color.BLACK)
	var rivers := {
		"dist": image, "carve_range": 150.0, "radius": SEA_RADIUS,
		"hydro_size": Vector2i(64, 32),
		"seg": PackedFloat32Array([31.5, 16, 32.5, 16, -20, -20, 12, 12]),
	}
	var river_bank := (pool + Vector3.UP * 17.0).normalized() * (SEA_RADIUS + 1.0)
	check(RiverField.distance_at(rivers, river_bank.normalized()) > Access.RIVER_REACH,
		"La imagen del río de regresión no detecta una ribera al alcance")
	check(not RiverField.nearby_channel_at(rivers, river_bank.normalized(), Access.RIVER_REACH).is_empty(),
		"Los segmentos detectan el borde del río a cinco metros")
	map.bodies[0].type = WorldMapData.WaterType.OCEAN
	check(Access.kind_at(river_bank, terrain, map, rivers, SEA_RADIUS) == &"fresh",
		"El cauce real se puede recoger aunque el mapa lo conecte con el océano")
	check(Access.kind_at(river_bank, terrain, null, rivers, SEA_RADIUS) == &"fresh",
		"El río permite beber mientras el mapa mundial está pendiente")
	var outside := (pool + Vector3.UP * 20.0).normalized()
	check(RiverField.nearby_channel_at(rivers, outside, Access.RIVER_REACH).is_empty(),
		"El río no amplía su alcance más allá de seis metros")
	tool.mode = VoxelTool.MODE_ADD
	tool.do_sphere(pool, 9.0)
	check(Access.kind_at(river_bank, terrain, null, rivers, SEA_RADIUS) == &"",
		"Un cauce seco no permite beber solo porque exista su segmento")
	world.queue_free()
	await process_frame
	await process_frame
	print("WATER ACCESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
