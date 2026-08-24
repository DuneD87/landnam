class_name GridSplitAnalyzer
extends RefCounted

## Análisis de conectividad de los bloques de un grupo de grids: rasteriza todas a una rejilla
## unificada —dos grids de distinto cell_size pueden tocarse— y etiqueta por BFS de 6-vecindad.
## Sirve para dos preguntas distintas: qué piezas han quedado sueltas (analyze) y qué trozos han
## dejado de estar sostenidos por el suelo (analyze_support). Solo datos planos, sin nodos:
## seguro en WorkerThreadPool.

const _DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## grids_data: [{cells: Array de Vector3i, cell_size: float}], en espacio del body.
## Devuelve [] si todo sigue de una pieza (el caso normal, y el que hay que resolver barato).
## Si no, las piezas ordenadas de mayor a menor: [{count, groups: [{grid_index, cells}]}].
static func analyze(grids_data: Array) -> Array:
	var raster := _rasterize(grids_data)
	if raster.is_empty() or (raster["owners"] as Array).size() < 2:
		return []

	var pieces := _group_components(raster["fine"], raster["owners"], raster["cell_sizes"], {})
	# Una sola componente es el caso abrumadoramente normal.
	return [] if pieces.size() <= 1 else pieces


## Trozos que han dejado de estar sostenidos: los que no se alcanzan desde ninguna celda anclada
## y los que quedan a más de max_span pasos de la más cercana (un voladizo largo cede aunque siga
## pegado). 'anchors' es paralelo a grids_data: anchors[i] = Dictionary[Vector3i, true] con las
## celdas de esa grid que se apoyan en algo firme. max_span va en celdas del cell_size más fino.
## Devuelve las piezas que caen, agrupadas por componente, o [] si no cae nada.
static func analyze_support(grids_data: Array, anchors: Array, max_span: int) -> Array:
	var raster := _rasterize(grids_data)
	if raster.is_empty():
		return []

	var owners: Array = raster["owners"]
	var fine: Dictionary = raster["fine"]

	var anchored: Dictionary = {}
	for oi in owners.size():
		var gi: int = owners[oi][0]
		if gi < anchors.size() and (anchors[gi] as Dictionary).has(owners[oi][1]):
			anchored[oi] = true

	# Sin un solo anclaje la estructura entera está en el aire; que caiga como un bloque.
	if anchored.is_empty():
		return _group_components(fine, owners, raster["cell_sizes"], {})

	# BFS multi-origen desde todas las celdas ancladas, en anchura (FIFO con puntero: pop_front
	# sobre un Array es O(n) y aquí serían decenas de miles de celdas).
	var depth: Dictionary = {}
	var queue: Array[Vector3i] = []
	for cell: Vector3i in fine:
		if anchored.has(fine[cell]):
			depth[cell] = 0
			queue.append(cell)

	var head := 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		var d: int = depth[c]
		if d >= max_span:
			continue
		for dir in _DIRS:
			var n: Vector3i = c + dir
			if fine.has(n) and not depth.has(n):
				depth[n] = d + 1
				queue.append(n)

	# Un bloque se sostiene si CUALQUIERA de sus celdas finas quedó dentro del alcance.
	var supported: Dictionary = {}
	for c: Vector3i in depth:
		supported[fine[c]] = true

	var falling: Dictionary = {}
	for oi in owners.size():
		if not supported.has(oi):
			falling[oi] = true

	if falling.is_empty():
		return []
	return _group_components(fine, owners, raster["cell_sizes"], falling)


## Rasteriza las grids a la rejilla del cell_size más fino. Devuelve {finest, owners, fine},
## donde owners[i] = [grid_index, celda original] y fine[celda fina] = i. Un bloque cubre un
## bloque contiguo de celdas finas, así que todas caen en la misma componente.
static func _rasterize(grids_data: Array) -> Dictionary:
	var finest := INF
	for gd: Dictionary in grids_data:
		if not (gd["cells"] as Array).is_empty():
			finest = minf(finest, gd["cell_size"])
	if finest == INF:
		return {}

	var owners: Array = []
	var fine: Dictionary = {}
	var cell_sizes := PackedFloat32Array()
	for gd2: Dictionary in grids_data:
		cell_sizes.append(gd2["cell_size"])
	for gi in grids_data.size():
		var gd: Dictionary = grids_data[gi]
		var scale: float = (gd["cell_size"] as float) / finest
		for p: Vector3i in gd["cells"]:
			var owner_idx := owners.size()
			owners.append([gi, p])
			var lo := Vector3i((Vector3(p) * scale).round())
			var hi := Vector3i((Vector3(p + Vector3i.ONE) * scale).round()) - Vector3i.ONE
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						fine[Vector3i(x, y, z)] = owner_idx

	return {"finest": finest, "owners": owners, "fine": fine, "cell_sizes": cell_sizes}


## Agrupa en componentes conexas los bloques cuyo índice esté en 'subset' (todos si va vacío),
## sin atravesar los que no lo están. Devuelve [{count, groups}] de mayor a menor.
static func _group_components(fine: Dictionary, owners: Array, cell_sizes: PackedFloat32Array,
	subset: Dictionary) -> Array:
	var owner_label := PackedInt32Array()
	owner_label.resize(owners.size())
	owner_label.fill(-1)

	var seen: Dictionary = {}
	var next_label := 0
	for start: Vector3i in fine:
		if seen.has(start) or not _in_subset(fine[start], subset):
			continue
		seen[start] = true
		var queue: Array[Vector3i] = [start]
		while not queue.is_empty():
			var c: Vector3i = queue.pop_back()
			owner_label[fine[c]] = next_label
			for dir in _DIRS:
				var n: Vector3i = c + dir
				if not fine.has(n) or seen.has(n) or not _in_subset(fine[n], subset):
					continue
				seen[n] = true
				queue.append(n)
		next_label += 1

	if next_label == 0:
		return []

	var pieces: Array = []
	for _i in next_label:
		pieces.append({})
	for oi in owners.size():
		var label: int = owner_label[oi]
		if label < 0:
			continue
		var piece: Dictionary = pieces[label]
		var gi: int = owners[oi][0]
		if not piece.has(gi):
			piece[gi] = []
		(piece[gi] as Array).append(owners[oi][1])

	# El centroide se acumula aquí, en el worker: con 18.000 bloques recorrerlos de nuevo en el
	# main thread para calcularlo era una de las pasadas que se comían el frame del corte.
	var out: Array = []
	for piece: Dictionary in pieces:
		var groups: Array = []
		var count := 0
		var centroid := Vector3.ZERO
		for gi: int in piece:
			var cells: Array = piece[gi]
			groups.append({"grid_index": gi, "cells": cells})
			count += cells.size()
			var cs: float = cell_sizes[gi]
			for cell: Vector3i in cells:
				centroid += (Vector3(cell) + Vector3.ONE * 0.5) * cs
		if count > 0:
			out.append({"count": count, "groups": groups, "centroid": centroid / float(count)})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["count"] > b["count"])
	return out


static func _in_subset(owner_idx: int, subset: Dictionary) -> bool:
	return subset.is_empty() or subset.has(owner_idx)
