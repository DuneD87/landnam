class_name ClimateGraph extends RefCounted

## Banda de frío dentro de un grafo de densidad de vegetación. Reproduce en nodos el campo de
## ClimateField (y de climate.gdshaderinc): |latitud| + gradiente · altura + dos octavas de ruido
## OpenSimplex2 con los mismos ZN_FastNoiseLite. Así un generador del JSON con
##   "climate": {"min": 41, "max": 53, "soft": 1.5}
## solo emite donde el frío cae en esa banda: los árboles de la taiga crecen exactamente donde el
## suelo tiene la nieve de la taiga, y los del bioma verde se paran donde empieza.
##
## No hay asin en el grafo: la latitud sale de la aproximación de Abramowitz-Stegun 4.4.45
## (error < 0,004 grados), que es mucho menos que el ruido del propio campo.

const _ASIN := [1.5707288, -0.2121144, 0.0742610, -0.0187293]


## Copia de `source` con la salida multiplicada por la banda de frío [cold_min, cold_max], con
## bordes suaves de ±soft grados. cold_min <= -90 o cold_max >= 180 dejan ese lado abierto.
static func gate(source: VoxelGraphFunction, climate: ClimateField, cold_min: float, cold_max: float,
		soft: float = 1.5) -> VoxelGraphFunction:
	if climate == null or not climate.enabled:
		return source
	var graph := source
	# El recurso cacheado del ResourceLoader no se toca: el módulo compila al asignar y otros
	# generadores lo comparten.
	if graph.resource_path != "":
		graph = source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var output := -1
	var inputs := {}
	for id in graph.get_node_ids():
		var type := graph.get_node_type_id(id)
		if type == VoxelGraphFunction.NODE_CUSTOM_OUTPUT:
			output = id
		elif type in [VoxelGraphFunction.NODE_INPUT_X, VoxelGraphFunction.NODE_INPUT_Y, VoxelGraphFunction.NODE_INPUT_Z]:
			inputs[type] = id
	var mask := {}
	for c in graph.get_connections():
		if c.dst_node_id == output:
			mask = c
	if mask.is_empty() or inputs.size() != 3:
		push_error("Vegetación: el grafo de densidad no tiene salida o entradas x, y, z; banda de frío sin aplicar.")
		return source
	graph.remove_connection(mask.src_node_id, mask.src_port_index, output, mask.dst_port_index)

	var cold := coldness_node(graph, climate,
		inputs[VoxelGraphFunction.NODE_INPUT_X], inputs[VoxelGraphFunction.NODE_INPUT_Y],
		inputs[VoxelGraphFunction.NODE_INPUT_Z])
	var band := -1
	if cold_min > -90.0:
		band = _smoothstep(graph, cold, cold_min - soft, cold_min + soft)
	if cold_max < 180.0:
		var upper := _smoothstep(graph, cold, cold_max + soft, cold_max - soft)
		band = upper if band < 0 else _op(graph, VoxelGraphFunction.NODE_MULTIPLY, band, upper)
	if band < 0:
		graph.add_connection(mask.src_node_id, mask.src_port_index, output, mask.dst_port_index)
		return graph
	# La máscara es >= 0 y la banda está en [0, 1]: el signo (quitar o dejar el punto) no cambia.
	var result := _op(graph, VoxelGraphFunction.NODE_MULTIPLY, mask.src_node_id, band, mask.src_port_index)
	graph.add_connection(result, 0, output, 0)
	return graph


## Nodo con el frío en grados a partir de las entradas x, y, z.
static func coldness_node(graph: VoxelGraphFunction, climate: ClimateField, x: int, y: int, z: int) -> int:
	var r := _node(graph, VoxelGraphFunction.NODE_DISTANCE_3D)
	graph.add_connection(x, 0, r, 0)
	graph.add_connection(y, 0, r, 1)
	graph.add_connection(z, 0, r, 2)
	for port in range(3, 6):
		graph.set_node_default_input(r, port, 0.0)
	# s = |y| / r, latitud = 90° - sqrt(1 - s) · polinomio(s)
	var s := _op(graph, VoxelGraphFunction.NODE_DIVIDE, _op(graph, VoxelGraphFunction.NODE_ABS, y), r)
	s = _op(graph, VoxelGraphFunction.NODE_MIN, s, 1.0)
	# Horner: ((a3 · s + a2) · s + a1) · s + a0
	var poly := _op(graph, VoxelGraphFunction.NODE_ADD, _op(graph, VoxelGraphFunction.NODE_MULTIPLY, s, _ASIN[3]), _ASIN[2])
	for coefficient in [_ASIN[1], _ASIN[0]]:
		poly = _op(graph, VoxelGraphFunction.NODE_ADD, _op(graph, VoxelGraphFunction.NODE_MULTIPLY, poly, s), coefficient)
	var one_minus := _op(graph, VoxelGraphFunction.NODE_MAX, _const_minus(graph, 1.0, s), 0.0)
	var root := _op(graph, VoxelGraphFunction.NODE_SQRT, one_minus)
	var colat := _op(graph, VoxelGraphFunction.NODE_MULTIPLY, root, poly)
	var lat := _op(graph, VoxelGraphFunction.NODE_MULTIPLY, _const_minus(graph, PI * 0.5, colat), rad_to_deg(1.0))
	# Altura: grados de frío por metro sobre lapse_base.
	var height := _op(graph, VoxelGraphFunction.NODE_SUBTRACT, r, climate.radius + climate.lapse_base)
	var cooling := _op(graph, VoxelGraphFunction.NODE_MULTIPLY,
		_op(graph, VoxelGraphFunction.NODE_MAX, height, 0.0), climate.lapse)
	var cold := _op(graph, VoxelGraphFunction.NODE_ADD, lat, cooling)
	for octave in [[climate.noise_period, climate.noise_seed, climate.noise_amplitude],
			[climate.detail_period, climate.detail_seed, climate.detail_amplitude]]:
		var noise := _node(graph, VoxelGraphFunction.NODE_FAST_NOISE_3D)
		graph.add_connection(x, 0, noise, 0)
		graph.add_connection(y, 0, noise, 1)
		graph.add_connection(z, 0, noise, 2)
		graph.set_node_param(noise, 0, ClimateField.make_noise(octave[0], octave[1]))
		cold = _op(graph, VoxelGraphFunction.NODE_ADD, cold,
			_op(graph, VoxelGraphFunction.NODE_MULTIPLY, noise, float(octave[2])))
	return cold


## Nodo sin autoconexión: por defecto el compilador engancha a X, Y, Z las entradas sin cable, y
## la segunda esquina de Distance3D o la constante de un Subtract dejaban de ser lo que se pone.
static func _node(graph: VoxelGraphFunction, type: int) -> int:
	var node := graph.create_node(type, Vector2())
	graph.set_node_default_inputs_autoconnect(node, false)
	return node


## c - node (Subtract con la constante en la primera entrada).
static func _const_minus(graph: VoxelGraphFunction, c: float, node: int) -> int:
	var sub := _node(graph, VoxelGraphFunction.NODE_SUBTRACT)
	graph.set_node_default_input(sub, 0, c)
	graph.add_connection(node, 0, sub, 1)
	return sub


static func _smoothstep(graph: VoxelGraphFunction, node: int, edge0: float, edge1: float) -> int:
	var step := _node(graph, VoxelGraphFunction.NODE_SMOOTHSTEP)
	graph.add_connection(node, 0, step, 0)
	graph.set_node_param_by_name(step, "edge0", edge0)
	graph.set_node_param_by_name(step, "edge1", edge1)
	return step


## Nodo conectado a `a` por su primera entrada; `b` es un id de nodo si es int, una constante si
## es float y nada en los nodos de una entrada.
static func _op(graph: VoxelGraphFunction, type: int, a: int, b = null, a_port: int = 0) -> int:
	var node := _node(graph, type)
	graph.add_connection(a, a_port, node, 0)
	if b is int:
		graph.add_connection(b, 0, node, 1)
	elif b != null:
		graph.set_node_default_input(node, 1, float(b))
	return node
