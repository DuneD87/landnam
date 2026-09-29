class_name SeaIceLayout extends RefCounted

## Reparto determinista de la banquisa: témpanos e icebergs salen de un hash de su celda, así que
## siempre están en el mismo sitio sin guardar nada, y la CPU (mallas, colisiones) y el shader del
## agua (la banquisa lejana, dibujada) ven los mismos.
##
## Témpanos: las celdas de Voronoi 3D de ice_cells() en water_shader.gdshader (misma rejilla, mismo
## hash, mismo umbral por celda), cortadas por el plano tangente al mar. El corte de un Voronoi 3D
## por un plano es un diagrama de potencias de los sitios proyectados, así que cada témpano es un
## polígono convexo exacto: se recorta un cuadrado con los semiplanos de los sitios vecinos.
##
## Todo aquí es estático y sin estado: lo llaman los hilos que construyen las mallas.

## Desplazamiento máximo del sitio dentro de su celda (ice_cells: * 0.9).
const JITTER := 0.9
## Celdas por lado de un bloque de mallas.
const CHUNK_CELLS := 4
## Grietas: ancho de ice_crack_width en el shader del agua, y canal abierto entre témpanos sueltos.
const CRACK := 0.35
## Por debajo de este hielo los témpanos se parten en trozos (borde de la banquisa, oleaje).
const BREAK_ICE := 0.55
## Achaflanado de las esquinas del polígono (fracción de la arista, con tope en metros).
const CHAMFER := 0.2
const CHAMFER_MAX := 1.4
## Aristas irregulares: tramos de este largo, metidos hasta ROUGH_DEPTH metros.
const ROUGH_STEP := 4.5
const ROUGH_DEPTH := 1.3
## Fondo mínimo del mapa bajo un témpano: en la orilla, con el mapa grueso, se quedaría varado
## atravesando la playa.
const MIN_DEPTH := 1.5

## Icebergs: una celda de ICEBERG_CELL metros puede tener uno.
const ICEBERG_CELL := 700.0
const ICEBERG_CHANCE := 0.4
## Grados de latitud que se adelantan al hielo marino: salen también en el mar abierto frente a la
## banquisa, a la deriva.
const ICEBERG_REACH := 5.0


## Réplica de ice_hash() de water_shader.gdshader.
static func ice_hash(p: Vector3) -> float:
	p = _fract3(p * 0.1031)
	var d := p.dot(Vector3(p.z, p.y, p.x) + Vector3(31.32, 31.32, 31.32))
	p += Vector3(d, d, d)
	var v := (p.x + p.y) * p.z
	return v - floorf(v)


static func _fract3(p: Vector3) -> Vector3:
	return p - p.floor()


## Sitio de Voronoi de la celda `c` (posición relativa al centro del planeta).
static func site(c: Vector3i, size: float) -> Vector3:
	var cf := Vector3(c)
	return (cf + Vector3(ice_hash(cf), ice_hash(cf + Vector3(17.1, 17.1, 17.1)),
		ice_hash(cf + Vector3(31.7, 31.7, 31.7))) * JITTER) * size


## Azar de la celda (id en ice_cells): decide con cuánto hielo aparece su témpano.
static func cell_id(c: Vector3i) -> float:
	return ice_hash(Vector3(c) + Vector3(5.3, 5.3, 5.3))


## Marco tangente de un punto del planeta: up radial, u y w en el plano. El shader de los témpanos
## (sea_ice.gdshader) construye el mismo para la deriva: cambiar uno obliga a cambiar el otro.
static func frame(up: Vector3) -> Basis:
	var u := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
	return Basis(u, up, u.cross(up))


## Hielo marino en `local` (sobre el radio del mar). Réplica de ice en wave_context: sin mapa, solo
## latitud; con el campo de orilla, los lagos y la costa se adelantan.
static func ice_at(local: Vector3, map: PlanetWorldMap, shore_on: bool, params: Vector4) -> float:
	var shore := -1.0
	if shore_on and map != null:
		shore = 0.0
		if map.shore_waves_allowed_local(local):
			shore = absf(map.shore_sample_local(local).w)
	return ClimateField.sea_ice_with(local, shore, params)


## Témpanos de un bloque. Cada uno: {id (celda y trozo), center (en reposo, sobre el mar), basis (marco tangente),
## poly (PackedVector2Array en u/w, convexo, antihorario), top, bottom, radius, seed, ice}.
## `sample` resuelve lo que depende del mundo: {map, shore_on, params, radius, bergs}.
static func chunk_floes(key: Vector3i, size: float, sample: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sea_radius: float = sample.radius
	var map: PlanetWorldMap = sample.map
	var base := key * CHUNK_CELLS
	for x in CHUNK_CELLS:
		for y in CHUNK_CELLS:
			for z in CHUNK_CELLS:
				var c := base + Vector3i(x, y, z)
				var s := site(c, size)
				if absf(s.length() - sea_radius) > size * 1.6:
					continue
				var p0 := s.normalized() * sea_radius
				var basis := frame(p0.normalized())
				var lines := _cell_lines(c, s, p0, basis, size)
				var poly := _clip(_square(size * 2.5), lines, 0.0)
				if poly.size() < 3:
					continue
				var centroid := _centroid(poly)
				var at := p0 + basis.x * centroid.x + basis.z * centroid.y
				at = at.normalized() * sea_radius
				var ice := ice_at(at, map, sample.shore_on, sample.params)
				var threshold := 0.08 + cell_id(c) * 0.84
				var amount := smoothstep(threshold - 0.04, threshold + 0.04, ice)
				if amount < 0.03:
					continue
				if map != null and map.is_ready() and map.water_depth_local(at) < MIN_DEPTH:
					continue
				if _inside_berg(at, size, sample.bergs):
					continue
				# Canal entre témpanos: el mismo "lead" del shader del agua.
				var lead := lerpf(CRACK * 6.0 + 2.5, CRACK, smoothstep(0.85, 1.0, ice)) * 0.5
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(c)
				var pieces: Array[PackedVector2Array] = [_clip(_square(size * 2.5), lines, lead)]
				if pieces[0].size() < 3:
					continue
				if ice < BREAK_ICE:
					pieces = _break(pieces[0], rng, 1 + int(rng.randf() * 2.2 * (1.0 - ice / BREAK_ICE) + 0.5), lead)
				var scale := lerpf(0.4, 1.0, amount)
				var piece_index := 0
				for piece in pieces:
					piece_index += 1
					if piece.size() < 3:
						continue
					var pc := _centroid(piece)
					var shaped := PackedVector2Array()
					for v in piece:
						shaped.append(pc + (v - pc) * scale)
					shaped = _roughen(_chamfer(shaped), rng, lerpf(1.0, 0.25, smoothstep(0.8, 1.0, ice)))
					if _area(shaped) < 1.5:
						continue
					var radius := 0.0
					for v in shaped:
						radius = maxf(radius, v.distance_to(pc))
					var local_poly := PackedVector2Array()
					for v in shaped:
						local_poly.append(v - pc)
					var center := (p0 + basis.x * pc.x + basis.z * pc.y).normalized() * sea_radius
					# Francobordo: la banquisa vieja y cerrada es más gruesa que los trozos del borde.
					var top := lerpf(0.16, 0.42, rng.randf()) * lerpf(0.7, 1.0, smoothstep(0.3, 0.95, ice))
					out.append({
						"id": Vector4i(c.x, c.y, c.z, piece_index),
						"center": center,
						"basis": frame(center.normalized()),
						"poly": _reframe(local_poly, basis, frame(center.normalized())),
						"top": top,
						"bottom": -top * 4.5,
						"radius": radius,
						"seed": rng.randf(),
						"ice": ice,
					})
	return out


## Semiplanos de la celda `c` en el plano tangente por p0: a·(x, y) <= d. Cada vecino aporta su
## bisectriz (plano de los puntos equidistantes) cortada por el plano.
static func _cell_lines(c: Vector3i, s: Vector3, p0: Vector3, basis: Basis, size: float) -> Array[Vector3]:
	var lines: Array[Vector3] = []
	var reach := (size * 2.6) * (size * 2.6)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			for dz in range(-2, 3):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var n := site(c + Vector3i(dx, dy, dz), size)
				var d := n - s
				if d.length_squared() > reach:
					continue
				# |p - s|² <= |p - n|²  <=>  2 p·d <= d·(n + s); con p = p0 + x u + y w.
				var a := 2.0 * d.dot(basis.x)
				var b := 2.0 * d.dot(basis.z)
				var rhs := d.dot(n + s - 2.0 * p0)
				var l := sqrt(a * a + b * b)
				if l < 1e-6:
					continue
				lines.append(Vector3(a / l, b / l, rhs / l))
	return lines


static func _square(half: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])


## Sutherland-Hodgman contra todos los semiplanos, metidos `inset` metros hacia dentro.
static func _clip(poly: PackedVector2Array, lines: Array[Vector3], inset: float) -> PackedVector2Array:
	for line in lines:
		poly = _clip_line(poly, Vector2(line.x, line.y), line.z - inset)
		if poly.size() < 3:
			return PackedVector2Array()
	return poly


static func _clip_line(poly: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var da := n.dot(a) - d
		var db := n.dot(b) - d
		if da <= 0.0:
			out.append(a)
		if (da <= 0.0) != (db <= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


static func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		sum += poly[i].cross(poly[(i + 1) % poly.size()])
	return sum * 0.5


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var area := 0.0
	var acc := Vector2.ZERO
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var cr := a.cross(b)
		area += cr
		acc += (a + b) * cr
	if absf(area) < 1e-6:
		return poly[0]
	return acc / (3.0 * area)


## Parte un témpano en trozos con cortes rectos por cerca del centro, separados por un canal.
static func _break(poly: PackedVector2Array, rng: RandomNumberGenerator, cuts: int,
		gap: float) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [poly]
	for _i in cuts:
		var biggest := 0
		for j in pieces.size():
			if _area(pieces[j]) > _area(pieces[biggest]):
				biggest = j
		var target := pieces[biggest]
		var c := _centroid(target)
		var angle := rng.randf() * TAU
		var n := Vector2(cos(angle), sin(angle))
		var d := n.dot(c) + rng.randf_range(-0.2, 0.2) * sqrt(absf(_area(target)))
		var half := gap * 0.5 + 0.4
		var a := _clip_line(target, n, d - half)
		var b := _clip_line(target, -n, -d - half)
		# Un trozo más estrecho que el canal se quedaría sin mitades: se deja entero y no se corta más.
		if a.size() < 3 and b.size() < 3:
			break
		pieces.remove_at(biggest)
		for piece in [a, b]:
			if piece.size() >= 3:
				pieces.append(piece)
	return pieces


## Parte un témpano con cortes que pasan cerca de `through` (el punto de un golpe), separados por
## una grieta fina. Como _break, nunca deja la lista vacía.
static func _break_through(poly: PackedVector2Array, rng: RandomNumberGenerator, cuts: int,
		through: Vector2) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [poly]
	for _i in cuts:
		var best := 0
		var best_d := INF
		for j in pieces.size():
			var d := _centroid(pieces[j]).distance_to(through)
			if d < best_d:
				best_d = d
				best = j
		var target := pieces[best]
		# La grieta va del golpe hacia el centro del trozo, con algo de desvío.
		var dir := (_centroid(target) - through)
		if dir.length() < 0.1:
			dir = Vector2.from_angle(rng.randf() * TAU)
		dir = dir.normalized().rotated(rng.randf_range(-0.5, 0.5))
		var n := Vector2(-dir.y, dir.x)
		var d := n.dot(through)
		var a := _clip_line(target, n, d - 0.15)
		var b := _clip_line(target, -n, -d - 0.15)
		if a.size() < 3 or b.size() < 3:
			break
		pieces.remove_at(best)
		pieces.append(a)
		pieces.append(b)
	return pieces


## Cambia cada esquina por dos puntos sobre sus aristas: el témpano deja de ser un polígono de
## aristas vivas, como los de verdad, que se redondean al chocar.
static func _chamfer(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	for i in count:
		var prev := poly[(i - 1 + count) % count]
		var cur := poly[i]
		var next := poly[(i + 1) % count]
		var cut_a := minf(cur.distance_to(prev) * CHAMFER, CHAMFER_MAX)
		var cut_b := minf(cur.distance_to(next) * CHAMFER, CHAMFER_MAX)
		out.append(cur + (prev - cur).normalized() * cut_a)
		out.append(cur + (next - cur).normalized() * cut_b)
	return out


## Rompe las aristas largas en tramos y los mete hacia dentro a trozos (nunca hacia fuera: así no
## invaden al vecino): los témpanos de verdad no tienen cantos rectos de varios metros.
## `strength` baja en la banquisa cerrada, donde las placas encajan con grietas finas.
static func _roughen(poly: PackedVector2Array, rng: RandomNumberGenerator, strength: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		out.append(a)
		var length := a.distance_to(b)
		var steps := int(length / ROUGH_STEP)
		if steps < 2:
			continue
		var e := (b - a) / length
		var inward := Vector2(-e.y, e.x)
		var phase := rng.randf() * TAU
		var amp := minf(ROUGH_DEPTH, length * 0.06) * rng.randf_range(0.4, 1.0) * strength
		for k in range(1, steps):
			var t := float(k) / float(steps)
			# Nulo en las esquinas; entre medias, ondulación con algo de azar.
			var bump := sin(t * PI) * (0.55 + 0.45 * sin(phase + t * 7.0)) * rng.randf_range(0.5, 1.0)
			out.append(a.lerp(b, t) + inward * amp * bump)
	return out


## Pasa un polígono del marco de su sitio al de su propio centro (difieren unos milímetros de
## curvatura; así el shader, que solo conoce el centro, reconstruye el mismo marco).
static func _reframe(poly: PackedVector2Array, from: Basis, to: Basis) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		var p := from.x * v.x + from.z * v.y
		out.append(Vector2(p.dot(to.x), p.dot(to.z)))
	return out


static func _inside_berg(at: Vector3, size: float, bergs: Array) -> bool:
	for berg in bergs:
		var r: float = berg.radius * 1.25 + size * 0.5
		if at.distance_squared_to(berg.center) < r * r:
			return true
	return false


## Iceberg de una celda de ICEBERG_CELL, o {} si no hay. {center (sobre el mar), radius, height,
## draft, seed, kind (0 tabular, 1 cúpula)}.
static func cell_berg(c: Vector3i, sample: Dictionary) -> Dictionary:
	var cf := Vector3(c)
	var roll := ice_hash(cf * 1.37 + Vector3(3.1, 7.7, 1.9))
	if roll > ICEBERG_CHANCE:
		return {}
	var sea_radius: float = sample.radius
	var p := (cf + Vector3(ice_hash(cf + Vector3(2.3, 2.3, 2.3)), ice_hash(cf + Vector3(9.1, 9.1, 9.1)),
		ice_hash(cf + Vector3(13.7, 13.7, 13.7))) * 0.8 + Vector3(0.1, 0.1, 0.1)) * ICEBERG_CELL
	# Solo los puntos a media celda del mar: a lo largo de la vertical cabe una celda, así que la
	# densidad es la misma en todo el planeta.
	if absf(p.length() - sea_radius) > ICEBERG_CELL * 0.5:
		return {}
	var center := p.normalized() * sea_radius
	var params: Vector4 = sample.params
	var reach := Vector4(params.x - ICEBERG_REACH, params.y, params.z, params.w)
	var zone := ice_at(center, sample.map, sample.shore_on, reach)
	if zone < 0.15 or roll > ICEBERG_CHANCE * zone:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) ^ 0x5bd1e995
	var kind := 0 if rng.randf() < 0.6 else 1
	var radius := rng.randf_range(14.0, 46.0)
	var height := radius * (rng.randf_range(0.28, 0.45) if kind == 0 else rng.randf_range(0.55, 0.9))
	var draft := height * 2.2
	var map: PlanetWorldMap = sample.map
	if map != null and map.is_ready() and map.water_depth_local(center) < draft * 0.6:
		return {}
	return {
		"center": center, "radius": radius, "height": height, "draft": draft,
		"seed": rng.randi(), "kind": kind,
	}
