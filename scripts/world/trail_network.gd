class_name TrailNetwork extends RefCounted

## Sendas del mundo trazadas sobre el relieve: puntos de paso repartidos por tierra firme y unidos por
## el camino que menos cuesta andar. La pendiente encarece cada celda, el mar no se cruza y un cauce
## solo por un vado caro. Las sendas que se trazan después aprovechan las de antes (lo pisado cuesta
## reuse_factor de lo que costaba), así se juntan en troncos y ramas en vez de correr paralelas.
##
## La rejilla es el relieve horneado con bake_sphere_bumpmap (convención acos con los centros de
## celda en +0,5, como el mapa de hidrología de los ríos). La búsqueda va en C++ (AStar3D, con las
## posiciones en 3D: la distancia entre celdas sale bien a cualquier latitud); en GDScript solo se
## monta la rejilla y se suavizan los trazos.
##
## Devuelve trazos: polilíneas de direcciones unitarias que siguen de largo por los cruces, con la otra
## senda del cruce acabando en ellos (ver _strokes). Es lo que TrailField reparte en capas.

## Vecinos hacia delante de cada celda: con los de atrás que pone la celda vecina, la vecindad de 8.
const _NX := [1, -1, 0, 1]
const _NY := [0, 1, 1, 1]
## Celdas que se recorre un brazo desde el cruce para saber hacia dónde sale.
const _ARM_STEPS := 3
## Dos brazos de un cruce siguen de largo como una sola senda si salen a más de unos 115°.
const _THROUGH_DOT := -0.4
## Paso del remuestreo para suavizar y del trazo final (m).
const _SMOOTH_STEP := 30.0
const _FINAL_STEP := 12.0


## Traza la red. [dem] son alturas normalizadas en [height_min, height_min + height_span] (m sobre el
## radio), [sea_height] la altura del mar sobre el radio y [rivers] la red de Planet.get_river_network().
## Devuelve {"strokes": Array[PackedVector3Array], "stats": {...}}.
static func build(dem: PackedFloat32Array, size: Vector2i, radius: float, height_min: float,
		height_span: float, sea_height: float, rivers: Dictionary, cfg: Dictionary) -> Dictionary:
	var w := size.x
	var h := size.y
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for i in w * h:
		heights[i] = height_min + dem[i] * height_span
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 1))

	var cost := _cell_costs(heights, _river_cells(rivers, w, h), w, h, radius, sea_height, cfg)
	var astar := _grid(cost, heights, w, h, radius)
	var anchors := _anchors(cost, heights, w, h, radius, float(cfg.get("anchor_spacing", 3000.0)), cfg, rng)
	var links := _links(anchors, w, h, radius, cfg, rng)
	var trodden := PackedByteArray()
	trodden.resize(w * h)
	var edges := {}
	_route(astar, cost, anchors, links, trodden, edges, cfg)
	var spurs := _spurs(astar, cost, heights, anchors, trodden, edges, w, h, radius, cfg, rng)
	var adj := _adjacency(edges, w * h)
	_drop_triangles(adj, w)
	var junctions := 0
	var ends := 0
	for cell: int in adj:
		var arms := (adj[cell] as Array).size()
		if arms > 2:
			junctions += 1
		elif arms == 1:
			ends += 1
	var strokes := _strokes(adj, w, h, radius)
	# El trazo que pasa de largo por cada cruce (la celda va por dentro de él).
	var through := {}
	for k in strokes.size():
		var cells: PackedInt64Array = strokes[k].cells
		for i in range(1, cells.size() - 1):
			if (adj[cells[i]] as Array).size() > 2:
				through[cells[i]] = k
	var lines: Array[PackedVector3Array] = []
	for k in strokes.size():
		lines.append(_smooth(strokes[k].points, radius, cfg, k))
	# El que pasa de largo se suaviza suelto, sin codo en el cruce, y el que llega se engancha luego a
	# él. Dos vueltas: el que pasa de largo puede llegar a su vez a otro cruce y moverse.
	for round_ in 2:
		for k in strokes.size():
			var cells: PackedInt64Array = strokes[k].cells
			var points: PackedVector3Array = (strokes[k].points as PackedVector3Array).duplicate()
			var moved := false
			for end in [0, cells.size() - 1]:
				var t: int = through.get(cells[end], -1)
				if t >= 0 and t != k:
					points[end] = _nearest_on(lines[t], points[end].normalized()) * radius
					moved = true
			if moved:
				lines[k] = _smooth(points, radius, cfg, k)
	var out: Array[PackedVector3Array] = []
	var length := 0.0
	for line in lines:
		if line.size() < 2:
			continue
		for i in line.size() - 1:
			length += line[i].distance_to(line[i + 1]) * radius
		out.append(line)
	return {"strokes": out, "stats": {"anchors": anchors.size(), "links": links.size(), "spurs": spurs,
		"strokes": out.size(), "junctions": junctions, "ends": ends, "km": length / 1000.0}}


## Coste de pisar cada celda (multiplica la distancia), o 0 si no se pisa: mar, más allá de
## max_latitude o más empinada que max_slope.
static func _cell_costs(heights: PackedFloat32Array, ford: PackedByteArray, w: int, h: int,
		radius: float, sea_height: float, cfg: Dictionary) -> PackedFloat32Array:
	var max_lat := deg_to_rad(float(cfg.get("max_latitude", 66.0)))
	var max_slope := float(cfg.get("max_slope", 0.6))
	var slope_cost := float(cfg.get("slope_cost", 30.0))
	var ford_cost := float(cfg.get("ford_cost", 10.0))
	var shore := sea_height + float(cfg.get("shore_margin", 1.5))
	var out := PackedFloat32Array()
	out.resize(w * h)
	var dy_m := PI * radius / h
	for y in h:
		var theta := (y + 0.5) / h * PI
		if absf(PI * 0.5 - theta) > max_lat:
			continue
		var dx_m := TAU * radius * sin(theta) / w
		var row := y * w
		var up := maxi(y - 1, 0) * w
		var down := mini(y + 1, h - 1) * w
		for x in w:
			var i := row + x
			if heights[i] <= shore:
				continue
			var gx := (heights[row + (x + 1) % w] - heights[row + (x + w - 1) % w]) / (2.0 * dx_m)
			var gy := (heights[down + x] - heights[up + x]) / (2.0 * dy_m)
			var s := sqrt(gx * gx + gy * gy)
			if s > max_slope:
				continue
			out[i] = (1.0 + slope_cost * s * s) * (ford_cost if ford[i] != 0 else 1.0)
	return out


## Celdas por las que pasa un cauce: la red de ríos va en la rejilla de hidrología, más gruesa.
static func _river_cells(rivers: Dictionary, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	var seg: PackedFloat32Array = rivers.get("seg", PackedFloat32Array())
	var hydro: Vector2i = rivers.get("hydro_size", Vector2i.ZERO)
	if seg.is_empty() or hydro.x <= 0 or hydro.y <= 0:
		return out
	var sx := float(w) / hydro.x
	var sy := float(h) / hydro.y
	for k in seg.size() / 8:
		var o := k * 8
		var ax := seg[o] * sx
		var ay := seg[o + 1] * sy
		var bx := seg[o + 2] * sx
		var by := seg[o + 3] * sy
		if bx - ax > w * 0.5:
			bx -= w
		elif ax - bx > w * 0.5:
			bx += w
		var steps := maxi(int(ceil(maxf(absf(bx - ax), absf(by - ay)) * 2.0)), 1)
		for s in steps + 1:
			var t := float(s) / steps
			var cx := posmod(int(floor(lerpf(ax, bx, t))), w)
			var cy := clampi(int(floor(lerpf(ay, by, t))), 0, h - 1)
			out[cy * w + cx] = 1
	return out


## La rejilla de AStar3D: un punto por celda pisable, a su altura, unido a sus 8 vecinas.
static func _grid(cost: PackedFloat32Array, heights: PackedFloat32Array, w: int, h: int,
		radius: float) -> AStar3D:
	var astar := AStar3D.new()
	var count := 0
	for c in cost:
		if c > 0.0:
			count += 1
	astar.reserve_space(count)
	for y in h:
		for x in w:
			var i := y * w + x
			if cost[i] > 0.0:
				astar.add_point(i, cell_dir(x + 0.5, y + 0.5, w, h) * (radius + heights[i]), cost[i])
	for y in h:
		for x in w:
			var i := y * w + x
			if cost[i] <= 0.0:
				continue
			for k in 4:
				var ny: int = y + _NY[k]
				if ny >= h:
					continue
				var j: int = ny * w + posmod(x + _NX[k], w)
				if cost[j] > 0.0:
					astar.connect_points(i, j)
	return astar


## Puntos de paso: una espiral de Fibonacci sobre la esfera con un punto cada [spacing] m, cada uno
## movido al azar y llevado a la celda más llana de alrededor que cumpla las alturas. Sale un reparto
## parejo, sin cuadrícula.
static func _anchors(cost: PackedFloat32Array, heights: PackedFloat32Array, w: int, h: int,
		radius: float, spacing: float, cfg: Dictionary, rng: RandomNumberGenerator) -> PackedInt32Array:
	var low := float(cfg.get("anchor_min_height", 2.0))
	var high := float(cfg.get("anchor_max_height", 450.0))
	var count := int(round(4.0 * PI * radius * radius / (spacing * spacing)))
	var golden := PI * (3.0 - sqrt(5.0))
	var out := PackedInt32Array()
	for k in count:
		var yk := 1.0 - 2.0 * (k + 0.5) / count
		var r := sqrt(maxf(1.0 - yk * yk, 0.0))
		var dir := Vector3(r * cos(golden * k), yk, r * sin(golden * k))
		var t1 := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := dir.cross(t1)
		dir = (dir * radius + (t1 * rng.randf_range(-0.35, 0.35) + t2 * rng.randf_range(-0.35, 0.35)) * spacing).normalized()
		var cell := cell_of(dir, w, h)
		var best := -1
		for dy in range(-2, 3):
			var y := cell.y + dy
			if y < 0 or y >= h:
				continue
			for dx in range(-2, 3):
				var i := y * w + posmod(cell.x + dx, w)
				if cost[i] > 0.0 and heights[i] >= low and heights[i] <= high and (best < 0 or cost[i] < cost[best]):
					best = i
		if best >= 0:
			out.append(best)
	return out


## Pares de puntos de paso a trazar, en orden: el árbol de expansión mínima de los vecinos a menos de
## link_radius × anchor_spacing (por distancia en línea recta), del más corto al más largo, y luego
## una parte (loop_fraction) de los demás pares, que cierran vueltas donde valga la pena.
static func _links(anchors: PackedInt32Array, w: int, h: int, radius: float, cfg: Dictionary,
		rng: RandomNumberGenerator) -> Array[Vector2i]:
	var reach := float(cfg.get("link_radius", 1.9)) * float(cfg.get("anchor_spacing", 3000.0))
	var loops := float(cfg.get("loop_fraction", 0.2))
	# La celda del hash va en unidades de la esfera unidad: lo que mide reach sobre el radio.
	var cell := reach / radius
	var dirs := _anchor_dirs(anchors, w, h)
	var grid := _hashed(dirs, cell)
	var pairs: Array = []
	for k in dirs.size():
		var key := Vector3i((dirs[k] / cell).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for j: int in grid.get(key + Vector3i(dx, dy, dz), []):
						if j > k:
							var dist := dirs[k].distance_to(dirs[j])
							if dist < cell:
								pairs.append([dist, k, j])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var parent := PackedInt32Array()
	parent.resize(anchors.size())
	for k in parent.size():
		parent[k] = k
	var tree: Array[Vector2i] = []
	var extra: Array[Vector2i] = []
	for p: Array in pairs:
		var ra := _find(parent, p[1])
		var rb := _find(parent, p[2])
		if ra != rb:
			parent[ra] = rb
			tree.append(Vector2i(p[1], p[2]))
		elif rng.randf() < loops:
			extra.append(Vector2i(p[1], p[2]))
	return tree + extra


static func _anchor_dirs(anchors: PackedInt32Array, w: int, h: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a in anchors:
		out.append(cell_dir((a % w) + 0.5, (a / w) + 0.5, w, h))
	return out


## {Vector3i: Array de índices de [dirs]} en cubos de lado [cell] (en la esfera unidad).
static func _hashed(dirs: Array[Vector3], cell: float) -> Dictionary:
	var grid := {}
	for k in dirs.size():
		var key := Vector3i((dirs[k] / cell).floor())
		if not grid.has(key):
			grid[key] = []
		grid[key].append(k)
	return grid


static func _find(parent: PackedInt32Array, k: int) -> int:
	while parent[k] != k:
		parent[k] = parent[parent[k]]
		k = parent[k]
	return k


## Traza los pares de [anchors] en orden, marcando lo pisado en [trodden] y las aristas en [edges].
static func _route(astar: AStar3D, cost: PackedFloat32Array, anchors: PackedInt32Array,
		links: Array[Vector2i], trodden: PackedByteArray, edges: Dictionary, cfg: Dictionary) -> void:
	for link in links:
		_trace(astar, cost, anchors[link.x], anchors[link.y], trodden, edges, cfg)


## Traza de la celda [a] a la [b] por donde menos cuesta y lo marca en [trodden] y [edges] ({clave:
## true}, clave de _edge_key); lo pisado pasa a costar reuse_factor de lo que costaba. Un trazado que
## rodea más de max_detour veces la línea recta se descarta: no merece una senda. Devuelve si se trazó.
static func _trace(astar: AStar3D, cost: PackedFloat32Array, a: int, b: int, trodden: PackedByteArray,
		edges: Dictionary, cfg: Dictionary) -> bool:
	var path := astar.get_id_path(a, b)
	if path.size() < 2:
		return false
	var length := 0.0
	for k in path.size() - 1:
		length += astar.get_point_position(path[k]).distance_to(astar.get_point_position(path[k + 1]))
	if length > float(cfg.get("max_detour", 2.2)) * astar.get_point_position(a).distance_to(astar.get_point_position(b)):
		return false
	var reuse := float(cfg.get("reuse_factor", 0.5))
	var n := trodden.size()
	for k in path.size():
		var c := path[k]
		if trodden[c] == 0:
			trodden[c] = 1
			astar.set_point_weight_scale(c, cost[c] * reuse)
		if k > 0:
			edges[_edge_key(path[k - 1], c, n)] = true
	return true


## Ramales: más puntos de paso, uno cada spur_spacing m, y los que quedan a más de spur_min_distance
## de lo ya pisado (ramales de antes incluidos) se unen al punto de paso de la red más cercano. Como lo
## pisado cuesta menos, el trazado se arrima a la senda en cuanto puede: sale un ramal que se aparta de
## ella y acaba en el punto. Sin spur_spacing no hay ramales. Devuelve cuántos se trazaron.
static func _spurs(astar: AStar3D, cost: PackedFloat32Array, heights: PackedFloat32Array,
		anchors: PackedInt32Array, trodden: PackedByteArray, edges: Dictionary, w: int, h: int,
		radius: float, cfg: Dictionary, rng: RandomNumberGenerator) -> int:
	var spacing := float(cfg.get("spur_spacing", 0.0))
	if spacing <= 0.0 or anchors.is_empty():
		return 0
	var gap := float(cfg.get("spur_min_distance", 600.0))
	var reach := float(cfg.get("link_radius", 1.9)) * float(cfg.get("anchor_spacing", 3000.0)) / radius
	var dirs := _anchor_dirs(anchors, w, h)
	var grid := _hashed(dirs, reach)
	var count := 0
	for p in _anchors(cost, heights, w, h, radius, spacing, cfg, rng):
		if _near(trodden, p, gap, w, h, radius):
			continue
		var d := cell_dir((p % w) + 0.5, (p / w) + 0.5, w, h)
		var key := Vector3i((d / reach).floor())
		var best := -1
		var best_dist := reach
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for j: int in grid.get(key + Vector3i(dx, dy, dz), []):
						var dist := d.distance_to(dirs[j])
						if dist < best_dist:
							best_dist = dist
							best = j
		if best >= 0 and _trace(astar, cost, p, anchors[best], trodden, edges, cfg):
			count += 1
	return count


## Si hay alguna celda pisada a menos de [gap] m de la celda [cell].
static func _near(trodden: PackedByteArray, cell: int, gap: float, w: int, h: int, radius: float) -> bool:
	var x0 := cell % w
	var y0 := cell / w
	var ry := ceilf(gap / (PI * radius / h))
	var rx := minf(ceilf(gap / maxf(TAU * radius * sin((y0 + 0.5) / h * PI) / w, 1.0)), w / 2)
	for dy in range(-int(ry), int(ry) + 1):
		var y := y0 + dy
		if y < 0 or y >= h:
			continue
		for dx in range(-int(rx), int(rx) + 1):
			if (dx / rx) * (dx / rx) + (dy / ry) * (dy / ry) <= 1.0 and trodden[y * w + posmod(x0 + dx, w)] != 0:
				return true
	return false


static func _edge_key(a: int, b: int, n: int) -> int:
	return mini(a, b) * n + maxi(a, b)


## {celda: Array de vecinas} de las aristas pisadas.
static func _adjacency(edges: Dictionary, n: int) -> Dictionary:
	var adj := {}
	for key: int in edges:
		var a := key / n
		var b := key % n
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		adj[a].append(b)
		adj[b].append(a)
	return adj


## Dos trazados que se cruzan en diagonal dejan triángulos de una celda (la diagonal y la ese de dos
## lados rectos): se quita la diagonal, que es la que sobra, y queda un codo.
static func _drop_triangles(adj: Dictionary, w: int) -> void:
	for a: int in adj.keys():
		var na: Array = adj[a]
		var k := 0
		while k < na.size():
			var b: int = na[k]
			var dropped := false
			if _diagonal(a, b, w):
				for c: int in na:
					if c != b and (adj[b] as Array).has(c):
						na.remove_at(k)
						(adj[b] as Array).erase(a)
						dropped = true
						break
			if not dropped:
				k += 1


static func _diagonal(a: int, b: int, w: int) -> bool:
	return a / w != b / w and a % w != b % w


## Los trazos de la red: en cada cruce los dos brazos que salen más enfrentados siguen de largo como un
## solo trazo (con cuatro brazos, dos parejas) y el resto acaba en él. Así cada cruce lo forman una
## senda que pasa y otra que llega, que es lo que TrailField necesita para repartirlas en dos capas.
## Devuelve [{"points": PackedVector3Array (en la esfera de radio [radius]), "cells": las celdas}].
static func _strokes(adj: Dictionary, w: int, h: int, radius: float) -> Array:
	# Brazos: clave (nodo, vecino) de los nodos que no son de paso.
	var pair := {}
	for node: int in adj:
		var arms: Array = adj[node]
		if arms.size() < 3:
			continue
		var up := cell_dir((node % w) + 0.5, (node / w) + 0.5, w, h)
		var dirs: Array[Vector3] = []
		for nb: int in arms:
			var far := _walk(adj, node, nb, _ARM_STEPS)
			dirs.append((cell_dir((far % w) + 0.5, (far / w) + 0.5, w, h) - up).slide(up).normalized())
		var free := range(arms.size())
		while free.size() >= 2:
			var best := Vector2i(-1, -1)
			var best_dot := _THROUGH_DOT
			for i in free.size():
				for j in range(i + 1, free.size()):
					var d := dirs[free[i]].dot(dirs[free[j]])
					if d < best_dot:
						best_dot = d
						best = Vector2i(free[i], free[j])
			if best.x < 0:
				break
			pair[Vector2i(node, arms[best.x])] = arms[best.y]
			pair[Vector2i(node, arms[best.y])] = arms[best.x]
			free.erase(best.x)
			free.erase(best.y)

	# Cadenas entre nodos que no son de paso; arm_chain[(nodo, vecino)] = cadena*2 + extremo.
	var chains: Array[PackedInt64Array] = []
	var arm_chain := {}
	var seen := {}
	for node: int in adj:
		if (adj[node] as Array).size() == 2:
			continue
		for nb: int in adj[node]:
			if seen.has(Vector2i(node, nb)):
				continue
			var chain := PackedInt64Array([node])
			var prev := node
			var cur: int = nb
			while true:
				chain.append(cur)
				seen[Vector2i(prev, cur)] = true
				seen[Vector2i(cur, prev)] = true
				var arms: Array = adj[cur]
				if arms.size() != 2 or cur == node:
					break
				var nxt: int = arms[0] if arms[0] != prev else arms[1]
				prev = cur
				cur = nxt
			var last := chain.size() - 1
			arm_chain[Vector2i(node, nb)] = chains.size() * 2
			arm_chain[Vector2i(chain[last], chain[last - 1])] = chains.size() * 2 + 1
			chains.append(chain)
	# Anillos sin cruces: se cortan por cualquier celda.
	for node: int in adj:
		if (adj[node] as Array).size() != 2 or seen.has(Vector2i(node, adj[node][0])):
			continue
		var chain := PackedInt64Array([node])
		var prev := node
		var cur: int = adj[node][0]
		seen[Vector2i(node, cur)] = true
		while cur != node:
			chain.append(cur)
			seen[Vector2i(cur, prev)] = true
			var arms: Array = adj[cur]
			var nxt: int = arms[0] if arms[0] != prev else arms[1]
			seen[Vector2i(cur, nxt)] = true
			prev = cur
			cur = nxt
		chain.append(node)
		chains.append(chain)

	# Trazos: se empieza por un extremo que no sigue en otro y se encadena por las parejas.
	var used := PackedByteArray()
	used.resize(chains.size())
	var out: Array = []
	for pass_ in 2:
		for c in chains.size():
			if used[c] != 0:
				continue
			var chain := chains[c]
			var reversed := false
			if pass_ == 0:
				# Primera pasada: solo trazos que empiezan en un extremo libre.
				if not pair.has(Vector2i(chain[0], chain[1])):
					reversed = false
				elif not pair.has(Vector2i(chain[chain.size() - 1], chain[chain.size() - 2])):
					reversed = true
				else:
					continue
			var cells := PackedInt64Array()
			var cur_c := c
			var rev := reversed
			while cur_c >= 0 and used[cur_c] == 0:
				used[cur_c] = 1
				var part := chains[cur_c].duplicate()
				if rev:
					part.reverse()
				if not cells.is_empty():
					part.remove_at(0)
				cells.append_array(part)
				var arm := Vector2i(cells[cells.size() - 1], cells[cells.size() - 2])
				cur_c = -1
				if pair.has(arm):
					var next_arm := Vector2i(arm.x, pair[arm])
					var owner: int = arm_chain.get(next_arm, -1)
					if owner >= 0:
						cur_c = owner / 2
						rev = owner % 2 == 1
			var points := PackedVector3Array()
			for cell in cells:
				points.append(cell_dir((cell % w) + 0.5, (cell / w) + 0.5, w, h) * radius)
			out.append({"points": points, "cells": cells})
	return out


## Celda a [steps] pasos de [node] saliendo por [nb], o la última antes de un cruce o un extremo.
static func _walk(adj: Dictionary, node: int, nb: int, steps: int) -> int:
	var prev := node
	var cur := nb
	for i in steps - 1:
		var arms: Array = adj[cur]
		if arms.size() != 2:
			break
		var nxt: int = arms[0] if arms[0] != prev else arms[1]
		prev = cur
		cur = nxt
	return cur


## Suaviza un trazo sin mover sus extremos y le da un serpenteo suave; lo devuelve remuestreado a
## _FINAL_STEP en direcciones unitarias. La curva mínima que deja (unos 200 m de radio) es la que la
## imagen del campo de sendas reproduce sin error apreciable (TrailField).
static func _smooth(points: PackedVector3Array, radius: float, cfg: Dictionary, noise_seed: int) -> PackedVector3Array:
	var pins := PackedByteArray()
	pins.resize(points.size())
	pins[0] = 1
	pins[pins.size() - 1] = 1
	var res := _resample(points, pins, _SMOOTH_STEP)
	var p: PackedVector3Array = res[0]
	var fixed: PackedByteArray = res[1]
	var sigma := float(cfg.get("smooth_sigma", 110.0))
	# Cada pasada (vecinos a 1/4, el punto a 1/2) suma paso²/2 a la varianza del suavizado.
	var passes := int(ceil(2.0 * sigma * sigma / (_SMOOTH_STEP * _SMOOTH_STEP)))
	for pass_ in passes:
		var prev := p.duplicate()
		for i in range(1, p.size() - 1):
			if fixed[i] == 0:
				p[i] = ((prev[i - 1] + prev[i] * 2.0 + prev[i + 1]) * 0.25).normalized() * radius

	# Serpenteo: un ruido 1D a lo largo, apagado cerca de los extremos para no despegarlos de sus cruces.
	var amplitude := float(cfg.get("meander_amplitude", 4.0))
	var wavelength := float(cfg.get("meander_wavelength", 180.0))
	if amplitude > 0.0 and p.size() > 2:
		var noise := FastNoiseLite.new()
		noise.seed = noise_seed
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 1.0 / wavelength
		var arc := PackedFloat32Array([0.0])
		for i in range(1, p.size()):
			arc.append(arc[i - 1] + p[i].distance_to(p[i - 1]))
		# Distancia por el trazo al punto fijo más cercano, hacia atrás y hacia delante.
		var to_pin := PackedFloat32Array()
		to_pin.resize(p.size())
		var last := -INF
		for i in p.size():
			if fixed[i] != 0:
				last = arc[i]
			to_pin[i] = arc[i] - last
		last = INF
		for i in range(p.size() - 1, -1, -1):
			if fixed[i] != 0:
				last = arc[i]
			to_pin[i] = minf(to_pin[i], last - arc[i])
		var moved := p.duplicate()
		for i in range(1, p.size() - 1):
			var taper := smoothstep(0.0, wavelength * 0.5, to_pin[i])
			if taper <= 0.0:
				continue
			var side := (p[i + 1] - p[i - 1]).normalized().cross(p[i].normalized())
			moved[i] = (p[i] + side * noise.get_noise_1d(arc[i]) * amplitude * taper).normalized() * radius
		p = moved
	var final := _resample(p, fixed, _FINAL_STEP)[0] as PackedVector3Array
	for i in final.size():
		final[i] = final[i].normalized()
	return final


## El punto de la polilínea [line] (direcciones unitarias) más cercano a la dirección [dir].
static func _nearest_on(line: PackedVector3Array, dir: Vector3) -> Vector3:
	var best := line[0]
	var best_d := INF
	for i in line.size() - 1:
		var a := line[i]
		var ab := line[i + 1] - a
		var t := clampf((dir - a).dot(ab) / maxf(ab.length_squared(), 1.0e-12), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_squared_to(dir)
		if d < best_d:
			best_d = d
			best = q
	return best.normalized()


## Remuestrea [points] a pasos de como mucho [step] m conservando los puntos fijos. Devuelve
## [puntos, fijos].
static func _resample(points: PackedVector3Array, pins: PackedByteArray, step: float) -> Array:
	var out := PackedVector3Array([points[0]])
	var fixed := PackedByteArray([pins[0]])
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var n := maxi(int(ceil(a.distance_to(b) / step)), 1)
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n).normalized() * a.length())
			fixed.append(pins[i] if k == n else 0)
	return [out, fixed]


## Dirección unitaria del centro de celda fraccionario ([px], [py]) de una rejilla acos de [w]×[h].
static func cell_dir(px: float, py: float, w: int, h: int) -> Vector3:
	return RiverField.hydro_dir(px, py, w, h)


## Celda de la rejilla acos de [w]×[h] que contiene la dirección [dir].
static func cell_of(dir: Vector3, w: int, h: int) -> Vector2i:
	var theta := acos(clampf(dir.y, -1.0, 1.0))
	var lon := atan2(-dir.z, dir.x)
	return Vector2i(posmod(int(floor((lon / TAU + 0.5) * w)), w), clampi(int(floor(theta / PI * h)), 0, h - 1))
