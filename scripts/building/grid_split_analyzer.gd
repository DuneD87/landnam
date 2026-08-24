class_name GridSplitAnalyzer
extends RefCounted

## Componentes conexas de los bloques de un body: rasteriza todas sus grids a una rejilla
## unificada —igual que ShipInteriorAnalyzer, porque dos grids de distinto cell_size pueden
## tocarse— etiqueta por BFS de 6-vecindad y devuelve los bloques ORIGINALES agrupados por pieza.
## Solo datos planos, sin nodos: seguro en WorkerThreadPool.

const _DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## grids_data: [{cells: Array de Vector3i, cell_size: float}], en espacio del body.
## Devuelve [] si todo sigue en una pieza (el caso normal, y el que hay que resolver barato).
## Si no, las piezas ordenadas de mayor a menor: [{count, groups: [{grid_index, cells}]}].
static func analyze(grids_data: Array) -> Array:
	var finest := INF
	for gd: Dictionary in grids_data:
		if not (gd["cells"] as Array).is_empty():
			finest = minf(finest, gd["cell_size"])
	if finest == INF:
		return []

	# owners[i] = [grid_index, celda original]; fine[celda fina] = i. Un bloque cubre un bloque
	# contiguo de celdas finas, así que todas caen en la misma componente y basta mirar una.
	var owners: Array = []
	var fine: Dictionary = {}
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

	if owners.size() < 2:
		return []

	var owner_label := PackedInt32Array()
	owner_label.resize(owners.size())
	owner_label.fill(-1)

	var seen: Dictionary = {}
	var next_label := 0
	for start: Vector3i in fine:
		if seen.has(start):
			continue
		seen[start] = true
		var queue: Array[Vector3i] = [start]
		while not queue.is_empty():
			var c: Vector3i = queue.pop_back()
			owner_label[fine[c]] = next_label
			for d in _DIRS:
				var n: Vector3i = c + d
				if fine.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		next_label += 1

	# Una sola componente es el caso abrumadoramente normal, y sale de aquí sin construir nada.
	if next_label <= 1:
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

	var out: Array = []
	for piece: Dictionary in pieces:
		var groups: Array = []
		var count := 0
		for gi: int in piece:
			var cells: Array = piece[gi]
			groups.append({"grid_index": gi, "cells": cells})
			count += cells.size()
		if count > 0:
			out.append({"count": count, "groups": groups})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["count"] > b["count"])
	return out
