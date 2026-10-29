class_name RepairSite
extends BlueprintSite

## Una reparación: la obra (BlueprintSite) de lo que le falta a una construcción en pie para volver a
## ser la de un blueprint. Se le aportan los materiales con la E y se rehace a martillazos, como una
## obra; con el martillo en modo quitar se cancela y la construcción se queda como está. Solo se
## apunta con el martillo en la mano: navegando, el barco no enseña su panel.
##
## Lo que hace (repair_plan):
## - pone los bloques del blueprint que faltan, si su celda está libre: lo que el jugador haya puesto
##   en su sitio, o encima, se respeta;
## - devuelve la vida a los bloques dañados que siguen siendo los del blueprint. Cuestan lo que les
##   falta para valer lo que costaron (lo que cuestan menos lo que devolverían al desmontarlos) y se
##   arreglan aunque quien martillea esté encima;
## - pone los colocables que faltan, al final, como en una obra.
##
## Qué blueprint es: el que apuntan sus grids (GridBase.source_blueprint: al colocarla, al guardarla
## como blueprint y al acabar de repararla), y así casa por poco que quede de ella. Si no lo saben, o
## ya no está en la biblioteca, se busca (match_blueprint): unos cuantos bloques suyos votan el
## desplazamiento entre sus celdas y las del blueprint, y gana el que hace coincidir más bloques. Si
## tampoco, se elige a mano en la biblioteca, y entonces basta con que coincida algo. Girado no casa
## (el giro va en la pose de la grid, no en sus celdas).
##
## Va colgada del cuerpo del barco (o del planeta, si es estática), en el espacio de sus grids, así
## que lo sigue al navegar. Su blueprint es solo lo que hay que hacer, ya en las celdas de esas grids:
## por cada grid del blueprint, una con lo que falta y otra con lo dañado ("repair" en la grid y
## "repair_cost" en cada bloque). Se guarda con las obras.

const KIND := "repair"
## Lo que tiene que salir del blueprint de lo que hay en pie (lo demás son añadidos), y lo que tiene
## que quedar del blueprint: con menos ya no es repararla, es levantar otra.
const MIN_MATCH := 0.6
const MIN_KEPT := 0.2
## Votación del desplazamiento: bloques que votan (entre el cuádruple de candidatos, los de un id
## más raro en el blueprint) y votos como mucho.
const VOTE_SAMPLES := 12
const VOTE_BUDGET := 200000
## Desplazamientos que se prueban con una muestra de QUICK_SAMPLES bloques, y los mejores que se
## cuentan enteros.
const CANDIDATES := 16
const QUICK_SAMPLES := 256
const FINALISTS := 3
const HEAL_COLOR := Color(1.0, 0.7, 0.3, 0.16)
const HEAL_AIMED_COLOR := Color(1.0, 0.76, 0.38, 0.3)
## Lo que el fantasma de lo dañado sobresale del bloque (m), para no pelear con su cara.
const HEAL_GROW := 0.015
## Cada cuánto mira si su construcción sigue ahí o se ha vuelto dinámica (s).
const RESYNC_TIME := 0.5

## Una grid de la construcción: con ella se encuentran las demás (las de su grupo).
var _anchor_id := ""
## Grids que tuvo que crear (se perdió la suya): si acaban vacías, se quitan.
var _created: Array = []
var _heal_grids := PackedByteArray()
var _heal_material: StandardMaterial3D = null
## La construcción entera en el espacio de sus grids: se apunta a la reparación desde cualquier
## punto de ella.
var _reach_box := AABB()
var _resync_left := RESYNC_TIME


## Empieza a reparar la construcción de [grid_id] con el blueprint [bp_name] (elegido a mano) o, sin
## él, con el suyo: el que dicen sus grids o, si no lo saben, el de la biblioteca que mejor case.
## Construyendo gratis la acaba al momento. Devuelve {"site", "name", "missing": piezas que reponer,
## "damaged": bloques que arreglar} o {"error": clave del aviso, "name"}; result_text lo cuenta.
## "GRID_REPAIR_NO_MATCH" es que hay que elegirlo a mano.
static func start(grid_id: String, bp_name: String = "") -> Dictionary:
	var group := GridManager.get_grid_group(grid_id)
	if group.is_empty():
		return {"error": "GRID_GONE"}
	var tree := (group[0] as GridBase).planet_node.get_tree()
	for site: BlueprintSite in sites_on(tree, group):
		return {"error": "GRID_REPAIR_ACTIVE" if site is RepairSite else "GRID_REPAIR_IS_SITE",
			"name": site.blueprint_name}
	var found := from_source(group, bp_name)
	if found.is_empty() and bp_name != "":
		var data := GridBlueprint.load_from_disk(bp_name)
		found = match_blueprint(data, group, false)
		if found.is_empty():
			return {"error": "GRID_REPAIR_NO_MATCH_ONE", "name": bp_name}
		found["name"] = bp_name
		found["data"] = data
	elif found.is_empty():
		found = find_blueprint(group)
		if found.is_empty():
			return {"error": "GRID_REPAIR_NO_MATCH"}
	var plan := repair_plan(found["data"], found, group)
	if plan["missing"] + plan["damaged"] == 0:
		# Entera: al menos ya sabe cuál es.
		for bi in (found["grids"] as Array).size():
			var grid: GridBase = found["grids"][bi]
			if grid != null:
				grid.set_source_blueprint(found["name"], bi, found["offset"])
		return {"error": "GRID_REPAIR_NOTHING", "name": found["name"]}
	var site := create_on(plan, group, found["name"])
	if BuildingSystem.free_build:
		while not site.is_complete():
			if site.work()["placed"] == 0:
				break
	return {"site": site, "name": found["name"], "missing": plan["missing"], "damaged": plan["damaged"]}


## Lo que se le cuenta al jugador de lo que devolvió start, ya traducido.
static func result_text(result: Dictionary) -> String:
	if result.has("error"):
		var reason := str(TranslationServer.translate(result["error"]))
		return reason % result.get("name", "") if reason.contains("%s") else reason
	if BuildingSystem.free_build:
		return str(TranslationServer.translate("GRID_REPAIRED_FREE")) % result["name"]
	return str(TranslationServer.translate("GRID_REPAIR_STARTED")) % [result["name"], result["missing"],
		result["damaged"]]


## Las obras y reparaciones que tienen alguna grid de [group].
static func sites_on(tree: SceneTree, group: Array) -> Array:
	var out := []
	for node in tree.get_nodes_in_group(GROUP):
		var site := node as BlueprintSite
		if site == null or site.is_queued_for_deletion():
			continue
		for grid: GridBase in group:
			if site.owns_grid(grid):
				out.append(site)
				break
	return out


## Pone la reparación de [plan] (repair_plan) en la construcción [group].
static func create_on(plan: Dictionary, group: Array, bp_name: String) -> RepairSite:
	var reference: GridBase = null
	for grid: GridBase in plan["grids"]:
		if grid != null:
			reference = grid
			break
	if reference == null:
		reference = group[0]
	var site := RepairSite.new()
	site._anchor_id = reference.grid_id
	site._attach(reference)
	site._setup(plan["plan"], bp_name, true)
	site._planet = reference.planet_node
	site._grids = (plan["grids"] as Array).duplicate()
	site._grid_ids = site._grids.map(func(grid: GridBase) -> String: return grid.grid_id if grid != null else "")
	site._refresh_ghost()
	return site


# --- Casar el blueprint ------------------------------------------------------------------------------

## El blueprint que apuntan las grids de [group] (GridBase.source_blueprint), casado como en
## match_blueprint pero sin buscar el desplazamiento: el de la mayoría de sus bloques o, con
## [bp_name], ese. {} si no lo saben, ya no está en la biblioteca o no queda nada suyo en pie.
static func from_source(group: Array, bp_name: String = "") -> Dictionary:
	var weight := {}
	for grid: GridBase in group:
		var source_name := str(grid.source_blueprint.get("name", ""))
		if source_name != "" and (bp_name == "" or source_name == bp_name):
			weight[source_name] = int(weight.get(source_name, 0)) + grid.get_block_count() + 1
	var best := ""
	for source_name: String in weight:
		if best == "" or weight[source_name] > weight[best]:
			best = source_name
	var data: Dictionary = GridBlueprint.load_from_disk(best) if best != "" else {}
	var index := _index(data)
	if index.is_empty():
		return {}
	var sorted := group.duplicate()
	sorted.sort_custom(func(a: GridBase, b: GridBase) -> bool: return a.get_block_count() > b.get_block_count())
	var grids := []
	grids.resize(index.size())
	var offset := Vector3.INF
	var matched := 0
	for grid: GridBase in sorted:
		var source := grid.source_blueprint
		if str(source.get("name", "")) != best:
			continue
		var bi := int(source.get("index", -1))
		var at := GridBase._array_to_vec3(source.get("offset", [0, 0, 0]))
		if offset == Vector3.INF:
			offset = at
		if bi < 0 or bi >= index.size() or grids[bi] != null or not at.is_equal_approx(offset) \
				or not is_equal_approx(grid.cell_size, index[bi]["cell_size"]):
			continue
		var cells: Variant = _cell_offset(offset, grid.cell_size)
		if cells == null:
			continue
		grids[bi] = grid
		matched += _count_matches(index[bi]["cells"], grid, cells)
	if matched == 0:
		return {}
	return {"offset": offset, "grids": grids, "matched": matched, "index": index, "name": best, "data": data}


## El blueprint de la biblioteca que mejor casa con [group]: el que explica más bloques suyos y, a
## igualdad, el más pequeño. Lo de match_blueprint con "name" y "data"; {} si no casa ninguno. Las
## fichas descartan sin leerlos los que no pueden casar por número de bloques o por tamaño de celda.
static func find_blueprint(group: Array) -> Dictionary:
	var blocks := _count_blocks(group)
	var sizes := {}
	for grid: GridBase in group:
		if grid.get_block_count() > 0:
			sizes[BuildCost.cell_key(grid.cell_size)] = true
	var best := {}
	for info: Dictionary in GridBlueprint.list_infos():
		var bp_blocks := int(info.get("blocks", 0))
		if bp_blocks < blocks * MIN_MATCH or blocks < bp_blocks * MIN_KEPT:
			continue
		var shares_cell := false
		for cell: Variant in info.get("cell_sizes", []):
			shares_cell = shares_cell or sizes.has(BuildCost.cell_key(float(cell)))
		if not shares_cell:
			continue
		var data := GridBlueprint.load_from_disk(info["name"])
		var found := match_blueprint(data, group)
		if found.is_empty():
			continue
		if best.is_empty() or found["matched"] > best["matched"] \
				or (found["matched"] == best["matched"] and found["bp_blocks"] < best["bp_blocks"]):
			found["name"] = info["name"]
			found["data"] = data
			best = found
	return best


## Casa el blueprint [data] con la construcción [group]. Devuelve {"offset": lo que hay que sumar
## (m) a una posición del blueprint para llevarla al espacio de las grids, "grids": la grid de la
## construcción de cada una del blueprint (null si no tiene), "matched": bloques de la construcción
## que están donde dice el blueprint, "blocks": los de la construcción, "bp_blocks": los del
## blueprint, "index": su _index}; {} si no casan bastante (MIN_MATCH, MIN_KEPT) o, sin [strict]
## (elegido a mano), si no coincide ningún bloque.
static func match_blueprint(data: Dictionary, group: Array, strict: bool = true) -> Dictionary:
	var index := _index(data)
	var filled := group.filter(func(grid: GridBase) -> bool: return grid.get_block_count() > 0)
	if index.is_empty() or filled.is_empty():
		return {}
	filled.sort_custom(func(a: GridBase, b: GridBase) -> bool: return a.get_block_count() > b.get_block_count())
	var reference: GridBase = filled[0]
	var sample := _spread(reference.get_all_blocks().keys(), QUICK_SAMPLES)
	var scored: Array = []
	for offset: Vector3i in _candidates(index, reference):
		scored.append([_quick_score(index, reference, sample, offset), offset])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var best := {}
	for k in mini(FINALISTS, scored.size()):
		var found := _score(index, filled, Vector3(scored[k][1]) * reference.cell_size)
		if best.is_empty() or found["matched"] > best["matched"]:
			best = found
	var blocks := _count_blocks(filled)
	var bp_blocks := 0
	for entry: Dictionary in index:
		bp_blocks += (entry["cells"] as Dictionary).size()
	if best.is_empty() or best["matched"] == 0 or (strict and (best["matched"] < blocks * MIN_MATCH
			or best["matched"] < bp_blocks * MIN_KEPT)):
		return {}
	best["blocks"] = blocks
	best["bp_blocks"] = bp_blocks
	best["index"] = index
	return best


## Por grid del blueprint, en su orden: su tamaño de celda, sus bloques (celda → id de bloque) y las
## celdas de cada id. Los de un id que ya no existe no cuentan.
static func _index(data: Dictionary) -> Array:
	var out := []
	for grid_data: Dictionary in data.get("grids", []):
		var cells := {}
		var by_id := {}
		var blocks: Dictionary = grid_data.get("blocks", {})
		for key: String in blocks:
			var parsed: Variant = GridBlueprint.parse_cell(key)
			var id := int((blocks[key] as Dictionary).get("block_id", -1))
			if parsed == null or BlockDatabase.get_block(id) == null:
				continue
			cells[parsed] = id
			if not by_id.has(id):
				by_id[id] = []
			(by_id[id] as Array).append(parsed)
		out.append({"cell_size": float(grid_data.get("cell_size", 1.0)), "cells": cells, "by_id": by_id})
	return out


## Desplazamientos (en celdas de [reference]) que merece la pena probar: los más votados (cada bloque
## que vota lo hace por los que lo llevan a un bloque igual del blueprint) y los que juntan las
## esquinas de las dos cajas, que valen aunque se hayan perdido los bloques que votan.
static func _candidates(index: Array, reference: GridBase) -> Array:
	var blocks := reference.get_all_blocks()
	var keys := blocks.keys()
	var low: Vector3i = keys[0]
	var high: Vector3i = keys[0]
	for cell: Vector3i in keys:
		low = low.min(cell)
		high = high.max(cell)
	var votes := {}
	var corners := []
	var budget := VOTE_BUDGET
	for entry: Dictionary in index:
		var cells: Dictionary = entry["cells"]
		if cells.is_empty() or not is_equal_approx(entry["cell_size"], reference.cell_size):
			continue
		var by_id: Dictionary = entry["by_id"]
		# Votan los de id más raro en el blueprint: votan por menos desplazamientos y cuestan menos.
		var voters := []
		for cell: Vector3i in _spread(keys, VOTE_SAMPLES * 4):
			voters.append([(by_id.get(int(blocks[cell]["block_id"]), []) as Array).size(), cell])
		voters.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for voter: Array in voters.slice(0, VOTE_SAMPLES):
			if budget <= 0:
				break
			var cell: Vector3i = voter[1]
			for match_cell: Vector3i in by_id.get(int(blocks[cell]["block_id"]), []):
				var offset := cell - match_cell
				votes[offset] = int(votes.get(offset, 0)) + 1
			budget -= int(voter[0])
		var bp_low: Vector3i = cells.keys()[0]
		var bp_high: Vector3i = bp_low
		for cell: Vector3i in cells:
			bp_low = bp_low.min(cell)
			bp_high = bp_high.max(cell)
		for mask in 8:
			var offset := Vector3i()
			for axis in 3:
				offset[axis] = high[axis] - bp_high[axis] if mask & (1 << axis) else low[axis] - bp_low[axis]
			corners.append(offset)
	# Los CANDIDATES más votados, sin ordenar todo lo votado (en un barco, decenas de miles).
	var top: Array = []
	for offset: Vector3i in votes:
		var n: int = votes[offset]
		if top.size() >= CANDIDATES and n <= top[-1][0]:
			continue
		var at := top.size()
		while at > 0 and top[at - 1][0] < n:
			at -= 1
		top.insert(at, [n, offset])
		if top.size() > CANDIDATES:
			top.pop_back()
	var out := top.map(func(pair: Array) -> Vector3i: return pair[1])
	for offset: Vector3i in corners:
		if not out.has(offset):
			out.append(offset)
	return out


## Cuántos bloques de [sample] (celdas de [reference]) caen, con [offset], en uno igual del blueprint.
static func _quick_score(index: Array, reference: GridBase, sample: Array, offset: Vector3i) -> int:
	var blocks := reference.get_all_blocks()
	var n := 0
	for cell: Vector3i in sample:
		var id := int(blocks[cell]["block_id"])
		for entry: Dictionary in index:
			if is_equal_approx(entry["cell_size"], reference.cell_size) \
					and int((entry["cells"] as Dictionary).get(cell - offset, -1)) == id:
				n += 1
				break
	return n


## Lo de match_blueprint para el desplazamiento [offset_m]: cada grid del blueprint se queda con la de
## la construcción de su tamaño de celda en la que más bloques coinciden (una para cada una).
static func _score(index: Array, group: Array, offset_m: Vector3) -> Dictionary:
	var pairs: Array = []
	for bi in index.size():
		var entry: Dictionary = index[bi]
		var offset: Variant = _cell_offset(offset_m, entry["cell_size"])
		if offset == null:
			continue
		var cells: Dictionary = entry["cells"]
		for grid: GridBase in group:
			if is_equal_approx(grid.cell_size, entry["cell_size"]):
				pairs.append([_count_matches(cells, grid, offset), bi, grid])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var grids := []
	grids.resize(index.size())
	var used := {}
	var matched := 0
	for pair: Array in pairs:
		if grids[pair[1]] == null and not used.has(pair[2]):
			grids[pair[1]] = pair[2]
			used[pair[2]] = true
			matched += pair[0]
	return {"offset": offset_m, "grids": grids, "matched": matched}


## Cuántos bloques de [grid], desplazados [offset] celdas, caen en uno igual de [cells] (celda del
## blueprint → id). Recorre el más pequeño de los dos.
static func _count_matches(cells: Dictionary, grid: GridBase, offset: Vector3i) -> int:
	var n := 0
	var blocks := grid.get_all_blocks()
	if blocks.size() <= cells.size():
		for cell: Vector3i in blocks:
			if int(cells.get(cell - offset, -1)) == int(blocks[cell]["block_id"]):
				n += 1
	else:
		for cell: Vector3i in cells:
			var info: Dictionary = blocks.get(cell + offset, {})
			if not info.is_empty() and int(info["block_id"]) == int(cells[cell]):
				n += 1
	return n


## [offset_m] en celdas de [cell_size], o null si no es un número entero de ellas.
static func _cell_offset(offset_m: Vector3, cell_size: float) -> Variant:
	var cells := offset_m / cell_size
	var error := (cells - cells.round()).abs()
	if maxf(error.x, maxf(error.y, error.z)) > GridBlueprint.CELL_EPSILON:
		return null
	return Vector3i(cells.round())


## Hasta [count] elementos de [items], repartidos.
static func _spread(items: Array, count: int) -> Array:
	if items.size() <= count:
		return items.duplicate()
	var out := []
	var step := float(items.size()) / count
	for k in count:
		out.append(items[floori(k * step)])
	return out


static func _count_blocks(group: Array) -> int:
	var n := 0
	for grid: GridBase in group:
		n += grid.get_block_count()
	return n


# --- Lo que hay que hacer ----------------------------------------------------------------------------

## Lo que hay que hacer para que [group] vuelva a ser [data], casados como dice [found]
## (match_blueprint): {"plan": el blueprint de la reparación, en el espacio de las grids, "grids": la
## grid de la construcción de cada una suya (null: hay que crearla), "missing": piezas que reponer,
## "damaged": bloques que arreglar}. El plan lleva también con qué casó, para apuntarlo en las grids
## al acabar: "offset", "owners" (id de grid → su grid en el blueprint) y "source" en cada grid suya.
static func repair_plan(data: Dictionary, found: Dictionary, group: Array) -> Dictionary:
	var offset_m: Vector3 = found["offset"]
	var index: Array = found["index"] if found.has("index") else _index(data)
	var grids_data: Array = data.get("grids", [])
	var plan_grids := []
	var refs := []
	var owners := {}
	var missing := 0
	var damaged := 0
	var low := Vector3.INF
	var high := -Vector3.INF
	for bi in grids_data.size():
		var grid_data: Dictionary = grids_data[bi]
		var cell_size := float(grid_data.get("cell_size", 1.0))
		var offset: Variant = _cell_offset(offset_m, cell_size)
		if offset == null:
			continue
		var grid: GridBase = found["grids"][bi]
		if grid != null:
			owners[grid.grid_id] = bi
		var cells: Dictionary = index[bi]["cells"]
		var blocks: Dictionary = grid_data.get("blocks", {})
		var put := {}
		var heal := {}
		for key: String in blocks:
			var parsed: Variant = GridBlueprint.parse_cell(key)
			if parsed == null or not cells.has(parsed):
				continue
			var info: Dictionary = blocks[key]
			var cell: Vector3i = parsed + offset
			var cell_key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
			var existing: Dictionary = grid.get_block(cell) if grid != null else {}
			if not existing.is_empty():
				if int(existing["block_id"]) == int(info.get("block_id", -1)) \
						and str(existing.get("material_id", "")) == str(info.get("material_id", "")) \
						and float(existing.get("hp", 1.0)) < 1.0:
					var entry := info.duplicate()
					entry["repair_cost"] = _heal_cost(existing, cell_size)
					heal[cell_key] = entry
				else:
					continue
			elif _taken(group, grid, cell, cell_size, found, index):
				continue
			else:
				put[cell_key] = info
			low = low.min(Vector3(cell) * cell_size)
			high = high.max(Vector3(cell + Vector3i.ONE) * cell_size)
		var props := []
		for prop: Dictionary in grid_data.get("props", []):
			var cell: Vector3i = GridBase._array_to_vec3i(prop.get("cell", [])) + offset
			if grid != null and grid.has_prop(cell, GridBase._array_to_vec3i(prop.get("face", []))):
				continue
			var moved := prop.duplicate(true)
			moved["cell"] = GridBase._vec3i_to_array(cell)
			var xform := GridBase._array_to_transform(prop.get("local_transform", []))
			xform.origin += offset_m
			moved["local_transform"] = GridBase._transform_to_array(xform)
			props.append(moved)
			low = low.min(Vector3(cell) * cell_size)
			high = high.max(Vector3(cell + Vector3i.ONE) * cell_size)
		var materials: Dictionary = grid_data.get("materials", {})
		if not put.is_empty() or not props.is_empty():
			plan_grids.append({"cell_size": cell_size, "blocks": put, "props": props, "materials": materials,
				"source": bi})
			refs.append(grid)
		if not heal.is_empty():
			plan_grids.append({"cell_size": cell_size, "blocks": heal, "props": [], "materials": materials,
				"repair": true, "source": bi})
			refs.append(grid)
		missing += put.size() + props.size()
		damaged += heal.size()
	var bp_low := GridBase._array_to_vec3(data.get("bounds_min", [0, 0, 0])) + offset_m
	var bp_high := GridBase._array_to_vec3(data.get("bounds_max", [0, 0, 0])) + offset_m
	if low == Vector3.INF:
		low = bp_low
		high = bp_high
	return {
		"plan": {
			"version": GridBlueprint.FORMAT_VERSION,
			"dynamic": false,
			"bounds_min": GridBase._vec3_to_array(low),
			"bounds_max": GridBase._vec3_to_array(high),
			"reach_min": GridBase._vec3_to_array(bp_low.min(low)),
			"reach_max": GridBase._vec3_to_array(bp_high.max(high)),
			"offset": GridBase._vec3_to_array(offset_m),
			"owners": owners,
			"grids": plan_grids,
		},
		"grids": refs,
		"missing": missing,
		"damaged": damaged,
	}


## Si en la celda [cell] (de una grid de [cell_size]) ya hay algo de otra grid de [group] que no es
## del blueprint: ahí no se repone nada, que lo puso el jugador. Los del blueprint sí se solapan (el
## relleno de un casco naval va en otra grid, encima de la pieza curva). [own] es la grid de la celda.
static func _taken(group: Array, own: GridBase, cell: Vector3i, cell_size: float, found: Dictionary,
	index: Array) -> bool:
	var low := Vector3(cell) * cell_size + Vector3.ONE * GridBlueprint.CELL_EPSILON
	var high := Vector3(cell + Vector3i.ONE) * cell_size - Vector3.ONE * GridBlueprint.CELL_EPSILON
	for grid: GridBase in group:
		if grid == own or grid.get_block_count() == 0:
			continue
		var bi: int = (found["grids"] as Array).find(grid)
		var offset: Variant = _cell_offset(found["offset"], grid.cell_size) if bi >= 0 else null
		var from := Vector3i((low / grid.cell_size).floor())
		var to := Vector3i((high / grid.cell_size).floor())
		for x in range(from.x, to.x + 1):
			for y in range(from.y, to.y + 1):
				for z in range(from.z, to.z + 1):
					var other := Vector3i(x, y, z)
					if not grid.has_block(other):
						continue
					if offset == null or not (index[bi]["cells"] as Dictionary).has(other - offset):
						return true
	return false


## Lo que cuesta devolverle la vida a un bloque: lo que le falta para valer lo que costó (al
## desmontarlo devuelve la parte que le queda, redondeando hacia arriba; ver BuildCost.of_grids).
static func _heal_cost(info: Dictionary, cell_size: float) -> int:
	var mat := BlockDatabase.get_material_by_id(str(info.get("material_id", "")))
	if mat == null or mat.item == null:
		return 0
	var cost := mat.get_cost_for_size(cell_size)
	return cost - mini(cost, ceili(cost * clampf(float(info.get("hp", 1.0)), 0.0, 1.0)))


# --- La obra ----------------------------------------------------------------------------------------

func _setup(data: Dictionary, bp_name: String, force_static: bool) -> void:
	super(data, bp_name, force_static)
	name = "RepairSite_%s" % bp_name.validate_node_name()
	var grids_data: Array = data.get("grids", [])
	_heal_grids.resize(grids_data.size())
	for gi in grids_data.size():
		_heal_grids[gi] = 1 if (grids_data[gi] as Dictionary).get("repair", false) else 0
	var reach_min := GridBase._array_to_vec3(data.get("reach_min", data.get("bounds_min", [0, 0, 0])))
	_reach_box = AABB(reach_min, GridBase._array_to_vec3(data.get("reach_max", data.get("bounds_max", [0, 0, 0]))) - reach_min)
	_heal_material = StandardMaterial3D.new()
	_heal_material.render_priority = 4
	_heal_material.albedo_color = HEAL_COLOR
	_heal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_heal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heal_material.grow = true
	_heal_material.grow_amount = HEAL_GROW


func _block_cost(info: Dictionary, cell_size: float) -> Dictionary:
	if not info.has("repair_cost"):
		return super(info, cell_size)
	var mat := BlockDatabase.get_material_by_id(str(info.get("material_id", "")))
	var amount := int(info["repair_cost"])
	if mat == null or mat.item == null or amount <= 0:
		return {}
	return {mat.item.id: amount}


func _is_heal(i: int) -> bool:
	return _heal_grids[_grid_of[i]] == 1


## Arreglar un bloque no ocupa más sitio del que ya ocupa: se puede estar encima.
func _needs_room(i: int) -> bool:
	return super(i) and not _is_heal(i)


func _put(i: int, grid: GridBase, others: Array) -> bool:
	if not _is_heal(i):
		return super(i, grid, others)
	var info: Dictionary = _data["grids"][_grid_of[i]]["blocks"][_keys[i]]
	var existing := grid.get_block(_cells[i])
	return not existing.is_empty() and int(existing["block_id"]) == int(info.get("block_id", -1)) \
		and grid.repair_block(_cells[i])


## Su grid [gi], buscada por id (al convertirla en dinámica cambia el objeto, no el id); si se perdió,
## otra alineada con la construcción.
func _grid(gi: int) -> GridBase:
	var grid: GridBase = GridManager.get_grid(str(_grid_ids[gi])) if gi < _grid_ids.size() else null
	if grid != null:
		_grids[gi] = grid
		return grid
	var reference := _reference()
	if reference == null or _planet == null:
		return null
	grid = GridManager.create_grid_aligned(_planet, reference, _cell_sizes[gi])
	GridBlueprint._restore_materials(grid, _data["grids"][gi])
	_grids[gi] = grid
	_grid_ids[gi] = grid.grid_id
	_created.append(grid.grid_id)
	return grid


## Una grid de la construcción que sigue en pie, o null.
func _reference() -> GridBase:
	var grid := GridManager.get_grid(_anchor_id)
	if grid != null:
		return grid
	for id: Variant in _grid_ids:
		grid = GridManager.get_grid(str(id))
		if grid != null:
			_anchor_id = grid.grid_id
			return grid
	return null


## Toda la construcción es suya: apuntándola se apunta a la reparación.
func _is_own(grid: GridBase) -> bool:
	var reference := _reference()
	return grid != null and reference != null and (grid == reference or grid.is_same_origin_basis(reference))


## Se cuelga de lo que mueve a [reference] (el cuerpo del barco o el planeta), en el espacio de sus
## grids.
func _attach(reference: GridBase) -> void:
	var parent: Node3D = (reference as DynamicPlanetGrid)._body if reference is DynamicPlanetGrid else reference.planet_node
	if parent == null or not is_instance_valid(parent):
		return
	if get_parent() != parent:
		if get_parent() != null:
			get_parent().remove_child(self)
		parent.add_child(self)
	transform = parent.global_transform.affine_inverse() * reference.get_grid_world_transform()


func _process(delta: float) -> void:
	_resync_left -= delta
	if _resync_left > 0.0:
		return
	_resync_left = RESYNC_TIME
	var reference := _reference()
	if reference == null:
		# La construcción ya no está (desmontarla desde el menú devuelve lo aportado; aquí no se
		# llega): lo aportado cae donde estaba y la reparación se quita.
		var down := -global_basis.y
		for id: StringName in deposited:
			var data := ItemCatalog.get_item(id)
			if data != null and int(deposited[id]) > 0:
				DroppedItem.spawn_at(self, data, int(deposited[id]), get_center(), down)
		deposited = {}
		remove()
		return
	# Convertida en dinámica: ahora la mueve su cuerpo.
	var body: Node3D = (reference as DynamicPlanetGrid)._body if reference is DynamicPlanetGrid else null
	if body != null and get_parent() != body:
		_attach(reference)


## Acabada: quita las grids que tuvo que crear y se quedaron vacías, y apunta en las de la
## construcción que son su blueprint. Devuelve las de la construcción.
func _complete() -> Array:
	for id: Variant in _created:
		var grid := GridManager.get_grid(str(id))
		if grid != null and grid.get_block_count() == 0 and grid.get_all_props().is_empty():
			GridManager.remove_grid(grid.grid_id)
	_mark_source()
	var reference := _reference()
	remove()
	return GridManager.get_grid_group(reference.grid_id) if reference != null else []


## Ya es la de su blueprint: lo apunta en sus grids (GridBase.source_blueprint), y la próxima vez
## no hay que buscarlo.
func _mark_source() -> void:
	if not _data.has("offset"):
		return
	var offset := GridBase._array_to_vec3(_data["offset"])
	var owners: Dictionary = (_data.get("owners", {}) as Dictionary).duplicate()
	var grids_data: Array = _data.get("grids", [])
	for gi in mini(_grid_ids.size(), grids_data.size()):
		if str(_grid_ids[gi]) != "" and (grids_data[gi] as Dictionary).has("source"):
			owners[str(_grid_ids[gi])] = grids_data[gi]["source"]
	for id: String in owners:
		var grid := GridManager.get_grid(id)
		if grid != null and grid.get_block_count() > 0:
			grid.set_source_blueprint(blueprint_name, int(owners[id]), offset)


func _ghost_material_for(gi: int) -> Material:
	return _heal_material if _heal_grids[gi] == 1 else _ghost_material


func set_aimed(aimed: bool) -> void:
	super(aimed)
	_heal_material.albedo_color = HEAL_AIMED_COLOR if aimed else HEAL_COLOR


func get_center() -> Vector3:
	return global_transform * _reach_box.get_center()


func get_radius() -> float:
	return _reach_box.size.length() * 0.5


func get_title() -> String:
	return tr("REPAIR_TITLE") % blueprint_name


func get_hint() -> String:
	return "REPAIR_HINT"


# --- Guardado -----------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var out := super()
	out["kind"] = KIND
	out["anchor_id"] = _anchor_id
	out["created"] = _created.duplicate()
	return out


## Vuelve a poner una reparación guardada, con las grids ya restauradas.
static func restore(tree: SceneTree, entry: Dictionary) -> void:
	var planet := tree.root.get_node_or_null(str(entry.get("planet_path", ""))) as Node3D
	var site := RepairSite.new()
	site._anchor_id = str(entry.get("anchor_id", ""))
	site._grid_ids = (entry.get("grid_ids", []) as Array).duplicate()
	var reference := site._reference()
	if planet == null or reference == null:
		push_warning("[RepairSite] No se encontró la construcción de la reparación '%s'" % entry.get("name", ""))
		site.free()
		return
	site._attach(reference)
	site._setup(entry.get("blueprint", {}), str(entry.get("name", "")), true)
	site._planet = planet
	site._created = (entry.get("created", []) as Array).duplicate()
	site._restore(entry)