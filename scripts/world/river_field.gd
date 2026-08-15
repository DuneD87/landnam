class_name RiverField extends RefCounted

## Convierte la red de cauces en las dos imágenes equirect que consume el grafo del terreno.
##
## Las imágenes NO están en el espacio del WorldMap. El nodo SdfSphereHeightmap del módulo de vóxeles
## mapea la latitud con v = 0.5 - (y + y^3)/4 (una aproximación polinómica barata de asin, medida
## contra el propio nodo), mientras que bake_sphere_bumpmap y WorldMapData usan acos: leer una imagen
## de mapa tal cual con ese nodo desplaza el contenido hasta 7 grados de latitud, o sea kilómetros.
## Aquí se rasteriza directamente en la convención del nodo, así no hace falta re-muestrear después.

## Dos resoluciones a propósito: la DISTANCIA necesita precisión espacial (decide dónde está la
## orilla del cauce, y su cero interpolado es lo que dibuja el canal), mientras que la COTA del lecho
## necesita precisión de valor pero varía muy despacio a lo largo del río. Así que la distancia va
## fina y en 8 bits, y el lecho grueso y en coma flotante.
const DIST_FORMAT := Image.FORMAT_R8
const BED_FORMAT := Image.FORMAT_RF

## Cuánto más allá del alcance del tallado se escribe la cota del lecho. En el borde del área pintada
## el filtro bilineal mezcla el lecho real con el valor neutro; escribiendo de más, esa mezcla cae
## fuera de donde el tallado sigue vivo y no se nota.
const _BED_MARGIN := 1.6


const FILE_MAGIC := "GVRF"
## 2: el fichero incluye la red de tramos, de la que sale la lámina de agua.
## 3: y los parámetros de rugosidad de las paredes.
const FILE_VERSION := 3

## Escalares del campo, en el orden en que se serializan.
const _SCALARS := ["radius", "height_min", "height_span", "carve_range", "bank_slope",
	"blend_range", "wall_amplitude", "wall_period", "wall_start", "wall_full"]


## Guarda el campo horneado junto a su clave de configuración. Sin caché, cada arranque se comería
## el horneado entero (unos siete segundos en el planeta Tierra).
static func save_to(field: Dictionary, path: String, key: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[rivers] no se pudo escribir el caché en %s" % path)
		return
	f.store_string(FILE_MAGIC)
	f.store_32(FILE_VERSION)
	f.store_pascal_string(key)
	for name in ["dist", "bed"]:
		var img: Image = field[name]
		f.store_32(img.get_width())
		f.store_32(img.get_height())
		f.store_32(img.get_format())
		var data := img.get_data()
		f.store_32(data.size())
		f.store_buffer(data)
	for name in _SCALARS:
		f.store_double(float(field[name]))
	# La red también se guarda: de ella sale la lámina de agua, y volver a deducirla costaría el
	# horneado entero.
	var hydro: Vector2i = field.hydro_size
	f.store_32(hydro.x)
	f.store_32(hydro.y)
	var seg: PackedFloat32Array = field.seg
	f.store_32(seg.size())
	f.store_buffer(seg.to_byte_array())
	f.close()


## Devuelve el campo cacheado, o {} si no hay o la clave no coincide.
static func load_from(path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != FILE_MAGIC or f.get_32() != FILE_VERSION:
		return {}
	if f.get_pascal_string() != key:
		return {}
	var out := {}
	for name in ["dist", "bed"]:
		var w := f.get_32()
		var h := f.get_32()
		var fmt := f.get_32()
		var n := f.get_32()
		if w <= 0 or h <= 0 or n <= 0:
			return {}
		out[name] = Image.create_from_data(w, h, false, fmt, f.get_buffer(n))
	for name in _SCALARS:
		out[name] = f.get_double()
	out.hydro_size = Vector2i(f.get_32(), f.get_32())
	var floats := f.get_32()
	out.seg = f.get_buffer(floats * 4).to_float32_array()
	out.segments = out.seg.size() / 8
	return out


## Rasteriza la red. Devuelve { "dist": Image, "bed": Image }.
##
## Las dos van INVERTIDAS, con el 0 como valor neutro, y eso no es cosmético: el generador lee como
## 0 las regiones donde la imagen es localmente constante (medido contra el propio nodo), y "lejos de
## cualquier río" es exactamente una región constante. Poniendo el neutro en 0, ese fallo de lectura
## cae justo en "aquí no hay río" en vez de en "cauce en todas partes".
##
## dist  -> 1 - distancia_al_borde_del_cauce / range_m. Vale 1 dentro del canal y 0 lejos.
## bed   -> (techo_del_rango - cota_del_lecho) / height_span, o sea la profundidad del lecho medida
##          desde arriba. Vale 0 cuando el lecho está en el techo, que es un lecho por encima del
##          terreno y por tanto no talla nada.
static func rasterize(net: Dictionary, hydro_size: Vector2i, radius: float,
		height_min: float, height_span: float, cfg: Dictionary) -> Dictionary:
	var dist_size: Vector2i = cfg.get("dist_size", Vector2i(4096, 2048))
	var bed_size: Vector2i = cfg.get("bed_size", Vector2i(2048, 1024))
	var range_m := float(cfg.get("carve_range", 220.0))
	# El alcance de búsqueda de la distancia va ampliado por la semianchura máxima: la distancia que
	# se guarda es al BORDE del cauce, así que un río ancho todavía tiene borde cerca a 'range_m + w'
	# del eje, y truncando en 'range_m' se le comería media ribera.
	var dist_reach := range_m + float(cfg.get("max_half_width", 60.0))

	var dist_m := _paint(net, hydro_size, dist_size, radius, dist_reach, range_m, false, 0.0, 0.0)
	var bed_m := _paint(net, hydro_size, bed_size, radius, range_m * _BED_MARGIN, range_m,
		true, height_min, height_span)

	var dist_bytes := PackedByteArray()
	dist_bytes.resize(dist_size.x * dist_size.y)
	var inv := 1.0 / range_m
	for i in dist_m.size():
		dist_bytes[i] = int(clampf(1.0 - dist_m[i] * inv, 0.0, 1.0) * 255.0 + 0.5)

	return {
		"dist": Image.create_from_data(dist_size.x, dist_size.y, false, DIST_FORMAT, dist_bytes),
		"bed": Image.create_from_data(bed_size.x, bed_size.y, false, BED_FORMAT,
			bed_m.to_byte_array()),
		"seg": net.seg,
		"segments": int(net.count),
		"hydro_size": hydro_size,
	}


## Pinta un campo en la convención del nodo. Con want_bed=false devuelve metros hasta el borde del
## cauce (saturados a 'range_m'); con want_bed=true, la cota normalizada del lecho del cauce más
## cercano. Es el mismo recorrido geométrico, así que va en una función sola.
static func _paint(net: Dictionary, hydro_size: Vector2i, size: Vector2i, radius: float,
		reach_m: float, range_m: float, want_bed: bool, height_min: float,
		height_span: float) -> PackedFloat32Array:
	var w := size.x
	var h := size.y
	var out := PackedFloat32Array()
	out.resize(w * h)
	# El lecho neutro es 0 (techo del rango); la distancia se acumula en metros y se invierte al
	# final, así que aquí arranca saturada.
	out.fill(0.0 if want_bed else range_m)

	var seg: PackedFloat32Array = net.seg
	var count: int = net.count
	if count <= 0:
		return out

	# Mejor distancia vista por téxel, para que un segmento no pise el resultado de otro más cercano.
	var best := PackedFloat32Array()
	if want_bed:
		best.resize(w * h)
		best.fill(1.0e20)

	# Tablas por columna: la longitud solo depende de x, y es la misma para todas las filas.
	var cosl := PackedFloat32Array()
	var sinl := PackedFloat32Array()
	cosl.resize(w)
	sinl.resize(w)
	for x in w:
		var lon := (float(x) / w - 0.5) * TAU
		cosl[x] = cos(lon)
		sinl[x] = sin(lon)

	# Tablas por fila: la latitud del nodo NO es lineal, así que se invierte una vez y se guarda.
	var row_y := PackedFloat32Array()
	var row_st := PackedFloat32Array()
	row_y.resize(h)
	row_st.resize(h)
	for y in h:
		var yy := inv_node_v(float(y) / h)
		row_y[y] = yy
		row_st[y] = sqrt(maxf(1.0 - yy * yy, 0.0))

	var hw := hydro_size.x
	var hh := hydro_size.y
	var ang := reach_m / radius

	for k in count:
		var o := k * 8
		var a := _hydro_dir(seg[o], seg[o + 1], hw, hh)
		var b := _hydro_dir(seg[o + 2], seg[o + 3], hw, hh)
		var pa := a * radius
		var pb := b * radius
		var ab := pb - pa
		var ab2 := ab.length_squared()
		var bed0 := seg[o + 4]
		var bed1 := seg[o + 5]
		var half0 := seg[o + 6]
		var half1 := seg[o + 7]

		# Caja de búsqueda: se evalúa el mapeo de fila en los extremos de latitud alcanzables en vez
		# de derivarlo, que cerca de los polos se dispara.
		var lat_a := asin(clampf(a.y, -1.0, 1.0))
		var lat_b := asin(clampf(b.y, -1.0, 1.0))
		var lat_lo := minf(lat_a, lat_b) - ang
		var lat_hi := maxf(lat_a, lat_b) + ang
		var y_lo := clampi(int(floor(node_v(sin(minf(lat_hi, PI * 0.5))) * h)), 0, h - 1)
		var y_hi := clampi(int(ceil(node_v(sin(maxf(lat_lo, -PI * 0.5))) * h)), 0, h - 1)

		var ua := fposmod(0.5 - atan2(a.z, a.x) / TAU, 1.0)
		var ub := fposmod(0.5 - atan2(b.z, b.x) / TAU, 1.0)
		var xa := ua * w
		var xb := ub * w
		if xb - xa > w * 0.5:
			xb -= w
		elif xa - xb > w * 0.5:
			xb += w

		for y in range(y_lo, y_hi + 1):
			var st: float = row_st[y]
			# Cuántas columnas caben en el alcance a esta latitud. Cerca del polo el paralelo es
			# minúsculo y la caja se come la fila entera.
			var span_f := reach_m * w / maxf(radius * st * TAU, 1.0e-3)
			var x_lo: int
			var x_hi: int
			if span_f >= w * 0.5:
				x_lo = 0
				x_hi = w - 1
			else:
				var span := int(ceil(span_f))
				x_lo = int(floor(minf(xa, xb))) - span
				x_hi = int(ceil(maxf(xa, xb))) + span
			var yy: float = row_y[y]
			var row := y * w
			for xr in range(x_lo, x_hi + 1):
				var xi := posmod(xr, w)
				var px := st * cosl[xi] * radius
				var pz := -st * sinl[xi] * radius
				var vx := px - pa.x
				var vy := yy * radius - pa.y
				var vz := pz - pa.z
				var t := 0.0
				if ab2 > 1.0e-9:
					t = clampf((vx * ab.x + vy * ab.y + vz * ab.z) / ab2, 0.0, 1.0)
				var qx := vx - ab.x * t
				var qy := vy - ab.y * t
				var qz := vz - ab.z * t
				var d := sqrt(qx * qx + qy * qy + qz * qz)
				if d > reach_m:
					continue
				var i := row + xi
				if want_bed:
					if d >= best[i]:
						continue
					best[i] = d
					# Profundidad del lecho medida desde el TECHO del rango: 0 = arriba del todo.
					out[i] = clampf(
						(height_min + height_span - lerpf(bed0, bed1, t)) / height_span, 0.0, 1.0)
				else:
					# Distancia al BORDE del cauce, no al eje: así el fondo sale plano y del ancho
					# que toca sin que el grafo tenga que saber nada de anchuras.
					var edge := maxf(d - lerpf(half0, half1, t), 0.0)
					if edge < out[i]:
						out[i] = edge
	return out


## Dirección de una coordenada de téxel fraccionaria del mapa de hidrología (convención acos, la de
## WorldMapData).
static func _hydro_dir(px: float, py: float, w: int, h: int) -> Vector3:
	var theta := clampf(py / h, 0.0, 1.0) * PI
	var lon := (px / w - 0.5) * TAU
	var st := sin(theta)
	return Vector3(st * cos(lon), cos(theta), -st * sin(lon))


## Fila normalizada que SdfSphereHeightmap asigna a una componente Y (unitaria). Medido contra el
## nodo, no documentado: encaja hasta el sexto decimal en todo el barrido de latitudes.
static func node_v(y: float) -> float:
	return 0.5 - (y + y * y * y) * 0.25


## Inversa de node_v: raíz real de y^3 + y = c por Cardano.
static func inv_node_v(v: float) -> float:
	var c := 2.0 - 4.0 * v
	var q := sqrt(c * c * 0.25 + 1.0 / 27.0)
	var lo := c * 0.5 + q
	var hi := c * 0.5 - q
	return signf(lo) * pow(absf(lo), 1.0 / 3.0) + signf(hi) * pow(absf(hi), 1.0 / 3.0)
