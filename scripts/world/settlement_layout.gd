class_name SettlementLayout extends RefCounted

## El plano de un poblado: dónde va la plaza, qué construcción va en cada sitio, girada cómo y a qué
## altura, con su zócalo y su rampa. No toca la escena: lee el suelo con [ground] (el radio del terreno
## en una dirección, o NAN) y las sendas con [trail_distance] (m a la más cercana), así que se prueba
## con un relieve inventado y se puede calcular en hilos (SettlementField).
##
## La plaza se busca en lo más llano justo más allá de la punta de la senda. Las construcciones se
## reparten en corona alrededor, con la puerta hacia el centro y sin tapar la llegada de la senda; la
## principal de la plantilla, al fondo, frente a ella. Cada una se apoya en el suelo así: la cara de
## arriba de su suelo queda MARGIN sobre el punto más alto de su huella (el suelo, una capa de celdas,
## va casi enterrado) y bajo cada columna se pone piedra hasta EMBED por debajo del terreno. Si la
## puerta queda alta, sale una rampa de celdas inclinadas hasta el suelo.
##
## Todo en el marco del terreno (el centro del planeta en el origen), en metros.

## Altura de la cara de arriba del suelo sobre lo más alto de la huella (m). Menos que el escalón del
## jugador (StepUpSystem.max_step_height, 0,55).
const MARGIN := 0.3
## Lo que entra el zócalo en el terreno (m).
const EMBED := 0.5
## Separación mínima entre construcciones (m).
const SPACING := 3.0
## Separación del eje de cualquier senda (m): media senda y un poco.
const TRAIL_GAP := 6.0
## Sector libre a cada lado de la llegada de la senda (rad).
const ENTRY_HALF := deg_to_rad(35.0)
## Giro al azar de cada construcción respecto a mirar al centro (rad).
const YAW_JITTER := deg_to_rad(12.0)
## Intentos por construcción.
const TRIES := 24
## Paso máximo entre muestras del suelo de una huella (m).
const SAMPLE_STEP := 4.0
## Celdas de rampa como mucho.
const MAX_RAMP := 4
## Desnivel que se sube sin rampa (m).
const STEP_OK := 0.4
## Los surcos de un huerto, y sus matas a lo largo de ellos (m).
const GARDEN_ROW := 1.0
const GARDEN_PLANT := 0.6
## La cerca (SettlementWall): cuántos tramos da la vuelta, lo que se aparta de las huellas (m), lo cerca
## que pasa una senda del centro de un tramo (m) para dejarle una puerta y lo que mide una puerta como
## poco (m). La llegada de la senda lleva puerta siempre, de WALL_GATE_SPAN tramos.
const WALL_SEGMENTS := 96
const WALL_GAP := 4.0
const WALL_GATE_TRAIL := 2.5
const WALL_GATE_SPAN := 2
const WALL_GATE_MIN := 3.5
## Los guardias: lo que se meten hacia dentro desde la puerta y desde la cerca al hacer la ronda (m).
const WALL_POST_IN := 2.2
const WALL_PATROL_IN := 3.0
## La villa (_plan_streets): lo que se aparta de una senda el cuerpo de una construcción (m), lo que dista
## de la calle la cara de la puerta, la separación entre vecinas a lo largo de la calle y cada cuánto se
## lee el suelo bajo las calles y la plaza (m).
const STREET_TRAIL_GAP := 3.0
const STREET_SETBACK := 2.0
const STREET_LOT_GAP := Vector2(3.1, 5.0)
const STREET_SAMPLE := 2.5
## La ronda de la villa: a qué parte del largo de las calles cruza las radiales y el ángulo de cada cuerda.
const RING_AT := 0.6
const RING_CHORD := 20.0
## Las calles que siguen a las sendas (_trail_ways): lo cerca del eje de una senda que tiene que pasar el
## círculo para que se cuente como que la cruza (m), cada cuánto se busca la senda hacia dentro (m), lo
## que se aparta una calle de otra por la vuelta (rad) y lo que se desvía como mucho de la senda al
## quitarle puntos (m).
const TRAIL_HIT := 2.0
const TRAIL_STEP := 4.0
const STREET_SPREAD := 0.6
const WAY_TOLERANCE := 0.4
## Lo que hay como mucho entre dos postes de un cercado (m).
const PEN_STEP := 2.0
## Bloques del zócalo y de la rampa (BlockDatabase.BLOCK_CUBE_ID, BLOCK_SLOPE_ID).
const _CUBE_BLOCK := 0
const _RAMP_BLOCK := 1


## Lo más llano junto a la punta [site] ({"dir", "into"}): {"dir", "ground" (radio del suelo), "slope"}
## o {} si no hay sitio. [cfg]: max_slope (desnivel / distancia), sea_radius y radius.
static func find_center(site: Dictionary, ground: Callable, cfg: Dictionary) -> Dictionary:
	var radius := float(cfg.radius)
	var e: Vector3 = site.dir
	var fwd: Vector3 = site.into
	var right := e.cross(fwd).normalized()
	var best := {}
	var best_score := INF
	for a: float in [6.0, 18.0, 30.0]:
		for b: float in [-12.0, 0.0, 12.0]:
			var c := _at(e, right, fwd, b, a, radius)
			var h := _heights(c, right, fwd, 12.0, ground, radius)
			if h.is_empty():
				continue
			var low: float = Array(h).min()
			var high: float = Array(h).max()
			if low < float(cfg.sea_radius) + 1.5:
				continue
			var slope := (high - low) / 24.0
			var score := slope + (a + absf(b)) * 0.002
			if slope <= float(cfg.max_slope) and score < best_score:
				best_score = score
				best = {"dir": c, "ground": h[0], "slope": slope}
	return best


## El plano del poblado de [template] con la plaza en [center] (de find_center), llegando la senda en
## la dirección [into]. [measures]: SettlementPrefab.id -> measure(). {} si no cabe la construcción
## principal o caben menos de dos (o la única de una plantilla de una).
## {"template", "center", "ground", "into", "extent" (m del centro al borde de lo más lejano),
##  "buildings": [{"prefab", "kind", "origin", "basis" (la pose de su grid principal), "door" (el
##  umbral, en el suelo de dentro), "extra": PackedInt32Array de x, y, z, bloque, cuartos de vuelta,
##  "work": sus sitios de trabajo (_workplace), "props": su decorado ({"kind", "pose", "item", "scale"})}],
##  "wall": la cerca (_wall; {} sin ella)}
## [trail_axis]: la distancia al eje de las sendas, más fina que [trail_distance] (la del campo del
## terreno, la que se pinta), para que las calles de la villa vayan encima; sin ella, [trail_distance].
static func plan(template: SettlementTemplate, center: Dictionary, into: Vector3, measures: Dictionary,
		ground: Callable, trail_distance: Callable, cfg: Dictionary, rng: RandomNumberGenerator,
		trail_axis := Callable()) -> Dictionary:
	var c: Vector3 = center.dir
	var fwd := into.slide(c).normalized()
	var right := c.cross(fwd).normalized()
	if template.layout == &"streets":
		return _plan_streets(template, center, c, right, fwd, measures, ground, trail_distance, cfg, rng,
			trail_axis if trail_axis.is_valid() else trail_distance)
	var queue: Array[SettlementPrefab] = []
	if template.center != null:
		queue.append(template.center)
	var count := rng.randi_range(template.count_min, template.count_max)
	for i in count:
		if not template.buildings.is_empty():
			queue.append(template.buildings[rng.randi() % template.buildings.size()])
	var placed: Array = []
	var rects: Array = []
	var extent := 0.0
	for k in queue.size():
		var prefab := queue[k]
		var m: Dictionary = measures.get(prefab.id, {})
		if m.is_empty():
			continue
		var main := k == 0 and template.center != null
		var shape := _shape(prefab, m)
		var depth: float = shape.z1 - shape.z0
		for attempt in TRIES:
			var theta: float
			var r: float
			if main:
				# Al fondo, frente a la llegada; si no cabe, abriéndose a los lados y más lejos.
				theta = [0.0, 0.45, -0.45, 0.9, -0.9, 1.35, -1.35][attempt % 7]
				r = template.plaza_radius + depth * 0.5 + 3.0 * (attempt / 7)
			else:
				theta = PI + rng.randf_range(ENTRY_HALF, TAU - ENTRY_HALF)
				r = template.plaza_radius + depth * 0.5 + rng.randf() * template.ring_depth
			var spot := _try(prefab, m, shape, c, right, fwd, float(center.ground), theta, r,
				rng.randf_range(-YAW_JITTER, YAW_JITTER), rects, ground, trail_distance, cfg)
			if spot.is_empty():
				continue
			rects.append(spot.rect)
			for q: Vector2 in spot.rect:
				extent = maxf(extent, q.length())
			placed.append(spot.building)
			break
		# La principal es lo que hace a la plantilla: un poblado sin su iglesia no es ese poblado.
		if main and placed.is_empty():
			return {}
	var needed := mini(2, queue.size())
	if placed.size() < needed:
		return {}
	var wall := {}
	if template.wall != &"":
		wall = _wall(template, c, right, fwd, rects, ground, trail_distance, cfg)
	return {"template": template.id, "center": c, "ground": float(center.ground), "into": fwd,
		"extent": extent, "buildings": placed, "wall": wall}


## La villa de [template] (layout &"streets") con la plaza en [center]: la principal al fondo de la plaza,
## frente a la llegada; las calles, que salen de la plaza (encima de las sendas que entran y, las demás,
## repartidas sin pasar por la principal); las de la plaza en corona, sin tapar ninguna calle; y las
## demás a los dos lados de cada calle (las radiales y una ronda que las cruza), con la puerta a ella.
## Además de lo de plan(), "streets": [{"points": el eje en el suelo cada STREET_SAMPLE m, de la plaza a
## pasar la cerca, "width"}] y "plaza": {"radius", "center" (en el suelo)}. {} si no cabe la principal o
## caben menos de count_min.
static func _plan_streets(template: SettlementTemplate, center: Dictionary, c: Vector3, right: Vector3,
		fwd: Vector3, measures: Dictionary, ground: Callable, trail_distance: Callable, cfg: Dictionary,
		rng: RandomNumberGenerator, trail_axis: Callable) -> Dictionary:
	var radius := float(cfg.radius)
	var ground_r := float(center.ground)
	var plaza := template.plaza_radius
	var half := template.street_width * 0.5
	var placed: Array = []
	var rects: Array = []
	var keep := func(spot: Dictionary) -> void:
		rects.append(spot.rect)
		placed.append(spot.building)

	# Las radiales ([ways]: líneas en el plano, de la plaza hasta pasar la cerca, a [out]). Primero las que
	# siguen a las sendas que entran (encima de la senda, alineadas con la de fuera); luego, hasta
	# template.streets, las de siempre por los huecos: la de la llegada, a los lados y en diagonal hacia
	# el fondo, algo torcidas. ([outer]: hasta dónde llegan.)
	var outer := template.street_length + WALL_GAP + 4.0
	var ways: Array = _trail_ways(c, right, fwd, radius, plaza, outer, trail_axis, template.streets)
	var bearings: Array[float] = []
	for way: PackedVector2Array in ways:
		var end := way[way.size() - 1]
		bearings.append(atan2(end.x, end.y))
	var others: Array[float] = [PI, PI * 0.5, -PI * 0.5, PI * 0.28, -PI * 0.28, PI * 0.75, -PI * 0.75]
	for bearing in others:
		if ways.size() >= template.streets:
			break
		var b := bearing + (rng.randf_range(-0.12, 0.12) if bearing != PI else 0.0)
		var free := true
		for other in bearings:
			free = free and absf(angle_difference(b, other)) > STREET_SPREAD
		if not free:
			continue
		var dir := Vector2(sin(b), cos(b))
		ways.append(PackedVector2Array([dir * (plaza - 1.0), dir * outer]))
		bearings.append(b)
	# Los tramos de calle ([a, b, radial, desde dónde y hasta dónde hay solares]): los de las radiales (con
	# solares hasta street_length del centro, no hasta la cerca) y la ronda, que las cruza a RING_AT del
	# largo, en cuerdas de RING_CHORD grados como mucho.
	var segments: Array = []
	for way: PackedVector2Array in ways:
		for i in way.size() - 1:
			segments.append([way[i], way[i + 1], true, 5.0 if i == 0 else 0.0,
				_inside(way[i], way[i + 1], template.street_length)])
	var ring_r := template.street_length * RING_AT
	var chords := ceili(TAU / deg_to_rad(RING_CHORD))
	for i in chords:
		var a0 := TAU * i / chords
		var a1 := TAU * (i + 1) / chords
		var p0 := Vector2(sin(a0), cos(a0)) * ring_r
		var p1 := Vector2(sin(a1), cos(a1)) * ring_r
		segments.append([p0, p1, false, 0.0, p0.distance_to(p1)])
	var corridors: Array = []
	for seg: Array in segments:
		corridors.append([seg[0], seg[1], half])

	# La principal, al fondo de la plaza.
	if template.center != null:
		var m: Dictionary = measures.get(template.center.id, {})
		if m.is_empty():
			return {}
		var shape := _street_shape(template.center, m)
		for attempt in TRIES:
			# Al fondo y, si una calle entra por ahí, a un lado.
			var theta: float = [0.0, 0.2, -0.2, 0.4, -0.4, 0.8, -0.8, 1.2][attempt % 8]
			var out := Vector2(sin(theta), cos(theta))
			# La cara de la puerta en el borde de la plaza: el centro de la huella, detrás de ella.
			var back := float(shape.door_z) - (float(shape.z0) + float(shape.z1)) * 0.5
			var r := plaza + back + 1.0 * (attempt / 8)
			var spot := _place(template.center, m, shape, c, right, fwd, ground_r, out * r, -out, rects, ground,
				trail_distance, cfg, corridors)
			if not spot.is_empty():
				keep.call(spot)
				break
		if placed.is_empty():
			return {}

	# Las de la plaza, en corona con la puerta al centro.
	var around := rng.randi_range(template.plaza_count_min, template.plaza_count_max)
	for i in around:
		if template.plaza_buildings.is_empty():
			break
		var prefab: SettlementPrefab = template.plaza_buildings[rng.randi() % template.plaza_buildings.size()]
		var m: Dictionary = measures.get(prefab.id, {})
		if m.is_empty():
			continue
		var shape := _street_shape(prefab, m)
		var depth: float = float(shape.z1) - float(shape.z0)
		# Los puestos, dentro de la plaza en corro (el mercado); lo demás, en su borde.
		var stall := prefab.kind == &"stall"
		for attempt in TRIES:
			var theta := rng.randf() * TAU
			var out := Vector2(sin(theta), cos(theta))
			var r := plaza * rng.randf_range(0.5, 0.7) if stall else plaza + depth * 0.5 + rng.randf() * 1.5
			var spot := _place(prefab, m, shape, c, right, fwd, ground_r, out * r,
				(-out).rotated(rng.randf_range(-YAW_JITTER, YAW_JITTER)), rects, ground, trail_distance, cfg, corridors)
			if not spot.is_empty():
				keep.call(spot)
				break

	# Las de las calles: a cada lado de cada tramo, una tras otra con la puerta a la calle. En las radiales
	# desde la plaza; en la ronda, apartadas de los cruces.
	var wanted := rng.randi_range(template.count_min, template.count_max)
	var lots: Array = []
	for k in segments.size():
		var seg: Array = segments[k]
		if float(seg[4]) <= float(seg[3]):
			continue
		for side: float in [-1.0, 1.0]:
			lots.append([k, side, seg[3], seg[4]])
	var stuck := 0
	var street_count := 0
	while street_count < wanted and not lots.is_empty() and stuck < 600:
		var pick := rng.randi() % lots.size()
		var lot: Array = lots[pick]
		var seg: Array = segments[lot[0]]
		var a: Vector2 = seg[0]
		var along: Vector2 = ((seg[1] as Vector2) - a).normalized()
		var side: float = lot[1]
		var t: float = lot[2]
		var prefab: SettlementPrefab = template.buildings[rng.randi() % template.buildings.size()]
		var m: Dictionary = measures.get(prefab.id, {})
		var shape := _street_shape(prefab, m)
		var width: float = float(shape.x1) - float(shape.x0)
		var to_center := (float(shape.z0) + float(shape.z1)) * 0.5
		# La puerta (+Z) hacia la calle: el centro de la huella, detrás de la cara de la puerta.
		var w := Vector2(along.y, -along.x) * -side
		var back: float = float(shape.door_z) - to_center
		var pc := a + along * (t + width * 0.5) - w * (half + STREET_SETBACK + back)
		if t + width > float(lot[3]):
			lots.remove_at(pick)
			continue
		var spot := _place(prefab, m, shape, c, right, fwd, ground_r, pc, w, rects, ground, trail_distance, cfg,
			corridors)
		if spot.is_empty():
			lot[2] = t + 2.0
			stuck += 1
			continue
		keep.call(spot)
		street_count += 1
		lot[2] = t + width + rng.randf_range(STREET_LOT_GAP.x, STREET_LOT_GAP.y)
	if placed.size() < template.count_min:
		return {}
	var extent := plaza
	for rect: Array in rects:
		for q: Vector2 in rect:
			extent = maxf(extent, q.length())

	# El suelo de las calles y de la plaza, para pintarlas (SettlementStreets): las radiales y las cuerdas
	# de la ronda.
	var lines: Array = ways.duplicate()
	for seg: Array in segments:
		if not seg[2]:
			lines.append(PackedVector2Array([seg[0], seg[1]]))
	var streets: Array = []
	for way: PackedVector2Array in lines:
		var points := PackedVector3Array()
		for q: Vector2 in _way_samples(way):
			var mid := _grounded(_at(c, right, fwd, q.x, q.y, radius), ground, cfg)
			if not mid.is_finite():
				break
			points.append(mid)
		if points.size() >= 2:
			streets.append({"points": points, "width": template.street_width})
	var wall := {}
	if template.wall != &"":
		wall = _wall(template, c, right, fwd, rects, ground, trail_distance, cfg, bearings, false)
	return {"template": template.id, "center": c, "ground": ground_r, "into": fwd, "extent": extent,
		"buildings": placed, "wall": wall, "streets": streets,
		"plaza": {"radius": plaza, "center": c * ground_r}}


## Las calles de la villa que siguen a las sendas que entran en ella, como mucho [count]. Cada una, donde
## una senda cruza el círculo de radio [outer] (un mínimo de [trail_axis] por la vuelta, a menos de
## TRAIL_HIT de su eje) y de ahí hacia dentro por la senda, en círculos cada TRAIL_STEP m mientras la
## haya, y luego derecha a la plaza. Una línea en el plano (de la plaza, a [plaza] - 1 del centro, a
## [outer]), sin los puntos que no la apartan más de WAY_TOLERANCE de la senda.
static func _trail_ways(c: Vector3, right: Vector3, fwd: Vector3, radius: float, plaza: float, outer: float,
		trail_axis: Callable, count: int) -> Array:
	var axis := func(theta: float, r: float) -> float:
		return float(trail_axis.call(_at(c, right, fwd, sin(theta) * r, cos(theta) * r, radius)))
	# Los cruces: los mínimos de la vuelta, cada grado, afinados.
	var n := 360
	var around := PackedFloat32Array()
	for i in n:
		around.append(axis.call(TAU * i / n, outer))
	var crossings: Array = []
	for i in n:
		var d := around[i]
		if d < TRAIL_HIT * 2.0 and d <= around[posmod(i - 1, n)] and d < around[(i + 1) % n]:
			var best := _closest_bearing(axis, outer, TAU * (i - 1) / n, TAU * (i + 1) / n)
			if float(best[1]) < TRAIL_HIT:
				crossings.append(best)
	crossings.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var ways: Array = []
	var taken: Array[float] = []
	for crossing: Array in crossings:
		if ways.size() >= count:
			break
		var theta: float = crossing[0]
		var near := false
		for other in taken:
			near = near or absf(angle_difference(theta, other)) < STREET_SPREAD
		if near:
			continue
		taken.append(theta)
		# Hacia dentro por la senda.
		var points := PackedVector2Array([Vector2(sin(theta), cos(theta)) * outer])
		var r := outer
		while r - TRAIL_STEP > plaza + 2.0:
			r -= TRAIL_STEP
			var window := clampf(2.0 * TRAIL_STEP / r, 0.1, 0.8)
			var best := _closest_bearing(axis, r, theta - window, theta + window)
			var q := Vector2(sin(best[0]), cos(best[0])) * r
			if float(best[1]) > TRAIL_HIT or q.distance_to(points[points.size() - 1]) > TRAIL_STEP * 2.5:
				break
			points.append(q)
			theta = best[0]
		points.append(Vector2(sin(theta), cos(theta)) * (plaza - 1.0))
		points.reverse()
		ways.append(_simplify(points, WAY_TOLERANCE))
	return ways


## El rumbo de [lo] a [hi] en el círculo de radio [r] más cerca del eje de una senda ([axis]: rumbo, radio
## -> distancia), cada medio grado y luego afinado: [rumbo, distancia].
static func _closest_bearing(axis: Callable, r: float, lo: float, hi: float) -> Array:
	var best := [lo, INF]
	var step := deg_to_rad(0.5)
	var theta := lo
	while theta <= hi:
		var d: float = axis.call(theta, r)
		if d < float(best[1]):
			best = [theta, d]
		theta += step
	var fine := step / 10.0
	var center: float = best[0]
	for k in range(-10, 11):
		var t := center + fine * k
		var d: float = axis.call(t, r)
		if d < float(best[1]):
			best = [t, d]
	return best


## [points] sin los puntos que, quitados, no la apartan más de [tolerance] (Douglas-Peucker).
static func _simplify(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var a := points[0]
	var b := points[points.size() - 1]
	var worst := -1
	var far := tolerance
	for i in range(1, points.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(points[i], a, b).distance_to(points[i])
		if d > far:
			far = d
			worst = i
	if worst < 0:
		return PackedVector2Array([a, b])
	var head := _simplify(points.slice(0, worst + 1), tolerance)
	var tail := _simplify(points.slice(worst), tolerance)
	head.append_array(tail.slice(1))
	return head


## Lo que hay del tramo de [a] a [b] (empezando en [a]) a menos de [limit] del centro (m).
static func _inside(a: Vector2, b: Vector2, limit: float) -> float:
	if a.length() > limit:
		return 0.0
	if b.length() <= limit:
		return a.distance_to(b)
	# a + t (b - a) con |·| = limit: la raíz de después de a.
	var d := b - a
	var qa := d.dot(d)
	var qb := 2.0 * a.dot(d)
	var qc := a.dot(a) - limit * limit
	var t := (-qb + sqrt(maxf(0.0, qb * qb - 4.0 * qa * qc))) / (2.0 * qa)
	return a.distance_to(b) * clampf(t, 0.0, 1.0)


## Los puntos donde leer el suelo de la calle [way] (una línea en el plano): sus vértices y, entre ellos,
## cada STREET_SAMPLE m como mucho.
static func _way_samples(way: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in way.size() - 1:
		var a := way[i]
		var b := way[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / STREET_SAMPLE))
		for k in steps:
			out.append(a.lerp(b, float(k) / steps))
	out.append(way[way.size() - 1])
	return out


## La cerca de [template] alrededor de las construcciones ([rects], en el plano del poblado de centro
## [c]): la envolvente convexa de sus huellas y de la plaza, apartada WALL_GAP m, con un vértice cada
## 360 / WALL_SEGMENTS grados y algo ondulada para que no parezca trazada a compás. {"kind", "points":
## los vértices en el suelo (marco del terreno, en orden y cerrando la vuelta), "open": por tramo, 0
## cerca, 1 puerta, 2 sin suelo}. Lleva puerta donde la cruza una senda y donde llega la del poblado.
static func _wall(template: SettlementTemplate, c: Vector3, right: Vector3, fwd: Vector3, rects: Array,
		ground: Callable, trail_distance: Callable, cfg: Dictionary, gates: Array = [], arrival := true) -> Dictionary:
	var radius := float(cfg.radius)
	var n := WALL_SEGMENTS
	var cloud := PackedVector2Array()
	for rect: Array in rects:
		for q: Vector2 in rect:
			for k in 8:
				cloud.append(q + Vector2.from_angle(TAU * k / 8.0) * WALL_GAP)
	for k in 24:
		cloud.append(Vector2.from_angle(TAU * k / 24.0) * (template.plaza_radius + 2.0 + WALL_GAP))
	var hull := Geometry2D.convex_hull(cloud)
	var phase := fposmod(c.x * 7919.0 + c.z * 104729.0, TAU)
	var points := PackedVector3Array()
	var dirs: Array[Vector3] = []
	var dry := PackedByteArray()
	for j in n:
		var theta := TAU * j / n
		var ray := Vector2(sin(theta), cos(theta))
		var r := 0.0
		for i in hull.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(Vector2.ZERO, ray * 1000.0, hull[i], hull[i + 1])
			if hit != null:
				r = maxf(r, (hit as Vector2).length())
		r *= 1.0 + 0.03 * sin(3.0 * theta + phase) + 0.015 * sin(7.0 * theta + phase * 2.0)
		var dir := _at(c, right, fwd, r * ray.x, r * ray.y, radius)
		var g: float = ground.call(dir)
		var ok := not is_nan(g) and g >= float(cfg.sea_radius) + 1.0
		dry.append(1 if ok else 0)
		dirs.append(dir)
		points.append(dir * (g if ok else radius))
	var open := PackedByteArray()
	open.resize(n)
	for j in n:
		var k := (j + 1) % n
		if dry[j] == 0 or dry[k] == 0:
			open[j] = 2
		elif trail_distance.call((dirs[j] + dirs[k]).normalized()) < WALL_GATE_TRAIL:
			open[j] = 1
	# La llegada de la senda, por detrás (rumbo PI), siempre con puerta (si [arrival]), y donde acaba cada
	# calle ([gates]).
	var bearings: Array = [PI] if arrival else []
	bearings.append_array(gates)
	for bearing: float in bearings:
		var at := roundi(fposmod(bearing, TAU) / TAU * n)
		for k in range(-WALL_GATE_SPAN / 2, WALL_GATE_SPAN - WALL_GATE_SPAN / 2):
			var j := posmod(at + k, n)
			if open[j] == 0:
				open[j] = 1
	# Ninguna puerta más estrecha que WALL_GATE_MIN: se abre el tramo de al lado.
	for j in n:
		if open[j] != 1 or open[posmod(j - 1, n)] == 1:
			continue
		var k := j
		var width := 0.0
		while open[k % n] == 1 and k - j < n:
			width += points[k % n].distance_to(points[(k + 1) % n])
			k += 1
		if width < WALL_GATE_MIN and open[k % n] == 0:
			open[k % n] = 1
	var wall := {"kind": template.wall, "points": points, "open": open}
	if template.wall == &"palisade":
		_guard_posts(wall, c * float(ground.call(c)), ground, cfg)
	return wall


## Los guardias de la empalizada [wall]: dos puestos por puerta, por dentro a cada lado, mirando fuera
## (wall.posts, como los sitios de trabajo de _workplace, de kind &"guard"); y la ronda (wall.patrol): los
## vértices de los tramos con cerca, metidos WALL_PATROL_IN m hacia el centro [center], uno de cada tres.
static func _guard_posts(wall: Dictionary, center: Vector3, ground: Callable, cfg: Dictionary) -> void:
	var points: PackedVector3Array = wall.points
	var open: PackedByteArray = wall.open
	var n := points.size()
	var posts: Array = []
	for j in n:
		if open[j] != 1 or open[posmod(j - 1, n)] == 1:
			continue
		var k := j
		while open[k % n] == 1 and k - j < n:
			k += 1
		if open[k % n] != 0 or open[posmod(j - 1, n)] != 0:
			continue
		var a := points[j]
		var b := points[k % n]
		var mid := (a + b) * 0.5
		var up := mid.normalized()
		var inward := (center - mid).slide(up).normalized()
		var along := (b - a).slide(up)
		var half := along.length() * 0.5
		along = along.normalized()
		var stands := PackedVector3Array()
		var looks := PackedVector3Array()
		for side: float in [-1.0, 1.0]:
			var stand := _grounded(mid + inward * WALL_POST_IN + along * side * (half + 0.8), ground, cfg)
			if not stand.is_finite():
				continue
			stands.append(stand)
			looks.append(stand - inward * 4.0)
		if not stands.is_empty():
			posts.append({"kind": &"guard", "pose": Transform3D(Basis(along, up, along.cross(up)), mid),
				"stands": stands, "looks": looks, "plants": PackedVector3Array(), "indoor": false})
	var patrol := PackedVector3Array()
	for j in range(0, n, 3):
		if open[j] != 0:
			continue
		var p := points[j]
		var at := _grounded(p + (center - p).slide(p.normalized()).normalized() * WALL_PATROL_IN, ground, cfg)
		if at.is_finite():
			patrol.append(at)
	wall.posts = posts
	wall.patrol = patrol


## La huella de [prefab] girada con la puerta a +Z: la caja de su blueprint en ese giro, alargada por
## delante lo que pueda ocupar la rampa. {"rot": giro del blueprint a ese marco, "x0", "x1", "z0", "z1"}.
static func _shape(prefab: SettlementPrefab, m: Dictionary) -> Dictionary:
	var door := Vector3(prefab.door)
	var rot := Basis(Vector3.UP, -atan2(door.x, door.z))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var bmin: Vector3 = m.min
	var bmax: Vector3 = m.max
	for corner: Vector3 in [Vector3(bmin.x, 0, bmin.z), Vector3(bmax.x, 0, bmin.z), Vector3(bmin.x, 0, bmax.z),
			Vector3(bmax.x, 0, bmax.z)]:
		var q: Vector3 = rot * corner
		lo = lo.min(Vector2(q.x, q.z))
		hi = hi.max(Vector2(q.x, q.z))
	# El cuerpo, sin el decorado ni los sitios de trabajo de fuera: lo que no puede pisar una calle.
	var body := -INF
	var bmin_body: Vector3 = m.get("body_min", bmin)
	var bmax_body: Vector3 = m.get("body_max", bmax)
	for corner: Vector3 in [Vector3(bmin_body.x, 0, bmin_body.z), Vector3(bmax_body.x, 0, bmin_body.z),
			Vector3(bmin_body.x, 0, bmax_body.z), Vector3(bmax_body.x, 0, bmax_body.z)]:
		body = maxf(body, (rot * corner).z)
	# La rampa sale de la celda de delante de la puerta, que ya está bajo el alero.
	var door_front := rot * (_cell_center(prefab.door_cell, m.cell) + door * float(m.cell))
	hi.y = maxf(hi.y, door_front.z + float(m.cell) * (MAX_RAMP - 0.5))
	return {"rot": rot, "x0": lo.x, "x1": hi.x, "z0": lo.y, "z1": hi.y, "body": body,
		"door_z": door_front.z - float(m.cell) * 0.5}


## Intenta poner [prefab] con el centro de su huella a [r] m del centro [c] del poblado (con el suelo a
## [ground_r] del centro del planeta) en el ángulo [theta] (0 = de frente, hacia [fwd]) y la puerta
## hacia el centro, girada [jitter]. {"rect": sus esquinas en el plano del poblado, "building"} o {}
## si no cabe.
static func _try(prefab: SettlementPrefab, m: Dictionary, shape: Dictionary, c: Vector3, right: Vector3,
		fwd: Vector3, ground_r: float, theta: float, r: float, jitter: float, rects: Array, ground: Callable,
		trail_distance: Callable, cfg: Dictionary) -> Dictionary:
	var out := Vector2(sin(theta), cos(theta))
	# La puerta (+Z de la huella girada) hacia el centro.
	return _place(prefab, m, shape, c, right, fwd, ground_r, out * r, (-out).rotated(jitter), rects, ground,
		trail_distance, cfg)


## La huella de [prefab] en la villa: la de _shape, pero por delante solo hasta el borde de la calle (la
## rampa, si hace falta, baja a la calle, y la calle no se reserva).
static func _street_shape(prefab: SettlementPrefab, m: Dictionary) -> Dictionary:
	var shape := _shape(prefab, m)
	shape.z1 = minf(float(shape.z1), maxf(float(shape.body), float(shape.door_z) + STREET_SETBACK))
	return shape


## Intenta poner [prefab] con el centro de su huella en [pc] (m en el plano del poblado: x a [right], y a
## [fwd]) y su puerta mirando a [w] (unitario). [corridors]: las calles ([a, b, medio ancho]), por las que
## no puede ir el cuerpo de la construcción (la rampa sí). Con calles, las sendas solo se miran bajo el
## cuerpo: la de llegada es la calle de entrada. {"rect", "building"} o {} si no cabe.
static func _place(prefab: SettlementPrefab, m: Dictionary, shape: Dictionary, c: Vector3, right: Vector3,
		fwd: Vector3, ground_r: float, pc: Vector2, w: Vector2, rects: Array, ground: Callable,
		trail_distance: Callable, cfg: Dictionary, corridors: Array = []) -> Dictionary:
	var radius := float(cfg.radius)
	var cell := float(m.cell)
	# +X de la huella, a la derecha de la puerta (arriba × +Z).
	var wx := Vector2(w.y, -w.x)
	var cx := (float(shape.x0) + float(shape.x1)) * 0.5
	var cz := (float(shape.z0) + float(shape.z1)) * 0.5
	var rect: Array[Vector2] = []
	for q: Vector2 in [Vector2(shape.x0, shape.z0), Vector2(shape.x1, shape.z0), Vector2(shape.x1, shape.z1),
			Vector2(shape.x0, shape.z1)]:
		rect.append(pc + wx * (q.x - cx) + w * (q.y - cz))
	for i in rects.size():
		if _overlap(rect, rects[i], SPACING):
			return {}
	var body: Array[Vector2] = []
	for q: Vector2 in [Vector2(shape.x0, shape.z0), Vector2(shape.x1, shape.z0), Vector2(shape.x1, shape.body),
			Vector2(shape.x0, shape.body)]:
		body.append(pc + wx * (q.x - cx) + w * (q.y - cz))
	var outline: Array[Vector2] = rect if corridors.is_empty() else body
	var probes: Array[Vector2] = [(outline[0] + outline[2]) * 0.5]
	for i in 4:
		probes.append(outline[i])
		probes.append((outline[i] + outline[(i + 1) % 4]) * 0.5)
	var gap := TRAIL_GAP if corridors.is_empty() else STREET_TRAIL_GAP
	for q in probes:
		if trail_distance.call(_at(c, right, fwd, q.x, q.y, radius)) < gap:
			return {}
	for street: Array in corridors:
		for q in probes:
			if Geometry2D.get_closest_point_to_segment(q, street[0], street[1]).distance_to(q) < float(street[2]) + 0.3:
				return {}

	# El marco de la construcción, con su arriba en su propio centro.
	var up := _at(c, right, fwd, pc.x, pc.y, radius)
	var fw := (right * w.x + fwd * w.y).slide(up).normalized()
	var rw := up.cross(fw).normalized()
	var rot: Basis = shape.rot
	var basis := Basis(rw, up, fw) * rot
	var floor_y := int(m.floor_y)
	var base := up * ground_r
	var origin := base - (rw * cx + up * (floor_y * cell) + fw * cz)

	# El suelo bajo la huella, en una rejilla sobre las celdas del suelo (alturas sobre el plano de base).
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for f: Vector2i in m.floor:
		lo = lo.min(f)
		hi = hi.max(f)
	var span := Vector2(hi - lo + Vector2i.ONE) * cell
	var nx := maxi(2, ceili(span.x / SAMPLE_STEP) + 1)
	var nz := maxi(2, ceili(span.y / SAMPLE_STEP) + 1)
	var grid := PackedFloat32Array()
	var floor_m := float(floor_y) * cell
	for iz in nz:
		for ix in nx:
			var p := Vector3(lo.x * cell + span.x * ix / (nx - 1), floor_m, lo.y * cell + span.y * iz / (nz - 1))
			var h := _height_at(origin + basis * p, up, base, ground, cfg)
			if is_nan(h):
				return {}
			grid.append(h)
	var top := grid[0]
	var bottom := grid[0]
	for h in grid:
		top = maxf(top, h)
		bottom = minf(bottom, h)
	if top - bottom > maxf(float(cfg.max_step), float(cfg.get("max_grade", 0.0)) * maxf(span.x, span.y)):
		return {}
	# Sube el plano de base para que la cara de arriba del suelo quede MARGIN sobre lo más alto.
	var lift := top + MARGIN - cell
	origin += up * lift
	var extra := PackedInt32Array()
	for f: Vector2i in m.floor:
		var g := _bilinear(grid, nx, nz, (Vector2(f) + Vector2(0.5, 0.5)) * cell - Vector2(lo) * cell, span)
		_fill(extra, Vector3i(f.x, floor_y - 1, f.y), lift - g, cell)

	# La rampa: desde la celda de delante de la puerta, una por cada celda que haya que bajar.
	var door := Vector3i(prefab.door)
	var step := Vector3i(door.x, 0, door.z)
	var quarter := posmod(roundi(atan2(-door.x, -door.z) / (PI * 0.5)), 4)
	var front := Vector3i(prefab.door_cell.x, floor_y, prefab.door_cell.y) + step
	var walk := lift + cell
	for k in MAX_RAMP + 1:
		var at := front + step * k
		var g := _height_at(origin + basis * ((Vector3(at) + Vector3(0.5, 0.0, 0.5)) * cell), up, base,
			ground, cfg)
		if is_nan(g):
			return {}
		var foot := walk - k * cell
		if g >= foot - STEP_OK:
			break
		if k == MAX_RAMP:
			return {}
		var ramp := at - Vector3i(0, k, 0)
		extra.append_array([ramp.x, ramp.y, ramp.z, _RAMP_BLOCK, quarter])
		# Bajo la rampa, piedra hasta el suelo: su cara de abajo está a foot - cell del plano de base.
		_fill(extra, ramp - Vector3i(0, 1, 0), foot - cell - g, cell)

	var door_point := origin + basis * ((Vector3(prefab.door_cell.x, floor_y + 1, prefab.door_cell.y)
		+ Vector3(0.5, 0.0, 0.5)) * cell)
	var work: Array = []
	for wp in prefab.workplaces:
		var placed := _workplace(wp, Transform3D(basis, origin), ground, cfg)
		if not placed.is_empty():
			work.append(placed)
	var props: Array = []
	for prop in prefab.props:
		var at := Transform3D(basis, origin) * prop.pose
		if prop.grounded:
			at.origin = _grounded(at.origin, ground, cfg)
			if not at.origin.is_finite():
				continue
		var placed_prop := {"kind": prop.kind, "pose": at, "item": prop.item, "scale": prop.scale}
		if prop.kind == &"pen":
			# El contorno de la cerca en el suelo, un poste cada PEN_STEP m como mucho.
			var fence := PackedVector3Array()
			var half := prop.size * 0.5
			var corners: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y),
				Vector2(-half.x, half.y)]
			for i in 4:
				var a := corners[i]
				var b := corners[(i + 1) % 4]
				var steps := maxi(1, ceili(a.distance_to(b) / PEN_STEP))
				for k in steps:
					var q := a.lerp(b, float(k) / steps)
					var g := _grounded(at * Vector3(q.x, 0.0, q.y), ground, cfg)
					fence.append(g if g.is_finite() else at * Vector3(q.x, 0.0, q.y))
			placed_prop.outline = fence
			placed_prop.size = prop.size
			placed_prop.animals = prop.animals
		props.append(placed_prop)
	return {"rect": rect, "building": {"prefab": prefab.id, "kind": prefab.kind, "origin": origin,
		"basis": basis, "door": door_point, "extra": extra, "work": work, "props": props}}


## [wp] en la construcción puesta en [pose] (su grid principal): lo de fuera, asentado en el terreno.
## {"kind", "pose" (su origen en el suelo), "stands", "looks", "plants" (las matas de un huerto, en el
## suelo)}, todo en el marco del terreno, o {} si fuera no hay suelo.
static func _workplace(wp: SettlementWorkplace, pose: Transform3D, ground: Callable, cfg: Dictionary) -> Dictionary:
	var at := pose * wp.pose
	var stands := PackedVector3Array()
	var looks := PackedVector3Array()
	var plants := PackedVector3Array()
	if not wp.indoor:
		at.origin = _grounded(at.origin, ground, cfg)
		if not at.origin.is_finite():
			return {}
	for i in wp.stands.size():
		var stand := at * wp.stands[i]
		if not wp.indoor:
			stand = _grounded(stand, ground, cfg)
			if not stand.is_finite():
				return {}
		stands.append(stand)
		looks.append(at * (wp.looks[i] if i < wp.looks.size() else Vector3.ZERO))
	if wp.kind == &"garden" and not wp.indoor:
		# El suelo en 3 × 3 puntos y cada mata a su altura entre ellos (leer el suelo es lo caro).
		var half := wp.size * 0.5
		var corners := PackedFloat32Array()
		for iz in 3:
			for ix in 3:
				var q := at * Vector3(lerpf(-half.x, half.x, ix * 0.5), 0.0, lerpf(-half.y, half.y, iz * 0.5))
				var g := _grounded(q, ground, cfg)
				if not g.is_finite():
					return {}
				corners.append((g - at.origin).dot(at.basis.y))
		var rows := maxi(1, floori(wp.size.y / GARDEN_ROW))
		var per_row := maxi(1, floori(wp.size.x / GARDEN_PLANT))
		for row in rows:
			var z := -half.y + (row + 0.5) * wp.size.y / rows
			for k in per_row:
				var x := -half.x + (k + 0.5) * wp.size.x / per_row
				var h := _bilinear(corners, 3, 3, Vector2(x + half.x, z + half.y), wp.size)
				plants.append(at * Vector3(x, h, z))
	return {"kind": wp.kind, "pose": at, "stands": stands, "looks": looks, "plants": plants, "indoor": wp.indoor}


## [p] (marco del terreno) bajado o subido al suelo, o un vector no finito si ahí no hay (o es mar).
static func _grounded(p: Vector3, ground: Callable, cfg: Dictionary) -> Vector3:
	var d := p.normalized()
	var g: float = ground.call(d)
	if is_nan(g) or g < float(cfg.sea_radius) + 1.0:
		return Vector3.INF
	return d * g


## Apila hacia abajo desde [top_cell] los cubos que hacen falta para cubrir [gap] m (lo que hay de la cara
## de abajo de la celda de encima hasta el terreno) y EMBED más.
static func _fill(extra: PackedInt32Array, top_cell: Vector3i, gap: float, cell: float) -> void:
	var n := ceili((gap + EMBED) / cell)
	for k in n:
		extra.append_array([top_cell.x, top_cell.y - k, top_cell.z, _CUBE_BLOCK, 0])


## Altura del terreno sobre el plano que pasa por [base] perpendicular a [up], en la vertical del punto
## [p]; NAN si no hay suelo o está bajo el mar.
static func _height_at(p: Vector3, up: Vector3, base: Vector3, ground: Callable, cfg: Dictionary) -> float:
	var d := p.normalized()
	var g: float = ground.call(d)
	if is_nan(g) or g < float(cfg.sea_radius) + 1.0:
		return NAN
	return (d * g - base).dot(up)


## Radios del suelo en [c] y a [reach] m delante, detrás y a los lados; [] si falta alguno.
static func _heights(c: Vector3, right: Vector3, fwd: Vector3, reach: float, ground: Callable,
		radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for q: Vector2 in [Vector2.ZERO, Vector2(reach, 0), Vector2(-reach, 0), Vector2(0, reach), Vector2(0, -reach)]:
		var g: float = ground.call(_at(c, right, fwd, q.x, q.y, radius))
		if is_nan(g):
			return PackedFloat32Array()
		out.append(g)
	return out


## La dirección a [u] m hacia [right] y [v] m hacia [fwd] de [c], en un planeta de [radius].
static func _at(c: Vector3, right: Vector3, fwd: Vector3, u: float, v: float, radius: float) -> Vector3:
	return (c * radius + right * u + fwd * v).normalized()


static func _cell_center(cell: Vector2i, size: float) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * size


## Interpolación de la rejilla [nx] × [nz] que cubre [span] (m) en el punto [p] (m desde su esquina).
static func _bilinear(grid: PackedFloat32Array, nx: int, nz: int, p: Vector2, span: Vector2) -> float:
	var fx := clampf(p.x / span.x, 0.0, 1.0) * (nx - 1)
	var fz := clampf(p.y / span.y, 0.0, 1.0) * (nz - 1)
	var ix := mini(int(fx), nx - 2)
	var iz := mini(int(fz), nz - 2)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(grid[iz * nx + ix], grid[iz * nx + ix + 1], tx)
	var b := lerpf(grid[(iz + 1) * nx + ix], grid[(iz + 1) * nx + ix + 1], tx)
	return lerpf(a, b, tz)


## Si los rectángulos [a] y [b] (esquinas en orden) están a menos de [gap] m: ejes separadores de los
## dos, con la holgura.
static func _overlap(a: Array, b: Array, gap: float) -> bool:
	for poly in [a, b]:
		for i in 4:
			var edge: Vector2 = poly[(i + 1) % 4] - poly[i]
			var n := Vector2(-edge.y, edge.x).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for p: Vector2 in a:
				amin = minf(amin, p.dot(n))
				amax = maxf(amax, p.dot(n))
			for p: Vector2 in b:
				bmin = minf(bmin, p.dot(n))
				bmax = maxf(bmax, p.dot(n))
			if amax + gap <= bmin or bmax + gap <= amin:
				return false
	return true
