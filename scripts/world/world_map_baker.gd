class_name WorldMapBaker extends RefCounted

## Hornea el WorldMapData de un planeta en dos fases separadas a propósito:
##
##  1. bake_heights() pide el equirect de alturas al VoxelGeneratorGraph (bake_sphere_bumpmap, en
##     C++, el mismo que usa el impostor). Va en el hilo principal porque toca el generador vivo.
##  2. classify_water() etiqueta los cuerpos de agua conectados. Es GDScript puro sobre arrays, es
##     la parte cara, y no toca nada de la escena: se puede lanzar en un hilo.

## Fracción de la superficie del planeta a partir de la cual un cuerpo de agua deja de ser un lago.
const OCEAN_AREA_FRACTION := 0.04
const SEA_AREA_FRACTION := 0.004
const LAKE_AREA_FRACTION := 0.00004

## Cada cuánto se muestrea el mapa para el aviso de saturación (ver _report_saturation).
const SATURATION_STRIDE := 97

## Centinela de "este téxel todavía no tiene semilla" en la transformada de distancia, y el umbral
## con el que se detecta. Cualquier desplazamiento real son unas decenas de téxeles.
const _SHORE_UNSET := 1.0e9
const _SHORE_UNSET_TEST := 1.0e8
## Margen con el que se propaga más allá del alcance pedido, para que el borde de la banda no corte
## caminos que sí acabarían dentro.
const _SHORE_RANGE_MARGIN := 1.3
## Pasadas de suavizado del campo de orilla. Ver _smooth_shore_field.
const _SHORE_SMOOTH_PASSES := 2

## Semirrango vertical (m) con el que se normaliza la altura para sacar el litoral. Solo decide
## dónde deja de interpolarse el cruce: por debajo de esta cota la costa se sitúa con precisión
## sub-téxel a partir de la pendiente real; por encima, el téxel satura y el cruce cae al medio.
## Subirlo mucho mete las montañas en la ecuación y arrastra la línea de costa tierra adentro.
const _SHORE_LEVEL_BAND := 60.0
## Pasadas de caja 3x3 sobre ese campo ANTES de extraer el litoral. Es el filtro paso bajo de la
## costa: quita el serpenteo de escala téxel que no puede refractar una ola de decenas de metros.
## Cada pasada mueve la línea de costa hasta ~medio téxel (~45 m), así que con franjas estrechas
## no conviene pasar de 1. 0 = contorno crudo.
const _SHORE_COAST_SMOOTH := 1
## Radio (en téxeles) alrededor de cada segmento de litoral que se siembra con el vector exacto.
## Con 2 basta: todo téxel a menos de 2 téxeles del litoral recibe su segmento más cercano de
## verdad, y de ahí para fuera propaga el barrido.
const _SHORE_SEED_RADIUS := 2


## Devuelve un WorldMapData con las alturas ya horneadas y sin clasificar, o null si el generador
## no sabe hornear. 'height_range' es el semirrango de búsqueda del SDF alrededor del radio: la
## superficie tiene que caer dentro de [radius - height_range, radius + height_range].
##
## bake_sphere_bumpmap devuelve u = 0.5 - atan2(z, x) / TAU con la fila 0 en el polo SUR (medido
## contra el SDF real). NO es la convención que asume planet_impostor.gdshader, que está girada 90°
## y espejada. Aquí se voltea la imagen para dejar el norte arriba.
static func bake_heights(generator: Object, size: Vector2i, radius: float,
		sea_level_radius: float, has_water: bool, height_range: float) -> WorldMapData:
	if generator == null:
		push_warning("[world-map] el planeta no tiene generador; sin mapa.")
		return null

	var argc := _method_arg_count(generator, "bake_sphere_bumpmap")
	if argc < 0:
		push_warning("[world-map] %s no expone bake_sphere_bumpmap; sin mapa."
			% generator.get_class())
		return null

	var img := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	# La firma cambia entre builds: unas piden (im, ref_radius, sdf_min, sdf_max) y otras
	# (im, ref_radius, strength). Se elige por el número de argumentos declarado, igual que en
	# planet_impostor_baker.gd, en vez de asumir una y comerse un error de llamada.
	if argc >= 4:
		generator.bake_sphere_bumpmap(img, radius, -height_range, height_range)
	else:
		generator.bake_sphere_bumpmap(img, radius, height_range)

	# El bake deja la fila 0 en el polo sur. Se voltea con la operación de imagen (en C++): darle
	# la vuelta al array de dos millones de flotantes desde GDScript costaría segundos.
	img.flip_y()

	var map := WorldMapData.new()
	map.size = size
	map.radius = radius
	map.has_water = has_water
	map.sea_level_radius = sea_level_radius if has_water else radius
	map.height_min = -height_range
	map.height_span = height_range * 2.0
	# FORMAT_RF ya es un float por téxel en orden de fila: el array sale de una sola conversión,
	# sin recorrer los dos millones de píxeles desde GDScript.
	map.heights = img.get_data().to_float32_array()

	_report_saturation(map)
	return map


## Etiqueta los cuerpos de agua conectados y mide cada uno. Solo toca arrays, así que es seguro
## llamarla desde un hilo.
static func classify_water(map: WorldMapData) -> void:
	var w := map.size.x
	var h := map.size.y
	var n := w * h
	var ids := PackedInt32Array()
	ids.resize(n)
	ids.fill(-1)
	map.bodies = []
	if not map.has_water or n <= 0:
		map.body_ids = ids
		return

	# El umbral se lleva al mismo espacio normalizado que 'heights' para no convertir por téxel.
	var sea_norm := (map.sea_level_radius - map.radius - map.height_min) / map.height_span
	var heights := map.heights

	# Inundación iterativa. Cada téxel se marca al apilarlo, así entra en la pila una sola vez y
	# 'stack' nunca necesita más de n huecos.
	var stack := PackedInt32Array()
	stack.resize(n)
	var neighbors := PackedInt32Array([0, 0, 0, 0])
	var next_id := 0

	for start in n:
		if heights[start] >= sea_norm or ids[start] != -1:
			continue
		var body := next_id
		next_id += 1
		ids[start] = body
		stack[0] = start
		var sp := 1
		while sp > 0:
			sp -= 1
			var i := stack[sp]
			var y := i / w
			var x := i - y * w
			# La envoltura en longitud también cose los polos: en la fila 0 (y en la última) todos
			# los téxeles son el mismo punto geométrico, y el anillo horizontal ya los conecta.
			neighbors[0] = i - 1 if x > 0 else i + w - 1
			neighbors[1] = i + 1 if x < w - 1 else i - w + 1
			neighbors[2] = i - w if y > 0 else -1
			neighbors[3] = i + w if y < h - 1 else -1
			for k in 4:
				var c := neighbors[k]
				if c < 0 or ids[c] != -1 or heights[c] >= sea_norm:
					continue
				ids[c] = body
				stack[sp] = c
				sp += 1

	map.body_ids = ids
	map.bodies = _measure_bodies(map, ids, next_id)


## Ids de los cuerpos de agua abiertos (océanos y mares), los mayores primero. Son los únicos que
## reciben temporal y los únicos cuyo litoral siembra olas de orilla: un lago no tiene recorrido
## para levantar oleaje.
static func open_water_ids(map: WorldMapData) -> PackedInt32Array:
	var eligible: Array[Dictionary] = []
	for body in map.bodies:
		if int(body.type) <= WorldMapData.WaterType.SEA:
			eligible.append(body)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.area > b.area)
	var out := PackedInt32Array()
	for body in eligible:
		out.append(int(body.id))
	return out


## Hornea el campo de orilla: por téxel, el vector tangente (metros) que apunta al punto de litoral
## más cercano. Solo toca arrays, así que va en el mismo hilo que classify_water, que es de quien
## depende. Es la parte cara del horneado.
##
## Lo que consume esto es la FASE de las olas de orilla (phase = k * |offset|) y su DIRECCIÓN de
## viaje. La fase perdona: solo importa su gradiente. La dirección no, y es lo que obliga a que el
## litoral sea una polilínea con posición sub-téxel y no un conjunto de téxeles: sembrar con el
## téxel-semilla más cercano deja el vector con módulo de uno o dos téxeles, o sea ocho o dieciséis
## ángulos posibles en toda la franja visible, y de ahí salen las crestas tangentes a la costa o
## dadas la vuelta. Con el vector exacto al segmento el campo es continuo y casi lineal, que es
## justo lo que el filtro bilineal de la textura sabe reconstruir a 90 m/téxel.
##
## 'eligible' son los cuerpos cuyo litoral siembra (ver open_water_ids). El agua interior queda a
## cero aunque caiga dentro del alcance de una costa marina.
static func bake_shore_field(map: WorldMapData, eligible: PackedInt32Array,
		max_range: float) -> void:
	map.shore_size = Vector2i.ZERO
	map.shore_offsets = PackedFloat32Array()
	map.shore_range = max_range

	var w := map.size.x
	var h := map.size.y
	var n := w * h
	if not map.has_water or n <= 0 or map.body_ids.size() != n or eligible.is_empty():
		return

	var started := Time.get_ticks_msec()
	var ids := map.body_ids
	var elig := PackedByteArray()
	elig.resize(map.bodies.size())
	for id in eligible:
		if id >= 0 and id < elig.size():
			elig[id] = 1

	# Métrica en metros: un paso horizontal encoge con el coseno de la latitud, uno vertical no.
	# Se usa la de la fila actual como aproximación; solo decide QUÉ semilla es la más cercana, y
	# la distancia final se calcula exacta desde la semilla elegida.
	var r := map.sea_level_radius
	var my := r * PI / float(h)
	var my2 := my * my
	var mx2 := PackedFloat32Array()
	mx2.resize(h)
	var sin_t := PackedFloat32Array()
	var cos_t := PackedFloat32Array()
	sin_t.resize(h)
	cos_t.resize(h)
	for y in h:
		var theta := (y + 0.5) / float(h) * PI
		sin_t[y] = sin(theta)
		cos_t[y] = cos(theta)
		var mx := r * TAU / float(w) * sin_t[y]
		mx2[y] = mx * mx

	var sin_l := PackedFloat32Array()
	var cos_l := PackedFloat32Array()
	sin_l.resize(w)
	cos_l.resize(w)
	for x in w:
		var lon := ((x + 0.5) / float(w) - 0.5) * TAU
		sin_l[x] = sin(lon)
		cos_l[x] = cos(lon)

	# El litoral, como polilínea sub-téxel. 'level' es el campo con signo del que sale, y además
	# decide de qué lado de la costa está cada téxel más abajo: usarlo a él y no los ids evita que
	# el filtro y el contorno discrepen en el téxel de la orilla, que es donde se dibuja todo.
	var level := _build_coast_level(map, ids, elig)
	var band := _coast_band(level, w, h, _SHORE_SEED_RADIUS + _SHORE_COAST_SMOOTH)
	for _blur in _SHORE_COAST_SMOOTH:
		level = _blur_coast_level(level, band, w, h)
	var segments := _extract_coastline(level, band, w, h)
	if segments.is_empty():
		return

	# dx/dy: desplazamiento EN TÉXELES (fraccionario) desde cada téxel hasta el punto de litoral más
	# cercano conocido. Se propaga el desplazamiento y no la distancia (transformada vectorial)
	# porque al final hace falta la dirección, y derivarla de un campo escalar a esta resolución la
	# deja escalonada.
	var dx := PackedFloat32Array()
	var dy := PackedFloat32Array()
	dx.resize(n)
	dy.resize(n)
	dx.fill(_SHORE_UNSET)
	dy.fill(_SHORE_UNSET)
	_seed_from_coastline(segments, dx, dy, w, h, sin_t)

	# Se propaga bastante más allá de la franja pedida: el suavizado de después necesita vecinos con
	# dato válido, y con franjas estrechas el margen relativo no da ni para un téxel.
	var reach := maxf(max_range * _SHORE_RANGE_MARGIN, _SHORE_SMOOTH_PASSES * 2.0 * my + my)
	_shore_sweep(dx, dy, w, h, mx2, my2, reach * reach, 1)
	_shore_sweep(dx, dy, w, h, mx2, my2, reach * reach, -1)

	# De desplazamiento en téxeles a vector tangente en metros, más el peso en la cuarta componente.
	# La proyección al plano tangente escalada por el radio ya es la longitud de arco con error de
	# segundo orden (0.4 m a 2 km sobre un radio de 40 km): ni normalize ni asin en dos millones
	# de téxeles.
	#
	# El PESO va horneado y NUNCA se deduce del módulo del vector. En el borde del campo el filtrado
	# bilineal mezcla un téxel con dato y otro a cero: el módulo se desploma de max_range a 0 en 90 m,
	# la fase barre decenas de longitudes de onda y sale un muro de agua. Por eso el vector se hornea
	# hasta 'reach' (con margen) mientras el peso ya se ha apagado en max_range: donde el peso es > 0,
	# los cuatro téxeles del filtro siempre tienen dato válido.
	#
	# La posición de la semilla es FRACCIONARIA, así que su dirección se calcula con trigonometría en
	# vez de leer las tablas por fila y columna. Redondearla al téxel más cercano tiraría justo la
	# precisión que se ha ido a buscar al litoral: a un téxel de la costa, medio téxel de error son
	# 30 grados de dirección. Solo se paga en los téxeles con dato, que son la franja costera.
	var offsets := PackedFloat32Array()
	offsets.resize(n * 4)
	# La fase firmada se mantiene separada del vector desde el principio. Si se reconstruye firmando
	# el MÓDULO ya suavizado, los dos lados del litoral quedan como -d/+d con d grande y aparece un
	# salto de muchas longitudes de onda entre téxeles vecinos.
	var signed_dist := PackedFloat32Array()
	signed_dist.resize(n)
	var fade_start := max_range * 0.75
	var inv_w := 1.0 / float(w)
	var inv_h := 1.0 / float(h)
	var i2 := 0
	for y in h:
		var st: float = sin_t[y]
		var ct: float = cos_t[y]
		for x in w:
			var side := -1.0 if level[i2] >= 0.0 else 1.0
			signed_dist[i2] = side * max_range
			var ox: float = dx[i2]
			if ox < _SHORE_UNSET_TEST:
				var theta := (clampf(y + dy[i2], -0.5, h - 0.5) + 0.5) * inv_h * PI
				var lon := ((x + ox + 0.5) * inv_w - 0.5) * TAU
				var sst := sin(theta)
				var d := Vector3(st * cos_l[x], ct, -st * sin_l[x])
				var s := Vector3(sst * cos(lon), cos(theta), -sst * sin(lon))
				var proj := (s - d * d.dot(s)) * r
				# En TIERRA el vector se guarda invertido. Este campo apunta siempre al litoral más
				# cercano, así que al cruzar la orilla su dirección gira 180 grados (es el gradiente
				# de |x| en el cero). El filtro bilineal del agua mezcla entonces las dos caras del
				# pliegue justo en la franja de uno o dos téxeles donde se dibuja la rompiente, y la
				# dirección que sale de ahí es la media de dos vectores opuestos. Invertido, la
				# dirección es continua a través de la costa y solo el módulo pasa por cero.
				#
				# El lado lo manda 'level', el mismo campo del que salió el contorno, y no el id del
				# téxel: el suavizado del litoral mueve la costa una fracción de téxel, y con los ids
				# habría téxeles de agua al otro lado de la línea invertidos al revés.
				if level[i2] >= 0.0:
					proj = -proj
				var o := i2 * 4
				offsets[o] = proj.x
				offsets[o + 1] = proj.y
				offsets[o + 2] = proj.z
				# El agua interior se apaga con el peso, conservando el vector: anularlo metería en
				# la orilla del lago el mismo salto de fase que en el borde del campo.
				var id := ids[i2]
				if id < 0 or elig[id] == 1:
					# Forma creciente para no depender del smoothstep con bordes invertidos. El campo
					# se hornea ancho y shore_reach decide después la franja visible en el shader.
					offsets[o + 3] = 1.0 - smoothstep(fade_start, max_range, proj.length())
					signed_dist[i2] = side * proj.length()
			i2 += 1

	for _pass in _SHORE_SMOOTH_PASSES:
		offsets = _smooth_shore_field(offsets, dx, w, h)
		signed_dist = _smooth_signed_shore_distance(signed_dist, offsets, w, h)
	# El cálculo interno usa vector = dirección * distancia porque así puede suavizar ambos por
	# separado. La textura final los desacopla: xyz unitario y w distancia FIRMADA. Al interpolar dos
	# riberas opuestas solo se cancela xyz; y al cruzar la costa W pasa por cero sin invertir el sentido
	# de avance de la ola aunque la costa del mapa y la geometría visible difieran unos metros.
	offsets = _encode_shore_field(offsets, signed_dist)
	map.shore_size = map.size
	map.shore_offsets = offsets
	print("[world-map] campo de orilla: %d segmentos de litoral, %.1f s"
		% [segments.size() / 4, (Time.get_ticks_msec() - started) / 1000.0])


## Campo con signo del que se extrae el litoral: altura sobre el nivel del mar en metros, acotada a
## +/-_SHORE_LEVEL_BAND. Todo lo que no sea agua abierta (tierra y agua interior) se fuerza positivo,
## así el contorno cero es exactamente la costa de mares y océanos y la de un lago no existe.
static func _build_coast_level(map: WorldMapData, ids: PackedInt32Array,
		elig: PackedByteArray) -> PackedFloat32Array:
	var n := map.heights.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var base := map.radius + map.height_min - map.sea_level_radius
	var span := map.height_span
	var inv := 1.0 / _SHORE_LEVEL_BAND
	var heights := map.heights
	for i in n:
		var v := clampf((base + heights[i] * span) * inv, -1.0, 1.0)
		var id := ids[i]
		if id < 0 or elig[id] == 0:
			v = maxf(v, 0.001)
		out[i] = v
	return out


## Índices de los téxeles a 'radius' o menos de un cambio de signo de 'level'. Es la única pasada
## que recorre el mapa entero: todo lo demás (suavizado del litoral, contorno, siembra) trabaja
## sobre esta lista, que a 2048x1024 son un par de cientos de miles de téxeles y no dos millones.
static func _coast_band(level: PackedFloat32Array, w: int, h: int,
		radius: int) -> PackedInt32Array:
	var n := w * h
	var mark := PackedByteArray()
	mark.resize(n)
	var out := PackedInt32Array()
	for i in n:
		var y := i / w
		var x := i - y * w
		var neg := level[i] < 0.0
		var east := y * w + (x + 1 if x < w - 1 else 0)
		var south := i + w
		if neg == (level[east] < 0.0) and (south >= n or neg == (level[south] < 0.0)):
			continue
		for ky in range(-radius, radius + 1):
			var sy := y + ky
			if sy < 0 or sy >= h:
				continue
			var row := sy * w
			for kx in range(-radius, radius + 1):
				var j := row + wrapi(x + kx, 0, w)
				if mark[j] == 0:
					mark[j] = 1
					out.append(j)
	return out


## Caja 3x3 sobre el campo con signo, solo dentro de la banda. Es el filtro paso bajo de la costa:
## una ola de decenas de metros no refracta contra los recovecos de un téxel, y ese serpenteo es lo
## que hacía girar la dirección de la cresta de un téxel al siguiente.
static func _blur_coast_level(level: PackedFloat32Array, band: PackedInt32Array,
		w: int, h: int) -> PackedFloat32Array:
	var out := level.duplicate()
	for i in band:
		var y := i / w
		var x := i - y * w
		var acc := 0.0
		var count := 0
		for ky in range(-1, 2):
			var sy := y + ky
			if sy < 0 or sy >= h:
				continue
			var row := sy * w
			for kx in range(-1, 2):
				acc += level[row + wrapi(x + kx, 0, w)]
				count += 1
		out[i] = acc / count
	return out


## Segmentos que unen los cruces de cada celda, indexados por el caso de marching squares
## (bit 0 = esquina superior izquierda negativa, y luego en el sentido de las agujas del reloj).
## Los índices son aristas: 0 = arriba, 1 = derecha, 2 = abajo, 3 = izquierda. Las dos diagonales
## ambiguas (5 y 10) se resuelven separando las esquinas de agua, o sea dejando la tierra unida por
## la diagonal: así un istmo de un téxel sigue siendo istmo en vez de partirse en dos islas.
const _MS_EDGES := [
	[], [3, 0], [0, 1], [3, 1],
	[1, 2], [3, 0, 1, 2], [0, 2], [3, 2],
	[2, 3], [0, 2], [0, 1, 2, 3], [1, 2],
	[3, 1], [0, 1], [0, 3], [],
]


## El litoral como sopa de segmentos en coordenadas de téxel fraccionarias [x0,y0,x1,y1]*. Marching
## squares sobre el campo con signo: el cruce se interpola con la pendiente real del terreno, así que
## la línea de costa queda situada por debajo del téxel y no pegada a la rejilla.
static func _extract_coastline(level: PackedFloat32Array, band: PackedInt32Array,
		w: int, h: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in band:
		var y := i / w
		if y >= h - 1:
			continue
		var x := i - y * w
		var xe := x + 1 if x < w - 1 else 0
		var r0 := y * w
		var r1 := r0 + w
		var a: float = level[r0 + x]
		var b: float = level[r0 + xe]
		var c: float = level[r1 + xe]
		var d: float = level[r1 + x]
		var code := ((1 if a < 0.0 else 0) | (2 if b < 0.0 else 0)
			| (4 if c < 0.0 else 0) | (8 if d < 0.0 else 0))
		var edges: Array = _MS_EDGES[code]
		if edges.is_empty():
			continue
		var px := PackedFloat32Array([x + _cross(a, b), x + 1.0, x + _cross(d, c), float(x)])
		var py := PackedFloat32Array([float(y), y + _cross(b, c), y + 1.0, y + _cross(a, d)])
		for j in range(0, edges.size(), 2):
			var e0: int = edges[j]
			var e1: int = edges[j + 1]
			out.append(px[e0])
			out.append(py[e0])
			out.append(px[e1])
			out.append(py[e1])
	return out


## Posición del cruce por cero entre dos esquinas, en [0,1]. Con las dos saturadas al mismo valor
## cae en el medio, que es lo que se puede decir de un acantilado a esta resolución.
static func _cross(a: float, b: float) -> float:
	var den := a - b
	if absf(den) < 1e-6:
		return 0.5
	return clampf(a / den, 0.0, 1.0)


## Siembra dx/dy con el vector EXACTO al segmento de litoral más cercano, para los téxeles a menos
## de _SHORE_SEED_RADIUS de él. Del resto se encarga el barrido, que propaga estos desplazamientos
## fraccionarios igual que propagaba los enteros.
##
## El punto más cercano se busca en un espacio donde la x va escalada por el seno de la colatitud:
## en téxeles la métrica es anisótropa y en latitudes altas elegiría un punto que no es el próximo.
static func _seed_from_coastline(segments: PackedFloat32Array, dx: PackedFloat32Array,
		dy: PackedFloat32Array, w: int, h: int, sin_t: PackedFloat32Array) -> void:
	var rad := _SHORE_SEED_RADIUS
	var count := segments.size() / 4
	for k in count:
		var o := k * 4
		var ax0: float = segments[o]
		var ay0: float = segments[o + 1]
		var bx0: float = segments[o + 2]
		var by0: float = segments[o + 3]
		var x_lo := floori(minf(ax0, bx0)) - rad
		var x_hi := floori(maxf(ax0, bx0)) + rad
		var y_lo := maxi(floori(minf(ay0, by0)) - rad, 0)
		var y_hi := mini(floori(maxf(ay0, by0)) + rad, h - 1)
		for yy in range(y_lo, y_hi + 1):
			var st: float = maxf(sin_t[yy], 0.001)
			var row := yy * w
			var ex := (bx0 - ax0) * st
			var ey := by0 - ay0
			var den := ex * ex + ey * ey
			var ay := ay0 - yy
			for xr in range(x_lo, x_hi + 1):
				var ax := (ax0 - xr) * st
				var t := 0.0 if den < 1e-12 else clampf(-(ax * ex + ay * ey) / den, 0.0, 1.0)
				var qx := ax + t * ex
				var qy := ay + t * ey
				var d2 := qx * qx + qy * qy
				var i := row + wrapi(xr, 0, w)
				var cur: float = dx[i]
				if cur < _SHORE_UNSET_TEST:
					var cs := cur * st
					if cs * cs + dy[i] * dy[i] <= d2:
						continue
				dx[i] = qx / st
				dy[i] = qy


## Suaviza el campo de orilla: una pasada de caja 3x3 sobre el MÓDULO (que es la fase de la ola) y
## sobre la dirección por separado.
##
## Hace falta porque la transformada de distancia no es exacta: compara candidatos con la escala
## horizontal de la fila actual, que cambia con la latitud, así que entre filas la comparación es
## inconsistente y a veces gana una semilla que no es la más próxima. Ahí 'dist' pega un brinco de
## decenas de metros, la fase salta ~pi, y el lugar geométrico de esos empates es una curva larga y
## serpenteante: en pantalla, bandas de espuma en bucle cruzando las crestas buenas.
##
## Suavizar el módulo vale porque de este campo solo importa el GRADIENTE, no su valor absoluto, y
## una caja sobre una función lineal la deja igual: solo se redondean los pliegues y los saltos.
##
## Módulo y dirección se promedian por separado a propósito. Promediando el vector entero, dos
## vecinos que miran distinto se cancelan, el módulo se hunde y la fase de ahí sale inventada; así
## el módulo conserva |grad| ~ 1 y la longitud de onda no se estira.
##
## La coherencia solo decide cuánto fiarse del promedio de DIRECCIÓN. No puede modificar W: hacerlo
## apagaba la amplitud por bloques y reintroducía el corte rectangular original. La calidad queda
## codificada después, gratuitamente, en el módulo de la dirección unitaria interpolada.
static func _smooth_shore_field(offsets: PackedFloat32Array, dx: PackedFloat32Array,
		w: int, h: int) -> PackedFloat32Array:
	var out := offsets.duplicate()
	var n := w * h
	for i in n:
		var o := i * 4
		if offsets[o + 3] <= 0.0 or dx[i] >= _SHORE_UNSET_TEST:
			continue
		var y := i / w
		var x := i - y * w

		var sum := Vector3.ZERO
		var sum_len := 0.0
		var count := 0
		for ky in range(-1, 2):
			var sy := y + ky
			if sy < 0 or sy >= h:
				continue
			var row := sy * w
			for kx in range(-1, 2):
				var j := row + wrapi(x + kx, 0, w)
				if dx[j] >= _SHORE_UNSET_TEST:
					continue
				var k := j * 4
				var v := Vector3(offsets[k], offsets[k + 1], offsets[k + 2])
				sum += v
				sum_len += v.length()
				count += 1

		if count == 0 or sum_len <= 0.0:
			continue
		var mean_len := sum_len / count
		var vec_len := sum.length()
		# Coherencia en [0,1]: módulo del vector medio contra la media de módulos, así que el count
		# se cancela. 1 = todos los vecinos miran igual.
		var coherence := vec_len / maxf(sum_len, 1e-4)
		var original := Vector3(offsets[o], offsets[o + 1], offsets[o + 2])
		var original_dir := original.normalized() if original.length_squared() > 1e-8 else Vector3.ZERO
		var smooth_dir := sum / vec_len if vec_len > 1e-4 else original_dir
		var blend := smoothstep(0.35, 0.8, coherence)
		var dir := original_dir.slerp(smooth_dir, blend).normalized()
		out[o] = dir.x * mean_len
		out[o + 1] = dir.y * mean_len
		out[o + 2] = dir.z * mean_len
		out[o + 3] = offsets[o + 3]
	return out


## Caja 3x3 sobre la fase FIRMADA. Una rampa lineal que cruza cero queda lineal; a diferencia de
## suavizar abs(distancia) y firmarla después, nunca fabrica un salto -d/+d junto al litoral.
static func _smooth_signed_shore_distance(values: PackedFloat32Array,
		coverage: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var out := values.duplicate()
	for i in w * h:
		if coverage[i * 4 + 3] <= 0.0:
			continue
		var y := i / w
		var x := i - y * w
		var sum := 0.0
		var count := 0
		for ky in range(-1, 2):
			var sy := y + ky
			if sy < 0 or sy >= h:
				continue
			var row := sy * w
			for kx in range(-1, 2):
				var j := row + wrapi(x + kx, 0, w)
				if coverage[j * 4 + 3] <= 0.0:
					continue
				sum += values[j]
				count += 1
		if count > 0:
			out[i] = sum / count
	return out


## Formato de consumo: xyz = dirección unitaria hacia tierra, w = la fase firmada ya suavizada.
static func _encode_shore_field(offsets: PackedFloat32Array,
		signed_dist: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(offsets.size())
	for i in offsets.size() / 4:
		var o := i * 4
		out[o + 3] = signed_dist[i]
		if offsets[o + 3] <= 0.0001:
			continue
		var v := Vector3(offsets[o], offsets[o + 1], offsets[o + 2])
		var dist := v.length()
		if dist <= 0.0001:
			continue
		var dir := v / dist
		out[o] = dir.x
		out[o + 1] = dir.y
		out[o + 2] = dir.z
	return out


## Un barrido raster de la transformada vectorial (8SSEDT): propaga la semilla más cercana desde la
## fila anterior y desde los vecinos de la propia fila. step = +1 recorre de norte a sur, -1 al revés.
## La x envuelve, y con ella el desplazamiento: dx es relativo, así que basta envolver el índice.
static func _shore_sweep(dx: PackedFloat32Array, dy: PackedFloat32Array, w: int, h: int,
		mx2: PackedFloat32Array, my2: float, range2: float, step: int) -> void:
	var y := 0 if step > 0 else h - 1
	while y >= 0 and y < h:
		var kx: float = mx2[y]
		var base := y * w
		var prev_row := y - step
		var has_prev := prev_row >= 0 and prev_row < h
		var prev := prev_row * w
		var sy := float(step)

		for x in w:
			var i := base + x
			var cx: float = dx[i]
			var best: float = INF if cx >= _SHORE_UNSET_TEST else cx * cx * kx + dy[i] * dy[i] * my2
			var xw := x - 1 if x > 0 else w - 1
			var xe := x + 1 if x < w - 1 else 0

			if has_prev:
				var j := prev + xw
				var jx: float = dx[j]
				if jx < _SHORE_UNSET_TEST:
					var nx := jx - 1.0
					var ny: float = dy[j] - sy
					var nd := nx * nx * kx + ny * ny * my2
					if nd < best and nd <= range2:
						best = nd
						dx[i] = nx
						dy[i] = ny

				j = prev + x
				jx = dx[j]
				if jx < _SHORE_UNSET_TEST:
					var ny: float = dy[j] - sy
					var nd := jx * jx * kx + ny * ny * my2
					if nd < best and nd <= range2:
						best = nd
						dx[i] = jx
						dy[i] = ny

				j = prev + xe
				jx = dx[j]
				if jx < _SHORE_UNSET_TEST:
					var nx := jx + 1.0
					var ny: float = dy[j] - sy
					var nd := nx * nx * kx + ny * ny * my2
					if nd < best and nd <= range2:
						best = nd
						dx[i] = nx
						dy[i] = ny

			var jw := base + xw
			var wx: float = dx[jw]
			if wx < _SHORE_UNSET_TEST:
				var nx := wx - 1.0
				var ny: float = dy[jw]
				var nd := nx * nx * kx + ny * ny * my2
				if nd < best and nd <= range2:
					dx[i] = nx
					dy[i] = ny

		# Vuelta por la fila para cubrir la propagación hacia el oeste.
		for xr in w:
			var x := w - 1 - xr
			var i := base + x
			var cx: float = dx[i]
			var best: float = INF if cx >= _SHORE_UNSET_TEST else cx * cx * kx + dy[i] * dy[i] * my2
			var je := base + (x + 1 if x < w - 1 else 0)
			var ex: float = dx[je]
			if ex < _SHORE_UNSET_TEST:
				var nx := ex + 1.0
				var ny: float = dy[je]
				var nd := nx * nx * kx + ny * ny * my2
				if nd < best and nd <= range2:
					dx[i] = nx
					dy[i] = ny

		y += step


## Recorre el mapa una vez acumulando área, profundidad y centroide de cada cuerpo, y los tipa.
static func _measure_bodies(map: WorldMapData, ids: PackedInt32Array,
		count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if count <= 0:
		return out

	var w := map.size.x
	var h := map.size.y
	var r := map.sea_level_radius

	# Senos y cosenos por fila y por columna: con esto la dirección de un téxel son tres productos
	# en vez de cuatro llamadas trigonométricas.
	var sin_t := PackedFloat32Array()
	var cos_t := PackedFloat32Array()
	var row_area := PackedFloat32Array()
	sin_t.resize(h)
	cos_t.resize(h)
	row_area.resize(h)
	var texel_solid_angle := (TAU / w) * (PI / h)
	for y in h:
		var theta := (y + 0.5) / float(h) * PI
		sin_t[y] = sin(theta)
		cos_t[y] = cos(theta)
		row_area[y] = r * r * texel_solid_angle * sin_t[y]

	var sin_p := PackedFloat32Array()
	var cos_p := PackedFloat32Array()
	sin_p.resize(w)
	cos_p.resize(w)
	for x in w:
		var phi := ((x + 0.5) / float(w) - 0.5) * TAU
		sin_p[x] = sin(phi)
		cos_p[x] = cos(phi)

	# Acumuladores por cuerpo. Packed en vez de Array porque el bucle de abajo los toca millones
	# de veces. resize() los deja a cero, que es el valor inicial correcto para todos.
	var texels := PackedInt32Array()
	var areas := PackedFloat64Array()
	var max_depth := PackedFloat64Array()
	var depth_sum := PackedFloat64Array()
	var cx := PackedFloat64Array()
	var cy := PackedFloat64Array()
	var cz := PackedFloat64Array()
	texels.resize(count)
	areas.resize(count)
	max_depth.resize(count)
	depth_sum.resize(count)
	cx.resize(count)
	cy.resize(count)
	cz.resize(count)

	var heights := map.heights
	var base_radius := map.radius + map.height_min
	var span := map.height_span
	var i := 0
	for y in h:
		var a := row_area[y]
		var st := sin_t[y]
		var ct := cos_t[y]
		for x in w:
			var id := ids[i]
			if id >= 0:
				var depth := r - (base_radius + heights[i] * span)
				texels[id] += 1
				areas[id] += a
				depth_sum[id] += depth * a
				if depth > max_depth[id]:
					max_depth[id] = depth
				cx[id] += st * sin_p[x] * a
				cy[id] += ct * a
				cz[id] += st * cos_p[x] * a
			i += 1

	var sphere_area := 4.0 * PI * r * r
	for id in count:
		var fraction: float = areas[id] / sphere_area
		var center := Vector3(cx[id], cy[id], cz[id])
		center = center.normalized() if center.length_squared() > 0.0 else Vector3.UP
		out.append({
			"id": id,
			"type": _classify(fraction),
			"name": "",
			"texels": texels[id],
			"area": areas[id],
			"area_fraction": fraction,
			"max_depth": max_depth[id],
			"mean_depth": depth_sum[id] / maxf(areas[id], 0.0001),
			"center": center,
			"center_latlon": WorldMapData.dir_to_latlon(center),
		})

	_name_bodies(out)
	return out


static func _classify(area_fraction: float) -> int:
	if area_fraction >= OCEAN_AREA_FRACTION:
		return WorldMapData.WaterType.OCEAN
	if area_fraction >= SEA_AREA_FRACTION:
		return WorldMapData.WaterType.SEA
	if area_fraction >= LAKE_AREA_FRACTION:
		return WorldMapData.WaterType.LAKE
	return WorldMapData.WaterType.POND


## Numera cada cuerpo dentro de su tipo por área descendente ("Lago 1" es el mayor). Solo ordena
## índices: el array queda indexado por id, que es lo que guarda body_ids.
static func _name_bodies(bodies: Array[Dictionary]) -> void:
	var order: Array[int] = []
	for i in bodies.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return bodies[a].area > bodies[b].area)

	var counters := {}
	for id in order:
		var t: int = bodies[id].type
		counters[t] = int(counters.get(t, 0)) + 1
		bodies[id].name = "%s %d" % [WorldMapData.TYPE_NAMES[t], counters[t]]


## Avisa si el rango de búsqueda se queda corto: un mapa saturado deja mesetas planas donde el
## terreno real sigue subiendo (o bajando), y ahí la costa y las alturas del mapa mienten.
static func _report_saturation(map: WorldMapData) -> void:
	var samples := 0
	var clipped := 0
	var lo := INF
	var hi := -INF
	var i := 0
	while i < map.heights.size():
		var v := map.heights[i]
		lo = minf(lo, v)
		hi = maxf(hi, v)
		if v <= 0.0005 or v >= 0.9995:
			clipped += 1
		samples += 1
		i += SATURATION_STRIDE

	if samples == 0:
		return
	if hi - lo < 0.0001:
		push_warning("[world-map] el mapa de alturas salió constante: el rango de búsqueda no " +
			"cruza la superficie.")
		return
	var ratio := float(clipped) / samples
	if ratio > 0.001:
		push_warning("[world-map] %.1f%% del mapa satura el rango de alturas (+/-%.0f). Sube " %
			[ratio * 100.0, map.height_span * 0.5] + "world_map_height_range en el planeta.")


## Número de argumentos declarados de un método, o -1 si el objeto no lo expone.
static func _method_arg_count(obj: Object, method: String) -> int:
	for m in obj.get_method_list():
		if m.name == method:
			return m.get("args", []).size()
	return -1
