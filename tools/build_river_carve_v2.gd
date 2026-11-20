extends SceneTree

## Genera data/graph_functions/river_carve_v2.tres: tallado de ríos en valle suave.
##   godot --headless --path . -s res://tools/build_river_carve_v2.gd
##
## Perfil en función de d = distancia al borde del cauce normalizada por el alcance del valle de cada
## río (RiverField.rasterize), sobre la cota del AGUA L del mapa "bed" (RiverLevels, medida sobre el
## terreno real): cauce bajo el agua, orilla, y paredes de valle que se empinan al alejarse. Excava lo
## que sobresalga del perfil y, solo junto al cauce, rellena hasta la ribera donde el terreno quede por
## debajo del agua (tope de corte en cuencas hondas). Al alcance el perfil ya va cientos de metros por
## encima del terreno: sin escalones.

const OUT := "res://data/graph_functions/river_carve_v2.tres"
const RADIUS := 30000.0
const HEIGHT_MIN := -2000.0
const HEIGHT_SPAN := 4000.0
const CARVE_RANGE := 400.0


func _initialize() -> void:
	var f := VoxelGraphFunction.new()
	var nx := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(-900, -60))
	var ny := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(-900, 20))
	var nz := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(-900, 100))
	var earth := f.create_node(VoxelGraphFunction.NODE_CUSTOM_INPUT, Vector2(-900, 300))
	f.set_node_name(earth, "earth_field")

	var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(-650, -60))
	f.set_node_name(sphere, RiverGenerator.SPHERE_NODE)
	f.set_node_default_input_by_name(sphere, "radius", RADIUS)
	var dist := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-650, 100))
	f.set_node_name(dist, RiverGenerator.DIST_NODE)
	f.set_node_param(dist, 0, Image.create(4, 2, false, Image.FORMAT_R8))
	f.set_node_param(dist, 1, RADIUS)
	f.set_node_param(dist, 2, CARVE_RANGE)
	var bed := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-650, 300))
	f.set_node_name(bed, RiverGenerator.BED_NODE)
	f.set_node_param(bed, 0, Image.create(4, 2, false, Image.FORMAT_RF))
	f.set_node_param(bed, 1, RADIUS + HEIGHT_MIN + HEIGHT_SPAN)
	f.set_node_param(bed, 2, -HEIGHT_SPAN)
	var gate := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-650, -260))
	f.set_node_name(gate, RiverGenerator.GATE_NODE)
	f.set_node_param(gate, 0, Image.create(4, 2, false, Image.FORMAT_R8))
	f.set_node_param(gate, 1, RADIUS)
	f.set_node_param(gate, 2, RiverGenerator.GATE_FACTOR)
	for n in [sphere, dist, bed, gate]:
		f.add_connection(nx, 0, n, 0)
		f.add_connection(ny, 0, n, 1)
		f.add_connection(nz, 0, n, 2)

	# d = alcance - (esfera - muestra) = (muestra - esfera) + alcance
	var dm := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-450, 60))
	f.add_connection(dist, 0, dm, 0)
	f.add_connection(sphere, 0, dm, 1)
	var d := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(-300, 60))
	f.set_node_name(d, RiverGenerator.RANGE_NODE)
	f.set_node_default_input_by_name(d, "b", CARVE_RANGE)
	f.add_connection(dm, 0, d, 0)

	# Perfil sobre la cota del agua L (mapa "bed"), en función de d:
	#   f(d) = -hondo + (hondo + ribera) * smoothstep(0, orilla, d) + x * (a + b * x),  x = max(d - orilla, 0)
	# Cauce de 'hondo' bajo el agua, orilla que sube a 'ribera' sobre ella y paredes de valle cada vez
	# más empinadas. Talla (intersección suave) lo que el terreno tenga por encima del perfil.
	var bank := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(-150, 200))
	f.set_node_name(bank, RiverGenerator.BANK_NODE)
	f.set_node_param(bank, 0, 0.0)
	f.set_node_param(bank, 1, 6.0)
	f.add_connection(d, 0, bank, 0)
	var rise := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(0, 200))
	f.set_node_name(rise, RiverGenerator.INCISION_NODE)
	f.set_node_default_input_by_name(rise, "b", 4.0)
	f.add_connection(bank, 0, rise, 0)
	var f0 := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(150, 200))
	f.set_node_name(f0, RiverGenerator.DEPTH_NODE)
	f.set_node_default_input_by_name(f0, "b", -2.5)
	f.add_connection(rise, 0, f0, 0)

	var xs := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-150, 400))
	f.set_node_name(xs, RiverGenerator.WALL_START_NODE)
	f.set_node_default_input_by_name(xs, "b", 6.0)
	f.add_connection(d, 0, xs, 0)
	var x := f.create_node(VoxelGraphFunction.NODE_MAX, Vector2(0, 400))
	f.set_node_default_input_by_name(x, "b", 0.0)
	f.add_connection(xs, 0, x, 0)
	var xb := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(150, 400))
	f.set_node_name(xb, RiverGenerator.WALL_CURVE_NODE)
	f.set_node_default_input_by_name(xb, "b", 0.0015)
	f.add_connection(x, 0, xb, 0)
	var xa := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(300, 400))
	f.set_node_name(xa, RiverGenerator.WALL_SLOPE_NODE)
	f.set_node_default_input_by_name(xa, "b", 0.12)
	f.add_connection(xb, 0, xa, 0)
	var wall := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(450, 400))
	f.add_connection(xa, 0, wall, 0)
	f.add_connection(x, 0, wall, 1)
	var prof := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(600, 300))
	f.set_node_name(prof, "river_profile")
	f.add_connection(f0, 0, prof, 0)
	f.add_connection(wall, 0, prof, 1)
	# -(sdf del perfil) = f - (|p| - R - L)
	var carve_neg := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(750, 300))
	f.add_connection(prof, 0, carve_neg, 0)
	f.add_connection(bed, 0, carve_neg, 1)

	# Ribera de relleno: donde el agua va más alta que el terreno (tope de corte), suelo hasta
	# 'ribera' sobre ella junto al cauce, cayendo con 'fill_slope' hacia fuera.
	var fs := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(150, 550))
	f.set_node_name(fs, RiverGenerator.FILL_SLOPE_NODE)
	f.set_node_default_input_by_name(fs, "b", 1.0)
	f.add_connection(x, 0, fs, 0)
	var g := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(300, 550))
	f.set_node_name(g, RiverGenerator.BANK_HEIGHT_NODE)
	f.set_node_default_input_by_name(g, "a", 1.5)
	f.add_connection(fs, 0, g, 1)
	var fill := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(450, 550))
	f.add_connection(bed, 0, fill, 0)
	f.add_connection(g, 0, fill, 1)
	var levee := f.create_node(VoxelGraphFunction.NODE_SDF_SMOOTH_UNION, Vector2(600, 550))
	f.set_node_name(levee, "river_levee")
	f.set_node_param(levee, 0, 2.0)
	f.add_connection(earth, 0, levee, 0)
	f.add_connection(fill, 0, levee, 1)
	var mix := f.create_node(VoxelGraphFunction.NODE_SDF_SMOOTH_SUBTRACT, Vector2(900, 400))
	f.set_node_name(mix, "river_carved_field")
	f.set_node_param(mix, 0, 2.0)
	f.add_connection(levee, 0, mix, 0)
	f.add_connection(carve_neg, 0, mix, 1)

	# Puerta: sin río cerca, el terreno tal cual y la poda se salta todo lo anterior.
	var sel := f.create_node(VoxelGraphFunction.NODE_SELECT, Vector2(650, 100))
	f.set_node_name(sel, "river_gate")
	f.set_node_param(sel, 0, RiverGenerator.GATE_THRESHOLD)
	f.add_connection(mix, 0, sel, 0)
	f.add_connection(earth, 0, sel, 1)
	f.add_connection(gate, 0, sel, 2)
	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(850, 100))
	f.set_node_name(out, "river_field")
	f.add_connection(sel, 0, out, 0)
	f.set("input_definitions", [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0],
		["earth_field", "CustomInput", 0]])
	f.set("output_definitions", [["river_field", "CustomOutput", 0]])
	print("guardado: ", error_string(ResourceSaver.save(f, OUT)))
	quit()
