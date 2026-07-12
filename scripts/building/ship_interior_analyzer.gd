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

## grids_data: [{cells: Array de Vector3i, cell_size: float}], en espacio del body.
## Devuelve compartimentos: [{cell_count, volume, aabb, boxes: [{pos, half}] (body-local),
## cells, cell_size (rejilla fina), open, sill_cell (celda de la apertura más baja)}].
static func analyze(grids_data: Array) -> Array:
	var finest := INF
	for gd: Dictionary in grids_data:
		if not (gd["cells"] as Array).is_empty():
			finest = minf(finest, gd["cell_size"])
	if finest == INF:
		return []

	# Rasterización por cobertura real del bloque; asume grids alineadas al origen del body.
	var blocks: Dictionary = {}
	var bmin := Vector3i(2147483647, 2147483647, 2147483647)
	var bmax := -bmin
	for gd: Dictionary in grids_data:
		var scale: float = (gd["cell_size"] as float) / finest
		for p: Vector3i in gd["cells"]:
			var lo_v := Vector3i((Vector3(p) * scale).round())
			var hi_v := Vector3i((Vector3(p + Vector3i.ONE) * scale).round()) - Vector3i.ONE
			for x in range(lo_v.x, hi_v.x + 1):
				for y in range(lo_v.y, hi_v.y + 1):
					for z in range(lo_v.z, hi_v.z + 1):
						var v := Vector3i(x, y, z)
						blocks[v] = true
						bmin = Vector3i(mini(bmin.x, v.x), mini(bmin.y, v.y), mini(bmin.z, v.z))
						bmax = Vector3i(maxi(bmax.x, v.x), maxi(bmax.y, v.y), maxi(bmax.z, v.z))

	# Encerrar un volumen exige al menos suelo + 4 paredes alrededor de una celda.
	if blocks.size() < 5:
		return []

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

	# Componentes conexas (6-dir) del aire interior no alcanzado por el exterior.
	var out: Array = []
	var visited: Dictionary = {}
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

				# Apertura al exterior: la celda adyacente a aire exterior de menor Y es la
				# cota por la que entra el mar (el BFS no baja: lo de debajo sigue interior).
				var open := false
				var sill_cell: Vector3i = start
				var sill_y: int = 2147483647
				for cell: Vector3i in comp_cells:
					for d3: Vector3i in _DIRS_ALL:
						if outside.has(cell + d3):
							open = true
							if cell.y < sill_y:
								sill_y = cell.y
								sill_cell = cell
							break

				var boxes: Array = []
				for box: Dictionary in GridColliderBuilder.merge_boxes(comp_cells):
					boxes.append({
						"pos": (Vector3(box["pos"]) + Vector3(box["size"]) * 0.5) * finest,
						"half": Vector3(box["size"]) * 0.5 * finest,
					})

				out.append({
					"cell_count": comp_cells.size(),
					"volume": comp_cells.size() * finest * finest * finest,
					"aabb": AABB(Vector3(cmin) * finest, Vector3(cmax - cmin + Vector3i.ONE) * finest),
					"boxes": boxes,
					"cells": comp_cells,
					"cell_size": finest,
					"open": open,
					"sill_cell": sill_cell,
				})
	return out
