extends SceneTree

## Genera data/graph_functions/trail_carve.tres (las sendas en el grafo del terreno) y
## trail_clearance.tres (lo que aparta de ellas la vegetación con grafo de densidad). Se escriben con
## la API, como build_river_carve.gd: el formato del grafo es un diccionario de ids y conexiones, y a
## mano se cometen errores mudos.
##   godot --headless --path . -s tools/build_trail_carve.gd
##
## Cada capa de TrailField son tres SdfSphereHeightmap (U, V y la compuerta D) que se combinan en una
## distancia efectiva: el módulo del vector (U, V) donde la compuerta abre y mil metros donde no. Las
## capas se juntan con un mínimo. Planet les mete las imágenes y los parámetros por nombre al cargar
## (TrailGenerator.apply); aquí llevan imágenes neutras, que no pintan nada.

const TERRAIN_OUT := "res://data/graph_functions/trail_carve.tres"
const CLEARANCE_OUT := "res://data/graph_functions/trail_clearance.tres"

const LAYERS := 2
const RADIUS := 30000.0
## Factor de los SdfSphereHeightmap (TrailGenerator.FACTOR). El nodo solo lee la imagen cerca de su
## propia superficie: si |p| - radio cae fuera de [mín, máx] ± 1,2 · (máx - mín), con mín y máx el
## rango de la imagen por el factor, devuelve la esfera sin leerla (medido contra el nodo). Con
## imágenes en [0, 1] y factor 1000 eso es de -1200 a 2200 m: todo el relieve. Un factor del tamaño de
## la banda (72) dejaba de leer a 86 m de altura. La escala de verdad la pone el nodo de después.
const FACTOR := 1000.0
const RB := 72.0
const G0 := 21.1
const G1 := 26.7
const HALF_WIDTH := 1.2
const SOFTNESS := 0.35
const WIDTH_NOISE := 0.36
const EDGE_PERIOD := 30.0
const OPEN_LO := 1.05
const OPEN_HI := 1.45
const SURFACE_NEAR := 16.0
const SURFACE_FAR := 24.0
const DIP := 0.12
const CLEARANCE := 3.0
## Distancia efectiva de una capa más allá de su compuerta (m).
const FAR := 1000.0
## Hasta dónde se le pone al borde el ruido de su ancho (m).
const NOISE_REACH := 10.0


func _initialize() -> void:
	_save(_terrain(), TERRAIN_OUT, true)
	_save(_clearance(), CLEARANCE_OUT, false)
	quit()


## Entradas x, y, z y earth_field (la superficie con los ríos tallados); salidas trail_field (la misma
## con la senda hundida DIP), trail_weight (cuánto es senda) y open_weight (cuánto es suelo libre).
## Los dos pesos solo valen cerca de la superficie: bajo tierra se quedan a 0 para no quitarles sus
## huecos de peso a las menas y a la profundidad.
func _terrain() -> VoxelGraphFunction:
	var f := VoxelGraphFunction.new()
	var xyz := _inputs(f)
	var field_in := f.create_node(VoxelGraphFunction.NODE_CUSTOM_INPUT, Vector2(-1200, 600))
	f.set_node_name(field_in, "earth_field")
	var edge := _edge(f, xyz)

	var core := _smoothstep(f, "trail_core", HALF_WIDTH + SOFTNESS, HALF_WIDTH - SOFTNESS, edge, Vector2(400, 0))
	var open := _smoothstep(f, "trail_open", OPEN_LO, OPEN_HI, edge, Vector2(400, 200))
	var depth := f.create_node(VoxelGraphFunction.NODE_ABS, Vector2(-900, 600))
	f.add_connection(field_in, 0, depth, 0)
	var surface := _smoothstep(f, "trail_surface_gate", SURFACE_FAR, SURFACE_NEAR, depth, Vector2(400, 400))
	var trail_w := _op(f, VoxelGraphFunction.NODE_MULTIPLY, core, surface, Vector2(600, 0))
	var open_w := _op(f, VoxelGraphFunction.NODE_MULTIPLY, open, surface, Vector2(600, 200))
	var dip := _op(f, VoxelGraphFunction.NODE_MULTIPLY, trail_w, DIP, Vector2(800, 400))
	f.set_node_name(dip, "trail_dip")
	var field_out := _op(f, VoxelGraphFunction.NODE_ADD, field_in, dip, Vector2(1000, 500))

	var outs := []
	for pair in [["trail_field", field_out], ["trail_weight", trail_w], ["open_weight", open_w]]:
		var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(1200, 200 * outs.size()))
		f.set_node_name(out, pair[0])
		f.add_connection(pair[1], 0, out, 0)
		outs.append([pair[0], "CustomOutput", 0])
	# El orden fija los índices de puerto: x=0, y=1, z=2, earth_field=3; y las salidas, en este orden.
	f.set("input_definitions", [
		["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0], ["earth_field", "CustomInput", 0],
	])
	f.set("output_definitions", outs)
	return f


## Entradas x, y, z; salida trail_clearance: 0 sobre la senda y hasta CLEARANCE m de su eje, 1 a un
## metro más. Se multiplica por la densidad de la vegetación (Planet._build_generator).
func _clearance() -> VoxelGraphFunction:
	var f := VoxelGraphFunction.new()
	var edge := _edge(f, _inputs(f))
	var clear := _smoothstep(f, "trail_clear", CLEARANCE, CLEARANCE + 1.0, edge, Vector2(400, 0))
	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(600, 0))
	f.set_node_name(out, "trail_clearance")
	f.add_connection(clear, 0, out, 0)
	f.set("input_definitions", [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0]])
	f.set("output_definitions", [["trail_clearance", "CustomOutput", 0]])
	return f


func _inputs(f: VoxelGraphFunction) -> Array:
	return [
		f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(-1200, 0)),
		f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(-1200, 80)),
		f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(-1200, 160)),
	]


## Distancia al borde de la senda más cercana de todas las capas, con su ancho variando por un ruido
## (trail_edge_noise, que también pone el borde irregular). Devuelve el nodo.
func _edge(f: VoxelGraphFunction, xyz: Array) -> int:
	# El radio es una ENTRADA del SdfSphere: Planet._apply_radius se lo pone al cargar.
	var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(-1000, -200))
	f.set_node_name(sphere, "trail_planet_sdf")
	f.set_node_default_input_by_name(sphere, "radius", RADIUS)
	_connect_xyz(f, xyz, sphere)
	var nearest := -1
	for k in LAYERS:
		var eff := _layer(f, xyz, sphere, k)
		if nearest < 0:
			nearest = eff
		else:
			nearest = _op(f, VoxelGraphFunction.NODE_MIN, nearest, eff, Vector2(100, 300 * k))
	var noise_res := FastNoise2.new()
	noise_res.noise_type = FastNoise2.TYPE_SIMPLEX
	noise_res.period = EDGE_PERIOD
	noise_res.fractal_type = FastNoise2.FRACTAL_FBM
	noise_res.fractal_octaves = 3
	var noise := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_2_3D, Vector2(-200, 900))
	f.set_node_name(noise, "trail_edge_noise")
	f.set_node_param(noise, 0, noise_res)
	_connect_xyz(f, xyz, noise)
	var widen := _op(f, VoxelGraphFunction.NODE_MULTIPLY, noise, WIDTH_NOISE, Vector2(0, 900))
	f.set_node_name(widen, "trail_width_noise")
	var ragged := _op(f, VoxelGraphFunction.NODE_SUBTRACT, nearest, widen, Vector2(200, 600))
	# El ruido solo cerca de la senda: más lejos el borde no se ve, y con la distancia por encima del
	# umbral en todo el bloque el módulo se salta la rama del ruido.
	return _select(f, ragged, nearest, nearest, NOISE_REACH, Vector2(300, 600))


## Distancia efectiva de la capa [k]: |(U, V)| donde la compuerta D abre, más 1000 m donde cierra.
func _layer(f: VoxelGraphFunction, xyz: Array, sphere: int, k: int) -> int:
	var y0 := 400.0 * k
	var comps := []
	for c in ["u", "v"]:
		# (muestra - esfera) = -FACTOR·h; por -2·rb / FACTOR da 2·rb·h y la componente es eso - rb:
		# h = 0,5 + c / (2·rb).
		var sample := _heightmap(f, xyz, sphere, "trail_%s_%d" % [c, k], -2.0 * RB, Vector2(-800, y0))
		var comp := _op(f, VoxelGraphFunction.NODE_ADD, sample, -RB, Vector2(-500, y0))
		f.set_node_name(comp, "trail_%s_bias_%d" % [c, k])
		comps.append(_op(f, VoxelGraphFunction.NODE_MULTIPLY, comp, comp, Vector2(-350, y0)))
	var length := f.create_node(VoxelGraphFunction.NODE_SQRT, Vector2(-100, y0))
	f.add_connection(_op(f, VoxelGraphFunction.NODE_ADD, comps[0], comps[1], Vector2(-200, y0)), 0, length, 0)
	# D = dmax - dmax·h, con h = 1 - D / dmax.
	var d_sample := _heightmap(f, xyz, sphere, "trail_d_%d" % k, -RB, Vector2(-800, y0 + 200))
	var d := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-500, y0 + 200))
	f.set_node_name(d, "trail_d_range_%d" % k)
	f.set_node_default_input(d, 0, RB)
	f.add_connection(d_sample, 0, d, 1)
	var gate := _smoothstep(f, "trail_gate_%d" % k, G1, G0, d, Vector2(-300, y0 + 200))
	var shut := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-150, y0 + 200))
	f.set_node_default_input(shut, 0, 1.0)
	f.add_connection(gate, 0, shut, 1)
	var far := _op(f, VoxelGraphFunction.NODE_MULTIPLY, shut, 1000.0, Vector2(0, y0 + 200))
	var full := _op(f, VoxelGraphFunction.NODE_ADD, length, far, Vector2(100, y0 + 100))
	# Más allá de la compuerta, 1000 m sin leer U y V: el módulo poda la rama que no elige el Select
	# cuando D cae entera a un lado del umbral en el bloque, que es casi todo el planeta.
	var sel := _select(f, full, FAR, d, G1, Vector2(200, y0 + 100))
	f.set_node_name(sel, "trail_select_%d" % k)
	return sel


## La muestra h de la imagen por -[scale]: (SdfSphereHeightmap - esfera) = -FACTOR·h, por
## [scale] / FACTOR en un nodo con el nombre de la muestra y "scale" (trail_scale_u_0).
func _heightmap(f: VoxelGraphFunction, xyz: Array, sphere: int, node_name: String, scale: float,
		at: Vector2) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, at)
	f.set_node_name(n, node_name)
	f.set_node_param(n, 0, _neutral())
	f.set_node_param(n, 1, RADIUS)
	f.set_node_param(n, 2, FACTOR)
	_connect_xyz(f, xyz, n)
	var sample := _op(f, VoxelGraphFunction.NODE_SUBTRACT, n, sphere, at + Vector2(100, 0))
	var scaled := _op(f, VoxelGraphFunction.NODE_MULTIPLY, sample, scale / FACTOR, at + Vector2(200, 0))
	f.set_node_name(scaled, node_name.replace("trail_", "trail_scale_"))
	return scaled


## Select: [a] donde [t] < [threshold] y [b] donde no; [b] es un nodo (int) o una constante.
func _select(f: VoxelGraphFunction, a: int, b, t: int, threshold: float, at: Vector2) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_SELECT, at)
	f.set_node_param(n, 0, threshold)
	f.add_connection(a, 0, n, 0)
	if b is int:
		f.add_connection(b, 0, n, 1)
	else:
		f.set_node_default_input(n, 1, float(b))
	f.add_connection(t, 0, n, 2)
	return n


func _smoothstep(f: VoxelGraphFunction, node_name: String, edge0: float, edge1: float, input: int,
		at: Vector2) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, at)
	f.set_node_name(n, node_name)
	f.set_node_param(n, 0, edge0)
	f.set_node_param(n, 1, edge1)
	f.add_connection(input, 0, n, 0)
	return n


## Nodo [type] con [a] en su primera entrada y [b] en la segunda: otro nodo si es int, una constante
## si es float.
func _op(f: VoxelGraphFunction, type: int, a: int, b, at: Vector2) -> int:
	var n := f.create_node(type, at)
	f.add_connection(a, 0, n, 0)
	if b is int:
		f.add_connection(b, 0, n, 1)
	else:
		f.set_node_default_input(n, 1, float(b))
	return n


func _connect_xyz(f: VoxelGraphFunction, xyz: Array, node: int) -> void:
	for i in 3:
		f.add_connection(xyz[i], 0, node, i)


## Imagen neutra: 0 en U, V y D, que es "lejos de toda senda" (la compuerta cierra).
func _neutral() -> Image:
	var b := PackedByteArray()
	b.resize(8)
	return Image.create_from_data(4, 2, false, Image.FORMAT_R8, b)


## Guarda [f] y comprueba que compila dentro de un generador de verdad.
func _save(f: VoxelGraphFunction, path: String, terrain: bool) -> void:
	var err := ResourceSaver.save(f, path)
	print("guardado ", path, " -> ", error_string(err))
	var loaded: VoxelGraphFunction = load(path)
	var gen := VoxelGeneratorGraph.new()
	var main := gen.get_main_function()
	var mx := main.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var my := main.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 40))
	var mz := main.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 80))
	var fn := main.create_function_node(loaded, Vector2(200, 0))
	var mo := main.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(400, 0))
	main.add_connection(mx, 0, fn, 0)
	main.add_connection(my, 0, fn, 1)
	main.add_connection(mz, 0, fn, 2)
	if terrain:
		var sphere := main.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(100, 120))
		main.add_connection(mx, 0, sphere, 0)
		main.add_connection(my, 0, sphere, 1)
		main.add_connection(mz, 0, sphere, 2)
		main.add_connection(sphere, 0, fn, 3)
		for layer in [[1, 14], [2, 13]]:
			var w := main.create_node(VoxelGraphFunction.NODE_OUTPUT_WEIGHT, Vector2(400, 100 * layer[1]))
			main.set_node_param(w, 0, layer[1])
			main.add_connection(fn, layer[0], w, 0)
	main.add_connection(fn, 0, mo, 0)
	print("  nodos: ", loaded.get_node_ids().size(), ", compila: ", gen.compile())
