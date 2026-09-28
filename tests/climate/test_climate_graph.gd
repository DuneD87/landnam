extends SceneTree

## La banda de frío de los grafos de vegetación (ClimateGraph) tiene que decidir lo mismo que
## ClimateField: evalúa el frío del grafo en puntos sueltos y lo compara con la CPU, y comprueba
## que un generador con "climate" solo deja puntos dentro de su banda.
##   godot --headless --path . -s res://tests/climate/test_climate_graph.gd

const CONFIG := "res://data/planet/planet_earth.json"
var failures := 0


func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var radius: float = config.terrain_settings.radius
	var climate := ClimateField.new(config.climate_settings, radius)

	# Grafo que saca el frío en crudo: la máscara de superficie (trae las entradas declaradas) con
	# la salida recableada.
	var fn := _rewired(func(g: VoxelGraphFunction, x: int, y: int, z: int) -> int:
		# El canal SDF recorta los valores grandes: el frío sale en centésimas.
		var scaled := g.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2())
		g.set_node_default_inputs_autoconnect(scaled, false)
		g.add_connection(ClimateGraph.coldness_node(g, climate, x, y, z), 0, scaled, 0)
		g.set_node_default_input(scaled, 1, 0.01)
		return scaled)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var worst := 0.0
	for i in 200:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var p := dir * (radius + rng.randf_range(-60.0, 700.0))
		var voxel := Vector3(roundi(p.x), roundi(p.y), roundi(p.z))
		var graph_cold := _eval(fn, voxel) * 100.0
		worst = maxf(worst, absf(graph_cold - climate.coldness(voxel)))
	print("frío del grafo contra la CPU: diferencia máxima %.4f grados" % worst)
	_check(worst < 0.05, "el grafo reproduce el frío de ClimateField")

	# Banda sobre una máscara de 1: dentro 1, fuera 0.
	var ones := _rewired(func(g: VoxelGraphFunction, _x: int, _y: int, _z: int) -> int:
		var one := g.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2())
		g.set_node_param(one, 0, 1.0)
		return one)
	var banded := ClimateGraph.gate(ones, climate, 41.0, 53.0, 1.5)
	var wrong := 0
	for i in 400:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var p := dir * (radius + rng.randf_range(-40.0, 500.0))
		var c := climate.coldness(p)
		var v := _eval(banded, p)
		if (c < 39.0 or c > 55.0) and v > 0.0:
			wrong += 1
		if c > 43.0 and c < 51.0 and v < 0.99:
			wrong += 1
	_check(wrong == 0, "la banda de frío deja pasar solo su franja (%d fallos)" % wrong)
	print("CLIMATE GRAPH: %d failures" % failures)
	quit(1 if failures > 0 else 0)


## Copia de la máscara de superficie con la salida conectada a lo que construya `build`.
func _rewired(build: Callable) -> VoxelGraphFunction:
	var g: VoxelGraphFunction = load("res://data/graph_functions/earth_terrain_surface.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var output := -1
	var inputs := {}
	for id in g.get_node_ids():
		var type := g.get_node_type_id(id)
		if type == VoxelGraphFunction.NODE_CUSTOM_OUTPUT:
			output = id
		elif type in [VoxelGraphFunction.NODE_INPUT_X, VoxelGraphFunction.NODE_INPUT_Y, VoxelGraphFunction.NODE_INPUT_Z]:
			inputs[type] = id
	for c in g.get_connections():
		if c.dst_node_id == output:
			g.remove_connection(c.src_node_id, c.src_port_index, c.dst_node_id, c.dst_port_index)
	var node: int = build.call(g, inputs[VoxelGraphFunction.NODE_INPUT_X], inputs[VoxelGraphFunction.NODE_INPUT_Y],
		inputs[VoxelGraphFunction.NODE_INPUT_Z])
	g.add_connection(node, 0, output, 0)
	return g


## Evalúa una función de grafo en un punto: la envuelve en un generador que la saca por el SDF.
func _eval(fn: VoxelGraphFunction, p: Vector3) -> float:
	var g := VoxelGeneratorGraph.new()
	var m := g.get_main_function()
	var ix := m.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var iy := m.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
	var iz := m.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
	var f := m.create_function_node(fn, Vector2())
	var out := m.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	m.add_connection(ix, 0, f, 0)
	m.add_connection(iy, 0, f, 1)
	m.add_connection(iz, 0, f, 2)
	m.add_connection(f, 0, out, 0)
	var result = g.compile()
	if result is Dictionary and not result.get("success", false):
		push_error("no compila: %s" % result)
		return NAN
	var buffer := VoxelBuffer.new()
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	buffer.create(1, 1, 1)
	g.generate_block(buffer, Vector3i(roundi(p.x), roundi(p.y), roundi(p.z)), 0)
	return buffer.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FALLO: " + what)
	else:
		print("ok: ", what)
