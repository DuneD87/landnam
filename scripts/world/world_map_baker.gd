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
