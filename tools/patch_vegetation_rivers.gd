extends SceneTree

## Prepara los grafos de densidad de la vegetación de superficie para el terreno v2:
## - Sin plantas en el cauce ni en la llanura del río: la salida se multiplica por river_keep, un
##   smoothstep sobre river_distance_m (los bordes los pone RiverGenerator.apply: de blend_range a
##   blend_range + 15).
## - La reconstrucción del terreno usa el relieve horneado (earth_relief.tres) en vez de la base vieja:
##   evaluaba 6 octavas de ruido celular 3D por punto candidato en cada uno de los ~49 tipos, y ya no
##   coincide con el terreno. Las imágenes del relieve las pone Planet._load_vegetation_graph.
##   godot --headless --path . -s res://tools/patch_vegetation_rivers.gd

const GRAPHS := ["earth_terrain_surface", "earth_terrain_sand_hemisphere_grass", "earth_terrain_sand_hemisphere",
	"earth_terrain_green_sand_hemisphere", "earth_terrain_green_hemisphere"]
const BASE := "res://data/graph_functions/earth_terrain_base.tres"
const RELIEF := "res://data/graph_functions/earth_relief.tres"


func _initialize() -> void:
	for g in GRAPHS:
		var path := "res://data/graph_functions/%s.tres" % g
		var header := FileAccess.get_file_as_string(path).split("\n")[0]
		var f: VoxelGraphFunction = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if f.find_node_by_name("river_keep") > 0:
			print(g, ": ya estaba")
			continue
		var out := -1
		for id in f.get_node_ids():
			if f.get_node_type_id(id) == VoxelGraphFunction.NODE_CUSTOM_OUTPUT:
				out = id
		var src := -1
		var src_port := 0
		for c in f.get_connections():
			if c.dst_node_id == out:
				src = c.src_node_id
				src_port = c.src_port_index
		var dist := f.find_node_by_name("river_distance_m")
		var keep := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(900, 400))
		f.set_node_name(keep, "river_keep")
		f.set_node_param(keep, 0, 25.0)
		f.set_node_param(keep, 1, 40.0)
		f.add_connection(dist, 0, keep, 0)
		var mul := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(1050, 300))
		f.set_node_name(mul, "river_veg_gate")
		f.remove_connection(src, src_port, out, 0)
		f.add_connection(src, src_port, mul, 0)
		f.add_connection(keep, 0, mul, 1)
		f.add_connection(mul, 0, out, 0)
		var err := ResourceSaver.save(f, path)
		# Guardar con la API pierde el uid del recurso y renombra las referencias: se restaura la
		# cabecera y se cambia la base vieja por el relieve en la referencia externa.
		var lines := FileAccess.get_file_as_string(path).split("\n")
		lines[0] = header
		for i in lines.size():
			if lines[i].begins_with("[ext_resource") and BASE in lines[i]:
				var id_part := lines[i].substr(lines[i].find(" id="))
				lines[i] = "[ext_resource type=\"VoxelGraphFunction\" path=\"%s\"%s" % [RELIEF, id_part]
		var w := FileAccess.open(path, FileAccess.WRITE)
		w.store_string("\n".join(lines))
		w.close()
		print(g, ": ", error_string(err))
	quit()
