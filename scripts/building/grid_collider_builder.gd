class_name GridColliderBuilder
extends RefCounted

## Fusiona celdas de cubos macizos en el mínimo razonable de cajas mediante merge codicioso 3D:
## cada caja se extiende primero en X, luego en Z (filas completas) y por último en Y (planos
## completos). Devuelve las cajas como {pos: Vector3i (celda mínima), size: Vector3i (en celdas)}.


## Agrupa un set de celdas (Dictionary[Vector3i, true]) en cajas fusionadas.
static func merge_boxes(cells: Dictionary) -> Array[Dictionary]:
	var used: Dictionary = {}
	var boxes: Array[Dictionary] = []

	var sorted_cells: Array = cells.keys()
	sorted_cells.sort()

	for start: Vector3i in sorted_cells:
		if used.has(start):
			continue

		var size := Vector3i.ONE

		while _cell_free(cells, used, start + Vector3i(size.x, 0, 0)):
			size.x += 1

		while _row_free(cells, used, start + Vector3i(0, 0, size.z), size.x):
			size.z += 1

		while _slab_free(cells, used, start + Vector3i(0, size.y, 0), size.x, size.z):
			size.y += 1

		for x in size.x:
			for y in size.y:
				for z in size.z:
					used[start + Vector3i(x, y, z)] = true

		boxes.append({"pos": start, "size": size})

	return boxes


static func _cell_free(cells: Dictionary, used: Dictionary, pos: Vector3i) -> bool:
	return cells.has(pos) and not used.has(pos)

static func _row_free(cells: Dictionary, used: Dictionary, row_start: Vector3i, count_x: int) -> bool:
	for x in count_x:
		if not _cell_free(cells, used, row_start + Vector3i(x, 0, 0)):
			return false
	return true

static func _slab_free(cells: Dictionary, used: Dictionary, slab_start: Vector3i, count_x: int, count_z: int) -> bool:
	for x in count_x:
		for z in count_z:
			if not _cell_free(cells, used, slab_start + Vector3i(x, 0, z)):
				return false
	return true
