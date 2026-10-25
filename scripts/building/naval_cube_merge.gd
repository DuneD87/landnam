class_name NavalCubeMerge
extends RefCounted

## Los cubos normales pueden compartir espacio con el casco. Su celda se almacena en una
## grid alineada del mismo barco, conservando el casco y descontando el sólido compartido.
var _cache := {}


static func is_hull(info: Dictionary) -> bool:
	return int(info.get("block_id", -1)) in [NavalHullMesh.PARTIAL_ID, NavalHullMesh.FULL_ID] \
		and not bool(info.get("naval_shape", {}).get("infill", false))


func resolve(reference: GridBase, position: Vector3i, size: float, material: String,
	refresh: bool = false, allow_empty: bool = false) -> Dictionary:
	var group := GridManager.get_grid_group(reference.grid_id)
	var signature := "%s:%s:%s:%s:%s" % [reference.grid_id, position, size, material, allow_empty]
	for grid: GridBase in group:
		signature += ":%s=%d" % [grid.grid_id, grid.edit_version]
	if not refresh and _cache.has(signature):
		return _cache[signature]
	var overlaps := []
	var blocked := false
	var destination: GridBase = null
	var origin := Vector3(position) * size
	for grid: GridBase in group:
		if is_equal_approx(grid.cell_size, size) and not grid.has_block(position):
			destination = grid
		var low := Vector3i(((origin + Vector3.ONE * 0.00001) / grid.cell_size).floor())
		var high := Vector3i(((origin + Vector3.ONE * size - Vector3.ONE * 0.00001) / grid.cell_size).floor())
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for z in range(low.z, high.z + 1):
					var cell := Vector3i(x, y, z)
					if not grid.has_block(cell):
						continue
					var info := grid.get_block(cell)
					if not is_hull(info):
						blocked = true
					else:
						overlaps.append([info, grid.cell_size / size, (Vector3(cell) * grid.cell_size - origin) / size])
	var result := {}
	if overlaps.is_empty() and allow_empty:
		result = {"allowed": false} if blocked else {"allowed": true, "grid": destination,
			"info": {"block_id": 0, "material_id": material, "rotation_basis": Basis.IDENTITY}}
	if not overlaps.is_empty():
		result = {"allowed": false}
		if not blocked:
			var solid := BlockBoolean.box()
			for overlap: Array in overlaps:
				solid = BlockBoolean.subtract(solid, BlockBoolean.from_block(overlap[0], overlap[1], overlap[2]))
				if solid.is_empty():
					break
			var shape := BlockBoolean.shape(solid)
			if float(shape["volume"]) > 0.0001:
				result = {"allowed": true, "grid": destination,
					"info": {"block_id": NavalHullMesh.PARTIAL_ID, "material_id": material,
						"rotation_basis": Basis.IDENTITY, "naval_shape": shape}}
	if _cache.size() >= 16:
		_cache.clear()
	_cache[signature] = result
	return result
