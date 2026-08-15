extends SceneTree

## Arregla la compuerta de superficie de los grafos de vegetación de bioma.
##
## Los cuatro llevan un nodo Function llamado 'cave_mask' que en realidad apunta a
## earth_terrain_base.tres, seguido de un Smoothstep(-3, 0): o sea "solo hay vegetación a menos de
## 3 m de la superficie SIN TALLAR". Una ribera de río está decenas de metros por debajo de eso, así
## que el campo vale 0 y no crece nada, pase lo que pase con min_height o max_slope_degrees.
##
## Se le mete delante la misma reconstrucción del terreno tallado que ya usa la vegetación de cueva:
##   valle   = lecho - bank_slope * distancia + wall_amplitude
##   tallado = max(terreno_sin_tallar, valle)
## Lejos de cualquier río las imágenes neutras dejan el valle muy por debajo del terreno, el max se
## queda con el terreno y el comportamiento es idéntico al de ahora.
##
## Idempotente: si los nodos ya están, los reutiliza.

const PATHS := [
	"res://data/graph_functions/earth_terrain_green_hemisphere.tres",
	"res://data/graph_functions/earth_terrain_green_sand_hemisphere.tres",
	"res://data/graph_functions/earth_terrain_sand_hemisphere.tres",
	"res://data/graph_functions/earth_terrain_sand_hemisphere_grass.tres",
]


func _initialize() -> void:
	for path in PATHS:
		_patch(path)
	quit()


func _patch(path: String) -> void:
	var g: VoxelGraphFunction = load(path)
	var base := g.find_node_by_name("cave_mask")
	if base <= 0:
		push_error("%s: no encuentro el nodo cave_mask" % path)
		return

	# El Smoothstep(-3, 0) que cuelga de él es la compuerta a interceptar.
	var gate := -1
	for nid in g.get_node_ids():
		var info = g.get_node_type_info(g.get_node_type_id(nid))
		if not (info is Dictionary and info.get("name", "") == "Smoothstep"):
			continue
		if is_equal_approx(float(g.get_node_param(nid, 0)), -3.0) \
				and is_equal_approx(float(g.get_node_param(nid, 1)), 0.0):
			gate = nid
	if gate <= 0:
		push_error("%s: no encuentro el Smoothstep(-3, 0)" % path)
		return

	var inputs := {}
	for nid in g.get_node_ids():
		var info = g.get_node_type_info(g.get_node_type_id(nid))
		if info is Dictionary:
			inputs[info.get("name", "")] = nid

	var sphere := _ensure(g, "river_planet_sdf", VoxelGraphFunction.NODE_SDF_SPHERE,
		Vector2(-520, 700), inputs)
	if sphere == _created:
		g.set_node_default_input_by_name(sphere, "radius", 30000.0)

	var dist := _ensure(g, "river_dist_map", VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP,
		Vector2(-520, 820), inputs)
	if dist == _created:
		g.set_node_param(dist, 0, _neutral_r8())
		g.set_node_param(dist, 1, 30000.0)
		g.set_node_param(dist, 2, 240.0)

	var bed := _ensure(g, "river_bed_map", VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP,
		Vector2(-520, 960), inputs)
	if bed == _created:
		g.set_node_param(bed, 0, _neutral_rf())
		g.set_node_param(bed, 1, 30000.0)
		g.set_node_param(bed, 2, -1000.0)

	# distancia en metros = (muestra - esfera) + alcance, igual que en river_carve.
	var sub := _ensure(g, "river_dist_sub", VoxelGraphFunction.NODE_SUBTRACT, Vector2(-280, 780), {})
	if sub == _created:
		g.add_connection(dist, 0, sub, 0)
		g.add_connection(sphere, 0, sub, 1)

	var dm := _ensure(g, "river_distance_m", VoxelGraphFunction.NODE_ADD, Vector2(-120, 780), {})
	if dm == _created:
		g.set_node_default_input_by_name(dm, "b", 240.0)
		g.add_connection(sub, 0, dm, 0)

	var slope := _ensure(g, "river_bank_slope", VoxelGraphFunction.NODE_MULTIPLY,
		Vector2(40, 860), {})
	if slope == _created:
		g.set_node_default_input_by_name(slope, "b", 1.0)
		g.add_connection(dm, 0, slope, 0)

	var valley := _ensure(g, "river_valley_surface", VoxelGraphFunction.NODE_SUBTRACT,
		Vector2(220, 900), {})
	if valley == _created:
		g.add_connection(bed, 0, valley, 0)
		g.add_connection(slope, 0, valley, 1)

	# Margen del ruido de pared: sin él, la mitad de la ladera (la que el ruido hundió) queda por
	# debajo del valle analítico y la compuerta la vuelve a leer como "lejos de la superficie".
	var margin := _ensure(g, "river_wall_amplitude", VoxelGraphFunction.NODE_ADD,
		Vector2(400, 900), {})
	if margin == _created:
		g.set_node_default_input_by_name(margin, "b", 34.0)
		g.add_connection(valley, 0, margin, 0)

	var carved := _ensure(g, "river_carved_surface", VoxelGraphFunction.NODE_MAX,
		Vector2(560, 800), {})
	if carved == _created:
		g.add_connection(base, 0, carved, 0)
		g.add_connection(margin, 0, carved, 1)

	g.remove_connection(base, 0, gate, 0)
	g.add_connection(carved, 0, gate, 0)

	var err := ResourceSaver.save(g, path)
	print("%s -> %s (%d nodos)" % [path.get_file(), error_string(err), g.get_node_ids().size()])


var _created := -1


## Devuelve el nodo con ese nombre, creándolo si no existe. Si lo crea, deja su id en _created para
## que el llamante sepa que toca inicializarlo y no le pise los parámetros a uno ya ajustado.
func _ensure(g: VoxelGraphFunction, name: String, type: int, pos: Vector2,
		inputs: Dictionary) -> int:
	var existing := g.find_node_by_name(name)
	if existing > 0:
		_created = -1
		return existing
	var nid := g.create_node(type, pos)
	g.set_node_name(nid, name)
	if inputs.has("InputX"):
		g.add_connection(inputs["InputX"], 0, nid, 0)
		g.add_connection(inputs["InputY"], 0, nid, 1)
		g.add_connection(inputs["InputZ"], 0, nid, 2)
	_created = nid
	return nid


func _neutral_r8() -> Image:
	var b := PackedByteArray()
	b.resize(8)
	return Image.create_from_data(4, 2, false, Image.FORMAT_R8, b)


func _neutral_rf() -> Image:
	var f := PackedFloat32Array()
	f.resize(8)
	return Image.create_from_data(4, 2, false, Image.FORMAT_RF, f.to_byte_array())
