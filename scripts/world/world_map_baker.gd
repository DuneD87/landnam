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
## Lo que consume esto es la FASE de las olas de orilla: phase = k * |offset|. Por eso el error
## absoluto de la distancia da igual y solo importa su gradiente, que sale de módulo 1 por
## construcción; y por eso una rejilla de ~90 m/téxel basta para crestas de decenas de metros.
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

	# dx/dy: desplazamiento EN TÉXELES desde cada téxel hasta su semilla más cercana conocida. Se
	# propaga el desplazamiento y no la distancia (transformada vectorial) porque al final hace
	# falta la dirección, y derivarla de un campo escalar a esta resolución la deja escalonada.
	var dx := PackedFloat32Array()
	var dy := PackedFloat32Array()
	dx.resize(n)
	dy.resize(n)
	dx.fill(_SHORE_UNSET)
	dy.fill(_SHORE_UNSET)

	# Semillas: agua abierta con algún vecino de tierra. El litoral real cae media celda más allá,
	# entre ambos téxeles; irrelevante para un campo del que solo se usa el gradiente.
	var seeds := 0
	for i in n:
		var id := ids[i]
		if id < 0 or id >= elig.size() or elig[id] == 0:
			continue
		var y := i / w
		var x := i - y * w
		var west := i - 1 if x > 0 else i + w - 1
		var east := i + 1 if x < w - 1 else i - w + 1
		var north := i - w if y > 0 else -1
		var south := i + w if y < h - 1 else -1
		if (ids[west] < 0 or ids[east] < 0
				or (north >= 0 and ids[north] < 0) or (south >= 0 and ids[south] < 0)):
			dx[i] = 0.0
			dy[i] = 0.0
			seeds += 1

	if seeds == 0:
		return

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
	var offsets := PackedFloat32Array()
	offsets.resize(n * 4)
	var fade_start := max_range * 0.75
	var i2 := 0
	for y in h:
		var st: float = sin_t[y]
		var ct: float = cos_t[y]
		for x in w:
			var ox: float = dx[i2]
			if ox < _SHORE_UNSET_TEST:
				var sy := clampi(y + roundi(dy[i2]), 0, h - 1)
				var sx := wrapi(x + roundi(ox), 0, w)
				var d := Vector3(st * cos_l[x], ct, -st * sin_l[x])
				var s := Vector3(sin_t[sy] * cos_l[sx], cos_t[sy], -sin_t[sy] * sin_l[sx])
				var proj := (s - d * d.dot(s)) * r
				var id := ids[i2]
				# En TIERRA el vector se guarda invertido. Este campo apunta siempre al litoral más
				# cercano, así que al cruzar la orilla su dirección gira 180 grados (es el gradiente
				# de |x| en el cero). El filtro bilineal del agua mezcla entonces las dos caras del
				# pliegue justo en la franja de uno o dos téxeles donde se dibuja la rompiente, y la
				# dirección que sale de ahí es la media de dos vectores opuestos. Invertido, la
				# dirección es continua a través de la costa y solo el módulo pasa por cero.
				if id < 0:
					proj = -proj
				var o := i2 * 4
				offsets[o] = proj.x
				offsets[o + 1] = proj.y
				offsets[o + 2] = proj.z
				# El agua interior se apaga con el peso, conservando el vector: anularlo metería en
				# la orilla del lago el mismo salto de fase que en el borde del campo.
				if id < 0 or elig[id] == 1:
					offsets[o + 3] = smoothstep(max_range, fade_start, proj.length())
			i2 += 1

	for _pass in _SHORE_SMOOTH_PASSES:
		offsets = _smooth_shore_field(offsets, dx, w, h)
	map.shore_size = map.size
	map.shore_offsets = offsets
	print("[world-map] campo de orilla: %d semillas de litoral, %.1f s"
		% [seeds, (Time.get_ticks_msec() - started) / 1000.0])


## Suaviza el campo de orilla: una pasada de caja 3x3 sobre el MÓDULO (que es la fase de la ola) y
## sobre la dirección por separado, más un apagado del peso donde el campo es incoherente.
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
## La coherencia (módulo del vector medio contra media de módulos) vale 1 donde todos miran igual y
## cae a 0 donde se oponen: es el eje medio de una bahía o un estrecho, donde de verdad chocan dos
## oleajes. Ahí se apaga la amplitud en vez de dibujar el cruce.
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
		var dir := sum / vec_len if vec_len > 1e-4 else Vector3.ZERO
		out[o] = dir.x * mean_len
		out[o + 1] = dir.y * mean_len
		out[o + 2] = dir.z * mean_len
		out[o + 3] = offsets[o + 3] * smoothstep(0.35, 0.8, coherence)
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
