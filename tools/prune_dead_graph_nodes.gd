extends SceneTree

## Quita de los grafos de vegetación los nodos que no alcanzan ninguna salida. Se llega a tenerlos
## por descarte de ideas a medio conectar, y aunque el compilador del generador probablemente los
## pode solos, ensucian el grafo en el editor y hacen dudar de qué está activo y qué no.
##
## Los nodos de un VoxelGraphFunction son puros, así que quitar los que no llegan a una salida no
## puede cambiar el resultado. Antes de tocar nada se comprueba que el grafo compila.

const PATHS := [
	"res://data/graph_functions/cave_vegetation_field.tres",
	"res://data/graph_functions/earth_terrain_green_hemisphere.tres",
	"res://data/graph_functions/earth_terrain_green_sand_hemisphere.tres",
	"res://data/graph_functions/earth_terrain_sand_hemisphere.tres",
	"res://data/graph_functions/earth_terrain_sand_hemisphere_grass.tres",
]


func _initialize() -> void:
	for path in PATHS:
		_prune(path)
	quit()


func _prune(path: String) -> void:
	var g: VoxelGraphFunction = load(path)

	# Aristas al revés: para cada nodo, de quién recibe. Los puertos de entrada se sondean hasta que
	# uno falla, que es la única forma de recorrerlos sin conocer el tipo de cada nodo.
	var feeders := {}
	var outputs := []
	for nid in g.get_node_ids():
		feeders[nid] = []
		var info = g.get_node_type_info(g.get_node_type_id(nid))
		var tname: String = info.get("name", "") if info is Dictionary else ""
		if tname.begins_with("Output") or tname == "CustomOutput":
			outputs.append(nid)
	# La API no expone las conexiones nodo a nodo, así que se leen del propio recurso serializado.
	var text := FileAccess.get_file_as_string(path)
	var block := text.substr(text.find("\"connections\": ["))
	block = block.substr(0, block.find("]," + "\n"))
	for m in block.split("["):
		var parts := m.replace("]", "").split(",")
		if parts.size() < 4:
			continue
		var from := int(parts[0].strip_edges())
		var to := int(parts[2].strip_edges())
		if feeders.has(to) and from > 0:
			(feeders[to] as Array).append(from)

	# Alcanzables hacia atrás desde cualquier salida.
	var alive := {}
	var stack: Array = outputs.duplicate()
	for o in outputs:
		alive[o] = true
	while not stack.is_empty():
		var nid: int = stack.pop_back()
		for src in (feeders.get(nid, []) as Array):
			if not alive.has(src):
				alive[src] = true
				stack.append(src)

	var dead := []
	for nid in g.get_node_ids():
		if not alive.has(nid):
			dead.append(nid)
	if dead.is_empty():
		print("%-44s sin nodos muertos" % path.get_file())
		return

	var names := []
	for nid in dead:
		var info = g.get_node_type_info(g.get_node_type_id(nid))
		var nm := g.get_node_name(nid)
		names.append("%s%s" % [info.get("name", "?") if info is Dictionary else "?",
			"" if nm == "" else " '%s'" % nm])
		g.remove_node(nid)

	var err := ResourceSaver.save(g, path)
	print("%-44s -%d nodos (%s) -> %s"
		% [path.get_file(), dead.size(), ", ".join(names), error_string(err)])
