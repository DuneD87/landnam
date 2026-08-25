class_name GridColliderBuilder
extends RefCounted

## Fusiona celdas de cubos macizos en el mínimo razonable de cajas mediante merge codicioso 3D:
## cada caja se extiende primero en X, luego en Z (filas completas) y por último en Y (planos
## completos). Devuelve las cajas como {pos: Vector3i (celda mínima), size: Vector3i (en celdas)}.


## Órdenes de crecimiento (índices de eje). El primero, X -> Z -> Y, es el histórico y el único
## que se prueba salvo que se pida lo contrario.
const _GROW_ORDERS: Array[Vector3i] = [
	Vector3i(0, 2, 1), Vector3i(0, 1, 2), Vector3i(1, 0, 2),
	Vector3i(1, 2, 0), Vector3i(2, 0, 1), Vector3i(2, 1, 0),
]


## Agrupa un set de celdas (Dictionary[Vector3i, true]) en cajas fusionadas. `growable` son
## celdas por las que una caja puede extenderse sin necesitar cubrirlas (para la máscara del
## agua, el sólido del casco). Con `try_all_orders` se prueban los seis órdenes de crecimiento y
## se queda el mayor: en volúmenes escalonados (proa, popa) baja mucho la cuenta de cajas, a
## cambio de seis veces el trabajo de merge.
static func merge_boxes(cells: Dictionary, growable: Dictionary = {},
	try_all_orders: bool = false) -> Array[Dictionary]:

	var used: Dictionary = {}
	var boxes: Array[Dictionary] = []
	var orders: int = _GROW_ORDERS.size() if try_all_orders else 1

	var sorted_cells: Array = cells.keys()
	sorted_cells.sort()

	for start: Vector3i in sorted_cells:
		if used.has(start):
			continue

		var size := Vector3i.ONE
		var best := 0
		for i in orders:
			var candidate := _grow_box(cells, growable, used, start, _GROW_ORDERS[i])
			var volume: int = candidate.x * candidate.y * candidate.z
			if volume > best:
				best = volume
				size = candidate

		for x in size.x:
			for y in size.y:
				for z in size.z:
					used[start + Vector3i(x, y, z)] = true

		boxes.append({"pos": start, "size": size})

	return boxes


## Crece la caja desde `start` extendiendo un eje cada vez, en el orden dado.
static func _grow_box(cells: Dictionary, growable: Dictionary, used: Dictionary,
	start: Vector3i, order: Vector3i) -> Vector3i:

	var size := Vector3i.ONE
	for i in 3:
		var axis: int = order[i]
		while _slice_free(cells, growable, used, start, size, axis):
			size[axis] += 1
	return size


## true si la rodaja que la caja ganaría al crecer un paso por `axis` está entera disponible.
static func _slice_free(cells: Dictionary, growable: Dictionary, used: Dictionary,
	start: Vector3i, size: Vector3i, axis: int) -> bool:

	var lo := Vector3i.ZERO
	var hi := size
	lo[axis] = size[axis]
	hi[axis] = size[axis] + 1
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			for z in range(lo.z, hi.z):
				if not _cell_free(cells, growable, used, start + Vector3i(x, y, z)):
					return false
	return true


static func _cell_free(cells: Dictionary, growable: Dictionary, used: Dictionary, pos: Vector3i) -> bool:
	return (cells.has(pos) or growable.has(pos)) and not used.has(pos)
