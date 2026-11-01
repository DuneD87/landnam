extends Node

## Las sendas del mundo (TrailField, TrailGenerator) en el grafo de verdad: sendas sintéticas en un
## planeta del tamaño de la Tierra del juego, con una que pasa de largo, otra que llega a ella en
## cruce, una curva de 250 m de radio y una punta suelta. Se generan bloques con trail_carve.tres sobre
## una esfera a varias alturas (el SdfSphereHeightmap deja de leer la imagen lejos de su propia
## superficie: tiene que verse igual a 0 m que a 400) y se miran los pesos de senda y de suelo libre,
## lo que lee la CPU, el cruce, la punta, la caché y el grafo que aparta los árboles. Y una red trazada
## sobre un relieve sintético con medio planeta de mar no se mete en el agua.
##   godot --headless --path . res://tests/world/test_trails.tscn

const RADIUS := 30000.0
const LAT := 20.0
const LON := 30.0
const CFG := {"layers": 2, "piece_length": 400.0, "half_width": 1.2, "edge_softness": 0.35,
	"width_variation": 0.3, "dip": 0.12}

var failures := 0
var origin: Vector3
var east: Vector3
var north: Vector3


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var lat := deg_to_rad(LAT)
	var lon := deg_to_rad(LON)
	origin = Vector3(cos(lat) * cos(lon), sin(lat), -cos(lat) * sin(lon))
	east = Vector3(-sin(lon), 0.0, -cos(lon))
	north = origin.cross(east).normalized()
	if north.y < 0.0:
		north = -north

	check(TrailGenerator.is_trail_layer(TrailGenerator.TRAIL_LAYER) and TrailGenerator.is_trail_layer(TrailGenerator.OPEN_LAYER)
		and not TrailGenerator.is_trail_layer(UndergroundDepth.LAYER) and not TrailGenerator.is_trail_layer(1),
		"las capas de las sendas no son menas")

	# La que pasa de largo (oeste-este, 1° torcida: cruza los téxeles por todas sus fases), la que llega
	# a ella por el norte, una curva y una que acaba suelta.
	var main := _line(Vector2(-900, 0), Vector2(1800, 31.4))
	var branch := _line(Vector2(100, 700), Vector2(0, _main_y(100.0) - 700.0))
	var arc := PackedVector3Array()
	for i in 120:
		var a := PI * float(i) / 119.0
		arc.append(_dir(Vector2(-200, -900) + Vector2(cos(a), sin(a)) * 250.0))
	var spur := _line(Vector2(1500, -600), Vector2(0, 900))
	var strokes: Array[PackedVector3Array] = [main, branch, arc, spur]
	var field := TrailField.build(strokes, RADIUS, CFG)
	check(int(field.unresolved) == 0, "los trozos caben en dos capas (%d sin capa)" % int(field.unresolved))

	for height in [0.0, 150.0, 400.0]:
		var gen := _generator(field, height)
		var axis := [Vector2(-600, _main_y(-600)), Vector2(400, _main_y(400)), Vector2(100, 400),
			Vector2(100, 40), Vector2(100, 28), Vector2(-200, -650),
			Vector2(-200 + 250 * cos(0.6), -900 + 250 * sin(0.6)), Vector2(1500, -200), Vector2(1500, 280)]
		var on := 0
		for p: Vector2 in axis:
			if _weights(gen, p, height).trail >= 0.6:
				on += 1
		check(on == axis.size(), "a %.0f m de altura la senda pesa en el eje: %d de %d (también junto al cruce y la punta)" % [height, on, axis.size()])
		var off := 0
		for p: Vector2 in [Vector2(-600, _main_y(-600) + 6.0), Vector2(400, _main_y(400) - 6.0),
				Vector2(106, 400), Vector2(1494, -200)]:
			var w := _weights(gen, p, height)
			if w.open >= 0.6 and w.trail < 0.1:
				off += 1
		check(off == 4, "a %.0f m de altura, a 6 m del eje es suelo libre: %d de 4" % [height, off])
		check(_weights(gen, Vector2(1500, 340), height).trail < 0.1, "a %.0f m, 40 m más allá de la punta no hay senda" % height)

	var cpu := maxf(TrailField.distance_at(field, _dir(Vector2(-600, _main_y(-600)))),
		TrailField.distance_at(field, _dir(Vector2(100, 400))))
	check(cpu < 0.6, "la CPU lee la distancia como el grafo (%.2f m sobre el eje)" % cpu)
	# El juego de los árboles es el que dibuja de lejos el shader: más grueso, pero la senda en su sitio.
	var far_on := maxf(TrailField.distance_at(field, _dir(Vector2(-600, _main_y(-600))), "trees"),
		TrailField.distance_at(field, _dir(Vector2(100, 400)), "trees"))
	var far_off := TrailField.distance_at(field, _dir(Vector2(-600, _main_y(-600) + 6.0)), "trees")
	check(far_on < 1.0 and absf(far_off - 6.0) < 1.0,
		"las imágenes de lejos ponen la senda en su sitio (%.2f m sobre el eje, %.2f a 6 m)" % [far_on, far_off])
	check(TrailField.distance_at(field, _dir(Vector2(0, 3000))) == INF, "lejos de todo la CPU lee INF")

	var path := "user://test_trails.bin"
	TrailField.save_to(field, path, "clave")
	var back := TrailField.load_from(path, "clave")
	check(not back.is_empty() and back.strokes.size() == strokes.size()
		and absf(TrailField.distance_at(back, _dir(Vector2(400, 20.0))) - TrailField.distance_at(field, _dir(Vector2(400, 20.0)))) < 0.001,
		"la caché devuelve el mismo campo")
	check(TrailField.load_from(path, "otra").is_empty(), "con otra clave la caché no vale")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var look := TrailGenerator.field_settings({"half_width": 1.6, "snow_tint": [1, 1, 1], "spur_spacing": 2000.0})
	check(look == {"spur_spacing": 2000.0}, "el ancho y el shader no entran en la clave de la caché (%s)" % look)

	_check_clearance(field)
	_check_map_lines(field, strokes)
	_check_network()
	print("TRAIL TESTS: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Una densidad de 1 con la limpieza de 3 m: 0 sobre el eje y 1 a 6 m.
func _check_clearance(field: Dictionary) -> void:
	var density := VoxelGraphFunction.new()
	density.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	density.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
	density.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
	var one := density.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2())
	density.set_node_param(one, 0, 1.0)
	var out := density.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2())
	# La salida de la definición se empareja con el nodo por su nombre.
	density.set_node_name(out, "density")
	density.add_connection(one, 0, out, 0)
	density.set("input_definitions", [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0]])
	density.set("output_definitions", [["density", "CustomOutput", 0]])
	var cleared := TrailGenerator.clear_vegetation(density, field, 3.0, CFG)
	var on := _density_at(cleared, _dir(Vector2(-300, _main_y(-300))))
	var off := _density_at(cleared, _dir(Vector2(-300, _main_y(-300) + 6.0)))
	check(on < 0.1 and off > 0.9, "la vegetación se aparta 3 m del eje (%.2f sobre él, %.2f a 6 m)" % [on, off])


## Lo que da el grafo de densidad [density] en la dirección [dir]: se suma a la SDF de una esfera por
## una milésima y se compara con la esfera sola (una sola salida de peso no se lee bien).
func _density_at(density: VoxelGraphFunction, dir: Vector3) -> float:
	var values := []
	for with_density in [true, false]:
		var gen := VoxelGeneratorGraph.new()
		var f := gen.get_main_function()
		var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
		var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
		var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
		var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2())
		f.set_node_default_input_by_name(sphere, "radius", RADIUS + 120.0)
		f.add_connection(x, 0, sphere, 0)
		f.add_connection(y, 0, sphere, 1)
		f.add_connection(z, 0, sphere, 2)
		var sdf := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
		if with_density:
			var fn := f.create_function_node(density, Vector2())
			f.add_connection(x, 0, fn, 0)
			f.add_connection(y, 0, fn, 1)
			f.add_connection(z, 0, fn, 2)
			var scaled := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2())
			f.add_connection(fn, 0, scaled, 0)
			f.set_node_default_input(scaled, 1, 0.001)
			var sum := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2())
			f.add_connection(sphere, 0, sum, 0)
			f.add_connection(scaled, 0, sum, 1)
			f.add_connection(sum, 0, sdf, 0)
		else:
			f.add_connection(sphere, 0, sdf, 0)
		gen.compile()
		var b := VoxelBuffer.new()
		b.create(1, 1, 1)
		b.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
		gen.generate_block(b, Vector3i((dir * (RADIUS + 120.0)).round()), 0)
		values.append(b.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF))
	return (values[0] - values[1]) / 0.001


## Las sendas para el mapa (TrailMap): la fina no se aleja más de su tolerancia de los trazos y la
## gruesa lleva menos puntos; un trazo que cruza el antimeridiano se parte en dos tramos del mapa.
func _check_map_lines(field: Dictionary, strokes: Array[PackedVector3Array]) -> void:
	var lines := TrailMap.lines(field)
	check(TrailMap.lines(field) == lines, "las líneas del mapa se preparan una vez")
	var worst := 0.0
	var fine := 0
	var coarse := 0
	for piece: Dictionary in lines.fine:
		fine += (piece.points as PackedVector3Array).size()
	for piece: Dictionary in lines.coarse:
		coarse += (piece.points as PackedVector3Array).size()
	for line in strokes:
		for p in line:
			var best := INF
			for piece: Dictionary in lines.fine:
				var pts: PackedVector3Array = piece.points
				for i in pts.size() - 1:
					var ab := pts[i + 1] - pts[i]
					var t := clampf((p - pts[i]).dot(ab) / maxf(ab.length_squared(), 1.0e-18), 0.0, 1.0)
					best = minf(best, p.distance_to(pts[i] + ab * t))
			worst = maxf(worst, best * RADIUS)
	check(worst <= TrailMap.FINE + 0.5, "la línea fina del mapa sigue la senda (%.1f m como mucho)" % worst)
	check(coarse < fine, "la gruesa lleva menos puntos (%d frente a %d)" % [coarse, fine])
	var seam := PackedVector3Array()
	for i in 40:
		var lon := PI + deg_to_rad(-0.2 + 0.01 * i)
		seam.append(Vector3(cos(lon), 0.1, -sin(lon)).normalized())
	var crossing: Array[PackedVector3Array] = [seam]
	var runs: Array = TrailMap.lines({"strokes": crossing, "radius": RADIUS}).fine_uv
	var jumps := 0
	for run: Dictionary in runs:
		var uvs: PackedVector2Array = run.points
		for i in uvs.size() - 1:
			if absf(uvs[i + 1].x - uvs[i].x) > 0.5:
				jumps += 1
	check(runs.size() == 2 and jumps == 0, "en el antimeridiano la senda se parte en dos tramos del mapa (%d)" % runs.size())


## Relieve sintético: medio planeta de mar al sur del ecuador y tierra suave al norte. Ningún punto
## de las sendas cae en el agua.
func _check_network() -> void:
	var w := 512
	var h := 256
	var height_min := -500.0
	var span := 1000.0
	var dem := PackedFloat32Array()
	dem.resize(w * h)
	for y in h:
		for xx in w:
			var meters := -80.0 if y > h / 2 else 20.0 + 15.0 * sin(xx * 0.05) * cos(y * 0.07)
			dem[y * w + xx] = (meters - height_min) / span
	var cfg := {"anchor_spacing": 2500.0, "anchor_max_height": 400.0, "seed": 3}
	var net := TrailNetwork.build(dem, Vector2i(w, h), RADIUS, height_min, span, -50.0, {}, cfg)
	var strokes: Array = net.strokes
	var wet := 0
	for line: PackedVector3Array in strokes:
		for p in line:
			if p.y < -0.02:
				wet += 1
	check(strokes.size() > 10, "la red tiene sendas (%d, %.0f km)" % [strokes.size(), float(net.stats.km)])
	check(wet == 0, "ninguna senda se mete en el mar (%d puntos al sur)" % wet)

	cfg.merge({"spur_spacing": 1500.0, "spur_min_distance": 600.0})
	var spurred := TrailNetwork.build(dem, Vector2i(w, h), RADIUS, height_min, span, -50.0, {}, cfg)
	check(int(spurred.stats.spurs) > 0 and int(spurred.stats.junctions) > int(net.stats.junctions),
		"los ramales añaden cruces (%d ramales, %d → %d cruces)" % [int(spurred.stats.spurs),
		int(net.stats.junctions), int(spurred.stats.junctions)])


## Altura en el plano del eje de la senda que pasa de largo en [x].
func _main_y(x: float) -> float:
	return (x + 900.0) * 31.4 / 1800.0


func _dir(p: Vector2) -> Vector3:
	return (origin * RADIUS + east * p.x + north * p.y).normalized()


func _line(from: Vector2, delta: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := int(ceil(delta.length() / 12.0))
	for i in n + 1:
		out.append(_dir(from + delta * float(i) / n))
	return out


## Generador con trail_carve.tres sobre una esfera a [height] m: los pesos de senda (14) y suelo
## libre (13) salen como en el terreno.
func _generator(field: Dictionary, height: float) -> VoxelGeneratorGraph:
	var gen := VoxelGeneratorGraph.new()
	var f := gen.get_main_function()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
	var sphere := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2())
	f.set_node_default_input_by_name(sphere, "radius", RADIUS + height)
	f.add_connection(x, 0, sphere, 0)
	f.add_connection(y, 0, sphere, 1)
	f.add_connection(z, 0, sphere, 2)
	var carve: VoxelGraphFunction = load("res://data/graph_functions/trail_carve.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	check(TrailGenerator.apply(carve, field, "terrain", CFG), "trail_carve.tres lleva los nodos de las sendas")
	var fn := f.create_function_node(carve, Vector2())
	f.add_connection(x, 0, fn, 0)
	f.add_connection(y, 0, fn, 1)
	f.add_connection(z, 0, fn, 2)
	f.add_connection(sphere, 0, fn, 3)
	var sdf := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	f.add_connection(fn, 0, sdf, 0)
	for pair in [[1, TrailGenerator.TRAIL_LAYER], [2, TrailGenerator.OPEN_LAYER]]:
		var weight := f.create_node(VoxelGraphFunction.NODE_OUTPUT_WEIGHT, Vector2())
		f.set_node_param(weight, 0, pair[1])
		f.add_connection(fn, pair[0], weight, 0)
	gen.compile()
	return gen


func _weights(gen: VoxelGeneratorGraph, p: Vector2, height: float) -> Dictionary:
	var at := _dir(p) * (RADIUS + height)
	return {"trail": _layer_weight(gen, at, TrailGenerator.TRAIL_LAYER),
		"open": _layer_weight(gen, at, TrailGenerator.OPEN_LAYER)}


## Peso de la capa [layer] en el vóxel de [at] (de 0 a 1).
func _layer_weight(gen: VoxelGeneratorGraph, at: Vector3, layer: int) -> float:
	var b := VoxelBuffer.new()
	b.create(1, 1, 1)
	gen.generate_block(b, Vector3i(at.round()), 0)
	var idx := VoxelTool.u16_indices_to_vec4i(b.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_INDICES))
	var w := VoxelTool.u16_weights_to_color(b.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_WEIGHTS))
	var ids := [idx.x, idx.y, idx.z, idx.w]
	var ws := [w.r, w.g, w.b, w.a]
	for s in 4:
		if ids[s] == layer:
			return ws[s] * 255.0 / 240.0
	return 0.0
