class_name TrailGenerator extends RefCounted

## Las sendas del mundo en el generador del terreno: hornea el campo (TrailNetwork traza, TrailField
## rasteriza) y lo enchufa por nombre en las funciones de trail_carve.tres y trail_clearance.tres
## (las genera tools/build_trail_carve.gd), como RiverGenerator con los ríos.
##
## El terreno saca dos pesos de vóxel: TRAIL_LAYER, cuánto es senda (lo pinta planet_biomes.gdshader),
## y OPEN_LAYER, cuánto es suelo libre (1 fuera de las sendas, 0 sobre ellas). La vegetación de suelo
## filtra por OPEN_LAYER (voxel_texture_filter del VoxelInstanceGenerator: solo brota donde pesa ≥ 0,5)
## sin coste de carga; la que va en un LOD grueso, como los árboles, no ve una senda de 4 m en una
## malla de 16 y se aparta en su grafo de densidad con clear_vegetation. Ninguno de los dos pesos es
## una mena: is_trail_layer.

const TRAIL_LAYER := 14
const OPEN_LAYER := 13

const CLEARANCE_GRAPH := "res://data/graph_functions/trail_clearance.tres"
const SPHERE_NODE := "trail_planet_sdf"
## Factor de los SdfSphereHeightmap: tiene que ser el de tools/build_trail_carve.gd (ver allí por qué
## no es la escala de la banda); la escala la pone el nodo trail_scale_* de detrás.
const FACTOR := 1000.0
## Claves de trail_settings que solo tocan el grafo (apply, clear_vegetation), la vegetación o el
## shader: cambiarlas no pide trazar otra vez la red.
const LOOK_KEYS := ["half_width", "edge_softness", "width_variation", "edge_noise_period", "dip",
	"clearance_max_lod", "texture_index", "albedo", "edge_blend", "edge_sharpness", "fade_start", "fade_end",
	"snow_clear", "snow_tint", "far_distance"]
## Índices de parámetro de SdfSphereHeightmap: imagen, radio, factor.
const _P_IMAGE := 0
const _P_RADIUS := 1
const _P_FACTOR := 2


## Si la capa de pesos [layer] es de las sendas (y no una mena).
static func is_trail_layer(layer: int) -> bool:
	return layer == TRAIL_LAYER or layer == OPEN_LAYER


## [cfg] sin LOOK_KEYS: lo que decide el campo, para la clave de su caché.
static func field_settings(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	for key in LOOK_KEYS:
		out.erase(key)
	return out


## Hornea el campo de sendas con el relieve de [generator], que tiene que llevar ya los ríos tallados y
## las sendas neutras. [sea_height] es la altura del mar sobre el radio. {} si no sale ninguna.
static func build_field(generator: VoxelGeneratorGraph, radius: float, sea_height: float,
		height_range: float, rivers: Dictionary, cfg: Dictionary) -> Dictionary:
	if generator == null or not generator.has_method("bake_sphere_bumpmap"):
		return {}
	var size: Vector2i = cfg.get("routing_size", Vector2i(2048, 1024))
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	generator.bake_sphere_bumpmap(img, radius, -height_range, height_range)
	# Como en RiverGenerator: el horneado deja la fila 0 en el polo sur.
	img.flip_y()
	var net := TrailNetwork.build(img.get_data().to_float32_array(), size, radius, -height_range,
		height_range * 2.0, sea_height, rivers, cfg)
	var strokes: Array[PackedVector3Array] = net.strokes
	if strokes.is_empty():
		return {}
	var field := TrailField.build(strokes, radius, cfg)
	field.stats = net.stats
	return field


## Mete en [target] (un VoxelGeneratorGraph o una VoxelGraphFunction) el juego [group] del campo
## ("terrain" o "trees") y los parámetros de forma de [cfg]. true si encontró las sendas.
static func apply(target, field: Dictionary, group: String, cfg: Dictionary) -> bool:
	var functions := _functions(target)
	if _owner(functions, SPHERE_NODE) == null:
		return false
	var radius := float(field.radius)
	var images: Dictionary = field[group]
	var layers: Array = images.images
	var k := 0
	while _owner(functions, "trail_u_%d" % k) != null:
		if k < layers.size():
			for c in ["u", "v", "d"]:
				var fn := _owner(functions, "trail_%s_%d" % [c, k])
				var node := fn.find_node_by_name("trail_%s_%d" % [c, k])
				fn.set_node_param(node, _P_IMAGE, layers[k][c])
				fn.set_node_param(node, _P_RADIUS, radius)
				fn.set_node_param(node, _P_FACTOR, FACTOR)
				var scale := -2.0 * float(images.rb) if c != "d" else -float(images.dmax)
				_set_input(functions, "trail_scale_%s_%d" % [c, k], "b", scale / FACTOR)
			_set_input(functions, "trail_u_bias_%d" % k, "b", -float(images.rb))
			_set_input(functions, "trail_v_bias_%d" % k, "b", -float(images.rb))
			_set_input(functions, "trail_d_range_%d" % k, "a", float(images.dmax))
			_set_smoothstep(functions, "trail_gate_%d" % k, float(images.g1), float(images.g0))
			var sel_fn := _owner(functions, "trail_select_%d" % k)
			if sel_fn != null:
				sel_fn.set_node_param(sel_fn.find_node_by_name("trail_select_%d" % k), 0, float(images.g1))
		k += 1
	if layers.size() > k:
		push_warning("[trails] el campo trae %d capas y el grafo, %d: sobran sendas." % [layers.size(), k])
	_set_input(functions, SPHERE_NODE, "radius", radius)

	var half := float(cfg.get("half_width", 1.2))
	var soft := float(cfg.get("edge_softness", 0.35))
	_set_smoothstep(functions, "trail_core", half + soft, half - soft)
	_set_smoothstep(functions, "trail_open", half - 0.15, half + 0.25)
	_set_input(functions, "trail_dip", "b", float(cfg.get("dip", 0.12)))
	_set_input(functions, "trail_width_noise", "b", half * float(cfg.get("width_variation", 0.3)))
	var noise_fn := _owner(functions, "trail_edge_noise")
	if noise_fn != null:
		var noise = noise_fn.get_node_param(noise_fn.find_node_by_name("trail_edge_noise"), 0)
		if noise != null:
			noise.period = float(cfg.get("edge_noise_period", 30.0))
	return true


## Copia de [graph] (el grafo de densidad de un generador de vegetación) con la densidad a 0 hasta
## [clearance] m del eje de las sendas y entera a un metro más. Lee el juego "trees" del campo.
static func clear_vegetation(graph: VoxelGraphFunction, field: Dictionary, clearance: float,
		cfg: Dictionary) -> VoxelGraphFunction:
	if graph.resource_path != "":
		graph = graph.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var output := -1
	var inputs := {}
	for id in graph.get_node_ids():
		var type := graph.get_node_type_id(id)
		if type == VoxelGraphFunction.NODE_CUSTOM_OUTPUT:
			output = id
		elif type in [VoxelGraphFunction.NODE_INPUT_X, VoxelGraphFunction.NODE_INPUT_Y, VoxelGraphFunction.NODE_INPUT_Z]:
			inputs[type] = id
	var density := {}
	for c in graph.get_connections():
		if c.dst_node_id == output:
			density = c
	if density.is_empty():
		push_error("[trails] el grafo de densidad no tiene salida; la vegetación no se aparta de las sendas.")
		return graph
	for type in [VoxelGraphFunction.NODE_INPUT_X, VoxelGraphFunction.NODE_INPUT_Y, VoxelGraphFunction.NODE_INPUT_Z]:
		if not inputs.has(type):
			inputs[type] = graph.create_node(type, Vector2())

	var clear: VoxelGraphFunction = load(CLEARANCE_GRAPH).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	apply(clear, field, "trees", cfg)
	_set_smoothstep([clear], "trail_clear", clearance, clearance + 1.0)
	var node := graph.create_function_node(clear, Vector2())
	graph.add_connection(inputs[VoxelGraphFunction.NODE_INPUT_X], 0, node, 0)
	graph.add_connection(inputs[VoxelGraphFunction.NODE_INPUT_Y], 0, node, 1)
	graph.add_connection(inputs[VoxelGraphFunction.NODE_INPUT_Z], 0, node, 2)
	graph.remove_connection(density.src_node_id, density.src_port_index, output, density.dst_port_index)
	var product := graph.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2())
	graph.add_connection(density.src_node_id, density.src_port_index, product, 0)
	graph.add_connection(node, 0, product, 1)
	graph.add_connection(product, 0, output, density.dst_port_index)
	return graph


static func _functions(target) -> Array:
	var root: VoxelGraphFunction = target.get_main_function() if target is VoxelGeneratorGraph else target
	var functions: Array = [root]
	_gather(root, functions)
	return functions


static func _gather(fn: VoxelGraphFunction, acc: Array) -> void:
	for node_id in fn.get_node_ids():
		if fn.get_node_type_id(node_id) != VoxelGraphFunction.NODE_FUNCTION:
			continue
		var sub = fn.get_node_param(node_id, 0)
		if sub is VoxelGraphFunction and not acc.has(sub):
			acc.append(sub)
			_gather(sub, acc)


static func _owner(functions: Array, node_name: String) -> VoxelGraphFunction:
	for fn: VoxelGraphFunction in functions:
		if fn.find_node_by_name(node_name) > 0:
			return fn
	return null


static func _set_input(functions: Array, node_name: String, input: String, value: float) -> void:
	var fn := _owner(functions, node_name)
	if fn != null:
		fn.set_node_default_input_by_name(fn.find_node_by_name(node_name), input, value)


static func _set_smoothstep(functions: Array, node_name: String, edge0: float, edge1: float) -> void:
	var fn := _owner(functions, node_name)
	if fn != null:
		var node := fn.find_node_by_name(node_name)
		fn.set_node_param(node, 0, edge0)
		fn.set_node_param(node, 1, edge1)
