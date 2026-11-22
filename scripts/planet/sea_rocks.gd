class_name SeaRocks extends RefCounted

## Islotes rocosos de la costa (escollos y farallones): rocas sueltas en aguas someras, cada una con
## su tamaño, su altura y un contorno irregular.
##
## Se colocan en GDScript sobre el relieve horneado (PlanetRelief) y se pintan en dos mapas en la
## proyección de SdfSphereHeightmap, que lee el grafo (coastal_reefs.tres, tools/build_sea_rocks.gd):
##   forma (R8, tamaño del relieve, ~23 m por píxel): 0,5 justo en el contorno de cada roca, subiendo
##     hasta 1 en el centro (de ahí sale la cima abombada) y bajando hacia fuera en una rampa de un
##     píxel. Interpolado, el contorno sale a su sitio con precisión de metros aunque la roca mida
##     un par de píxeles; un ruido 3D fino lo deforma en salientes y entrantes.
##   cima (R8, mitad de tamaño): altura de la cima sobre el mar, de TOP_MIN a TOP_MIN + TOP_SPAN.
## El grafo corta la columna del contorno con una cúpula que baja de la cima hacia el borde, con
## bultos y rugosidad, y la une al terreno. Lejos de toda roca la forma vale 0 y una segunda lectura
## con un factor enorme (como la puerta de los ríos) deja que el generador se salte el ruido.

const SHAPE_NODE := "rock_shape"
const TOP_NODE := "rock_top"
const GATE_NODE := "rock_gate"
const CRAG_NODE := "rock_crag"
const OUTLINE_NODE := "rock_outline_scale"
const ROUGH_NODE := "rock_top_roughness"
const DOME_NODE := "rock_dome"
const DOME_BASE_NODE := "rock_dome_base"
const LUMP_NODE := "rock_lump"
const LUMP_AMOUNT_NODE := "rock_top_lumps"
const OUTLINE_NOISE_NODE := "rock_outline_noise"
## Prefijo de los tres Multiply que proyectan la dirección a la superficie del mar (+ eje).
const PROJ_NODE := "rock_proj_"
## Rango de la cima sobre el mar (m).
const TOP_MIN := -10.0
const TOP_SPAN := 50.0
const GATE_FACTOR := 1.0e7
## Escala con que se lee el mapa de forma (luego se divide): SdfSphereHeightmap solo consulta la
## imagen hasta 1,2 * factor del radio, y con factor 1 el mar (a decenas de metros) quedaba fuera.
const SHAPE_FACTOR := 200.0
const FILE_MAGIC := "GVSR"
const FILE_VERSION := 10

## Altura máxima que puede alcanzar una roca sobre el mar (cima + bultos + rugosidad).
static func crest_height(cfg: Dictionary) -> float:
	return float(cfg.get("top_max", 16.0)) + float(cfg.get("crag_amplitude", 1.0)) \
		+ float(cfg.get("lump_amplitude", 4.0))


static var last_stats := ""
## Rocas del último horneado (para sondas); vacío si los mapas salieron del caché.
static var last_rocks: Array = []


## Hornea (o recupera) los mapas y los enchufa al grafo. Sin relieve horneado no hay dónde mirar la
## profundidad y se queda sin rocas (mapas neutros).
static func setup(functions: Array, relief: Image, radius: float, sea_h: float, cfg: Dictionary,
		cache_name: String) -> bool:
	if _owner(functions, SHAPE_NODE) == null or relief == null:
		return false
	var path := "user://maps/%s_rocks.bin" % cache_name
	var key := _cache_key(relief, radius, sea_h, cfg)
	var maps := _load(path, key)
	if maps.is_empty():
		var t := Time.get_ticks_msec()
		maps = bake(relief, radius, sea_h, cfg)
		_save(path, key, maps)
		print("[rocks] %s en %.1f s" % [last_stats, (Time.get_ticks_msec() - t) / 1000.0])
	apply(functions, maps, radius, sea_h, cfg)
	return true


static func apply(functions: Array, maps: Dictionary, radius: float, sea_h: float,
		cfg: Dictionary) -> void:
	_set_map(functions, SHAPE_NODE, maps.shape, radius, SHAPE_FACTOR)
	_set_map(functions, GATE_NODE, maps.shape, radius, GATE_FACTOR)
	_set_map(functions, TOP_NODE, maps.top, radius + sea_h + TOP_MIN, TOP_SPAN)
	# El contorno en metros: la rampa de la forma cruza 0,5 en un píxel, y el ruido lo desplaza
	# 'outline_noise' de esa rampa.
	var px := TAU * (radius + sea_h) / float((maps.shape as Image).get_width())
	_set_b(functions, OUTLINE_NODE, "b", 2.0 * px)
	_set_b(functions, OUTLINE_NOISE_NODE, "b", float(cfg.get("outline_noise", 0.15)))
	_set_b(functions, ROUGH_NODE, "b", float(cfg.get("crag_amplitude", 1.0)))
	_set_b(functions, LUMP_AMOUNT_NODE, "b", float(cfg.get("lump_amplitude", 4.0)))
	# Fracción de la altura (cima + dome_base) que baja la cúpula del centro al contorno.
	_set_b(functions, DOME_NODE, "b", float(cfg.get("dome", 0.85)))
	_set_b(functions, DOME_BASE_NODE, "b", float(cfg.get("dome_base", 6.0)))
	for axis in 3:
		_set_b(functions, "%s%d" % [PROJ_NODE, axis], "b", radius + sea_h)
	_set_period(functions, CRAG_NODE, float(cfg.get("crag_period", 9.0)))
	_set_period(functions, LUMP_NODE, float(cfg.get("lump_period", 45.0)))


static func _set_period(functions: Array, node_name: String, period: float) -> void:
	var fn := _owner(functions, node_name)
	if fn == null:
		return
	var noise = fn.get_node_param(fn.find_node_by_name(node_name), 0)
	if noise != null:
		noise.period = period


static func _set_map(functions: Array, node_name: String, img: Image, r: float, factor: float) -> void:
	var fn := _owner(functions, node_name)
	if fn == null:
		return
	var node := fn.find_node_by_name(node_name)
	fn.set_node_param(node, 0, img)
	fn.set_node_param(node, 1, r)
	fn.set_node_param(node, 2, factor)


static func _set_b(functions: Array, node_name: String, port: String, value: float) -> void:
	var fn := _owner(functions, node_name)
	if fn != null:
		fn.set_node_default_input_by_name(fn.find_node_by_name(node_name), port, value)


## Coloca las rocas y pinta los mapas. 'relief' es el de PlanetRelief (RF, altura = 2H * v - H sobre
## el radio); el mapa de forma comparte su rejilla.
static func bake(relief: Image, radius: float, sea_h: float, cfg: Dictionary) -> Dictionary:
	var w := relief.get_width()
	var h := relief.get_height()
	var hr := PlanetRelief.H_RANGE
	var spacing := float(cfg.get("rock_spacing", 220.0))
	var density := float(cfg.get("rock_density", 0.3))
	var depth_min := float(cfg.get("depth_min", 1.5))
	var depth_max := float(cfg.get("depth_max", 28.0))
	var clearance := float(cfg.get("shore_clearance", 80.0))
	var shore_depth := float(cfg.get("shore_depth", 3.0))
	var r_min := float(cfg.get("radius_min", 9.0))
	var r_max := float(cfg.get("radius_max", 42.0))
	var top_min := float(cfg.get("top_min", -0.5))
	var top_max := float(cfg.get("top_max", 16.0))
	var seed_v := int(cfg.get("seed", 1717))

	# Manchas de costa rocosa: las rocas se agrupan en unas costas y faltan en otras.
	var cluster := FastNoiseLite.new()
	cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cluster.seed = seed_v
	cluster.frequency = 1.0 / float(cfg.get("cluster_period", 2600.0))
	cluster.fractal_octaves = 2
	var cl_lo := float(cfg.get("cluster_threshold", 0.05))
	var cl_soft := float(cfg.get("cluster_softness", 0.35))

	var sea_r := radius + sea_h
	var rocks := []
	var rows := int(ceil(PI * radius / spacing))
	var rng := RandomNumberGenerator.new()
	for row in rows:
		var lat0 := -PI * 0.5 + PI * float(row) / rows
		var lat_c := lat0 + PI * 0.5 / rows
		var cols := maxi(int(ceil(TAU * radius * cos(lat_c) / spacing)), 1)
		for col in cols:
			rng.seed = hash(Vector3i(row, col, seed_v))
			var lat := lat0 + PI / rows * rng.randf()
			var lon := TAU * (float(col) + rng.randf()) / cols
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var depth := sea_h - _relief_at(relief, dir, hr)
			if depth < depth_min or depth > depth_max:
				continue
			var c := cluster.get_noise_3dv(dir * radius)
			if rng.randf() >= density * smoothstep(cl_lo, cl_lo + cl_soft, c):
				continue
			var u := rng.randf()
			var r := lerpf(r_min, r_max, u * u)
			var size_t := (r - r_min) / maxf(r_max - r_min, 1.0)
			# Separadas de la costa: agua clara alrededor (contando sus satélites) hasta 'shore_clearance'
			# más allá; pegadas a la orilla se leían como restos de la misma costa.
			if not _offshore(relief, dir, sea_r, r * 1.3 + clearance, sea_h - shore_depth, hr):
				continue
			var top := lerpf(top_min, top_max, pow(rng.randf(), 0.9) * (0.4 + 0.6 * size_t))
			rocks.append(_rock(dir, r, top, rng))
			# Satélites: rocas más pequeñas junto a las grandes, que es como salen en la costa real.
			# Solo donde caben por debajo de la principal sin bajar de MIN_RADIUS (más pequeñas no
			# se resuelven en el mapa), y con los mismos filtros de profundidad y costa que ella.
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
			var fwd := side.cross(dir)
			for s in rng.randi_range(0, int(1 + 2 * size_t)):
				var ang := rng.randf() * TAU
				var dist := r * rng.randf_range(1.0, 1.9)
				var sr := r * rng.randf_range(0.45, 0.75)
				var stop := lerpf(minf(2.0, top), maxf(top - 1.0, 2.0), rng.randf() * 0.7)
				if sr < MIN_RADIUS:
					continue
				var sdir := (dir * sea_r + (side * cos(ang) + fwd * sin(ang)) * dist).normalized()
				var sdepth := sea_h - _relief_at(relief, sdir, hr)
				if sdepth < depth_min or sdepth > depth_max:
					continue
				if not _offshore(relief, sdir, sea_r, sr * 1.3 + clearance * 0.5, sea_h - shore_depth, hr):
					continue
				rocks.append(_rock(sdir, sr, stop, rng))

	var shape := PackedByteArray()
	shape.resize(w * h)
	var tw := maxi(w / 2, 4)
	var th := maxi(h / 2, 2)
	var top_map := PackedByteArray()
	top_map.resize(tw * th)
	var big := 0
	for rock in rocks:
		shape = _paint_shape(rock, shape, w, h, sea_r)
		top_map = _paint_top(rock, top_map, tw, th, sea_r)
		if rock.top > 4.0:
			big += 1
	last_rocks = rocks
	last_stats = "%d rocas (%d asoman más de 4 m)" % [rocks.size(), big]
	return {"shape": Image.create_from_data(w, h, false, Image.FORMAT_R8, shape),
		"top": Image.create_from_data(tw, th, false, Image.FORMAT_R8, top_map)}


## Radio mínimo (m): el mapa de forma tiene ~23 m por píxel; con la interpolación, la cúpula y el ruido
## del contorno, las rocas más pequeñas se quedaban bajo el agua o desaparecían.
const MIN_RADIUS := 28.0


static func _rock(dir: Vector3, r: float, top: float, rng: RandomNumberGenerator) -> Dictionary:
	return {"dir": dir, "r": maxf(r, MIN_RADIUS), "top": top,
		"ph": Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU),
		"lump": rng.randf_range(0.1, 0.25)}


## Recorre los téxeles de [data] (w x h) que caen a menos de 'reach' metros del centro de la roca y
## llama a f(i, d, theta). Devuelve el array (los packed se pasan por valor).
static func _for_texels(rock: Dictionary, data: PackedByteArray, w: int, h: int, sea_r: float,
		reach: float, f: Callable) -> PackedByteArray:
	var dir: Vector3 = rock.dir
	var ang := reach / sea_r
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var fwd := side.cross(dir)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var y_lo := clampi(int(floor(RiverField.node_v(sin(minf(lat + ang, PI * 0.5))) * h)) - 1, 0, h - 1)
	var y_hi := clampi(int(ceil(RiverField.node_v(sin(maxf(lat - ang, -PI * 0.5))) * h)) + 1, 0, h - 1)
	var uc := fposmod(0.5 - atan2(dir.z, dir.x) / TAU, 1.0) * w
	var span := int(ceil(ang / maxf(cos(lat), 0.02) / TAU * w)) + 2
	for y in range(y_lo, y_hi + 1):
		var yy := RiverField.inv_node_v((y + 0.5) / h)
		var st := sqrt(maxf(1.0 - yy * yy, 0.0))
		for xr in range(int(uc) - span, int(uc) + span + 1):
			var x := posmod(xr, w)
			var a := (0.5 - (x + 0.5) / w) * TAU
			var p := Vector3(st * cos(a), yy, st * sin(a))
			if p.dot(dir) <= 0.0:
				continue
			var off := (p - dir * p.dot(dir)) * sea_r
			var d := off.length()
			if d > reach:
				continue
			data = f.call(data, y * w + x, d, atan2(off.dot(fwd), off.dot(side)))
	return data


static func _paint_shape(rock: Dictionary, data: PackedByteArray, w: int, h: int,
		sea_r: float) -> PackedByteArray:
	var r: float = rock.r
	var ph: Vector3 = rock.ph
	var lump: float = rock.lump
	var px := TAU * sea_r / w
	var reach := r * (1.0 + lump) + px * 1.5
	return _for_texels(rock, data, w, h, sea_r, reach,
		func(arr: PackedByteArray, i: int, d: float, theta: float) -> PackedByteArray:
			var edge := r * (1.0 + lump * (sin(2.0 * theta + ph.x) * 0.55
				+ sin(3.0 * theta + ph.y) * 0.3 + sin(5.0 * theta + ph.z) * 0.15))
			# Fuera, rampa de un píxel (contorno preciso); dentro, hasta 1 en el centro (la cima
			# abombada del grafo sale de ahí).
			var g := 0.5 - 0.5 * (d - edge) / px if d > edge else 0.5 + 0.5 * (edge - d) / maxf(edge, px)
			g = clampf(g, 0.0, 1.0)
			arr[i] = maxi(arr[i], int(round(g * 255.0)))
			return arr)


static func _paint_top(rock: Dictionary, data: PackedByteArray, w: int, h: int,
		sea_r: float) -> PackedByteArray:
	var px := TAU * sea_r / w
	var value := int(round(clampf((float(rock.top) - TOP_MIN) / TOP_SPAN, 0.0, 1.0) * 255.0))
	return _for_texels(rock, data, w, h, sea_r, float(rock.r) * 1.3 + px * 1.5,
		func(arr: PackedByteArray, i: int, _d: float, _t: float) -> PackedByteArray:
			arr[i] = maxi(arr[i], value)
			return arr)


## True si en dos anillos (a la mitad y a 'reach' metros) el relieve queda por debajo de 'max_h' en
## las ocho direcciones: no hay tierra ni bajío cerca.
static func _offshore(relief: Image, dir: Vector3, sea_r: float, reach: float, max_h: float,
		hr: float) -> bool:
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var fwd := side.cross(dir)
	for ring: float in [0.5, 1.0]:
		for k in 8:
			var a := TAU * k / 8.0
			var p := (dir * sea_r + (side * cos(a) + fwd * sin(a)) * reach * ring).normalized()
			if _relief_at(relief, p, hr) > max_h:
				return false
	return true


## Altura del relieve (sobre el radio) en una dirección, por el téxel más cercano.
static func _relief_at(relief: Image, dir: Vector3, hr: float) -> float:
	var u := fposmod(0.5 - atan2(dir.z, dir.x) / TAU, 1.0)
	var v := RiverField.node_v(dir.y)
	var x := clampi(int(u * relief.get_width()), 0, relief.get_width() - 1)
	var y := clampi(int(v * relief.get_height()), 0, relief.get_height() - 1)
	return 2.0 * hr * relief.get_pixel(x, y).r - hr


static func _cache_key(relief: Image, radius: float, sea_h: float, cfg: Dictionary) -> String:
	var keys := cfg.keys()
	keys.sort()
	var parts := PackedStringArray(["v%d" % FILE_VERSION, "r%.3f" % radius, "s%.3f" % sea_h,
		"%dx%d" % [relief.get_width(), relief.get_height()],
		"%.4f" % relief.get_pixel(relief.get_width() / 3, relief.get_height() / 2).r])
	for k in keys:
		var v = cfg[k]
		if v is float or v is int:
			parts.append("%s=%s" % [k, str(v)])
	return "|".join(parts).sha256_text()


static func _load(path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != FILE_MAGIC or f.get_32() != FILE_VERSION:
		return {}
	if f.get_pascal_string() != key:
		return {}
	var out := {}
	for name in ["shape", "top"]:
		var w := f.get_32()
		var h := f.get_32()
		var bytes := f.get_buffer(w * h)
		if bytes.size() != w * h:
			return {}
		out[name] = Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)
	return out


static func _save(path: String, key: String, maps: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_buffer(FILE_MAGIC.to_ascii_buffer())
	f.store_32(FILE_VERSION)
	f.store_pascal_string(key)
	for name in ["shape", "top"]:
		var img: Image = maps[name]
		f.store_32(img.get_width())
		f.store_32(img.get_height())
		f.store_buffer(img.get_data())


static func _owner(functions: Array, node_name: String) -> VoxelGraphFunction:
	for fn in functions:
		if fn.find_node_by_name(node_name) > 0:
			return fn
	return null
