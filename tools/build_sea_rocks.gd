extends SceneTree

## Rehace data/graph_functions/coastal_reefs.tres: islotes rocosos de la costa (SeaRocks).
##   godot --headless --path . -s res://tools/build_sea_rocks.gd
##
## Cada roca es la intersección de dos cosas, unida después al terreno:
##   contorno: columna vertical del mapa de forma, deformada cerca del borde por un ruido de bultos
##     evaluado en la dirección (sin variar con la altura: paredes sin aleros);
##   cima: a la altura del mapa de cima en el centro, bajando hacia el contorno en cúpula
##     ((1 - q)^2, q = 0 en el borde y 1 en el centro) hasta por debajo del mar, con bultos grandes y
##     rugosidad fina por encima.
## Fuera de las rocas (forma 0) la puerta deja el terreno tal cual y los ruidos no se evalúan. Mantiene
## los nombres que usa Planet (reef_planet_sdf, reef_sea_offset, reef_shell_lo/hi) y las entradas
## earth_field y band_field (esta última ya no se usa: la profundidad la mira el horneado).

const OUT := "res://data/graph_functions/coastal_reefs.tres"
const RADIUS := 30000.0

var f: VoxelGraphFunction


func _initialize() -> void:
	var header := FileAccess.get_file_as_string(OUT).get_slice("\n", 0)
	f = VoxelGraphFunction.new()
	var nx := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(-1300, -60))
	var ny := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(-1300, 20))
	var nz := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(-1300, 100))
	var earth := f.create_node(VoxelGraphFunction.NODE_CUSTOM_INPUT, Vector2(-1300, 320))
	f.set_node_name(earth, "earth_field")
	var band := f.create_node(VoxelGraphFunction.NODE_CUSTOM_INPUT, Vector2(-1300, 440))
	f.set_node_name(band, "band_field")

	var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(-1050, -60))
	f.set_node_name(sphere, "reef_planet_sdf")
	f.set_node_default_input_by_name(sphere, "radius", RADIUS)
	# Altura sobre el mar.
	var sea := _op(VoxelGraphFunction.NODE_ADD, sphere, null, {"b": 50.0}, "reef_sea_offset")

	var shape := _lookup(SeaRocks.SHAPE_NODE, SeaRocks.SHAPE_FACTOR)
	var gate := _lookup(SeaRocks.GATE_NODE, SeaRocks.GATE_FACTOR)
	var top := _lookup(SeaRocks.TOP_NODE, SeaRocks.TOP_SPAN)
	for n in [sphere, shape, gate, top]:
		f.add_connection(nx, 0, n, 0)
		f.add_connection(ny, 0, n, 1)
		f.add_connection(nz, 0, n, 2)

	# Forma (0-1) = (esfera - muestra) / SHAPE_FACTOR. El nodo solo mira la imagen a 1,2 veces su
	# rango de su radio (más lejos devuelve la esfera): con factor 1 no llegaba al nivel del mar.
	var g_raw := _op(VoxelGraphFunction.NODE_SUBTRACT, sphere, shape, {}, "rock_shape_value")
	var g := _op(VoxelGraphFunction.NODE_MULTIPLY, g_raw, null, {"b": 1.0 / SeaRocks.SHAPE_FACTOR})
	# q: 0 en el contorno, 1 en el centro. inv = 1 - q.
	var gq := _op(VoxelGraphFunction.NODE_SUBTRACT, g, null, {"b": 0.5})
	var gq2 := _op(VoxelGraphFunction.NODE_MULTIPLY, gq, null, {"b": 2.0})
	var q := _op(VoxelGraphFunction.NODE_CLAMP, gq2, null, {"min": 0.0, "max": 1.0})
	var inv := _op(VoxelGraphFunction.NODE_SUBTRACT, null, q, {"a": 1.0})

	# Ruido de bultos en la dirección proyectada a la superficie: no cambia con la altura.
	var norm := f.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, Vector2(-1050, 700))
	f.add_connection(nx, 0, norm, 0)
	f.add_connection(ny, 0, norm, 1)
	f.add_connection(nz, 0, norm, 2)
	var proj := []
	for axis in 3:
		var pn := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(-850, 640 + axis * 70))
		f.set_node_name(pn, "%s%d" % [SeaRocks.PROJ_NODE, axis])
		f.set_node_default_input_by_name(pn, "b", RADIUS)
		f.add_connection(norm, axis, pn, 0)
		proj.append(pn)
	var lump := _noise(SeaRocks.LUMP_NODE, 45.0, 2, 777, proj)
	var crag := _noise(SeaRocks.CRAG_NODE, 9.0, 3, 4242, [nx, ny, nz])

	# Contorno en metros: (0,5 - (forma + bultos * (1 - q))) * 2 píxeles. Los bultos solo mueven el
	# borde: dentro (q = 1) no abren agujeros.
	var ln := _op(VoxelGraphFunction.NODE_MULTIPLY, lump, inv, {})
	var lns := _op(VoxelGraphFunction.NODE_MULTIPLY, ln, null, {"b": 0.15}, SeaRocks.OUTLINE_NOISE_NODE)
	var gsum := _op(VoxelGraphFunction.NODE_ADD, g, lns, {})
	var half := _op(VoxelGraphFunction.NODE_SUBTRACT, null, gsum, {"a": 0.5})
	var outline := _op(VoxelGraphFunction.NODE_MULTIPLY, half, null, {"b": 46.0}, SeaRocks.OUTLINE_NODE)
	var neg_outline := _op(VoxelGraphFunction.NODE_MULTIPLY, outline, null, {"b": -1.0})

	# Cúpula: la cima baja (altura de la cima + dome_base) * dome * (1 - q)^2 hacia el borde.
	var t_abs := _op(VoxelGraphFunction.NODE_SUBTRACT, sea, top, {}, "rock_top_height")
	var t_base := _op(VoxelGraphFunction.NODE_ADD, t_abs, null, {"b": 6.0}, SeaRocks.DOME_BASE_NODE)
	var sq := _op(VoxelGraphFunction.NODE_MULTIPLY, inv, inv, {})
	var drop0 := _op(VoxelGraphFunction.NODE_MULTIPLY, t_base, sq, {})
	var drop := _op(VoxelGraphFunction.NODE_MULTIPLY, drop0, null, {"b": 0.85}, SeaRocks.DOME_NODE)
	var lumps := _op(VoxelGraphFunction.NODE_MULTIPLY, lump, null, {"b": 4.0}, SeaRocks.LUMP_AMOUNT_NODE)
	var rough := _op(VoxelGraphFunction.NODE_MULTIPLY, crag, null, {"b": 1.0}, SeaRocks.ROUGH_NODE)
	var top_a := _op(VoxelGraphFunction.NODE_ADD, top, drop, {})
	var top_b := _op(VoxelGraphFunction.NODE_ADD, top_a, lumps, {})
	var top_r := _op(VoxelGraphFunction.NODE_ADD, top_b, rough, {})

	# Cuerpo = max(cima, contorno) suavizado; unido al terreno para que arranque del fondo sin arista.
	var body := _op(VoxelGraphFunction.NODE_SDF_SMOOTH_SUBTRACT, top_r, neg_outline, {}, "rock_body")
	f.set_node_param(body, 0, 2.0)
	var rocky := _op(VoxelGraphFunction.NODE_SDF_SMOOTH_UNION, earth, body, {}, "rock_field")
	f.set_node_param(rocky, 0, 2.5)

	var sel := f.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(500, 150))
	f.set_node_name(sel, "rock_gate_select")
	f.set_node_param(sel, 0, -20000.0)
	f.add_connection(rocky, 0, sel, 0)
	f.add_connection(earth, 0, sel, 1)
	f.add_connection(gate, 0, sel, 2)

	# Ventana radial alrededor del mar: fuera, terreno tal cual (y con los umbrales al infinito,
	# Planet apaga las rocas).
	var lo := f.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(700, 100))
	f.set_node_name(lo, "reef_shell_lo")
	f.set_node_param(lo, 0, -60.0)
	f.add_connection(earth, 0, lo, 0)
	f.add_connection(sel, 0, lo, 1)
	f.add_connection(sea, 0, lo, 2)
	var hi := f.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(900, 100))
	f.set_node_name(hi, "reef_shell_hi")
	f.set_node_param(hi, 0, 40.0)
	f.add_connection(lo, 0, hi, 0)
	f.add_connection(earth, 0, hi, 1)
	f.add_connection(sea, 0, hi, 2)
	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(1100, 100))
	f.set_node_name(out, "reef_field")
	f.add_connection(hi, 0, out, 0)

	f.set("input_definitions", [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0],
		["earth_field", "CustomInput", 0], ["band_field", "CustomInput", 0]])
	f.set("output_definitions", [["reef_field", "CustomOutput", 0]])
	var err := ResourceSaver.save(f, OUT)
	# ResourceSaver pierde el uid de la cabecera: se restaura para no romper las referencias.
	var text := FileAccess.get_file_as_string(OUT)
	if header.contains("uid=") and not text.get_slice("\n", 0).contains("uid="):
		var lines := text.split("\n")
		lines[0] = header
		var fw := FileAccess.open(OUT, FileAccess.WRITE)
		fw.store_string("\n".join(lines))
		fw.close()
	print("guardado: ", error_string(err))
	quit()


var _x := -700.0


## Nodo de operación con 'a' y 'b' conectados (null = suelta) y valores por defecto.
func _op(type: int, a, b, defaults: Dictionary, node_name := "") -> int:
	_x += 10.0
	var n := f.create_node(type, Vector2(_x, 0))
	if node_name != "":
		f.set_node_name(n, node_name)
	for k in defaults:
		f.set_node_default_input_by_name(n, k, defaults[k])
	if a != null:
		f.add_connection(a, 0, n, 0)
	if b != null:
		f.add_connection(b, 0, n, 1)
	return n


func _noise(node_name: String, period: float, octaves: int, seed_v: int, inputs: Array) -> int:
	var noise := FastNoise2.new()
	noise.noise_type = FastNoise2.TYPE_OPEN_SIMPLEX_2
	noise.fractal_type = FastNoise2.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.period = period
	noise.seed = seed_v
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_2_3D, Vector2(-650, 700))
	f.set_node_name(n, node_name)
	f.set_node_param(n, 0, noise)
	for i in 3:
		f.add_connection(inputs[i], 0, n, i)
	return n


func _lookup(node_name: String, factor: float) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-1050, 100))
	f.set_node_name(n, node_name)
	f.set_node_param(n, 0, Image.create(4, 2, false, Image.FORMAT_R8))
	f.set_node_param(n, 1, RADIUS)
	f.set_node_param(n, 2, factor)
	return n
