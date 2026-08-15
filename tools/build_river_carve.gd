extends SceneTree

## Genera data/graph_functions/river_carve.tres. Se escribe con la API en vez de a mano porque el
## formato del grafo es un diccionario de ids y conexiones, y a mano se cometen errores mudos.

const OUT := "res://data/graph_functions/river_carve.tres"

const RADIUS := 30000.0
const HEIGHT_MIN := -2000.0
const HEIGHT_SPAN := 4000.0
const CARVE_RANGE := 220.0
const BANK_SLOPE := 0.12
const BLEND := 60.0
const WALL_AMPLITUDE := 18.0
const WALL_PERIOD := 540.0
const WALL_START := 25.0
const WALL_FULL := 90.0


func _initialize() -> void:
	var f := VoxelGraphFunction.new()

	var nx := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(-780, -60))
	var ny := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(-780, 20))
	var nz := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(-780, 100))

	var field_in := f.create_node(VoxelGraphFunction.NODE_CUSTOM_INPUT, Vector2(-780, 260))
	f.set_node_name(field_in, "earth_field")

	# Esfera de referencia. El 'radius' es una ENTRADA, así que Planet._apply_radius se lo pone solo
	# al cargar el planeta, igual que a los SdfSphere del resto del grafo.
	var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(-520, -60))
	f.set_node_name(sphere, "river_planet_sdf")
	f.set_node_default_input_by_name(sphere, "radius", RADIUS)

	# Distancia al borde del cauce, guardada INVERTIDA: 1 en el cauce y 0 lejos de cualquier río.
	# La inversión no es cosmética. El generador lee como 0 las regiones donde la imagen es
	# localmente constante (medido), y "lejos de todo río" es exactamente eso; con la convención
	# directa un 0 mal leído significaba "distancia cero", o sea cauce en todas partes.
	var dist := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-520, 140))
	f.set_node_name(dist, "river_dist_map")
	f.set_node_param(dist, 0, _neutral_dist())
	f.set_node_param(dist, 1, RADIUS)
	f.set_node_param(dist, 2, CARVE_RANGE)

	# Cota del lecho, medida hacia ABAJO desde el techo del rango (factor negativo) por el mismo
	# motivo: 0 = lecho en el techo = por encima del terreno = no talla nada. La salida del nodo ya
	# es el earth_field de un terreno a la altura del lecho, sin reconstruir nada.
	var bed := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(-520, 340))
	f.set_node_name(bed, "river_bed_map")
	f.set_node_param(bed, 0, _neutral_bed())
	f.set_node_param(bed, 1, RADIUS + HEIGHT_MIN + HEIGHT_SPAN)
	f.set_node_param(bed, 2, -HEIGHT_SPAN)

	# distancia = alcance - (esfera - muestra) = (muestra - esfera) + alcance
	var dm := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(-300, 40))
	var dm2 := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(-180, 40))
	f.set_node_name(dm2, "river_distance_m")
	f.set_node_default_input_by_name(dm2, "b", CARVE_RANGE)

	var slope := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(-60, 40))
	f.set_node_name(slope, "river_bank_slope")
	f.set_node_default_input_by_name(slope, "b", BANK_SLOPE)

	var vbase := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(100, 200))

	# Rugosidad de las paredes. Donde el max elige el valle, la superficie es una V analítica pura:
	# sin esto sale un cono perfecto, y el shader del terreno, que reparte texturas por pendiente,
	# pinta toda la pared del mismo lado del umbral. El ruido es 3D a propósito (una pared casi
	# vertical con ruido 2D sobre la esfera saldría rayada en vertical).
	var noise_res := FastNoise2.new()
	noise_res.noise_type = FastNoise2.TYPE_SIMPLEX
	noise_res.period = WALL_PERIOD
	noise_res.fractal_type = FastNoise2.FRACTAL_FBM
	noise_res.fractal_octaves = 4
	noise_res.fractal_gain = 0.5
	noise_res.fractal_lacunarity = 2.0
	var wall_noise := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_2_3D, Vector2(-520, 540))
	f.set_node_name(wall_noise, "river_wall_noise")
	f.set_node_param(wall_noise, 0, noise_res)

	var wall_amp := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(-260, 540))
	f.set_node_name(wall_amp, "river_wall_amplitude")
	f.set_node_default_input_by_name(wall_amp, "b", WALL_AMPLITUDE)

	# Máscara: 0 en el cauce (el lecho tiene que quedar liso para el agua) y 1 en la pared.
	var wall_mask := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(-60, 620))
	f.set_node_name(wall_mask, "river_wall_mask")
	f.set_node_param(wall_mask, 0, WALL_START)
	f.set_node_param(wall_mask, 1, WALL_FULL)

	var wall_mix := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(60, 560))

	var valley := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(260, 300))
	f.set_node_name(valley, "river_valley_field")

	var carved := f.create_node(VoxelGraphFunction.NODE_MAX, Vector2(380, 320))
	f.set_node_name(carved, "river_carved_field")

	# Peso de la mezcla: 0 en el cauce (lecho plano forzado) y 1 pasado el blend (solo excavar).
	var blend := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(160, -60))
	f.set_node_name(blend, "river_blend")
	f.set_node_param(blend, 0, 0.0)
	f.set_node_param(blend, 1, BLEND)

	var mix := f.create_node(VoxelGraphFunction.NODE_MIX, Vector2(620, 120))
	f.set_node_name(mix, "river_mix")

	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(860, 120))
	f.set_node_name(out, "river_field")

	for n in [sphere, dist, bed]:
		f.add_connection(nx, 0, n, 0)
		f.add_connection(ny, 0, n, 1)
		f.add_connection(nz, 0, n, 2)

	f.add_connection(dist, 0, dm, 0)
	f.add_connection(sphere, 0, dm, 1)
	f.add_connection(dm, 0, dm2, 0)
	f.add_connection(dm2, 0, slope, 0)
	f.add_connection(bed, 0, vbase, 0)
	f.add_connection(slope, 0, vbase, 1)
	f.add_connection(nx, 0, wall_noise, 0)
	f.add_connection(ny, 0, wall_noise, 1)
	f.add_connection(nz, 0, wall_noise, 2)
	f.add_connection(wall_noise, 0, wall_amp, 0)
	f.add_connection(dm2, 0, wall_mask, 0)
	f.add_connection(wall_amp, 0, wall_mix, 0)
	f.add_connection(wall_mask, 0, wall_mix, 1)
	f.add_connection(vbase, 0, valley, 0)
	f.add_connection(wall_mix, 0, valley, 1)
	f.add_connection(field_in, 0, carved, 0)
	f.add_connection(valley, 0, carved, 1)
	f.add_connection(dm2, 0, blend, 0)
	f.add_connection(valley, 0, mix, 0)
	f.add_connection(carved, 0, mix, 1)
	f.add_connection(blend, 0, mix, 2)
	f.add_connection(mix, 0, out, 0)

	# Sin esto la función no expone puertos con nombre y el nodo Function del grafo padre no puede
	# engancharle el earth_field. El orden fija los índices de puerto: x=0, y=1, z=2, earth_field=3.
	f.set("input_definitions", [
		["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0], ["earth_field", "CustomInput", 0],
	])
	f.set("output_definitions", [["river_field", "CustomOutput", 0]])

	var err := ResourceSaver.save(f, OUT)
	print("guardado ", OUT, " -> ", error_string(err))

	# Comprobación: se vuelve a cargar y se compila dentro de un generador de verdad.
	var loaded: VoxelGraphFunction = load(OUT)
	print("nodos: ", loaded.get_node_ids().size())
	var gen := VoxelGeneratorGraph.new()
	var main := gen.get_main_function()
	var mx := main.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var my := main.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 40))
	var mz := main.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 80))
	var fn := main.create_function_node(loaded, Vector2(200, 0))
	var mo := main.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(400, 0))
	main.add_connection(mx, 0, fn, 0)
	main.add_connection(my, 0, fn, 1)
	main.add_connection(mz, 0, fn, 2)
	main.add_connection(fn, 0, mo, 0)
	print("compila dentro de un generador: ", gen.compile())
	quit()


## Imagen neutra de distancia: 0 = "lejos de cualquier río" con la convención invertida.
func _neutral_dist() -> Image:
	var b := PackedByteArray()
	b.resize(8)
	return Image.create_from_data(4, 2, false, Image.FORMAT_R8, b)


## Imagen neutra de lecho: 0 = el techo del rango de alturas (el factor es negativo). Un lecho por
## encima del terreno no talla nada, que es lo que toca donde no hay río.
func _neutral_bed() -> Image:
	var f := PackedFloat32Array()
	f.resize(8)
	return Image.create_from_data(4, 2, false, Image.FORMAT_RF, f.to_byte_array())
