extends SceneTree

## Genera data/graph_functions/settlement_flatten.tres: el aplanado de los poblados en el grafo del
## terreno (SettlementFlatten). Se escribe con la API, como build_trail_carve.gd.
##   godot --headless --path . -s tools/build_settlement_flatten.gd
##
## Dos SdfSphereHeightmap: la cota del plano de cada poblado (settlement_flat_t, que da directamente la
## SDF del plano: |p| - (radio + FACTOR · h)) y su peso (settlement_flat_w, h en [0, 1]). El campo de
## entrada se lleva hacia la del plano por el peso, solo cerca de la superficie (la compuerta
## settlement_flat_surface, para no mover cuevas ni menas), y donde el peso es 0 en todo el bloque el
## Select se salta la rama entera: fuera de los poblados no cuesta nada más que leer el peso. Planet les
## mete las imágenes por nombre al cargar (SettlementFlatten.apply); aquí llevan imágenes neutras.
##
## Saca también el peso (flat_weight, con la compuerta): el grafo del terreno lo usa para que las cuevas
## no abran boca dentro de un poblado (el techo de cave_field.tres), porque su ruido no sabe del
## relieve y vaciaría lo rellenado.

const OUT := "res://data/graph_functions/settlement_flatten.tres"
const RADIUS := 30000.0
## Tienen que ser SettlementFlatten.FACTOR y WEIGHT_FACTOR. El peso lleva uno enorme por el análisis
## de rangos: sale de restar la muestra y la esfera, que varían por el bloque, y el rango de la resta
## se abre lo que mide el bloque dividido por el factor. Con 1000, un bloque de 32 m ya pasa del
## umbral del Select y no poda nunca (el peso se leía en cada vóxel de todo el planeta, un 30 % más
## caro); con 10⁶ se queda en milésimas aun en bloques de 512 m, y en float sigue afinando a 10⁻⁷.
const FACTOR := 1000.0
const WEIGHT_FACTOR := 1000000.0
## La compuerta de superficie: entera hasta SURFACE_NEAR m de la superficie de entrada y a 0 en
## SURFACE_FAR.
const SURFACE_NEAR := 60.0
const SURFACE_FAR := 90.0
## Peso por debajo del cual no se aplana. El Select no prueba el peso sino max(peso - WEIGHT_EPS, 0):
## lejos de los poblados su rango sale de un solo valor (0) y el runtime deja de calcularlo, y con él la
## lectura de la imagen. Un Select calcula siempre lo que prueba, aunque pode la rama que no elige.
const WEIGHT_EPS := 0.002
const TEST_THRESHOLD := 1.0e-7


func _initialize() -> void:
	var f := _flatten()
	var err := ResourceSaver.save(f, OUT)
	print("guardado ", OUT, " -> ", error_string(err))
	_check(load(OUT))
	quit()


## Entradas x, y, z y earth_field; salidas flat_field y flat_weight.
func _flatten() -> VoxelGraphFunction:
	var f := VoxelGraphFunction.new()
	var xyz := [
		f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(-1000, 0)),
		f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(-1000, 80)),
		f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(-1000, 160)),
	]
	var field_in := f.create_node(VoxelGraphFunction.NODE_CUSTOM_INPUT, Vector2(-1000, 400))
	f.set_node_name(field_in, "earth_field")
	# El radio es una ENTRADA del SdfSphere: Planet._apply_radius se lo pone al cargar.
	var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(-800, -200))
	f.set_node_name(sphere, "settlement_planet_sdf")
	f.set_node_default_input_by_name(sphere, "radius", RADIUS)
	_connect_xyz(f, xyz, sphere)

	# Peso: (muestra - esfera) = -WEIGHT_FACTOR · h, por -1 / WEIGHT_FACTOR.
	var w_map := _heightmap(f, xyz, "settlement_flat_w", Vector2(-800, 0), WEIGHT_FACTOR)
	var w_raw := _op(f, VoxelGraphFunction.NODE_SUBTRACT, w_map, sphere, Vector2(-600, 0))
	var weight := _op(f, VoxelGraphFunction.NODE_MULTIPLY, w_raw, -1.0 / WEIGHT_FACTOR, Vector2(-450, 0))
	f.set_node_name(weight, "settlement_flat_weight")
	var shifted := _op(f, VoxelGraphFunction.NODE_SUBTRACT, weight, WEIGHT_EPS, Vector2(-300, -100))
	var test := _op(f, VoxelGraphFunction.NODE_MAX, shifted, 0.0, Vector2(-150, -100))
	f.set_node_name(test, "settlement_flat_test")
	# La cota: la muestra ya es la SDF del plano.
	var target := _heightmap(f, xyz, "settlement_flat_t", Vector2(-800, 200), FACTOR)

	var depth := f.create_node(VoxelGraphFunction.NODE_ABS, Vector2(-800, 400))
	f.add_connection(field_in, 0, depth, 0)
	var gate := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(-600, 400))
	f.set_node_name(gate, "settlement_flat_surface")
	f.set_node_param(gate, 0, SURFACE_FAR)
	f.set_node_param(gate, 1, SURFACE_NEAR)
	f.add_connection(depth, 0, gate, 0)
	var w := _op(f, VoxelGraphFunction.NODE_MULTIPLY, weight, gate, Vector2(-300, 200))
	var diff := _op(f, VoxelGraphFunction.NODE_SUBTRACT, target, field_in, Vector2(-300, 300))
	var pull := _op(f, VoxelGraphFunction.NODE_MULTIPLY, diff, w, Vector2(-150, 250))
	var mixed := _op(f, VoxelGraphFunction.NODE_ADD, field_in, pull, Vector2(0, 300))
	# Select: la entrada donde el peso no pasa de WEIGHT_EPS y lo aplanado donde sí.
	var sel := f.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(200, 300))
	f.set_node_name(sel, "settlement_flat_select")
	f.set_node_param(sel, 0, TEST_THRESHOLD)
	f.add_connection(field_in, 0, sel, 0)
	f.add_connection(mixed, 0, sel, 1)
	f.add_connection(test, 0, sel, 2)

	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(400, 300))
	f.set_node_name(out, "flat_field")
	f.add_connection(sel, 0, out, 0)
	# El peso que sale, también tras un Select: lejos de los poblados es un 0 constante y no obliga a
	# leer la imagen.
	var sel_w := f.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(200, 450))
	f.set_node_name(sel_w, "settlement_flat_weight_select")
	f.set_node_param(sel_w, 0, TEST_THRESHOLD)
	f.set_node_default_input(sel_w, 0, 0.0)
	f.add_connection(w, 0, sel_w, 1)
	f.add_connection(test, 0, sel_w, 2)
	var out_w := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(400, 450))
	f.set_node_name(out_w, "flat_weight")
	f.add_connection(sel_w, 0, out_w, 0)
	# El orden fija los índices de puerto: x=0, y=1, z=2, earth_field=3.
	f.set("input_definitions", [
		["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0], ["earth_field", "CustomInput", 0],
	])
	f.set("output_definitions", [["flat_field", "CustomOutput", 0], ["flat_weight", "CustomOutput", 0]])
	return f


func _heightmap(f: VoxelGraphFunction, xyz: Array, node_name: String, at: Vector2, factor: float) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, at)
	f.set_node_name(n, node_name)
	f.set_node_param(n, 0, _neutral())
	f.set_node_param(n, 1, RADIUS)
	f.set_node_param(n, 2, factor)
	_connect_xyz(f, xyz, n)
	return n


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


## Imagen neutra: peso 0 (no aplana).
func _neutral() -> Image:
	return Image.create(4, 2, false, Image.FORMAT_RF)


## Que compila dentro de un generador de verdad.
func _check(loaded: VoxelGraphFunction) -> void:
	var gen := VoxelGeneratorGraph.new()
	var main := gen.get_main_function()
	var mx := main.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var my := main.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 40))
	var mz := main.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 80))
	var sphere := main.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(100, 120))
	var fn := main.create_function_node(loaded, Vector2(200, 0))
	var mo := main.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(400, 0))
	for i in 3:
		main.add_connection([mx, my, mz][i], 0, sphere, i)
		main.add_connection([mx, my, mz][i], 0, fn, i)
	main.add_connection(sphere, 0, fn, 3)
	main.add_connection(fn, 0, mo, 0)
	print("  nodos: ", loaded.get_node_ids().size(), ", compila: ", gen.compile())
