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
##  "work": sus sitios de trabajo (_workplace)}]}
static func plan(template: SettlementTemplate, center: Dictionary, into: Vector3, measures: Dictionary,
		ground: Callable, trail_distance: Callable, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var radius := float(cfg.radius)
	var c: Vector3 = center.dir
	var fwd := into.slide(c).normalized()
	var right := c.cross(fwd).normalized()
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
	return {"template": template.id, "center": c, "ground": float(center.ground), "into": fwd,
		"extent": extent, "buildings": placed}


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
	# La rampa sale de la celda de delante de la puerta, que ya está bajo el alero.
	var door_front := rot * (_cell_center(prefab.door_cell, m.cell) + door * float(m.cell))
	hi.y = maxf(hi.y, door_front.z + float(m.cell) * (MAX_RAMP - 0.5))
	return {"rot": rot, "x0": lo.x, "x1": hi.x, "z0": lo.y, "z1": hi.y}


## Intenta poner [prefab] con el centro de su huella a [r] m del centro [c] del poblado (con el suelo a
## [ground_r] del centro del planeta) en el ángulo [theta] (0 = de frente, hacia [fwd]) y la puerta
## hacia el centro, girada [jitter]. {"rect": sus esquinas en el plano del poblado, "building"} o {}
## si no cabe.
static func _try(prefab: SettlementPrefab, m: Dictionary, shape: Dictionary, c: Vector3, right: Vector3,
		fwd: Vector3, ground_r: float, theta: float, r: float, jitter: float, rects: Array, ground: Callable,
		trail_distance: Callable, cfg: Dictionary) -> Dictionary:
	var radius := float(cfg.radius)
	var cell := float(m.cell)
	var out := Vector2(sin(theta), cos(theta))
	var pc := out * r
	# La puerta (+Z de la huella girada) hacia el centro; +X de la huella, a su derecha (arriba × +Z).
	var w := (-out).rotated(jitter)
	var wx := Vector2(w.y, -w.x)
	var cx := (float(shape.x0) + float(shape.x1)) * 0.5
	var cz := (float(shape.z0) + float(shape.z1)) * 0.5
	var rect: Array[Vector2] = []
	for q: Vector2 in [Vector2(shape.x0, shape.z0), Vector2(shape.x1, shape.z0), Vector2(shape.x1, shape.z1),
			Vector2(shape.x0, shape.z1)]:
		rect.append(pc + wx * (q.x - cx) + w * (q.y - cz))
	for other: Array in rects:
		if _overlap(rect, other, SPACING):
			return {}
	var probes: Array[Vector2] = [pc]
	for i in 4:
		probes.append(rect[i])
		probes.append((rect[i] + rect[(i + 1) % 4]) * 0.5)
	for q in probes:
		if trail_distance.call(_at(c, right, fwd, q.x, q.y, radius)) < TRAIL_GAP:
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
	return {"rect": rect, "building": {"prefab": prefab.id, "kind": prefab.kind, "origin": origin,
		"basis": basis, "door": door_point, "extra": extra, "work": work}}


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
	return {"kind": wp.kind, "pose": at, "stands": stands, "looks": looks, "plants": plants}


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
