class_name PlanetRelief extends RefCounted

## Relieve grande del terreno v2 (data/graph_functions/earth_relief.tres), horneado en mapas esféricos.
##
## La base vieja (earth_terrain_base.tres) evalúa en cada vóxel los continentes y 6 octavas de ruido
## celular 3D para las montañas: ~450 us por bloque de superficie de 16^3. Aquí se hornean los
## continentes, el perfilado de la costa y las BAKED_OCTAVES primeras octavas de montaña (lo que tiene
## periodo de cientos de metros o más) a una imagen de RELIEF_SIZE, más la máscara de montaña, y el
## grafo solo lee el mapa y suma en vivo las octavas finas donde hay montaña. Se hornea con el mismo
## grafo de la base, así que el carácter del terreno es el mismo; no es idéntico porque el ruido se
## muestrea en la esfera de radio R y no a la altura de cada punto.
##
## Horneado ~2 s, guardado en user://maps/<planeta>_relief.bin con una clave que incluye la huella del
## grafo fuente: tocar la base o estos parámetros lo vuelve a hornear.

const RELIEF_NODE := "relief_map"
const MASK_NODE := "relief_mask_map"
## Factor de la lectura de la máscara: (esfera - muestra) / F devuelve el valor del píxel con un rango
## por bloque casi exacto (la resta de la esfera solo lo ensancha tamaño_del_bloque / F).
const MASK_FACTOR := 1.0e6
## Octavas de montaña horneadas; el resto van en vivo en earth_relief.tres (relief_detail).
const BAKED_OCTAVES := 2
## Multiplicador de la montaña en la base (nodo Multiply detrás de mountains_masked).
const MOUNTAIN_AMPLITUDE := 250.0

const SOURCE := "res://data/graph_functions/earth_terrain_base.tres"
const RELIEF_SIZE := Vector2i(8192, 4096)
const MASK_SIZE := Vector2i(4096, 2048)
## Alturas horneadas en [-H_RANGE, H_RANGE] m sobre el radio (la base vieja no pasa de ~±900).
const H_RANGE := 1500.0
const FILE_VERSION := 4

## Último relieve preparado por setup(), para enchufarlo también en los grafos de vegetación.
static var last_data: Dictionary = {}


## Suma de gain^i para i en [0, n): la normalización de FastNoise2 en FBm y Ridged.
static func _gain_sum(gain: float, n: int) -> float:
	var s := 0.0
	for i in n:
		s += pow(gain, i)
	return s


## Amplitud en metros del ruido de detalle (octavas BAKED_OCTAVES.. de la montaña con su propia
## normalización) para que valga lo mismo que esas octavas dentro de la suma de todas.
static func detail_amplitude(mountains: Resource) -> float:
	var g := float(mountains.fractal_gain)
	var n := int(mountains.fractal_octaves)
	return MOUNTAIN_AMPLITUDE * pow(g, BAKED_OCTAVES) * _gain_sum(g, n - BAKED_OCTAVES) / _gain_sum(g, n)


## Hornea (o lee del caché) y enchufa los mapas en el grafo. Devuelve true si el grafo lleva relieve
## horneado y se ha parcheado (hay que recompilar).
static func setup(generator: VoxelGeneratorGraph, radius: float, cache_name: String) -> bool:
	var functions := _functions(generator)
	if _owner(functions, RELIEF_NODE) == null:
		return false
	var path := "user://maps/%s_relief.bin" % cache_name
	var key := _cache_key(radius)
	var data := _load(path, key)
	if data.is_empty():
		var t := Time.get_ticks_msec()
		data = bake(radius)
		_save(path, key, data)
		print("[relief] horneado en %.1f s" % ((Time.get_ticks_msec() - t) / 1000.0))
	apply(functions, data, radius)
	last_data = data
	return true


static func apply(functions: Array, data: Dictionary, radius: float) -> void:
	var fn := _owner(functions, RELIEF_NODE)
	var node := fn.find_node_by_name(RELIEF_NODE)
	fn.set_node_param(node, 0, data.relief)
	fn.set_node_param(node, 1, radius - H_RANGE)
	fn.set_node_param(node, 2, 2.0 * H_RANGE)
	var mfn := _owner(functions, MASK_NODE)
	if mfn != null:
		var mnode := mfn.find_node_by_name(MASK_NODE)
		mfn.set_node_param(mnode, 0, data.mask)
		mfn.set_node_param(mnode, 1, radius)
		mfn.set_node_param(mnode, 2, MASK_FACTOR)


## Hornea el relieve y la máscara con el grafo de la base vieja, envuelto como función (sus ruidos
## toman x, y, z por conexión automática a las entradas de la función).
##
## La base vieja evalúa el ruido en el punto 3D, así que su superficie está donde h = -perfil(d * (R + h)),
## no donde h = -perfil(d * R). El horneado itera esa condición (BAKE_ITERATIONS evaluaciones más) para
## que el relieve horneado caiga donde caía el viejo también en las montañas.
static func bake(radius: float) -> Dictionary:
	var relief_gen := _iterated(radius, null)
	relief_gen.compile()
	var relief := Image.create(RELIEF_SIZE.x, RELIEF_SIZE.y, false, Image.FORMAT_RF)
	relief_gen.bake_sphere_heightmap(relief, radius, -H_RANGE, H_RANGE)

	# Máscara de montaña (0-1) en el mismo punto convergido: el horneado guarda -sdf = continent_mask.
	var mf := _source_copy(radius)
	var out := mf.find_node_by_name("earth_field")
	for c in mf.get_connections():
		if c.dst_node_id == out:
			mf.remove_connection(c.src_node_id, c.src_port_index, out, c.dst_port_index)
	var neg := mf.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2.ZERO)
	mf.set_node_default_input_by_name(neg, "b", -1.0)
	mf.add_connection(mf.find_node_by_name("continent_mask"), 0, neg, 0)
	mf.add_connection(neg, 0, out, 0)
	var mask_gen := _iterated(radius, mf)
	mask_gen.compile()
	var mask := Image.create(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_R8)
	mask_gen.bake_sphere_heightmap(mask, radius, 0.0, 1.0)
	return {"relief": relief, "mask": mask}


const BAKE_ITERATIONS := 2


## Generador para hornear a radio R: evalúa el relieve reducido (BAKED_OCTAVES) en p, y luego otra vez
## en p * (R + h) / R con la altura h estimada, BAKE_ITERATIONS veces. Con e_i = salida de la evaluación
## i, la altura tras la iteración n es -(e_0 + ... + e_n). Sin 'final' la salida es esa suma (el
## horneado guarda -sdf = altura); con 'final', la salida de esa función en el punto convergido.
static func _iterated(radius: float, final: VoxelGraphFunction) -> VoxelGeneratorGraph:
	var gen := VoxelGeneratorGraph.new()
	var m := gen.get_main_function()
	var xyz := [m.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2.ZERO),
		m.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2.ZERO),
		m.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2.ZERO)]
	var total := -1
	for i in BAKE_ITERATIONS + 2:
		var last := i == BAKE_ITERATIONS + 1
		if last and final == null:
			break
		var fn := final if last else _reduced_relief(radius)
		var f := m.create_function_node(fn, Vector2.ZERO)
		for axis in 3:
			if total < 0:
				m.add_connection(xyz[axis], 0, f, axis)
			else:
				# p * (1 - suma / R)
				var k := m.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2.ZERO)
				m.set_node_default_input_by_name(k, "b", -1.0 / radius)
				m.add_connection(total, 0, k, 0)
				var k1 := m.create_node(VoxelGraphFunction.NODE_ADD, Vector2.ZERO)
				m.set_node_default_input_by_name(k1, "b", 1.0)
				m.add_connection(k, 0, k1, 0)
				var q := m.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2.ZERO)
				m.add_connection(xyz[axis], 0, q, 0)
				m.add_connection(k1, 0, q, 1)
				m.add_connection(q, 0, f, axis)
		if last:
			total = f
			break
		if total < 0:
			total = f
		else:
			var add := m.create_node(VoxelGraphFunction.NODE_ADD, Vector2.ZERO)
			m.add_connection(total, 0, add, 0)
			m.add_connection(f, 0, add, 1)
			total = add
	var o := m.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2.ZERO)
	m.add_connection(total, 0, o, 0)
	return gen


## La base con BAKED_OCTAVES octavas de montaña. La normalización de FastNoise2 depende del número de
## octavas; se compensa en el multiplicador de la montaña para que valgan lo mismo que dentro de las 6.
static func _reduced_relief(radius: float) -> VoxelGraphFunction:
	var rf := _source_copy(radius)
	var rnoise_id := rf.find_node_by_name("fast_noise_mountains")
	var rnoise: Resource = rf.get_node_param(rnoise_id, 0)
	var n := int(rnoise.fractal_octaves)
	var g := float(rnoise.fractal_gain)
	rnoise.fractal_octaves = BAKED_OCTAVES
	var amp_id := _downstream(rf, rf.find_node_by_name("mountains_masked"))
	rf.set_node_default_input_by_name(amp_id, "b",
		MOUNTAIN_AMPLITUDE * _gain_sum(g, BAKED_OCTAVES) / _gain_sum(g, n))
	return rf


## Copia de la base con el radio del planeta en sus esferas.
static func _source_copy(radius: float) -> VoxelGraphFunction:
	var f: VoxelGraphFunction = load(SOURCE).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for id in f.get_node_ids():
		if f.get_node_type_id(id) == VoxelGraphFunction.NODE_SDF_SPHERE:
			f.set_node_default_input_by_name(id, "radius", radius)
	return f


## Generador X, Y, Z -> función -> SDF.
static func _wrap(fn: VoxelGraphFunction) -> VoxelGeneratorGraph:
	var gen := VoxelGeneratorGraph.new()
	var m := gen.get_main_function()
	var x := m.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2.ZERO)
	var y := m.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2.ZERO)
	var z := m.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2.ZERO)
	var f := m.create_function_node(fn, Vector2.ZERO)
	var o := m.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2.ZERO)
	m.add_connection(x, 0, f, 0)
	m.add_connection(y, 0, f, 1)
	m.add_connection(z, 0, f, 2)
	m.add_connection(f, 0, o, 0)
	return gen


## Primer nodo que recibe la salida de 'node_id'.
static func _downstream(fn: VoxelGraphFunction, node_id: int) -> int:
	for c in fn.get_connections():
		if c.src_node_id == node_id:
			return c.dst_node_id
	return -1


static func _cache_key(radius: float) -> String:
	return "v%d|r%.3f|%s|%s|%d|%d|%.1f|%s" % [FILE_VERSION, radius, str(RELIEF_SIZE), str(MASK_SIZE),
		BAKED_OCTAVES, BAKE_ITERATIONS, H_RANGE, PlanetWorldMap._resource_fingerprint(SOURCE)]


static func _load(path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_var() != key:
		return {}
	var relief := Image.create_from_data(RELIEF_SIZE.x, RELIEF_SIZE.y, false, Image.FORMAT_RF,
		f.get_buffer(RELIEF_SIZE.x * RELIEF_SIZE.y * 4))
	var mask := Image.create_from_data(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_R8,
		f.get_buffer(MASK_SIZE.x * MASK_SIZE.y))
	return {"relief": relief, "mask": mask}


static func _save(path: String, key: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[relief] no se pudo guardar el caché en %s" % path)
		return
	f.store_var(key)
	f.store_buffer((data.relief as Image).get_data())
	f.store_buffer((data.mask as Image).get_data())


static func _functions(generator: VoxelGeneratorGraph) -> Array:
	return _functions_of(generator.get_main_function())


## La función y todas sus subfunciones.
static func _functions_of(main: VoxelGraphFunction) -> Array:
	var out: Array = [main]
	_gather(main, out)
	return out


static func _gather(fn: VoxelGraphFunction, acc: Array) -> void:
	for id in fn.get_node_ids():
		if fn.get_node_type_id(id) != VoxelGraphFunction.NODE_FUNCTION:
			continue
		var sub = fn.get_node_param(id, 0)
		if sub is VoxelGraphFunction and not acc.has(sub):
			acc.append(sub)
			_gather(sub, acc)


static func _owner(functions: Array, node_name: String) -> VoxelGraphFunction:
	for fn in functions:
		if fn.find_node_by_name(node_name) > 0:
			return fn
	return null
