extends Node

## La azada (TerrainLeveling) sobre un terreno de vóxeles llano de verdad: el plano de alrededor es la
## mediana de las muestras, cada golpe recorre RATE de lo que falta con el tope STEP, rebaja un
## montículo y rellena un hoyo hasta dejarlos a nivel, no toca nada fuera del borde y sube al que
## pisa lo rellenado. El terreno va desplazado para que el mundo y los vóxeles no coincidan. Vigila
## también la escala que do_graph pone a la SDF del pincel (√3): si el módulo la cambiara, los golpes
## dejarían de medir lo que dicen.
##   godot --headless --path . res://tests/planet/test_terrain_leveling.tscn

## Dónde va el terreno en el mundo: el suelo llano queda a la altura de su origen.
const OFFSET := Vector3(300.0, 40.0, -200.0)
const UP := Vector3.UP
## Error admitido en las alturas leídas (m): la SDF va cuantizada y el rayo refina a 1/64.
const TOLERANCE := 0.03

var failures := 0
var terrain: VoxelLodTerrain
var tool: VoxelTool


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	terrain = VoxelLodTerrain.new()
	var generator := VoxelGeneratorFlat.new()
	generator.height = 0.0
	terrain.generator = generator
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 4
	# Límites más allá de lo que carga el visor: fuera de los límites el módulo lo da todo por editable.
	terrain.voxel_bounds = AABB(Vector3(-2048, -64, -2048), Vector3(4096, 128, 4096))
	terrain.view_distance = 128
	terrain.position = OFFSET
	add_child(terrain)
	terrain.add_child(VoxelViewer.new())
	tool = TerrainLeveling._tool(terrain)
	var loaded := false
	for i in 300:
		await get_tree().process_frame
		if tool.is_area_editable(AABB(Vector3(-24, -16, -16), Vector3(48, 32, 32))):
			loaded = true
			break
	check(loaded, "el terreno de prueba carga")
	if not loaded:
		_finish()
		return

	check(absf(_height(Vector3(-15, 0, 0))) < TOLERANCE, "el suelo llano está a 0 (%.3f)" % _height(Vector3(-15, 0, 0)))

	# Un montículo de 1 m: una esfera de 2,5 m de radio con el centro 1,5 m bajo el suelo.
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.mode = VoxelTool.MODE_ADD
	tool.do_sphere(Vector3(0, -1.5, 0), 2.5)
	var top := _height(Vector3.ZERO)
	check(absf(top - 1.0) < TOLERANCE, "el montículo mide 1 m (%.3f)" % top)
	# Muestras: el centro a 1 m, las seis de 0,9 m a 0,83 y las diez del borde a 0,13: la mediana es
	# una del borde.
	var center = TerrainLeveling.plane_center(terrain, _world(Vector3(0, top, 0)), UP)
	check(center != null, "hay plano sobre el montículo")
	if center != null:
		var plane := UP.dot(center - _world(Vector3.ZERO))
		check(absf(plane - 0.125) < 0.1, "el plano es la mediana de alrededor, no la media (%.3f)" % plane)
	var outside := _height(Vector3(3.2, 0, 0))

	# Golpes al nivel del suelo llano: el primero topa en STEP, los siguientes recorren RATE.
	var expected := 1.0
	for stroke in 4:
		check(TerrainLeveling.apply(terrain, _world(Vector3.ZERO), UP), "el golpe %d se da" % (stroke + 1))
		expected -= minf(expected * TerrainLeveling.RATE, TerrainLeveling.STEP)
		var now := _height(Vector3.ZERO)
		check(absf(now - expected) < TOLERANCE, "golpe %d: el centro baja a %.3f (%.3f)" % [stroke + 1, expected, now])
	check(absf(_height(Vector3(0.8, 0, 0.5))) < 0.1, "dentro de RADIUS queda a nivel (%.3f)" % _height(Vector3(0.8, 0, 0.5)))
	check(absf(_height(Vector3(3.2, 0, 0)) - outside) < 0.01, "fuera del borde no cambia nada")

	# Un hoyo de 1 m: se rellena igual, hacia arriba.
	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(Vector3(12, 1.5, 0), 2.5)
	var bottom := _height(Vector3(12, 0, 0))
	check(absf(bottom + 1.0) < TOLERANCE, "el hoyo tiene 1 m (%.3f)" % bottom)
	check(TerrainLeveling.apply(terrain, _world(Vector3(12, 0, 0)), UP), "el golpe sobre el hoyo se da")
	var filled := _height(Vector3(12, 0, 0))
	check(absf(filled + 0.5) < TOLERANCE, "rellena como mucho STEP por golpe (%.3f)" % filled)

	# Quien está en el hoyo sube con el relleno, y quien está fuera del círculo, no.
	var body := Node3D.new()
	add_child(body)
	body.global_position = _world(Vector3(12, filled, 0))
	TerrainLeveling.apply(terrain, _world(Vector3(12, 0, 0)), UP)
	TerrainLeveling.lift_onto_ground(terrain, body, _world(Vector3(12, 0, 0)), UP)
	var feet := UP.dot(body.global_position - _world(Vector3(12, 0, 0)))
	var ground := _height(Vector3(12, 0, 0))
	check(feet > ground and feet - ground < 0.05, "sube al que pisa lo rellenado (pies %.3f, suelo %.3f)" % [feet, ground])
	var away := Node3D.new()
	add_child(away)
	away.global_position = _world(Vector3(16, 0, 0))
	TerrainLeveling.lift_onto_ground(terrain, away, _world(Vector3(12, 0, 0)), UP)
	check(away.global_position.is_equal_approx(_world(Vector3(16, 0, 0))), "fuera del círculo no mueve a nadie")

	# A los pies: un plano por encima del suelo rellena hacia él.
	check(TerrainLeveling.apply(terrain, _world(Vector3(-12, 0.3, 0)), UP), "el golpe a los pies se da")
	var raised := _height(Vector3(-12, 0, 0))
	check(absf(raised - 0.3 * TerrainLeveling.RATE) < TOLERANCE, "sube hacia un plano más alto (%.3f)" % raised)

	check(not TerrainLeveling.apply(terrain, _world(Vector3(2000, 0, 0)), UP), "sin terreno cargado no hace nada")
	_finish()


## Altura del suelo en [local] (vóxeles, sobre el plano y = 0), leída como la lee la azada.
func _height(local: Vector3) -> float:
	return TerrainLeveling.ground_height(tool, _world(Vector3(local.x, 0, local.z)), UP)


func _world(local: Vector3) -> Vector3:
	return terrain.global_transform * local


func _finish() -> void:
	print("TERRAIN LEVELING TESTS: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
