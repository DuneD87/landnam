extends SceneTree

## Sustituye la compuerta de proximidad de cave_vegetation_field.tres por la buena.
##
## El problema: 'in_cave_gate' decide "esto es cueva" con un Smoothstep(-3,-12) sobre el terreno SIN
## tallar, así que toda la ribera de un río, que está decenas de metros por debajo de donde estaba el
## terreno original, se lee como cueva. El parche anterior apagaba la vegetación cerca del cauce, pero
## eso ni cubre el valle entero ni distingue una ladera de una cueva de verdad bajo el valle.
##
## Lo que se monta aquí reconstruye la superficie tallada con lo que ya hay a mano:
##   valle  = lecho - bank_slope * distancia_al_cauce + wall_amplitude
##   tallado = max(terreno_sin_tallar, valle)      (el max se queda con la superficie más baja)
## y el gate pasa a medir contra eso. En la ladera da 0 (no es cueva) y bajo la ladera sigue dando 1.
##
## El sumando de wall_amplitude no es cosmético: el tallado de verdad le mete al valle un ruido de
## esa amplitud, y sin el margen la mitad de la pared (la que el ruido hundió) queda por debajo del
## valle analítico y se vuelve a leer como cueva. Medido: sin él salían setas en toda la ribera.
## El precio es que las cuevas a menos de wall_amplitude+12 m bajo la ladera tampoco las tendrán.
##
## Es idempotente: si los nodos ya están, los reutiliza.

const PATH := "res://data/graph_functions/cave_vegetation_field.tres"


func _initialize() -> void:
	var g: VoxelGraphFunction = load(PATH)
	var base := g.find_node_by_name("earth_base")
	var gate := g.find_node_by_name("in_cave_gate")
	var dist_m := g.find_node_by_name("river_distance_m")
	var weight := g.find_node_by_name("cave_field_weight")
	var old_gate := g.find_node_by_name("river_veg_gate")
	var old_mul := g.find_node_by_name("cave_veg_river_masked")
	for pair in [["earth_base", base], ["in_cave_gate", gate], ["river_distance_m", dist_m],
			["cave_field_weight", weight]]:
		if pair[1] <= 0:
			push_error("no encuentro el nodo %s" % pair[0])
			quit(1)
			return

	var out := -1
	for nid in g.get_node_ids():
		var info = g.get_node_type_info(g.get_node_type_id(nid))
		if info is Dictionary and info.get("name", "") == "CustomOutput":
			out = nid
	var inputs := {}
	for nid in g.get_node_ids():
		var info = g.get_node_type_info(g.get_node_type_id(nid))
		if info is Dictionary:
			inputs[info.get("name", "")] = nid

	# Lecho del río. Mismo convenio que river_carve: se mide hacia ABAJO desde el techo del rango
	# (factor negativo) para que el valor neutro de la imagen, 0, quede por encima del terreno y no
	# talle nada. RiverGenerator.apply le mete la imagen y los parámetros por nombre.
	var bed := g.find_node_by_name("river_bed_map")
	if bed <= 0:
		bed = g.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(320, 300))
		g.set_node_name(bed, "river_bed_map")
		g.set_node_param(bed, 0, _neutral_bed())
		g.set_node_param(bed, 1, 30000.0)
		g.set_node_param(bed, 2, -1000.0)
		g.add_connection(inputs["InputX"], 0, bed, 0)
		g.add_connection(inputs["InputY"], 0, bed, 1)
		g.add_connection(inputs["InputZ"], 0, bed, 2)

	var slope := g.find_node_by_name("river_bank_slope")
	if slope <= 0:
		slope = g.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(640, 420))
		g.set_node_name(slope, "river_bank_slope")
		g.set_node_default_input_by_name(slope, "b", 1.0)
		g.add_connection(dist_m, 0, slope, 0)

	var valley := g.find_node_by_name("river_valley_surface")
	if valley <= 0:
		valley = g.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(860, 340))
		g.set_node_name(valley, "river_valley_surface")
		g.add_connection(bed, 0, valley, 0)
		g.add_connection(slope, 0, valley, 1)

	# Margen del ruido de pared. Lleva el nombre que ya busca RiverGenerator.apply, así que recibe el
	# wall_amplitude del JSON sin tocar nada más.
	var margin := g.find_node_by_name("river_wall_amplitude")
	if margin <= 0:
		margin = g.create_node(VoxelGraphFunction.NODE_ADD, Vector2(960, 340))
		g.set_node_name(margin, "river_wall_amplitude")
		g.set_node_default_input_by_name(margin, "b", 34.0)
		g.add_connection(valley, 0, margin, 0)

	var carved := g.find_node_by_name("river_carved_surface")
	if carved <= 0:
		carved = g.create_node(VoxelGraphFunction.NODE_MAX, Vector2(1060, 120))
		g.set_node_name(carved, "river_carved_surface")
		g.add_connection(base, 0, carved, 0)
	# El valle entra al max a través del margen, no directo.
	g.remove_connection(valley, 0, carved, 1)
	g.add_connection(margin, 0, carved, 1)

	# El gate pasa a mirar la superficie tallada en vez del terreno original.
	g.remove_connection(base, 0, gate, 0)
	g.add_connection(carved, 0, gate, 0)

	# Fuera el parche de proximidad: ya no hace falta, y era el que dejaba sin setas a las cuevas que
	# pasan por debajo de un valle.
	if old_gate > 0 and old_mul > 0 and out > 0:
		g.remove_connection(old_mul, 0, out, 0)
		g.remove_connection(weight, 0, old_mul, 0)
		g.remove_connection(old_gate, 0, old_mul, 1)
		g.remove_connection(dist_m, 0, old_gate, 0)
		g.remove_node(old_mul)
		g.remove_node(old_gate)
		g.add_connection(weight, 0, out, 0)

	var err := ResourceSaver.save(g, PATH)
	print("guardado -> ", error_string(err), "  nodos: ", g.get_node_ids().size())

	var check: VoxelGraphFunction = load(PATH)
	var gen := VoxelGeneratorGraph.new()
	var main := gen.get_main_function()
	var fn := main.create_function_node(check, Vector2(200, 0))
	var o := main.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(400, 0))
	main.add_connection(fn, 0, o, 0)
	print("compila: ", gen.compile())
	quit()


## Imagen neutra de lecho: 0 = techo del rango de alturas, o sea un lecho por encima del terreno, que
## no talla nada. Es lo que toca donde no hay río.
func _neutral_bed() -> Image:
	var f := PackedFloat32Array()
	f.resize(8)
	return Image.create_from_data(4, 2, false, Image.FORMAT_RF, f.to_byte_array())
