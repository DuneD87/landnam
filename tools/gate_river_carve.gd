extends SceneTree

## Añade a data/graph_functions/river_carve.tres una puerta que devuelve el terreno sin tallar donde
## no hay río a menos del alcance, para que el generador se salte el tallado (y su ruido 3D de las
## paredes) en todos los bloques lejos de un cauce.
##   godot --headless --path . -s res://tools/gate_river_carve.gd
##
## Por qué una segunda lectura del mapa de distancias y no un Select sobre river_distance_m: los
## metros salen de restar la esfera a la muestra, y en el análisis de rangos por bloque esa resta no
## se cancela (los dos intervalos se tratan como independientes), así que el rango de la distancia se
## ensancha tanto como mide el bloque y la puerta nunca se cerraría. Con un factor enorme, cualquier
## píxel no nulo del mapa (>= 1/255) baja la muestra miles de km, mucho más que la altura del bloque.

const PATH := "res://data/graph_functions/river_carve.tres"
const GATE_NODE := "river_near_gate"
const SELECT_NODE := "river_gate"


func _initialize() -> void:
	var f: VoxelGraphFunction = load(PATH)
	if f.find_node_by_name(GATE_NODE) > 0:
		print("ya tenía la puerta")
		quit()
		return
	var inputs := {}
	for id in f.get_node_ids():
		inputs[f.get_node_type_id(id)] = id
	var nx: int = inputs[VoxelGraphFunction.NODE_INPUT_X]
	var ny: int = inputs[VoxelGraphFunction.NODE_INPUT_Y]
	var nz: int = inputs[VoxelGraphFunction.NODE_INPUT_Z]
	var field_in := f.find_node_by_name("earth_field")
	var mix := f.find_node_by_name("river_mix")
	var out := f.find_node_by_name("river_field")
	var dist := f.find_node_by_name("river_dist_map")

	var gate := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-520, -260))
	f.set_node_name(gate, GATE_NODE)
	f.set_node_param(gate, 0, f.get_node_param(dist, 0))
	f.set_node_param(gate, 1, f.get_node_param(dist, 1))
	f.set_node_param(gate, 2, RiverGenerator.GATE_FACTOR)
	for pair in [[nx, 0], [ny, 1], [nz, 2]]:
		f.add_connection(pair[0], 0, gate, pair[1])

	# Select: muestra < umbral (hay río cerca) -> a = mezcla tallada; si no -> b = terreno tal cual.
	var sel := f.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(740, -60))
	f.set_node_name(sel, SELECT_NODE)
	f.set_node_param(sel, 0, RiverGenerator.GATE_THRESHOLD)
	f.remove_connection(mix, 0, out, 0)
	f.add_connection(mix, 0, sel, 0)
	f.add_connection(field_in, 0, sel, 1)
	f.add_connection(gate, 0, sel, 2)
	f.add_connection(sel, 0, out, 0)
	print("guardado: ", error_string(ResourceSaver.save(f, PATH)))
	quit()
