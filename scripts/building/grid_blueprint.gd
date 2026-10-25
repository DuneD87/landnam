class_name GridBlueprint
extends RefCounted

## Captura un grupo de grids (todas las que forman una misma estructura o barco) en un
## diccionario independiente del lugar donde estaban: los bloques se guardan en coordenadas de
## celda relativas a la esquina del grupo, así que el blueprint se puede reconstruir en cualquier
## punto de cualquier planeta. También gestiona sus ficheros en user://blueprints: el blueprint
## (<nombre>.json), su ficha (<nombre>.info: lo que la biblioteca enseña y el recuento de lo que
## cuesta, para no leer el blueprint entero, que en un barco son megas) y su miniatura
## (<nombre>.png, BlueprintThumbnail).

const DIR := "user://blueprints/"
const EXTENSION := ".json"
const INFO_EXTENSION := ".info"
const THUMBNAIL_EXTENSION := ".png"
const FORMAT_VERSION := 1
## Versión de la ficha: una distinta se vuelve a sacar del blueprint.
const INFO_VERSION := 1

## Tolerancia al convertir el desplazamiento de normalización a celdas de cada grid.
const CELL_EPSILON := 0.001


## Captura el grupo de grids en un blueprint. Devuelve {} si el grupo no tiene bloques.
static func capture(grids: Array) -> Dictionary:
	var filled: Array = []
	for grid: GridBase in grids:
		if grid.get_block_count() > 0:
			filled.append(grid)
	if filled.is_empty():
		return {}

	filled.sort_custom(func(a: GridBase, b: GridBase) -> bool:
		return a.get_block_count() > b.get_block_count())

	var min_m := Vector3.INF
	var max_m := -Vector3.INF
	for grid: GridBase in filled:
		for grid_pos: Vector3i in grid.get_all_blocks():
			var corner := Vector3(grid_pos) * grid.cell_size
			min_m = min_m.min(corner)
			max_m = max_m.max(corner + Vector3.ONE * grid.cell_size)

	var offset_m := _quantized_offset(filled, min_m)

	var grids_data: Array = []
	var block_count := 0
	var prop_count := 0
	for grid: GridBase in filled:
		var cell_offset := Vector3i(
			roundi(offset_m.x / grid.cell_size),
			roundi(offset_m.y / grid.cell_size),
			roundi(offset_m.z / grid.cell_size)
		)
		var entry := _capture_grid(grid, cell_offset, offset_m)
		block_count += (entry["blocks"] as Dictionary).size()
		prop_count += (entry["props"] as Array).size()
		grids_data.append(entry)

	return {
		"version": FORMAT_VERSION,
		"created": Time.get_datetime_string_from_system(),
		"dynamic": filled[0] is DynamicPlanetGrid,
		"bounds_min": GridBase._vec3_to_array(min_m - offset_m),
		"bounds_max": GridBase._vec3_to_array(max_m - offset_m),
		"block_count": block_count,
		"prop_count": prop_count,
		"grids": grids_data,
	}


## Desplazamiento que lleva la esquina del grupo al origen. Se cuantiza al mayor cell_size para
## que caiga en un número entero de celdas de todas las grids; si aun así alguna no encaja, se
## renuncia a normalizar (el blueprint conserva sus índices originales y sigue siendo válido).
static func _quantized_offset(grids: Array, min_m: Vector3) -> Vector3:
	var quantum := 0.0
	for grid: GridBase in grids:
		quantum = maxf(quantum, grid.cell_size)
	if quantum <= 0.0:
		return Vector3.ZERO

	var offset := (min_m / quantum).floor() * quantum
	for grid: GridBase in grids:
		for axis in 3:
			var cells: float = offset[axis] / grid.cell_size
			if absf(cells - roundf(cells)) > CELL_EPSILON:
				push_warning("[GridBlueprint] Tamaños de celda incompatibles: se guarda sin normalizar")
				return Vector3.ZERO
	return offset


static func _capture_grid(grid: GridBase, cell_offset: Vector3i, offset_m: Vector3) -> Dictionary:
	var blocks_data: Dictionary = {}
	var all_blocks := grid.get_all_blocks()
	for grid_pos: Vector3i in all_blocks:
		var info: Dictionary = all_blocks[grid_pos]
		var local := grid_pos - cell_offset
		blocks_data["%d,%d,%d" % [local.x, local.y, local.z]] = {
			"block_id": info["block_id"],
			"rotation_basis": GridBase._basis_to_array(info.get("rotation_basis", Basis.IDENTITY)),
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}
		if info.has("naval_shape"):
			blocks_data["%d,%d,%d" % [local.x, local.y, local.z]]["naval_shape"] = info["naval_shape"]

	var props_data: Array = []
	var all_props := grid.get_all_props()
	for key: String in all_props:
		var info: Dictionary = all_props[key]
		var local_xform: Transform3D = info["local_transform"]
		local_xform.origin -= offset_m
		props_data.append({
			"item_id": str(info["item_id"]),
			"cell": GridBase._vec3i_to_array(info["cell"] - cell_offset),
			"face": GridBase._vec3i_to_array(info["face"]),
			"local_transform": GridBase._transform_to_array(local_xform),
		})

	var materials_data: Dictionary = {}
	for mat_id: String in grid.mesh_materials:
		var mat: Material = grid.mesh_materials[mat_id]
		if mat and mat.resource_path != "":
			materials_data[mat_id] = mat.resource_path

	return {
		"cell_size": grid.cell_size,
		"blocks": blocks_data,
		"props": props_data,
		"materials": materials_data,
	}


## Reconstruye el blueprint en el planeta, con su esquina en origin_world y orientado según
## basis_world. Devuelve las grids creadas (ya dinámicas si el blueprint lo era y no se fuerza
## force_static, que las deja ancladas al planeta).
static func instantiate(data: Dictionary, planet: Node3D, origin_world: Vector3, basis_world: Basis,
	force_static: bool = false) -> Array:

	var created := create_grids(data, planet, origin_world, basis_world)
	var grids_data: Array = data.get("grids", [])
	for i in created.size():
		_restore_blocks(created[i], blocks_dict(grids_data[i]))
		_restore_props(created[i], grids_data[i].get("props", []))
	return finish(data, created, force_static)


## Las grids del blueprint, vacías y con sus materiales, una por cada una suya y en su orden: la
## primera con la esquina en origin_world y orientada según basis_world, y las demás alineadas a
## ella. [] sin grids o sin planeta.
static func create_grids(data: Dictionary, planet: Node3D, origin_world: Vector3, basis_world: Basis) -> Array:
	var grids_data: Array = data.get("grids", [])
	if grids_data.is_empty() or not planet:
		return []

	var created: Array = []
	var reference: GridBase = null

	for grid_data: Dictionary in grids_data:
		var cell: float = float(grid_data.get("cell_size", 1.0))
		var grid: GridBase
		if reference == null:
			grid = GridManager.create_grid_exact(planet, origin_world, basis_world, cell)
			reference = grid
		else:
			grid = GridManager.create_grid_aligned(planet, reference, cell)
		_restore_materials(grid, grid_data)
		created.append(grid)
	return created


## Con todo puesto: si el blueprint era dinámico y no se fuerza force_static, lo convierte. Devuelve
## las grids resultantes.
static func finish(data: Dictionary, created: Array, force_static: bool = false) -> Array:
	if data.get("dynamic", false) and not force_static and not created.is_empty():
		var dynamic_grids := GridManager.convert_to_dynamic((created[0] as GridBase).grid_id)
		if not dynamic_grids.is_empty():
			return dynamic_grids
	return created


## Materiales de los bloques de la grid. Manda el BuildMaterial de ahora con ese id: los de piedra
## y madera son subrecursos (su ruta lleva «::») y no se pueden cargar sueltos, y así un blueprint
## viejo se ve con el material actual. La ruta guardada solo sirve para ids que ya no existen.
static func _restore_materials(grid: GridBase, grid_data: Dictionary) -> void:
	var paths: Dictionary = grid_data.get("materials", {})
	var used := {}
	for info: Dictionary in (grid_data.get("blocks", {}) as Dictionary).values():
		used[str(info.get("material_id", ""))] = true
	for mat_id: String in used:
		if mat_id == "":
			continue
		var mat := BlockDatabase.get_material_by_id(mat_id)
		if mat and mat.surface_material:
			grid.mesh_materials[mat_id] = mat.surface_material
		elif paths.has(mat_id) and ResourceLoader.exists(paths[mat_id]):
			grid.mesh_materials[mat_id] = load(paths[mat_id])
		else:
			push_warning("[GridBlueprint] Material desconocido: %s" % mat_id)


## Bloques de una grid del blueprint en el formato que usan las grids y ChunkMeshBuilder
## (Vector3i -> {block_id, rotation_basis, material_id, mirrored, mirror_axis}).
static func blocks_dict(grid_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var blocks_data: Dictionary = grid_data.get("blocks", {})

	for key: String in blocks_data:
		var cell: Variant = parse_cell(key)
		if cell != null:
			out[cell] = block_info(blocks_data[key])
	return out


## La celda de una clave «x,y,z» del blueprint, o null si no lo es.
static func parse_cell(key: String) -> Variant:
	var parts := key.split(",")
	if parts.size() < 3:
		return null
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


## Un bloque del blueprint (lo leído del JSON) en el formato de las grids.
static func block_info(info: Dictionary) -> Dictionary:
	var out := {
		"block_id": int(info.get("block_id", 0)),
		"rotation_basis": GridBase._array_to_basis(info.get("rotation_basis", [1,0,0, 0,1,0, 0,0,1])),
		"material_id": info.get("material_id", ""),
		"mirrored": info.get("mirrored", false),
		"mirror_axis": info.get("mirror_axis", -1),
	}
	if info.has("naval_shape"):
		out["naval_shape"] = info["naval_shape"]
	return out


static func _restore_blocks(grid: GridBase, blocks_data: Dictionary) -> void:
	grid.begin_bulk_edit()
	for grid_pos: Vector3i in blocks_data:
		place_block(grid, grid_pos, blocks_data[grid_pos])
	grid.end_bulk_edit()


## Pone en [grid] un bloque del blueprint ([info] como lo da block_info). false si su id ya no
## existe o la celda está ocupada.
static func place_block(grid: GridBase, grid_pos: Vector3i, info: Dictionary) -> bool:
	var block_data: BlockData = BlockDatabase.get_block(info["block_id"])
	if not block_data:
		push_warning("[GridBlueprint] Block ID %d desconocido" % info["block_id"])
		return false

	var rotation_basis: Basis = info["rotation_basis"]
	var world_transform := Transform3D(grid.get_basis_world() * rotation_basis, grid.grid_to_world(grid_pos))
	return grid.place_block(grid_pos, block_data, rotation_basis, world_transform,
		info["material_id"], {
			"mirrored": info["mirrored"],
			"mirror_axis": info["mirror_axis"],
			"naval_shape": info.get("naval_shape", {}),
		})


static func _restore_props(grid: GridBase, props_data: Array) -> void:
	for info: Dictionary in props_data:
		place_prop(grid, info)


## Pone en [grid] un colocable del blueprint (lo leído del JSON).
static func place_prop(grid: GridBase, info: Dictionary) -> bool:
	return grid.place_prop(
		GridBase._array_to_vec3i(info.get("cell", [])),
		GridBase._array_to_vec3i(info.get("face", [])),
		StringName(info.get("item_id", "")),
		GridBase._array_to_transform(info.get("local_transform", []))
	)


## Tamaño del blueprint en metros, en su propio espacio de grid (ancho, alto, largo).
static func get_size(data: Dictionary) -> Vector3:
	var bmin := GridBase._array_to_vec3(data.get("bounds_min", [0, 0, 0]))
	var bmax := GridBase._array_to_vec3(data.get("bounds_max", [0, 0, 0]))
	return bmax - bmin


## Resumen del blueprint para la UI, sin instanciarlo.
static func get_stats(data: Dictionary) -> Dictionary:
	var cells: Array = []
	for grid_data: Dictionary in data.get("grids", []):
		cells.append(float(grid_data.get("cell_size", 1.0)))
	cells.sort()

	return {
		"blocks": int(data.get("block_count", 0)),
		"props": int(data.get("prop_count", 0)),
		"grids": (data.get("grids", []) as Array).size(),
		"dynamic": bool(data.get("dynamic", false)),
		"size": get_size(data),
		"cell_sizes": cells,
		"created": str(data.get("created", "")),
	}


## Ficha del blueprint (lo que se guarda en <nombre>.info): sus datos, el recuento de lo que cuesta
## (BuildCost) y cuántos bloques no se van a poder reconstruir (de un id que ya no existe).
static func summarize(data: Dictionary) -> Dictionary:
	var stats := get_stats(data)
	var size: Vector3 = stats["size"]
	var unknown := 0
	for grid_data: Dictionary in data.get("grids", []):
		for info: Dictionary in (grid_data.get("blocks", {}) as Dictionary).values():
			if BlockDatabase.get_block(int(info.get("block_id", -1))) == null:
				unknown += 1
	return {
		"info_version": INFO_VERSION,
		"created": stats["created"],
		"dynamic": stats["dynamic"],
		"blocks": stats["blocks"],
		"props": stats["props"],
		"grids": stats["grids"],
		"size": [size.x, size.y, size.z],
		"cell_sizes": stats["cell_sizes"],
		"counts": BuildCost.count_blueprint(data),
		"unknown_blocks": unknown,
	}


## Ficha de un blueprint guardado, con su nombre en "name" y el tamaño como Vector3. Si falta o es
## de otra versión se saca del blueprint y se guarda. {} si el blueprint no se puede leer.
static func load_info(bp_name: String) -> Dictionary:
	var info: Dictionary = {}
	var path := info_path_for(bp_name)
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and int(parsed.get("info_version", 0)) == INFO_VERSION:
			info = parsed
	if info.is_empty():
		var data := load_from_disk(bp_name)
		if data.is_empty():
			return {}
		info = summarize(data)
		_store_info(bp_name, info)
	info["name"] = bp_name
	var size: Array = info.get("size", [0, 0, 0])
	info["size"] = Vector3(float(size[0]), float(size[1]), float(size[2])) if size.size() >= 3 else Vector3.ZERO
	return info


## Fichas de todos los blueprints guardados, por nombre.
static func list_infos() -> Array:
	var out: Array = []
	for bp_name: String in list_names():
		var info := load_info(bp_name)
		if not info.is_empty():
			out.append(info)
	return out


static func _store_info(bp_name: String, info: Dictionary) -> void:
	_ensure_dir()
	var file := FileAccess.open(info_path_for(bp_name), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(info, "\t"))
		file.close()


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


## Nombre de fichero seguro (sin caracteres prohibidos ni extensión); "" si no queda nada.
static func sanitize_name(raw: String) -> String:
	return raw.strip_edges().validate_filename().trim_suffix(EXTENSION)


static func path_for(bp_name: String) -> String:
	return DIR + bp_name + EXTENSION


static func info_path_for(bp_name: String) -> String:
	return DIR + bp_name + INFO_EXTENSION


static func thumbnail_path_for(bp_name: String) -> String:
	return DIR + bp_name + THUMBNAIL_EXTENSION


## La miniatura guardada, o null si aún no tiene.
static func load_thumbnail(bp_name: String) -> Texture2D:
	var path := thumbnail_path_for(bp_name)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func exists(bp_name: String) -> bool:
	return FileAccess.file_exists(path_for(bp_name))


static func save_to_disk(bp_name: String, data: Dictionary) -> bool:
	_ensure_dir()
	var file := FileAccess.open(path_for(bp_name), FileAccess.WRITE)
	if not file:
		push_error("[GridBlueprint] No se puede escribir %s" % path_for(bp_name))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_store_info(bp_name, summarize(data))
	return true


static func load_from_disk(bp_name: String) -> Dictionary:
	var path := path_for(bp_name)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[GridBlueprint] No se puede leer %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("[GridBlueprint] JSON inválido en %s" % path)
		return {}
	return parsed


## Nombres de los blueprints guardados, ordenados alfabéticamente.
static func list_names() -> Array:
	_ensure_dir()
	var names: Array = []
	for file_name in DirAccess.get_files_at(DIR):
		if file_name.ends_with(EXTENSION):
			names.append(file_name.trim_suffix(EXTENSION))
	names.sort()
	return names


static func delete_from_disk(bp_name: String) -> bool:
	var path := path_for(bp_name)
	if not FileAccess.file_exists(path):
		return false
	for extra in [info_path_for(bp_name), thumbnail_path_for(bp_name)]:
		if FileAccess.file_exists(extra):
			DirAccess.remove_absolute(extra)
	return DirAccess.remove_absolute(path) == OK


## Cambia el nombre de un blueprint (con su ficha y su miniatura). No pisa otro que ya exista.
static func rename_on_disk(old_name: String, new_name: String) -> bool:
	if new_name == "" or new_name == old_name or exists(new_name) or not exists(old_name):
		return false
	if DirAccess.rename_absolute(path_for(old_name), path_for(new_name)) != OK:
		return false
	for pair in [[info_path_for(old_name), info_path_for(new_name)],
			[thumbnail_path_for(old_name), thumbnail_path_for(new_name)]]:
		if FileAccess.file_exists(pair[0]):
			DirAccess.rename_absolute(pair[0], pair[1])
	return true
