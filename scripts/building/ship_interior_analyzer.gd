class_name ShipInteriorAnalyzer
extends RefCounted

## Análisis de interiores de un barco: rasteriza los bloques de todas las grids del body
## (multi-size) a una rejilla unificada, hace un BFS del aire exterior (sube pero no baja:
## una bodega abierta solo por arriba retiene agua) y agrupa el aire no alcanzado en
## compartimentos. Solo datos planos, sin nodos: seguro en WorkerThreadPool.

const _DIRS_ALL: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# Exterior sin (0,-1,0): el aire exterior no cala hacia abajo dentro de un contenedor.
const _DIRS_EXTERIOR: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Subdivisiones por eje de una celda fina con geometría naval. Su hueco se reparte por
## sub-vóxeles entre la bodega y el mar: con la celda entera no se sabe de qué lado cae.
## Los 64 sub-vóxeles caben en un int; las máscaras de cara de _flood_air asumen 4.
const SUB := 4

## grids_data: [{cells: Array de Vector3i, full: Array de bool (opcional, todo lleno si
## falta), shapes: Array (opcional; por celda, null o la info del bloque con naval_shape,
## rotation_basis, mirrored y mirror_axis), cell_size: float}], en espacio del body.
## Devuelve compartimentos: [{cell_count, volume, aabb, boxes: [{pos, half}] (body-local),
## cells, cell_size (rejilla fina), open, openings (centros body-local de las celdas que dan al
## exterior: por la más baja según la escora del momento entra el mar)}].
## shape_cache guarda la ocupación de las celdas con geometría entre análisis del mismo barco: quien
## lo pase no debe compartirlo entre dos análisis simultáneos.
static func analyze(grids_data: Array, shape_cache: Dictionary = {}) -> Array:
	var finest := INF
	for gd: Dictionary in grids_data:
		if not (gd["cells"] as Array).is_empty():
			finest = minf(finest, gd["cell_size"])
	if finest == INF:
		return []

	# Rasterización por cobertura real del bloque; asume grids alineadas al origen del body.
	# Los bloques parciales ocupan celda entera para sellar (una pared de slopes es estanca)
	# pero se anotan aparte: su hueco es aire y se recupera al cerrar cada compartimento.
	var blocks: Dictionary = {}
	var partial: Dictionary = {}
	var shaped: Dictionary = {}
	var plain: Dictionary = {}
	var bmin := Vector3i(2147483647, 2147483647, 2147483647)
	var bmax := -bmin
	for gd: Dictionary in grids_data:
		var scale: float = (gd["cell_size"] as float) / finest
		var cells: Array = gd["cells"]
		var full: Array = gd.get("full", [])
		var shapes: Array = gd.get("shapes", [])
		for i in cells.size():
			var p: Vector3i = cells[i]
			var is_full: bool = full[i] if i < full.size() else true
			var shape = shapes[i] if i < shapes.size() else null
			var lo_v := Vector3i((Vector3(p) * scale).round())
			var hi_v := Vector3i((Vector3(p + Vector3i.ONE) * scale).round()) - Vector3i.ONE
			for x in range(lo_v.x, hi_v.x + 1):
				for y in range(lo_v.y, hi_v.y + 1):
					for z in range(lo_v.z, hi_v.z + 1):
						var v := Vector3i(x, y, z)
						blocks[v] = true
						if not is_full:
							partial[v] = true
						if shape == null:
							plain[v] = true
						else:
							if not shaped.has(v):
								shaped[v] = []
							shaped[v].append([shape, v - lo_v, hi_v.x - lo_v.x + 1])
						bmin = Vector3i(mini(bmin.x, v.x), mini(bmin.y, v.y), mini(bmin.z, v.z))
						bmax = Vector3i(maxi(bmax.x, v.x), maxi(bmax.y, v.y), maxi(bmax.z, v.z))
	# Encerrar un volumen exige al menos suelo + 4 paredes alrededor de una celda.
	if blocks.size() < 5:
		return []

	# Una celda con algún bloque sin geometría conocida se queda con la regla de los parciales.
	for v: Vector3i in plain:
		shaped.erase(v)
	var occupancy := _occupancy(shaped, shape_cache)

	var lo := bmin - Vector3i.ONE
	var hi := bmax + Vector3i.ONE

	var outside: Dictionary = {lo: true}
	var queue: Array[Vector3i] = [lo]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_back()
		for d: Vector3i in _DIRS_EXTERIOR:
			var n := c + d
			if n.x < lo.x or n.y < lo.y or n.z < lo.z \
				or n.x > hi.x or n.y > hi.y or n.z > hi.z:
				continue
			if outside.has(n) or blocks.has(n):
				continue
			outside[n] = true
			queue.append(n)

	# Un bloque parcial pegado al aire exterior es piel del casco y su medio hueco puede caer
	# FUERA: ni se absorbe ni sirve para crecer, porque taparlo recorta mar a la vista desde el
	# costado. Los de dentro sí: ahí el hueco es aire del compartimento.
	# Las celdas navales saben dónde está su hueco: es piel solo la que tiene aire de mar dentro.
	# La que no, se puede tapar entera (lo que sobra es madera, que ya tapa el agua) y se absorbe
	# en el compartimento al que llega su aire, aunque no toque una celda de aire libre: en un
	# pantoque curvo el hueco de la bodega cruza dos o tres celdas parciales seguidas.
	var sea_air := _flood_air(occupancy, outside, _DIRS_EXTERIOR, {})
	var closed: Dictionary = {}
	for c: Vector3i in sea_air:
		closed[c] = true
	var growable: Dictionary = blocks.duplicate()
	var inner_partial: Dictionary = {}
	for c: Vector3i in partial:
		if occupancy.has(c):
			if sea_air.has(c):
				growable.erase(c)
			continue
		var skin := false
		for d: Vector3i in _DIRS_ALL:
			if outside.has(c + d):
				skin = true
				break
		if skin:
			growable.erase(c)
		else:
			inner_partial[c] = true

	# Componentes conexas (6-dir) del aire interior no alcanzado por el exterior.
	var out: Array = []
	var visited: Dictionary = {}
	var partial_taken: Dictionary = {}
	for x in range(bmin.x, bmax.x + 1):
		for y in range(bmin.y, bmax.y + 1):
			for z in range(bmin.z, bmax.z + 1):
				var start := Vector3i(x, y, z)
				if blocks.has(start) or outside.has(start) or visited.has(start):
					continue

				var comp_cells: Dictionary = {start: true}
				visited[start] = true
				var q: Array[Vector3i] = [start]
				var cmin := start
				var cmax := start
				while not q.is_empty():
					var c2: Vector3i = q.pop_back()
					for d2: Vector3i in _DIRS_ALL:
						var n2 := c2 + d2
						if n2.x < bmin.x or n2.y < bmin.y or n2.z < bmin.z \
							or n2.x > bmax.x or n2.y > bmax.y or n2.z > bmax.z:
							continue
						if visited.has(n2) or blocks.has(n2) or outside.has(n2):
							continue
						visited[n2] = true
						comp_cells[n2] = true
						cmin = Vector3i(mini(cmin.x, n2.x), mini(cmin.y, n2.y), mini(cmin.z, n2.z))
						cmax = Vector3i(maxi(cmax.x, n2.x), maxi(cmax.y, n2.y), maxi(cmax.z, n2.z))
						q.append(n2)

				# Aperturas al exterior: las celdas adyacentes a aire exterior (el BFS no baja: lo de
				# debajo sigue interior). Se guardan todas porque cuál es la más baja depende de la
				# escora: en una bodega abierta por arriba, la borda de la banda que se hunde.
				var openings := PackedVector3Array()
				for cell: Vector3i in comp_cells:
					for d3: Vector3i in _DIRS_ALL:
						if outside.has(cell + d3):
							openings.append((Vector3(cell) + Vector3.ONE * 0.5) * finest)
							break
				var open := not openings.is_empty()

				# El rasterizado dio por macizas las celdas de bloque parcial interiores, y su
				# medio hueco es aire de este compartimento: se absorben como hojas (entran en
				# las cajas, pero el BFS no se propaga a través de ellas, que siguen siendo
				# pared). Cada celda va a un solo compartimento para no contar su volumen dos
				# veces.
				var air_cells: Array = comp_cells.keys()
				var leaf_volume := 0.0
				var reached := _flood_air(occupancy, comp_cells, _DIRS_ALL, closed)
				for n4: Vector3i in reached:
					closed[n4] = true
					comp_cells[n4] = true
					leaf_volume += _air_fraction(occupancy[n4])
					cmin = Vector3i(mini(cmin.x, n4.x), mini(cmin.y, n4.y), mini(cmin.z, n4.z))
					cmax = Vector3i(maxi(cmax.x, n4.x), maxi(cmax.y, n4.y), maxi(cmax.z, n4.z))
				for cell: Vector3i in air_cells:
					for d4: Vector3i in _DIRS_ALL:
						var n4 := cell + d4
						if not inner_partial.has(n4) or partial_taken.has(n4):
							continue
						partial_taken[n4] = true
						comp_cells[n4] = true
						leaf_volume += 0.5
						cmin = Vector3i(mini(cmin.x, n4.x), mini(cmin.y, n4.y), mini(cmin.z, n4.z))
						cmax = Vector3i(maxi(cmax.x, n4.x), maxi(cmax.y, n4.y), maxi(cmax.z, n4.z))

				# Las cajas pueden crecer dentro del sólido macizo del casco (invisible: el
				# bloque tapa el agua enmascarada de más) pero nunca sobre aire exterior, sobre
				# otro compartimento (que puede estar inundado) ni sobre la piel parcial. Sin
				# esto una bodega escalonada gasta más de 100 cajas y revienta el presupuesto.
				var boxes: Array = []
				for box: Dictionary in GridColliderBuilder.merge_boxes(comp_cells, growable, true):
					boxes.append({
						"pos": (Vector3(box["pos"]) + Vector3(box["size"]) * 0.5) * finest,
						"half": Vector3(box["size"]) * 0.5 * finest,
					})

				# Media celda por hoja: es lo que aporta un slope o un corner al hueco. Las navales
				# aportan su hueco medido.
				out.append({
					"cell_count": air_cells.size(),
					"volume": (air_cells.size() + leaf_volume) * finest * finest * finest,
					"aabb": AABB(Vector3(cmin) * finest, Vector3(cmax - cmin + Vector3i.ONE) * finest),
					"boxes": boxes,
					"cells": comp_cells,
					"cell_size": finest,
					"open": open,
					"openings": openings,
				})
	return out


## Sub-vóxeles macizos de cada celda fina con geometría: bit x + y·SUB + z·SUB² encendido si su
## centro cae dentro de alguno de sus sólidos. Las celdas repetidas (un tramo de casco las repite
## a lo largo) se calculan una vez.
static func _occupancy(shaped: Dictionary, cache: Dictionary) -> Dictionary:
	var out := {}
	for v: Vector3i in shaped:
		var mask := 0
		for entry: Array in shaped[v]:
			var info: Dictionary = entry[0]
			var key := [(info["naval_shape"]["faces"] as Array).hash(), info.get("rotation_basis", Basis.IDENTITY),
				info.get("mirrored", false), info.get("mirror_axis", -1), entry[1], entry[2]]
			if not cache.has(key):
				cache[key] = _solid_mask(BlockBoolean.from_block(info, 1.0, Vector3.ZERO), entry[1], entry[2])
			mask |= cache[key]
		out[v] = mask
	return out


## Rayos en +X por el centro de cada fila de sub-vóxeles de la parte offset/scale de la celda: la
## paridad de los cruces con las caras del sólido cerrado dice qué centros quedan dentro.
static func _solid_mask(faces: Array, offset: Vector3i, scale: int) -> int:
	var polygons := []
	for face: BlockBoolean.Face in faces:
		if absf(face.normal.x) < 0.000001:
			continue
		var yz := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := -lo
		for point in face.points:
			var q := Vector2(point.y, point.z)
			yz.append(q)
			lo = lo.min(q)
			hi = hi.max(q)
		polygons.append([face, yz, lo, hi])
	var mask := 0
	for j in SUB:
		for k in SUB:
			# Un desplazamiento mínimo evita que la fila roce una arista justo en su centro.
			var row := Vector2((offset.y + (j + 0.5) / SUB) / scale + 0.0000137,
				(offset.z + (k + 0.5) / SUB) / scale + 0.0000071)
			var xs := PackedFloat32Array()
			for polygon: Array in polygons:
				var lo: Vector2 = polygon[2]
				var hi: Vector2 = polygon[3]
				if row.x < lo.x or row.x > hi.x or row.y < lo.y or row.y > hi.y:
					continue
				if not Geometry2D.is_point_in_polygon(row, polygon[1]):
					continue
				var face: BlockBoolean.Face = polygon[0]
				xs.append((face.distance - face.normal.y * row.x - face.normal.z * row.y) / face.normal.x)
			for i in SUB:
				var x := (offset.x + (i + 0.5) / SUB) / scale
				var crossings := 0
				for cross in xs:
					if cross < x:
						crossings += 1
				if crossings % 2 == 1:
					mask |= 1 << (i + j * SUB + k * SUB * SUB)
	return mask


## Inunda el aire de los sub-vóxeles desde las celdas de `from` hacia las celdas con geometría que
## tocan, moviéndose solo en `dirs` y sin entrar en las de `closed`. Devuelve, por celda alcanzada,
## la máscara de sus sub-vóxeles de aire alcanzados. Cada celda se inunda entera con operaciones de
## bits y solo pasa a la vecina lo que asoma por la cara común.
static func _flood_air(occupancy: Dictionary, from: Dictionary, dirs: Array[Vector3i], closed: Dictionary) -> Dictionary:
	var reached := {}
	var pending: Array[Vector3i] = []
	for v: Vector3i in occupancy:
		if closed.has(v):
			continue
		var seed := 0
		for d: Vector3i in dirs:
			if from.has(v - d):
				seed |= _entry_face(d)
		seed &= ~(occupancy[v] as int)
		if seed != 0:
			reached[v] = seed
			pending.append(v)
	while not pending.is_empty():
		var v: Vector3i = pending.pop_back()
		var air := ~(occupancy[v] as int)
		var mask: int = reached[v]
		while true:
			var grown := mask
			for d: Vector3i in dirs:
				grown |= _move(mask, d)
			grown &= air
			if grown == mask:
				break
			mask = grown
		reached[v] = mask
		for d: Vector3i in dirs:
			var w := v + d
			if not occupancy.has(w) or closed.has(w):
				continue
			var entering := _cross(mask, d) & ~(occupancy[w] as int)
			var have: int = reached.get(w, 0)
			if entering & ~have:
				reached[w] = have | entering
				pending.append(w)
	return reached


# Máscaras de las caras de una celda subdividida en 4 × 4 × 4 (bit x + 4y + 16z).
const _X0 := 0x1111111111111111
const _X3 := _X0 << 3
const _Y0 := 0x000F000F000F000F
const _Y3 := _Y0 << 12
const _Z0 := 0xFFFF
const _Z3 := _Z0 << 48


## Cara por la que entra en una celda lo que se mueve en d.
static func _entry_face(d: Vector3i) -> int:
	if d.x != 0:
		return _X0 if d.x > 0 else _X3
	if d.y != 0:
		return _Y0 if d.y > 0 else _Y3
	return _Z0 if d.z > 0 else _Z3


## Un paso en d dentro de la celda.
static func _move(mask: int, d: Vector3i) -> int:
	if d.x > 0:
		return (mask & ~_X3) << 1
	if d.x < 0:
		return _shr(mask & ~_X0, 1)
	if d.y > 0:
		return (mask & ~_Y3) << 4
	if d.y < 0:
		return _shr(mask & ~_Y0, 4)
	if d.z > 0:
		return (mask & ~_Z3) << 16
	return _shr(mask & ~_Z0, 16)


## Lo que pasa a la celda vecina en d, ya en sus coordenadas.
static func _cross(mask: int, d: Vector3i) -> int:
	if d.x > 0:
		return _shr(mask & _X3, 3)
	if d.x < 0:
		return (mask & _X0) << 3
	if d.y > 0:
		return _shr(mask & _Y3, 12)
	if d.y < 0:
		return (mask & _Y0) << 12
	if d.z > 0:
		return _shr(mask & _Z3, 48)
	return (mask & _Z0) << 48


## Desplazamiento lógico: el >> de GDScript arrastra el signo y el bit 63 es un sub-vóxel más.
static func _shr(mask: int, bits: int) -> int:
	return (mask >> bits) & ~(-1 << (64 - bits))


static func _air_fraction(mask: int) -> float:
	var solid := 0
	for i in SUB * SUB * SUB:
		if mask & (1 << i):
			solid += 1
	return 1.0 - float(solid) / (SUB * SUB * SUB)
