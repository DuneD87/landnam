class_name TrailField extends RefCounted

## Las sendas de TrailNetwork en las imágenes que lee el grafo del terreno (nodos SdfSphereHeightmap,
## en la convención de latitud polinómica del nodo, como RiverField), y su caché en disco.
##
## Una senda mide 2-3 m y un téxel, unos 25. Guardar la distancia a la senda no sirve: el nodo
## interpola entre téxeles y redondea la uve de la distancia justo sobre la línea, hasta medio téxel
## (unos 12 m), y una senda estrecha se borra o cambia de ancho según por dónde pase. Lo que se guarda
## es el VECTOR del téxel al punto más cercano de la senda (U al este, V al norte): a un lado y al otro
## de la línea apunta en sentidos contrarios y pasa por cero sobre ella, y eso sí se interpola sin
## error. Su módulo es la distancia (milímetros en recta, unos 0,3 m en una curva de 200 m).
##
## Las dos piezas que lo hacen funcionar:
##  - La compuerta D (distancia gruesa al eje, la de siempre). Lejos de la senda U y V valen 0 (el
##    neutro del nodo: las regiones constantes las lee como 0), y al interpolar entre un vector de
##    la banda y ese neutro se cruza el cero a un lado de la senda. Con D < g0 los cuatro téxeles de
##    alrededor están dentro de la banda (rb) y el vector vale; más allá de g1 no cuenta.
##  - Las capas. En un cruce, un téxel a la misma distancia de las dos sendas solo puede apuntar a
##    una, y al interpolar entre téxeles que apuntan a sendas distintas salen huecos y manchas. Así que
##    las sendas se parten en trozos (piece_length) y los trozos cercanos (a menos de 2 · g1 + un
##    téxel, layer_reach) van a capas distintas: en cada cruce, la senda que sigue en una y la que
##    llega en otra.
##    Dos trozos seguidos de una misma senda en capas distintas se tocan por la punta y la unión no
##    se nota: el grafo se queda con lo más cercano de todas las capas.
##
## Dos juegos de imágenes: el del terreno (field_size, el fino) y el de la vegetación que se aparta
## por su grafo de densidad (tree_field_size: cuatro veces menos téxeles, ±1 m, que es lo que
## necesita un árbol, y cuatro veces menos de compilar por generador).

const FILE_MAGIC := "GVTF"
const FILE_VERSION := 3
## Holgura que se suma al radio de la compuerta y al de la banda (m).
const _MARGIN := 2.5


## Reparte [strokes] (de TrailNetwork) en capas y las rasteriza. Devuelve el campo:
## {"strokes", "radius", "layers", "unresolved" (trozos que no cupieron en ninguna capa),
##  "terrain": {"size", "rb", "dmax", "g0", "g1", "images": [{"u", "v", "d"} por capa]},
##  "trees": igual con tree_field_size}.
static func build(strokes: Array[PackedVector3Array], radius: float, cfg: Dictionary) -> Dictionary:
	var terrain_size: Vector2i = cfg.get("field_size", Vector2i(8192, 4096))
	var tree_size: Vector2i = cfg.get("tree_field_size", Vector2i(4096, 2048))
	var terrain := params(terrain_size, radius)
	var trees := params(tree_size, radius)
	var count := maxi(int(cfg.get("layers", 2)), 1)
	var pieces := _pieces(strokes, float(cfg.get("piece_length", 400.0)), radius)
	var reach := float(cfg.get("layer_reach", 2.0 * terrain.g1 + terrain.texel))
	var layered := _color(pieces, radius, reach, count)
	var layer_of: PackedInt32Array = layered.layer
	for group: Dictionary in [terrain, trees]:
		var images: Array = []
		for layer in count:
			var mine: Array = []
			for k in pieces.size():
				if layer_of[k] == layer:
					mine.append(_tipped(pieces[k], strokes, float(group.g0) / radius))
			images.append(_paint(mine, group.size, radius, group.rb, group.dmax))
		group.images = images
	return {"strokes": strokes, "radius": radius, "layers": count, "unresolved": layered.unresolved,
		"pieces": pieces.size(), "terrain": terrain, "trees": trees}


## Radios de la compuerta y la banda para una imagen de [size] en un planeta de [radius]. El téxel más
## grande del nodo es el del ecuador: 2πR/ancho de lado y 4R/alto de alto (la latitud del nodo va
## comprimida en el ecuador). La distancia gruesa se pasa como mucho medio téxel sobre la línea: la
## compuerta abre del todo hasta ahí (g0) y cierra a g1; lo que pasa la compuerta tiene sus cuatro
## téxeles a menos de g1 + un téxel, y la banda llega más lejos.
static func params(size: Vector2i, radius: float) -> Dictionary:
	var texel := Vector2(TAU * radius / size.x, 4.0 * radius / size.y).length()
	var g0 := texel * 0.5 + _MARGIN
	var g1 := g0 + maxf(5.0, texel * 0.15)
	var rb := ceilf(g1 + texel + _MARGIN * 3.0)
	return {"size": size, "texel": texel, "g0": g0, "g1": g1, "rb": rb, "dmax": rb}


## Parte los trazos en trozos de como mucho [length] m que comparten el punto del corte. Cada trozo
## lleva su trazo y los índices de sus puntos en él (i0, i1).
static func _pieces(strokes: Array[PackedVector3Array], length: float, radius: float) -> Array:
	var out: Array = []
	for s in strokes.size():
		var line := strokes[s]
		var start := 0
		var run := 0.0
		for i in range(1, line.size()):
			run += line[i].distance_to(line[i - 1]) * radius
			if run >= length or i == line.size() - 1:
				out.append({"stroke": s, "i0": start, "i1": i, "points": line.slice(start, i + 1)})
				start = i
				run = 0.0
	return out


## El trozo [piece] listo para rasterizar: {"points", "open0", "open1"}, con open en las puntas que son
## punta de su trazo. Al rasterizar, el vector de esas puntas apunta a la prolongación de la línea y no
## a la punta (que dejaría casi un téxel de senda sin leer: los téxeles de más allá apuntarían a ella)
## y la que corta la senda es la compuerta D, que empieza a cerrar a g0 más allá de la punta: por eso
## cada punta se recorta [pull] (g0, en la esfera unidad) y la senda se apaga en su sitio, con unos
## metros de más. Recortando hasta media compuerta las puntas se quedan cortas en los cruces.
static func _tipped(piece: Dictionary, strokes: Array[PackedVector3Array], pull: float) -> Dictionary:
	var open0: bool = piece.i0 == 0
	var open1: bool = piece.i1 == strokes[piece.stroke].size() - 1
	var points: PackedVector3Array = piece.points
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	# Un trozo corto no se recorta entero: le queda al menos un tercio.
	var cut := minf(pull, total / 3.0)
	if open0:
		points = _trim(points, cut)
	if open1:
		points.reverse()
		points = _trim(points, cut)
		points.reverse()
	return {"points": points, "open0": open0, "open1": open1}


## [points] sin su primer tramo de [length] (en la esfera unidad).
static func _trim(points: PackedVector3Array, length: float) -> PackedVector3Array:
	var run := 0.0
	for i in points.size() - 1:
		var step := points[i].distance_to(points[i + 1])
		if run + step >= length:
			var out := points.slice(i + 1)
			out.insert(0, points[i].lerp(points[i + 1], (length - run) / maxf(step, 1.0e-12)).normalized())
			return out
		run += step
	return points


## Asigna una capa a cada trozo de modo que dos trozos a menos de [reach] m no compartan capa (salvo
## dos seguidos de la misma senda, que se tocan por la punta y comparten sin problema). Coloreado
## voraz por saturación (DSatur): primero el trozo con más capas distintas tomadas alrededor. Un trozo
## que no cabe en ninguna se parte por la mitad (el choque suele estar en una punta) y se vuelve a
## probar con cada mitad; [pieces] crece con las mitades. Devuelve {"layer": PackedInt32Array,
## "unresolved": los que ni partidos caben}.
static func _color(pieces: Array, radius: float, reach: float, count: int) -> Dictionary:
	# Vecinos por un hash de puntos (uno de cada tres: el error de 24 m se suma al alcance).
	var cell := (reach + 24.0) / radius
	var grid := {}
	for k in pieces.size():
		var pts: PackedVector3Array = pieces[k].points
		for i in range(0, pts.size(), 3):
			var key := Vector3i((pts[i] / cell).floor())
			if not grid.has(key):
				grid[key] = []
			grid[key].append(k)
	var near: Array = []
	for k in pieces.size():
		near.append({})
	var offsets: Array[Vector3i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				offsets.append(Vector3i(dx, dy, dz))
	for key: Vector3i in grid:
		var here: Array = grid[key]
		for o in offsets:
			for j: int in grid.get(key + o, []):
				for k: int in here:
					if j != k and not near[k].has(j) and _conflict(pieces[k], pieces[j], cell):
						near[k][j] = true
						near[j][k] = true

	# Los trozos sin vecinos (casi todos) van a la capa 0.
	var layer := PackedInt32Array()
	layer.resize(pieces.size())
	layer.fill(-1)
	var pending: Array[int] = []
	for k in pieces.size():
		if near[k].is_empty():
			layer[k] = 0
		else:
			pending.append(k)
	var unresolved := 0
	while not pending.is_empty():
		var at := 0
		var at_sat := -1
		for i in pending.size():
			var sat := _taken(near[pending[i]], layer).size()
			if sat > at_sat or (sat == at_sat and near[pending[i]].size() > near[pending[at]].size()):
				at = i
				at_sat = sat
		var pick := pending[at]
		pending.remove_at(at)
		var uses := PackedInt32Array()
		uses.resize(count)
		for j: int in near[pick]:
			if layer[j] >= 0:
				uses[layer[j]] += 1
		var best := 0
		for l in count:
			if uses[l] < uses[best]:
				best = l
		if uses[best] > 0 and (pieces[pick].points as PackedVector3Array).size() >= 8:
			var half := _split(pieces, near, pick, cell)
			layer.append(-1)
			pending.append(pick)
			pending.append(half)
			continue
		if uses[best] > 0:
			unresolved += 1
		layer[pick] = best
	return {"layer": layer, "unresolved": unresolved}


## Las capas que ya tienen los vecinos [near] de un trozo.
static func _taken(near: Dictionary, layer: PackedInt32Array) -> Dictionary:
	var out := {}
	for j: int in near:
		if layer[j] >= 0:
			out[layer[j]] = true
	return out


## Parte el trozo [k] por la mitad: él se queda la primera y la segunda se añade al final de
## [pieces]. Rehace los vecinos de los dos con los que tenía. Devuelve el índice de la segunda.
static func _split(pieces: Array, near: Array, k: int, cell: float) -> int:
	var piece: Dictionary = pieces[k]
	var pts: PackedVector3Array = piece.points
	var mid := pts.size() / 2
	var second := {"stroke": piece.stroke, "i0": piece.i0 + mid, "i1": piece.i1, "points": pts.slice(mid)}
	piece.i1 = piece.i0 + mid
	piece.points = pts.slice(0, mid + 1)
	var n := pieces.size()
	pieces.append(second)
	near.append({})
	var around: Dictionary = near[k]
	near[k] = {}
	for j: int in around:
		near[j].erase(k)
		for m in [k, n]:
			if _conflict(pieces[m], pieces[j], cell):
				near[m][j] = true
				near[j][m] = true
	return n


## Si los trozos [pa] y [pb] chocan: puntos a menos del alcance (el lado de [cell] en la esfera
## unidad) y no son dos seguidos de la misma senda.
static func _conflict(pa: Dictionary, pb: Dictionary, cell: float) -> bool:
	if pa.stroke == pb.stroke and (pa.i1 == pb.i0 or pb.i1 == pa.i0):
		return false
	var la: PackedVector3Array = pa.points
	var lb: PackedVector3Array = pb.points
	var limit := cell * cell
	for i in range(0, la.size(), 3):
		for j in range(0, lb.size(), 3):
			if la[i].distance_squared_to(lb[j]) < limit:
				return true
	return false


## Rasteriza los trozos de una capa (de _tipped): {"u", "v", "d"} (Image R8 de [size]). U y V van en
## 0,5 + c / (2 · rb) dentro de la banda y a 0 fuera; D en 1 - d / dmax.
static func _paint(lines: Array, size: Vector2i, radius: float, rb: float, dmax: float) -> Dictionary:
	var w := size.x
	var h := size.y
	var reach := maxf(rb, dmax)
	var best := PackedFloat32Array()
	best.resize(w * h)
	best.fill(1.0e20)
	var bu := PackedByteArray()
	var bv := PackedByteArray()
	var bd := PackedByteArray()
	bu.resize(w * h)
	bv.resize(w * h)
	bd.resize(w * h)

	var cosl := PackedFloat32Array()
	var sinl := PackedFloat32Array()
	cosl.resize(w)
	sinl.resize(w)
	for x in w:
		var lon := (float(x) / w - 0.5) * TAU
		cosl[x] = cos(lon)
		sinl[x] = sin(lon)
	var row_y := PackedFloat32Array()
	var row_st := PackedFloat32Array()
	row_y.resize(h)
	row_st.resize(h)
	for y in h:
		var yy := RiverField.inv_node_v(float(y) / h)
		row_y[y] = yy
		row_st[y] = sqrt(maxf(1.0 - yy * yy, 0.0))

	var ang := reach / radius
	var inv_rb := 0.5 / rb
	for piece: Dictionary in lines:
		var line: PackedVector3Array = piece.points
		for k in line.size() - 1:
			var open_lo: bool = k == 0 and piece.open0
			var open_hi: bool = k == line.size() - 2 and piece.open1
			var a := line[k]
			var b := line[k + 1]
			var pa := a * radius
			var ab := b * radius - pa
			var ab2 := ab.length_squared()
			var lat_a := asin(clampf(a.y, -1.0, 1.0))
			var lat_b := asin(clampf(b.y, -1.0, 1.0))
			var y_lo := clampi(int(floor(RiverField.node_v(sin(minf(maxf(lat_a, lat_b) + ang, PI * 0.5))) * h)), 0, h - 1)
			var y_hi := clampi(int(ceil(RiverField.node_v(sin(maxf(minf(lat_a, lat_b) - ang, -PI * 0.5))) * h)), 0, h - 1)
			var xa := fposmod(0.5 - atan2(a.z, a.x) / TAU, 1.0) * w
			var xb := fposmod(0.5 - atan2(b.z, b.x) / TAU, 1.0) * w
			if xb - xa > w * 0.5:
				xb -= w
			elif xa - xb > w * 0.5:
				xb += w
			for y in range(y_lo, y_hi + 1):
				var st: float = row_st[y]
				var yy: float = row_y[y]
				var span_f := reach * w / maxf(radius * st * TAU, 1.0e-3)
				var x_lo := 0
				var x_hi := w - 1
				if span_f < w * 0.5:
					x_lo = int(floor(minf(xa, xb) - span_f))
					x_hi = int(ceil(maxf(xa, xb) + span_f))
				var row := y * w
				var py := yy * radius
				for xr in range(x_lo, x_hi + 1):
					var xi := posmod(xr, w)
					var c: float = cosl[xi]
					var s: float = sinl[xi]
					var vx := st * c * radius - pa.x
					var vy := py - pa.y
					var vz := -st * s * radius - pa.z
					var t_line := 0.0
					if ab2 > 1.0e-9:
						t_line = (vx * ab.x + vy * ab.y + vz * ab.z) / ab2
					var t := clampf(t_line, 0.0, 1.0)
					# Del téxel al punto de la senda.
					var ox := ab.x * t - vx
					var oy := ab.y * t - vy
					var oz := ab.z * t - vz
					var d := sqrt(ox * ox + oy * oy + oz * oz)
					var i := row + xi
					if d >= reach or d >= best[i]:
						continue
					best[i] = d
					if (open_lo and t_line < 0.0) or (open_hi and t_line > 1.0):
						# Más allá de una punta del trazo: a la prolongación de la línea.
						ox = ab.x * t_line - vx
						oy = ab.y * t_line - vy
						oz = ab.z * t_line - vz
					if d < rb:
						# Este (-sen, 0, -cos) y norte (-y·cos, sen θ, y·sen) del téxel.
						var u := -ox * s - oz * c
						var v := -ox * yy * c + oy * st + oz * yy * s
						bu[i] = int(clampf(u * inv_rb + 0.5, 0.0, 1.0) * 255.0 + 0.5)
						bv[i] = int(clampf(v * inv_rb + 0.5, 0.0, 1.0) * 255.0 + 0.5)
					else:
						bu[i] = 0
						bv[i] = 0
					bd[i] = int(clampf(1.0 - d / dmax, 0.0, 1.0) * 255.0 + 0.5)
	return {
		"u": Image.create_from_data(w, h, false, Image.FORMAT_R8, bu),
		"v": Image.create_from_data(w, h, false, Image.FORMAT_R8, bv),
		"d": Image.create_from_data(w, h, false, Image.FORMAT_R8, bd),
	}


## Distancia efectiva (m) a la senda más cercana en la dirección [up] desde el centro del planeta,
## leída de las imágenes del juego [group] ("terrain" o "trees") igual que la lee el grafo; INF lejos
## de todas. Con "trees" es lo que dibuja de lejos planet_biomes.gdshader (trail_far.gdshaderinc).
static func distance_at(field: Dictionary, up: Vector3, group_name := "terrain") -> float:
	if field.is_empty():
		return INF
	var group: Dictionary = field[group_name]
	var uv := Vector2(fposmod(0.5 - atan2(up.z, up.x) / TAU, 1.0), RiverField.node_v(up.normalized().y))
	var best := INF
	for layer: Dictionary in group.images:
		var d := float(group.dmax) * (1.0 - sample(layer.d, uv))
		if d >= float(group.g1):
			continue
		var u := float(group.rb) * (2.0 * sample(layer.u, uv) - 1.0)
		var v := float(group.rb) * (2.0 * sample(layer.v, uv) - 1.0)
		var gate := smoothstep(float(group.g1), float(group.g0), d)
		best = minf(best, sqrt(u * u + v * v) + (1.0 - gate) * 1000.0)
	return best


## [img] en [uv] como lo lee el nodo: bilineal, con el téxel x en u = x / ancho, dando la vuelta en
## horizontal (medido contra el propio nodo; RiverField.sample usa el centro del téxel en x + 0,5).
static func sample(img: Image, uv: Vector2) -> float:
	var x := uv.x * img.get_width()
	var y := uv.y * img.get_height()
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy
	var w := img.get_width()
	var y0 := clampi(iy, 0, img.get_height() - 1)
	var y1 := clampi(iy + 1, 0, img.get_height() - 1)
	var a := img.get_pixel(wrapi(ix, 0, w), y0).r
	var b := img.get_pixel(wrapi(ix + 1, 0, w), y0).r
	var c := img.get_pixel(wrapi(ix, 0, w), y1).r
	var d := img.get_pixel(wrapi(ix + 1, 0, w), y1).r
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## Guarda el campo con su clave de configuración. Las imágenes son casi todo ceros: con zstd, poco.
static func save_to(field: Dictionary, path: String, key: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("[trails] no se pudo escribir el caché en %s" % path)
		return
	f.store_string(FILE_MAGIC)
	f.store_32(FILE_VERSION)
	f.store_pascal_string(key)
	f.store_double(float(field.radius))
	f.store_32(int(field.layers))
	f.store_32(int(field.unresolved))
	f.store_32(int(field.pieces))
	for name in ["terrain", "trees"]:
		var group: Dictionary = field[name]
		f.store_32(group.size.x)
		f.store_32(group.size.y)
		for k in ["texel", "g0", "g1", "rb", "dmax"]:
			f.store_double(float(group[k]))
		for layer: Dictionary in group.images:
			for channel in ["u", "v", "d"]:
				var data := (layer[channel] as Image).get_data()
				f.store_32(data.size())
				f.store_buffer(data)
	var strokes: Array = field.strokes
	f.store_32(strokes.size())
	for line: PackedVector3Array in strokes:
		var floats := PackedFloat32Array()
		for p in line:
			floats.append_array([p.x, p.y, p.z])
		f.store_32(line.size())
		f.store_buffer(floats.to_byte_array())
	f.close()


## El campo cacheado, o {} si no hay o su clave no coincide.
static func load_from(path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != FILE_MAGIC or f.get_32() != FILE_VERSION:
		return {}
	if f.get_pascal_string() != key:
		return {}
	var out := {"radius": f.get_double(), "layers": f.get_32(), "unresolved": f.get_32(),
		"pieces": f.get_32()}
	for name in ["terrain", "trees"]:
		var size := Vector2i(f.get_32(), f.get_32())
		var group := {"size": size}
		for k in ["texel", "g0", "g1", "rb", "dmax"]:
			group[k] = f.get_double()
		var images: Array = []
		for layer in out.layers:
			var entry := {}
			for channel in ["u", "v", "d"]:
				var n := f.get_32()
				if n != size.x * size.y:
					return {}
				entry[channel] = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, f.get_buffer(n))
			images.append(entry)
		group.images = images
		out[name] = group
	var strokes: Array[PackedVector3Array] = []
	for s in f.get_32():
		var n := f.get_32()
		var floats := f.get_buffer(n * 12).to_float32_array()
		var line := PackedVector3Array()
		line.resize(n)
		for i in n:
			line[i] = Vector3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
		strokes.append(line)
	out.strokes = strokes
	return out
