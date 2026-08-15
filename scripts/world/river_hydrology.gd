class_name RiverHydrology extends RefCounted

## Hidrología de un planeta sobre el mapa equirect ya horneado: rellena las depresiones, deduce las
## direcciones de flujo, acumula caudal y extrae la red de cauces como sopa de segmentos.
##
## Todo son operaciones sobre arrays planos, así que se puede llamar desde el hilo de horneado del
## mapa, detrás de classify_water (necesita saber dónde está el mar para sembrar la inundación).

## Incremento por celda que garantiza descenso ESTRICTO al rellenar depresiones, en el espacio
## normalizado de alturas. Con un rango de 4 km son ~4 mm por celda: suficiente para que no queden
## llanos (y un llano rompe el árbol de drenaje) y demasiado poco para verse en el terreno.
const _FILL_EPSILON := 1.0e-6

## Cubos de la cola de prioridad. La inundación es monótona (nunca se saca una celda más baja que la
## última sacada), así que una cola de cubos con cursor de solo avance es exacta salvo por la
## cuantización, y cuesta O(1) por operación en vez del log N de un montículo binario.
const _BUCKETS := 65536

## Vecindad de 8. Con 4 los cauces salen en escalera de 90 grados; con 8 el zigzag baja a 45 y el
## suavizado posterior ya lo absorbe.
const _NX := [1, 1, 0, -1, -1, -1, 0, 1]
const _NY := [0, 1, 1, 1, 0, -1, -1, -1]

## Pasadas de suavizado de la posición de los nodos del cauce. El camino D8 crudo zigzaguea entre
## ocho direcciones y eso se ve como un río serrado; el suavizado corre los nodos dentro de su propia
## celda sin cambiar la topología de la red.
const _SMOOTH_PASSES := 6


## Resuelve la hidrología completa. Devuelve un diccionario con:
##   filled   -> alturas normalizadas con las depresiones rellenas (el "nivel de lago")
##   receiver -> índice de la celda aguas abajo, o -1 si es mar o sumidero
##   accum    -> caudal acumulado en m2 de cuenca drenada (ponderado por lluvia)
static func solve(heights: PackedFloat32Array, size: Vector2i, sea_n: float, radius: float,
		rain_stops: Array, smooth_passes: int = 2) -> Dictionary:
	var w := size.x
	var h := size.y
	var n := w * h

	var dem := _smooth_dem(heights, w, h, smooth_passes)
	var filled := _priority_flood(dem, w, h, sea_n)
	var receiver := _steepest_descent(filled, w, h, sea_n)
	var accum := _accumulate(filled, receiver, w, h, sea_n, radius, rain_stops)

	return {"filled": filled, "receiver": receiver, "accum": accum, "dem": dem}


## Caja 3x3 sobre el terreno antes de inundarlo. El terreno crudo está picado de hoyos de un téxel
## (los deja el ruido 3D), y cada hoyo es una depresión que rellenar: sin esto la red acaba corriendo
## sobre llanos de relleno en vez de por los valles de verdad. Es el paso bajo equivalente al que ya
## se le da al litoral antes de sacar la línea de costa.
static func _smooth_dem(heights: PackedFloat32Array, w: int, h: int,
		passes: int) -> PackedFloat32Array:
	var out := heights.duplicate()
	if passes <= 0:
		return out
	var n := w * h
	for _pass in passes:
		var src := out.duplicate()
		for i in n:
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
					var sx := x + kx
					if sx < 0:
						sx += w
					elif sx >= w:
						sx -= w
					acc += src[row + sx]
					count += 1
			out[i] = acc / count
	return out


## Inundación por prioridad (Barnes 2014): se siembra desde el mar y se crece hacia arriba sacando
## siempre la celda más baja pendiente. Al llegar a una celda por primera vez se le asigna como cota
## el máximo entre su cota real y la de quien la alcanzó más un epsilon, así las depresiones quedan
## rellenas hasta su punto de derrame y no queda ni un llano.
static func _priority_flood(heights: PackedFloat32Array, w: int, h: int,
		sea_n: float) -> PackedFloat32Array:
	var n := w * h
	var filled := PackedFloat32Array()
	filled.resize(n)

	# Cola de cubos como lista enlazada: 'head' guarda la primera celda de cada cubo y 'next' encadena
	# el resto. Dos arrays de enteros y ninguna reserva de memoria por empuje.
	var head := PackedInt32Array()
	head.resize(_BUCKETS)
	head.fill(-1)
	var next := PackedInt32Array()
	next.resize(n)
	var visited := PackedByteArray()
	visited.resize(n)

	var last := _BUCKETS - 1
	var seeded := false
	for i in n:
		if heights[i] > sea_n:
			continue
		# El mar es el nivel base: entra ya resuelto y a su propia cota.
		filled[i] = heights[i]
		visited[i] = 1
		var b := clampi(int(heights[i] * _BUCKETS), 0, last)
		next[i] = head[b]
		head[b] = i
		seeded = true

	if not seeded:
		# Planeta sin mar: se siembra desde el punto más bajo, que hace de desagüe único.
		var lowest := 0
		for i in n:
			if heights[i] < heights[lowest]:
				lowest = i
		filled[lowest] = heights[lowest]
		visited[lowest] = 1
		var b := clampi(int(heights[lowest] * _BUCKETS), 0, last)
		next[lowest] = head[b]
		head[b] = lowest

	var count := 0
	for bucket in _BUCKETS:
		var i := head[bucket]
		while i >= 0:
			var nxt := next[i]
			count += 1
			var y := i / w
			var x := i - y * w
			var base := filled[i] + _FILL_EPSILON
			for k in 8:
				var ny: int = y + _NY[k]
				if ny < 0 or ny >= h:
					continue
				var nxi: int = x + _NX[k]
				if nxi < 0:
					nxi += w
				elif nxi >= w:
					nxi -= w
				var j := ny * w + nxi
				if visited[j] == 1:
					continue
				visited[j] = 1
				var v: float = heights[j]
				filled[j] = v if v > base else base
				var nb := clampi(int(filled[j] * _BUCKETS), 0, _BUCKETS - 1)
				# La cola es monótona: nunca se empuja por detrás del cursor. Si la cuantización
				# devolviera un cubo ya pasado se fuerza al actual, que es donde toca sacarla.
				if nb <= bucket:
					# Al cubo que se está vaciando: se encadena en la lista LOCAL. Tocar head[bucket]
					# no serviría de nada porque ya se consumió al entrar en el cubo.
					next[j] = nxt
					nxt = j
				else:
					next[j] = head[nb]
					head[nb] = j
			i = nxt
	if count < n:
		push_warning("[rivers] la inundación dejó %d celdas sin alcanzar" % (n - count))
	return filled


## Direcciones de flujo por máxima pendiente sobre el terreno YA relleno. Como el relleno dejó cada
## celda estrictamente por encima de su alcanzadora, siempre existe un vecino más bajo y el árbol no
## puede tener ciclos.
static func _steepest_descent(filled: PackedFloat32Array, w: int, h: int,
		sea_n: float) -> PackedInt32Array:
	var n := w * h
	var receiver := PackedInt32Array()
	receiver.resize(n)
	receiver.fill(-1)
	# Longitud horizontal de un paso por fila, relativa a la vertical: cerca de los polos un paso en
	# longitud es mucho más corto y sin esto la pendiente saldría subestimada.
	var kx := PackedFloat32Array()
	kx.resize(h)
	var ky := PI / float(h)
	for y in h:
		kx[y] = sin((y + 0.5) / float(h) * PI) * TAU / float(w)

	for i in n:
		if filled[i] <= sea_n:
			continue
		var y := i / w
		var x := i - y * w
		var best := -1
		var best_slope := 0.0
		var hi := filled[i]
		for k in 8:
			var ny: int = y + _NY[k]
			if ny < 0 or ny >= h:
				continue
			var nxi: int = x + _NX[k]
			if nxi < 0:
				nxi += w
			elif nxi >= w:
				nxi -= w
			var j := ny * w + nxi
			var drop := hi - filled[j]
			if drop <= 0.0:
				continue
			var dx: float = _NX[k] * kx[y]
			var dy: float = _NY[k] * ky
			var slope := drop / sqrt(dx * dx + dy * dy)
			if slope > best_slope:
				best_slope = slope
				best = j
		receiver[i] = best
	return receiver


## Caudal acumulado: área de cuenca drenada, ponderada por la lluvia de cada latitud.
##
## El recorrido va en orden topológico del árbol de drenaje (Kahn desde las divisorias), NO en el
## orden inverso de inundación. Ese orden es ascendente POR CUBOS, y el relleno epsilon encadena
## ~15 celdas dentro del mismo cubo: dentro de un cubo el orden es arbitrario, así que de vez en
## cuando un donante se procesaba después de su receptor y su agua se quedaba por el camino (se
## perdía el 40% del caudal, y más cuanto más fina la rejilla).
static func _accumulate(filled: PackedFloat32Array, receiver: PackedInt32Array,
		w: int, h: int, sea_n: float, radius: float,
		rain_stops: Array) -> PackedFloat32Array:
	var n := w * h
	var accum := PackedFloat32Array()
	accum.resize(n)

	# Área real de la celda: en una equirect encoge con el seno de la colatitud.
	var cell := PackedFloat32Array()
	cell.resize(h)
	var dtheta := PI / float(h)
	var dphi := TAU / float(w)
	for y in h:
		var theta := (y + 0.5) * dtheta
		var lat := 90.0 - rad_to_deg(theta)
		cell[y] = radius * radius * sin(theta) * dtheta * dphi * _rain_at(lat, rain_stops)

	for i in n:
		accum[i] = cell[i / w] if filled[i] > sea_n else 0.0

	# Cada celda entrega su caudal cuando ya ha recibido el de todos sus afluentes, que es justo lo
	# que garantiza el orden topológico.
	var order := _topological_order(receiver, n)
	for i in order:
		var r := receiver[i]
		if r >= 0:
			accum[r] += accum[i]
	if order.size() < n:
		push_warning("[rivers] el árbol de drenaje tiene %d celdas en ciclo" % (n - order.size()))
	return accum


## Factor de lluvia en una latitud, interpolando la tabla de paradas [[lat, factor], ...] del JSON.
## Es lo que hace que un desierto tenga ramblas y una franja templada ríos gordos.
static func _rain_at(lat_deg: float, stops: Array) -> float:
	if stops.is_empty():
		return 1.0
	var prev: Array = stops[0]
	if lat_deg >= float(prev[0]):
		return float(prev[1])
	for si in range(1, stops.size()):
		var cur: Array = stops[si]
		if lat_deg >= float(cur[0]):
			var span := float(prev[0]) - float(cur[0])
			var t := 0.0 if span <= 0.0 else (lat_deg - float(cur[0])) / span
			return lerpf(float(cur[1]), float(prev[1]), t)
		prev = cur
	return float((stops[stops.size() - 1])[1])


## Extrae la red de cauces como sopa de segmentos en el espacio del mapa. Cada segmento es una arista
## celda -> receptor de las celdas que superan el umbral de caudal, con la cota y la anchura ya
## resueltas en cada extremo.
##
## Se emiten aristas y no polilíneas a propósito: para el campo de distancia da igual el orden, y
## así un tronco compartido por veinte afluentes no se rasteriza veinte veces.
##
## Devuelve { "seg": PackedFloat32Array, "count": int } donde cada segmento ocupa 8 flotantes:
##   x0, y0, x1, y1 (coordenadas de téxel fraccionarias), bed0, bed1 (altura en metros sobre el radio
##   nominal) y width0, width1 (semianchura del cauce en metros).
##
## Devuelve además "px"/"py" (posición ya suavizada de cada celda) y "channels" (los índices de celda
## que son cauce). La sopa de segmentos pierde la topología, y hace falta para medir el trazado.
static func extract_channels(sol: Dictionary, size: Vector2i, sea_n: float,
		height_min: float, height_span: float, radius: float, cfg: Dictionary) -> Dictionary:
	var w := size.x
	var h := size.y
	var n := w * h
	var filled: PackedFloat32Array = sol.filled
	var receiver: PackedInt32Array = sol.receiver
	var accum: PackedFloat32Array = sol.accum

	var min_area := float(cfg.get("min_drainage_area", 2.0e6))
	var min_outlet := float(cfg.get("min_outlet_drainage", 0.0))
	var width_coef := float(cfg.get("width_coefficient", 0.0035))
	var width_max := float(cfg.get("max_half_width", 60.0))
	var width_min := float(cfg.get("min_half_width", 6.0))
	var incision := float(cfg.get("channel_incision", 3.0))

	# Hundir el lecho hasta pasar el nivel del mar allí donde la incisión normal no llega. Los planetas
	# de este proyecto no tienen lámina de agua propia para los ríos: la pone la esfera del océano, que
	# inunda cualquier cosa por debajo de su cota. Sin esto las cabeceras quedan como barrancos secos
	# aunque el cauce siga hasta el mar, porque se quedan cortas por unos pocos metros.
	#
	# El cavado extra tiene tope: si el valle no puede volver a subir hasta el terreno dentro de su
	# alcance queda un escalón vertical en todo el borde, así que nunca se excava más de lo que el
	# talud es capaz de remontar. Los tramos que no lleguen con ese presupuesto se quedan secos.
	var wet_margin := float(cfg.get("channel_wet_margin", 0.0))
	var sea_h := height_min + sea_n * height_span
	var max_dig := float(cfg.get("bank_slope", 0.12)) * float(cfg.get("carve_range", 220.0))

	# Filtros de CUENCA ENTERA, distintos del de 'min_drainage_area': aquel mira el caudal de cada
	# celda, así que recorta todas las cuencas por la cabecera por igual y deja un muñón de cada una.
	# Estos descartan cuencas completas, que es lo que hace falta cuando el terreno drena en radial y
	# suelta cientos de arroyos costeros de nueve celdas.
	var max_per_land := int(cfg.get("max_rivers_per_landmass", 0))
	var outlet := PackedInt32Array()
	var keep_outlet := PackedByteArray()
	if min_outlet > 0.0 or max_per_land > 0:
		outlet.resize(n)
		outlet.fill(-1)
		var order := _topological_order(receiver, n)
		for k in range(order.size() - 1, -1, -1):
			var i := order[k]
			if filled[i] <= sea_n:
				continue
			var r := receiver[i]
			outlet[i] = i if (r < 0 or filled[r] <= sea_n) else outlet[r]

		keep_outlet.resize(n)
		if max_per_land <= 0:
			for i in n:
				if outlet[i] == i and accum[i] >= min_outlet:
					keep_outlet[i] = 1
		else:
			# Por masa de tierra en vez de por umbral global: un umbral absoluto deja sin un solo río
			# a los continentes que no tienen ninguna cuenca dominante, y son justo los que drenan más
			# en radial. Así cada masa se queda con sus N mayores, tenga el tamaño que tenga.
			var land := _landmass_labels(filled, w, h, sea_n)
			var by_land := {}
			for i in n:
				if outlet[i] != i or accum[i] < min_outlet:
					continue
				var id := land[i]
				if not by_land.has(id):
					by_land[id] = []
				by_land[id].append(i)
			for id in by_land:
				var outs: Array = by_land[id]
				outs.sort_custom(func(a, b): return accum[a] > accum[b])
				for k in mini(outs.size(), max_per_land):
					keep_outlet[outs[k]] = 1

	# Posición de cada nodo del cauce, en coordenadas de téxel fraccionarias. Arranca en el centro de
	# su celda y el suavizado la mueve después.
	var px := PackedFloat32Array()
	var py := PackedFloat32Array()
	px.resize(n)
	py.resize(n)
	var is_channel := PackedByteArray()
	is_channel.resize(n)

	var channels := PackedInt32Array()
	for i in n:
		if accum[i] < min_area or filled[i] <= sea_n:
			continue
		if not keep_outlet.is_empty() and keep_outlet[outlet[i]] == 0:
			continue
		is_channel[i] = 1
		channels.append(i)
		var y := i / w
		px[i] = (i - y * w) + 0.5
		py[i] = y + 0.5

	if channels.is_empty():
		return {"seg": PackedFloat32Array(), "count": 0, "px": px, "py": py, "channels": channels}

	_smooth_channel_positions(px, py, receiver, is_channel, channels, w, h)
	_meander(px, py, receiver, is_channel, channels, accum, w, h, radius, cfg)

	var seg := PackedFloat32Array()
	var count := 0
	for i in channels:
		var r := receiver[i]
		if r < 0:
			continue
		# El cauce se dibuja hasta el mar: el último tramo termina en una celda marina, que no es
		# cauce pero sí es la desembocadura.
		var y := r / w
		var rx: float = px[r] if is_channel[r] == 1 else (r - y * w) + 0.5
		var ry: float = py[r] if is_channel[r] == 1 else y + 0.5
		# Las aristas que cruzan la costura de longitud se dibujan por el lado corto.
		var x0: float = px[i]
		if rx - x0 > w * 0.5:
			rx -= w
		elif x0 - rx > w * 0.5:
			rx += w
		seg.append(x0)
		seg.append(py[i])
		seg.append(rx)
		seg.append(ry)
		seg.append(_bed(filled[i], height_min, height_span, incision, sea_h, wet_margin, max_dig))
		seg.append(_bed(filled[r], height_min, height_span, incision, sea_h, wet_margin, max_dig))
		seg.append(clampf(width_coef * sqrt(accum[i]), width_min, width_max))
		seg.append(clampf(width_coef * sqrt(accum[r]), width_min, width_max))
		count += 1
	return {"seg": seg, "count": count, "px": px, "py": py, "channels": channels}


## Cota del lecho en un nodo. Normalmente es el terreno menos la incisión, pero si 'wet_margin' está
## activo se hunde lo que haga falta para quedar por debajo del mar, sin pasarse del cavado que el
## talud puede remontar. Sigue siendo monótona aguas abajo: el mínimo con una constante no rompe el
## orden, y el tope depende del terreno, que ya baja.
static func _bed(filled_v: float, height_min: float, height_span: float, incision: float,
		sea_h: float, wet_margin: float, max_dig: float) -> float:
	var ground := height_min + filled_v * height_span
	var bed := ground - incision
	if wet_margin <= 0.0:
		return bed
	return maxf(minf(bed, sea_h - wet_margin), ground - max_dig)


## Suaviza la posición de los nodos del cauce moviéndolos hacia la media de su receptor y su donante
## principal. La topología no cambia (nadie cambia de receptor): solo se quita el serrado del D8.
static func _smooth_channel_positions(px: PackedFloat32Array, py: PackedFloat32Array,
		receiver: PackedInt32Array, is_channel: PackedByteArray, channels: PackedInt32Array,
		w: int, h: int) -> void:
	# Donante principal de cada celda: el afluente que llega desde más lejos. Con él y el receptor,
	# cada nodo tiene el tramo de río que lo atraviesa y se puede promediar a lo largo de la corriente.
	var main_donor := PackedInt32Array()
	main_donor.resize(px.size())
	main_donor.fill(-1)
	var depth := PackedInt32Array()
	depth.resize(px.size())
	for i in channels:
		var r := receiver[i]
		if r < 0 or is_channel[r] == 0:
			continue
		if main_donor[r] < 0 or depth[i] > depth[main_donor[r]]:
			main_donor[r] = i
		depth[r] = maxi(depth[r], depth[i] + 1)

	for _pass in _SMOOTH_PASSES:
		var nx := px.duplicate()
		var ny := py.duplicate()
		for i in channels:
			var r := receiver[i]
			var d := main_donor[i]
			if r < 0 or is_channel[r] == 0 or d < 0:
				continue
			# Media a lo largo de la corriente. Se desenrolla la costura para no promediar una x de
			# 2047 con una de 0 y mandar el nodo al centro del mapa.
			var xr := _unwrap(px[r], px[i], w)
			var xd := _unwrap(px[d], px[i], w)
			nx[i] = px[i] * 0.5 + (xr + xd) * 0.25
			ny[i] = py[i] * 0.5 + (py[r] + py[d]) * 0.25
		for i in channels:
			px[i] = fposmod(nx[i], float(w))
			py[i] = clampf(ny[i], 0.0, h - 1.0)


## Desplaza los nodos del cauce a un lado y a otro para que serpenteen. La máxima pendiente sobre un
## DEM suavizado da trazados prácticamente rectos (sinuosidad medida 1.02, y un río encajado real
## anda por 1.1-1.3) porque nada en el modelo simula erosión lateral, que es lo que hace los meandros.
## Aquí se añaden como geometría: no cambian ni el árbol de drenaje ni las cotas, solo dónde cae el
## nodo dentro del mapa.
##
## La longitud de onda y la amplitud van con la anchura del cauce, que es la relación real (onda de
## 10-14 anchuras, amplitud de 2-3). La fase se ACUMULA aguas arriba en vez de sacarse de la posición:
## así un afluente entra en el tronco con la fase que le toca y la confluencia no da un salto.
static func _meander(px: PackedFloat32Array, py: PackedFloat32Array, receiver: PackedInt32Array,
		is_channel: PackedByteArray, channels: PackedInt32Array, accum: PackedFloat32Array,
		w: int, h: int, radius: float, cfg: Dictionary) -> void:
	var amp_factor := float(cfg.get("meander_amplitude", 0.0))
	if amp_factor <= 0.0 or radius <= 0.0:
		return
	var wave_factor := float(cfg.get("meander_wavelength", 12.0))
	var width_coef := float(cfg.get("width_coefficient", 0.0035))
	var width_max := float(cfg.get("max_half_width", 60.0))
	var width_min := float(cfg.get("min_half_width", 6.0))

	# Metros por téxel. En longitud encoge con el seno de la colatitud, en latitud es constante.
	var mx := PackedFloat32Array()
	mx.resize(h)
	for y in h:
		mx[y] = sin((y + 0.5) / float(h) * PI) * TAU / float(w) * radius
	var my := PI / float(h) * radius

	# Hay un nodo por celda, así que la onda más corta representable la fija el muestreo. Con 3 nodos
	# por onda sale un triángulo, no una curva, y el aliasing se ve como codos de 45 grados justo lo
	# que se pretendía quitar; con 6 la curva ya es curva. Las cabeceras estrechas pedirían meandros
	# sub-celda y se quedan en ondulaciones largas y suaves, que es lo correcto aquí.
	var min_wave := 6.0 * my

	var n := px.size()
	var order := _topological_order(receiver, n)

	var phase := PackedFloat32Array()
	phase.resize(n)
	var off_x := PackedFloat32Array()
	var off_y := PackedFloat32Array()
	off_x.resize(n)
	off_y.resize(n)

	for k in range(order.size() - 1, -1, -1):
		var i := order[k]
		if is_channel[i] == 0:
			continue
		var r := receiver[i]
		if r < 0 or is_channel[r] == 0:
			continue
		var half := clampf(width_coef * sqrt(accum[i]), width_min, width_max)
		var wave := maxf(wave_factor * half * 2.0, min_wave)

		var y := i / w
		var vx := _unwrap(px[r], px[i], w) - px[i]
		var v := Vector2(vx * mx[y], (py[r] - py[i]) * my)
		var step := v.length()
		if step < 0.01:
			continue
		phase[i] = phase[r] + TAU * step / wave

		# Dos frecuencias inconmensurables desde la misma fase: sigue siendo coherente a lo largo de
		# la corriente pero no se repite, que es lo que separa un meandro de una onda de sierra.
		var s := sin(phase[i]) * 0.75 + sin(phase[i] * 0.37) * 0.25
		var perp := Vector2(-v.y, v.x) / step * (amp_factor * half * s)
		off_x[i] = perp.x / mx[y]
		off_y[i] = perp.y / my

	# Se aplica al final para que todos los nodos hayan usado la dirección de flujo sin desplazar.
	for i in channels:
		px[i] = fposmod(px[i] + off_x[i], float(w))
		py[i] = clampf(py[i] + off_y[i], 0.0, h - 1.0)


## Componentes conexas de tierra emergida, con vecindad de 8 para que una diagonal no parta una isla
## en dos. Devuelve la etiqueta de masa de cada celda, o -1 si es mar.
static func _landmass_labels(filled: PackedFloat32Array, w: int, h: int,
		sea_n: float) -> PackedInt32Array:
	var n := w * h
	var label := PackedInt32Array()
	label.resize(n)
	label.fill(-1)
	var stack := PackedInt32Array()
	var next_id := 0
	for start in n:
		if label[start] >= 0 or filled[start] <= sea_n:
			continue
		var id := next_id
		next_id += 1
		stack.clear()
		stack.append(start)
		label[start] = id
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var y := i / w
			var x := i - y * w
			for k in 8:
				var ny: int = y + _NY[k]
				if ny < 0 or ny >= h:
					continue
				var nxi: int = x + _NX[k]
				if nxi < 0:
					nxi += w
				elif nxi >= w:
					nxi -= w
				var j := ny * w + nxi
				if label[j] < 0 and filled[j] > sea_n:
					label[j] = id
					stack.append(j)
	return label


## Orden topológico del árbol de drenaje por Kahn, de las divisorias hacia el mar: cada celda sale
## después de todos sus donantes. Recorrerlo al revés da el orden contrario, con el receptor ya
## resuelto antes que quien le entrega.
static func _topological_order(receiver: PackedInt32Array, n: int) -> PackedInt32Array:
	var pending := PackedInt32Array()
	pending.resize(n)
	for i in n:
		if receiver[i] >= 0:
			pending[receiver[i]] += 1
	var order := PackedInt32Array()
	order.resize(n)
	var stack := PackedInt32Array()
	stack.resize(n)
	var sp := 0
	for i in n:
		if pending[i] == 0:
			stack[sp] = i
			sp += 1
	var done := 0
	while sp > 0:
		sp -= 1
		var i := stack[sp]
		order[done] = i
		done += 1
		var r := receiver[i]
		if r < 0:
			continue
		pending[r] -= 1
		if pending[r] == 0:
			stack[sp] = r
			sp += 1
	order.resize(done)
	return order


static func _unwrap(x: float, reference: float, w: int) -> float:
	if x - reference > w * 0.5:
		return x - w
	if reference - x > w * 0.5:
		return x + w
	return x
