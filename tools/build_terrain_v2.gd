extends SceneTree

## Construye el SDF del terreno v2 junto al viejo, sin tocarlo:
## - data/graph_functions/earth_relief.tres: earth_field = relieve grande horneado (PlanetRelief) +
##   octavas 3-6 de la montaña en vivo, solo donde hay montaña.
## - data/graph_functions/cave_field_v2.tres: cave_field con las cuevas a más de CAVE_MIN_DEPTH metros
##   bajo la superficie, salvo en las bocas (Spots3D).
## - data/graph_functions/earth_terrain_v2.tres: earth_terrain_terraces con esas dos funciones y el
##   tallado de ríos v2 (river_carve_v2.tres, de tools/build_river_carve_v2.gd: ejecutarlo antes).
##   godot --headless --path . -s res://tools/build_terrain_v2.gd
##
## Por qué así (medido con build/ab/relief_proto.gd, bloques de superficie 16^3): la base vieja cuesta
## ~450 us (6 octavas de ruido celular 3D en cada vóxel) y las cuevas otros ~235 us en todo bloque que
## toque el suelo. El relieve horneado cuesta ~107 us y las octavas finas ~180 más solo en montaña; la
## puerta de profundidad deja que la poda se salte las cuevas en los bloques de superficie.

const BASE := "res://data/graph_functions/earth_terrain_base.tres"
const CAVE := "res://data/graph_functions/cave_field.tres"
const MAIN := "res://data/graph_functions/earth_terrain_terraces.tres"
const OUT_RELIEF := "res://data/graph_functions/earth_relief.tres"
const OUT_CAVE := "res://data/graph_functions/cave_field_v2.tres"
const OUT_MAIN := "res://data/graph_functions/earth_terrain_v2.tres"
const RIVER := "res://data/graph_functions/river_carve.tres"
const OUT_RIVER := "res://data/graph_functions/river_carve_v2.tres"

const CAVE_MIN_DEPTH := 30.0
const ENTRANCE_CELL := 350.0
const ENTRANCE_RADIUS := 45.0
const ENTRANCE_SEED := 909


func _initialize() -> void:
	_build_relief()
	_build_caves()
	_build_main()
	quit()


func _build_relief() -> void:
	var base: VoxelGraphFunction = load(BASE)
	var mountains = base.get_node_param(base.find_node_by_name("fast_noise_mountains"), 0)
	var f := VoxelGraphFunction.new()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(-900, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(-900, 80))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(-900, 160))

	# Relieve horneado. Imagen, radio y factor los pone PlanetRelief.apply al cargar el planeta.
	var low := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-600, -100))
	f.set_node_name(low, PlanetRelief.RELIEF_NODE)
	f.set_node_param(low, 0, _neutral(Image.FORMAT_RF))
	f.set_node_param(low, 1, 30000.0)
	f.set_node_param(low, 2, 1.0)

	# Máscara de montaña horneada, leída con el truco del factor enorme: (esfera - muestra) / F.
	var mmap := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-600, 100))
	f.set_node_name(mmap, PlanetRelief.MASK_NODE)
	f.set_node_param(mmap, 0, _neutral(Image.FORMAT_R8))
	f.set_node_param(mmap, 1, 30000.0)
	f.set_node_param(mmap, 2, PlanetRelief.MASK_FACTOR)
	var sph := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(-600, 250))
	f.set_node_name(sph, "relief_planet_sdf")
	f.set_node_default_input_by_name(sph, "radius", 30000.0)
	for n in [low, mmap, sph]:
		f.add_connection(x, 0, n, 0)
		f.add_connection(y, 0, n, 1)
		f.add_connection(z, 0, n, 2)
	var msub := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-400, 150))
	f.add_connection(sph, 0, msub, 0)
	f.add_connection(mmap, 0, msub, 1)
	var mscale := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(-250, 150))
	f.set_node_name(mscale, "relief_mask")
	f.set_node_default_input_by_name(mscale, "b", 1.0 / PlanetRelief.MASK_FACTOR)
	f.add_connection(msub, 0, mscale, 0)
	# Por debajo de un escalón de la máscara (1/255) el producto es 0 exacto y la poda se salta el ruido.
	var moff := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-100, 150))
	f.set_node_default_input_by_name(moff, "b", 0.004)
	f.add_connection(mscale, 0, moff, 0)
	var mgate := f.create_node(VoxelGraphFunction.NODE_MAX, Vector2(50, 150))
	f.set_node_name(mgate, "relief_mask_gate")
	f.set_node_default_input_by_name(mgate, "b", 0.0)
	f.add_connection(moff, 0, mgate, 0)

	# Octavas 3-6 del mismo ruido de montaña: misma semilla por octava (FastNoise2 suma 1 por octava),
	# frecuencia de la tercera octava, 4 octavas. Amplitud: la parte de esas octavas en la suma
	# normalizada de 6, por los 250 m de la montaña.
	var detail_noise: Resource = mountains.duplicate()
	detail_noise.seed = int(mountains.seed) + PlanetRelief.BAKED_OCTAVES
	detail_noise.period = float(mountains.period) / pow(float(mountains.fractal_lacunarity), PlanetRelief.BAKED_OCTAVES)
	detail_noise.fractal_octaves = int(mountains.fractal_octaves) - PlanetRelief.BAKED_OCTAVES
	var det := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_2_3D, Vector2(-250, 350))
	f.set_node_name(det, "relief_detail")
	f.set_node_param(det, 0, detail_noise)
	f.add_connection(x, 0, det, 0)
	f.add_connection(y, 0, det, 1)
	f.add_connection(z, 0, det, 2)
	var damp := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(-50, 350))
	f.set_node_name(damp, "relief_detail_amplitude")
	f.set_node_default_input_by_name(damp, "b", PlanetRelief.detail_amplitude(mountains))
	f.add_connection(det, 0, damp, 0)
	var dm := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(150, 250))
	f.add_connection(damp, 0, dm, 0)
	f.add_connection(mgate, 0, dm, 1)
	var sum := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(300, 0))
	f.add_connection(low, 0, sum, 0)
	f.add_connection(dm, 0, sum, 1)
	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(450, 0))
	f.set_node_name(out, "earth_field")
	f.add_connection(sum, 0, out, 0)
	f.set("input_definitions", [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0]])
	f.set("output_definitions", [["earth_field", "CustomOutput", 0]])
	print("relieve: ", error_string(ResourceSaver.save(f, OUT_RELIEF)), "  amplitud del detalle ",
		PlanetRelief.detail_amplitude(mountains), " m, periodo ", detail_noise.period)


func _build_caves() -> void:
	var f: VoxelGraphFunction = load(CAVE).duplicate(false)
	var ids := {}
	for id in f.get_node_ids():
		ids[f.get_node_type_id(id)] = id
	var earth := f.find_node_by_name("earth_field")
	var gate := f.find_node_by_name("cave_depth_gate")
	# Profundidad mínima: CAVE_MIN_DEPTH fuera de las bocas, 0 dentro (Spots3D vale 1 en la boca).
	var spots := f.create_node(VoxelGraphFunction.NODE_SPOTS_3D, Vector2(-500, 400))
	f.set_node_name(spots, "cave_entrance_spots")
	f.set_node_param_by_name(spots, "cell_size", ENTRANCE_CELL)
	f.set_node_param_by_name(spots, "jitter", 0.9)
	f.set_node_param_by_name(spots, "seed", ENTRANCE_SEED)
	f.set_node_default_input_by_name(spots, "spot_radius", ENTRANCE_RADIUS)
	f.add_connection(ids[VoxelGraphFunction.NODE_INPUT_X], 0, spots, 0)
	f.add_connection(ids[VoxelGraphFunction.NODE_INPUT_Y], 0, spots, 1)
	f.add_connection(ids[VoxelGraphFunction.NODE_INPUT_Z], 0, spots, 2)
	var depth := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(-350, 400))
	f.set_node_name(depth, "cave_min_depth")
	f.set_node_default_input_by_name(depth, "b", -CAVE_MIN_DEPTH)
	f.add_connection(spots, 0, depth, 0)
	var depth2 := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(-200, 400))
	f.set_node_default_input_by_name(depth2, "b", CAVE_MIN_DEPTH)
	f.add_connection(depth, 0, depth2, 0)
	# earth_field + profundidad mínima: el Max del gate ya no deja cuevas por encima de ella.
	var shifted := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(-100, 300))
	f.set_node_name(shifted, "cave_depth_shift")
	f.add_connection(earth, 0, shifted, 0)
	f.add_connection(depth2, 0, shifted, 1)
	f.remove_connection(earth, 0, gate, 0)
	f.add_connection(shifted, 0, gate, 0)
	print("cuevas: ", error_string(ResourceSaver.save(f, OUT_CAVE)))


## El grafo principal se copia como TEXTO cambiando solo las rutas de la base y de las cuevas: cambiar
## la función de un nodo Function por la API borra sus conexiones, y rehacerlas choca con aserciones del
## módulo. Las funciones nuevas tienen los mismos puertos que las que sustituyen.
func _build_main() -> void:
	var text := FileAccess.get_file_as_string(MAIN)
	var lines := text.split("\n")
	# Sin uid propio (el original lo tiene; Godot asigna uno nuevo).
	lines[0] = lines[0].replace(" uid=\"%s\"" % ResourceUID.id_to_text(ResourceLoader.get_resource_uid(MAIN)), "")
	text = "\n".join(lines)
	for pair in [[BASE, OUT_RELIEF], [CAVE, OUT_CAVE], [RIVER, OUT_RIVER]]:
		var uid := ResourceUID.id_to_text(ResourceLoader.get_resource_uid(pair[0]))
		text = text.replace("uid=\"%s\" path=\"%s\"" % [uid, pair[0]], "path=\"%s\"" % pair[1])
		if not ("path=\"%s\"" % pair[1]) in text:
			push_error("no se encontró la referencia a %s" % pair[0])
	var f := FileAccess.open(OUT_MAIN, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var check: VoxelGeneratorGraph = ResourceLoader.load(OUT_MAIN, "", ResourceLoader.CACHE_MODE_IGNORE)
	print("principal: ", check.compile(), "  conexiones ", check.get_main_function().get_connections().size())


func _neutral(format: int) -> Image:
	return Image.create(4, 2, false, format)
