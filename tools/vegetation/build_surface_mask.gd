extends SceneTree

## Deriva earth_terrain_surface.tres del grafo de densidad verde: la misma puerta de superficie
## (fuera de cuevas y del fondo de los cauces, con las imágenes de ríos que el planeta rellena) sin
## la banda de latitud ni sus manchas. Es la base de las máscaras del clima frío: Planet la
## multiplica por la banda de frío de cada generador ("climate" en el JSON, ver ClimateGraph).
##   godot --headless --path . -s res://tools/vegetation/build_surface_mask.gd

const SOURCE := "res://data/graph_functions/earth_terrain_green_hemisphere.tres"
const TARGET := "res://data/graph_functions/earth_terrain_surface.tres"
## Nodo del grafo verde con la puerta de superficie (Smoothstep de la cueva y el cauce).
const SURFACE_GATE := 61


func _initialize() -> void:
	var source: VoxelGraphFunction = load(SOURCE)
	var g: VoxelGraphFunction = source.duplicate()
	var output := -1
	for id in g.get_node_ids():
		if g.get_node_type_id(id) == VoxelGraphFunction.NODE_CUSTOM_OUTPUT:
			output = id
	if output < 0 or not SURFACE_GATE in g.get_node_ids() \
			or g.get_node_type_id(SURFACE_GATE) != VoxelGraphFunction.NODE_SMOOTHSTEP:
		push_error("El grafo verde ya no tiene la puerta de superficie en el nodo %d" % SURFACE_GATE)
		quit(1)
		return
	for c in g.get_connections():
		if c.dst_node_id == output:
			g.remove_connection(c.src_node_id, c.src_port_index, c.dst_node_id, c.dst_port_index)
	g.add_connection(SURFACE_GATE, 0, output, 0)
	g.set_node_name(SURFACE_GATE, &"surface_gate")

	# Fuera lo que ya no llega a la salida (banda de latitud, manchas).
	var feeders := {}
	for c in g.get_connections():
		(feeders.get_or_add(c.dst_node_id, []) as Array).append(c.src_node_id)
	var alive := {output: true}
	var stack := [output]
	while not stack.is_empty():
		for src in feeders.get(stack.pop_back(), []):
			if not alive.has(src):
				alive[src] = true
				stack.append(src)
	var removed := 0
	for id in g.get_node_ids():
		if not alive.has(id):
			g.remove_node(id)
			removed += 1

	var check := VoxelGeneratorGraph.new()
	var main := check.get_main_function()
	var ix := main.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var iy := main.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
	var iz := main.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
	var f := main.create_function_node(g, Vector2())
	var out := main.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	main.add_connection(ix, 0, f, 0)
	main.add_connection(iy, 0, f, 1)
	main.add_connection(iz, 0, f, 2)
	main.add_connection(f, 0, out, 0)
	var compiled = check.compile()
	if compiled is Dictionary and not compiled.get("success", false):
		push_error("La máscara de superficie no compila: %s" % compiled)
		quit(1)
		return
	var err := ResourceSaver.save(g, TARGET)
	print("SURFACE MASK %s: -%d nodos, %d quedan (%s)" % [TARGET, removed, g.get_node_ids().size(), error_string(err)])
	quit(0 if err == OK else 1)
