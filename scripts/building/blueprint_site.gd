class_name BlueprintSite
extends Node3D

## Una obra: un blueprint colocado sin pagar que se levanta poco a poco. Se le aportan los
## materiales (deposit, con la E apuntándola) y se construye a martillazos (work): cada golpe pone los
## siguientes bloques, de abajo arriba, mientras haya aportado lo que cuestan. Si al que toca le falta
## su material se sigue con los siguientes que sí lo tienen. Lo que falta se ve como un fantasma
## translúcido; lo puesto ya son bloques de verdad en las grids de la obra. Los colocables van los
## últimos, con todos los bloques puestos. Acabada, se convierte en dinámica si el blueprint lo era (y
## no se colocó como estática) y la obra desaparece.
##
## El trabajo de un bloque es lo que cuesta (como mínimo 1) y el de un colocable, 1. Un golpe hace el
## de work_per_hit(): unos WORK_PER_HIT, sin bajar de MIN_HITS golpes para acabarla ni pasar de
## MAX_HITS.
##
## Una celda que al llegarle ya está ocupada (otra construcción, o un bloque puesto ahí a mano) se
## salta sin cobrar. Las que ocupa quien martillea esperan a que se aparte.
##
## Construyendo gratis (BuildingSystem.free_build) los golpes no piden material.
##
## Se guardan con las grids (GridManager): capture_all y restore_all.

const GROUP := &"blueprint_site"
const WORK_PER_HIT := 8.0
const MIN_HITS := 3
const MAX_HITS := 40
## Por encima de estos bloques el fantasma es la caja de lo que falta (como en BlueprintPlacer).
const GHOST_BLOCK_LIMIT := 4000
const GHOST_COLOR := Color(0.55, 0.85, 1.0, 0.18)
const GHOST_AIMED_COLOR := Color(0.65, 0.9, 1.0, 0.32)
## Cuerpo de quien martillea: lo que no se construye encima de él (radio y alto, m).
const BODY_RADIUS := 0.4
const BODY_HEIGHT := 1.8

enum State { PENDING, DONE, SKIPPED }

var blueprint_name := ""
var as_static := false
## Lo aportado que aún no se ha gastado (id de objeto → cantidad).
var deposited := {}

var _data: Dictionary = {}
var _planet: Node3D = null
## Una por grid del blueprint, en su orden (null si aún no hay o se perdió).
var _grids: Array = []
var _grid_ids: Array = []
var _cell_sizes := PackedFloat32Array()
## Celdas de los bloques de cada grid del blueprint (Vector3i → índice de su entrada): apuntar.
var _cells_by_grid: Array[Dictionary] = []
## Lo que hay que poner, en orden de construcción. Cada entrada es un bloque (_keys: su clave en el
## blueprint) o un colocable (_keys: su índice en la lista de la grid).
var _grid_of := PackedInt32Array()
var _keys: Array = []
var _cells: Array[Vector3i] = []
var _costs: Array[Dictionary] = []
var _amounts := PackedInt32Array()
var _state := PackedByteArray()
var _cursor := 0
var _blocks_left := 0
var _left := 0
var _total_work := 0.0
var _effective_work := 0.0
var _done_work := 0.0
## Lo que piden las entradas que no se han saltado, y lo ya gastado en las puestas (id → cantidad).
var _needed := {}
var _used := {}
var _box := AABB()
var _ghost_material: StandardMaterial3D = null
var _aimed := false
## Bloques de cada grid en el formato de ChunkMeshBuilder, para el fantasma (solo si se malla).
var _ghost_blocks: Array[Dictionary] = []
## Caja de las otras grids (id → [edit_version, AABB]): no se recorre cada una en cada golpe.
var _bounds_cache := {}


## Pone una obra de [data] en el planeta, con la esquina del blueprint en [placement] (mundo), y crea
## sus grids vacías.
static func create(data: Dictionary, planet: Node3D, placement: Transform3D, bp_name: String = "",
	force_static: bool = false) -> BlueprintSite:
	var site := BlueprintSite.new()
	planet.add_child(site)
	site.global_transform = placement
	site._setup(data, bp_name, force_static)
	site._grids = GridBlueprint.create_grids(data, planet, placement.origin, placement.basis)
	site._grid_ids = site._grids.map(func(grid: GridBase) -> String: return grid.grid_id)
	site._refresh_ghost()
	if site.is_complete():
		site._complete()
	return site


func _setup(data: Dictionary, bp_name: String, force_static: bool) -> void:
	name = "BlueprintSite_%s" % bp_name.validate_node_name()
	add_to_group(GROUP)
	_planet = get_parent() as Node3D
	_data = data
	blueprint_name = bp_name
	as_static = force_static
	var bmin := GridBase._array_to_vec3(data.get("bounds_min", [0, 0, 0]))
	_box = AABB(bmin, GridBase._array_to_vec3(data.get("bounds_max", [0, 0, 0])) - bmin)
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.render_priority = 4
	_ghost_material.albedo_color = GHOST_COLOR
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_entries()
	_state = PackedByteArray()
	_state.resize(_keys.size())
	_recount()


# --- Lo que hay que poner ---------------------------------------------------------------------------

## Las entradas en orden de construcción: por la altura de la base del bloque, después por grid y
## por filas (x, z); los colocables al final. Se ordena una clave entera por entrada (con su índice
## en los bits bajos) con el sort nativo: con sort_custom, un barco de decenas de miles de bloques
## tardaba en cargar.
func _build_entries() -> void:
	var grid_of := PackedInt32Array()
	var keys: Array = []
	var cells: Array[Vector3i] = []
	var costs: Array[Dictionary] = []
	var amounts := PackedInt32Array()
	var order := PackedInt64Array()
	var grids_data: Array = _data.get("grids", [])
	_cells_by_grid.clear()
	_cell_sizes.resize(grids_data.size())
	for gi in grids_data.size():
		var grid_data: Dictionary = grids_data[gi]
		var cell_size := float(grid_data.get("cell_size", 1.0))
		_cell_sizes[gi] = cell_size
		var blocks: Dictionary = grid_data.get("blocks", {})
		for key: String in blocks:
			var info: Dictionary = blocks[key]
			var parsed: Variant = GridBlueprint.parse_cell(key)
			if parsed == null or BlockDatabase.get_block(int(info.get("block_id", -1))) == null:
				continue
			var cell: Vector3i = parsed
			var item := &""
			var amount := 0
			var mat := BlockDatabase.get_material_by_id(str(info.get("material_id", "")))
			if mat != null and mat.item != null:
				item = mat.item.id
				amount = mat.get_cost_for_size(cell_size)
			order.append(_order_key(roundi(cell.y * cell_size * 8.0) + 32768, gi, cell.x, cell.z, keys.size()))
			grid_of.append(gi)
			keys.append(key)
			cells.append(cell)
			costs.append({item: amount} if item != &"" else {})
			amounts.append(amount)
		_cells_by_grid.append({})
		var props: Array = grid_data.get("props", [])
		for pi in props.size():
			var cost := BuildCost.prop_cost(props[pi])
			order.append(_order_key(65535, gi, 0, 0, keys.size()))
			grid_of.append(gi)
			keys.append(pi)
			cells.append(GridBase._array_to_vec3i((props[pi] as Dictionary).get("cell", [])))
			costs.append(cost)
			amounts.append(BuildCost.total(cost))
	if keys.size() < (1 << 20):
		order.sort()
	_grid_of = PackedInt32Array()
	_keys = []
	_cells = []
	_costs = []
	_amounts = PackedInt32Array()
	for key in order:
		var i := int(key & ((1 << 20) - 1)) if keys.size() < (1 << 20) else _grid_of.size()
		_grid_of.append(grid_of[i])
		_keys.append(keys[i])
		_cells.append(cells[i])
		_costs.append(costs[i])
		_amounts.append(amounts[i])
		if keys[i] is String:
			_cells_by_grid[grid_of[i]][cells[i]] = _keys.size() - 1
	_total_work = 0.0
	for amount in _amounts:
		_total_work += maxi(1, amount)


## Clave de orden: 16 bits de capa, 3 de grid, 12 de x, 12 de z y 20 del índice. Lo que se sale se
## recorta, y solo cambia el orden.
static func _order_key(layer: int, gi: int, x: int, z: int, index: int) -> int:
	return (clampi(layer, 0, 65535) << 47) | (clampi(gi, 0, 7) << 44) | (clampi(x + 2048, 0, 4095) << 32) \
		| (clampi(z + 2048, 0, 4095) << 20) | (index & ((1 << 20) - 1))


## Rehace las cuentas a partir del estado de cada entrada.
func _recount() -> void:
	_needed = {}
	_used = {}
	_effective_work = 0.0
	_done_work = 0.0
	_blocks_left = 0
	_left = 0
	_cursor = 0
	for i in _state.size():
		if _state[i] == State.SKIPPED:
			continue
		var work := maxi(1, _amounts[i])
		_effective_work += work
		for id: StringName in _costs[i]:
			BuildCost.add(_needed, id, _costs[i][id])
		if _state[i] == State.DONE:
			_done_work += work
			for id: StringName in _costs[i]:
				BuildCost.add(_used, id, _costs[i][id])
		else:
			_left += 1
			if _keys[i] is String:
				_blocks_left += 1
	_advance_cursor()


func _advance_cursor() -> void:
	while _cursor < _state.size() and _state[_cursor] != State.PENDING:
		_cursor += 1


# --- Estado -------------------------------------------------------------------------------------------

func is_complete() -> bool:
	return _left == 0


## Lo hecho (0–1), por trabajo.
func progress() -> float:
	return 1.0 if _effective_work <= 0.0 else clampf(_done_work / _effective_work, 0.0, 1.0)


## Lo que se lleva a la obra hasta acabarla (id → cantidad).
func get_cost() -> Dictionary:
	return _needed


## Lo que ya tiene, gastado o por gastar (id → cantidad).
func get_supplied() -> Dictionary:
	var out := _used.duplicate()
	for id: StringName in deposited:
		BuildCost.add(out, id, int(deposited[id]))
	return out


## Lo que falta aportarle para acabarla (id → cantidad); vacío si ya tiene todo.
func get_missing() -> Dictionary:
	var out := {}
	for id: StringName in _needed:
		var left := int(_needed[id]) - int(_used.get(id, 0)) - int(deposited.get(id, 0))
		if left > 0:
			out[id] = left
	return out


## Trabajo de un golpe.
func work_per_hit() -> float:
	var hits := clampi(ceili(_total_work / WORK_PER_HIT), MIN_HITS, MAX_HITS)
	return _total_work / hits


## Por qué ahora un golpe no pondría nada: &"missing" (le falta material para todo lo que queda),
## &"blocked" (lo único que se puede poner está donde está alguien de [bodies], posiciones de los
## pies en el mundo) o &"done"; &"" si pondría algo.
func work_problem(bodies: Array = []) -> StringName:
	if is_complete():
		return &"done"
	var boxes := _body_boxes(bodies)
	var blocked := false
	for i in range(_cursor, _state.size()):
		if _state[i] != State.PENDING:
			continue
		if _keys[i] is int and _blocks_left > 0:
			break
		if not _can_pay(i):
			continue
		if _keys[i] is String and _under_body(i, boxes):
			blocked = true
			continue
		return &""
	return &"blocked" if blocked else &"missing"


## Saca de [inventory] lo que le falta, lo que haya. Devuelve lo aportado (id → cantidad).
func deposit(inventory: Inventory) -> Dictionary:
	var moved := {}
	if inventory == null:
		return moved
	var missing := get_missing()
	for id: StringName in missing:
		var item := ItemCatalog.get_item(id)
		var amount := mini(int(missing[id]), inventory.get_item_count(item))
		if amount > 0:
			amount = inventory.remove_item(item, amount)
			BuildCost.add(deposited, id, amount)
			BuildCost.add(moved, id, amount)
	return moved


## Lo aportado y sin gastar, que sale de la obra (al desmontarla o al acabarla con sobrante).
func take_deposited() -> Dictionary:
	var out := deposited
	deposited = {}
	return out


# --- Martillazos --------------------------------------------------------------------------------------

## Un golpe: pone lo siguiente hasta hacer el trabajo de un golpe. [bodies] son los pies de quien
## está cerca (nada se pone encima de ellos). Devuelve {"placed": cuántos puso, "sound": la familia
## de sonido del material del primero, "problem": como work_problem si no puso nada, "finished": si
## la ha acabado, "grids": las grids resultantes al acabarla}.
func work(bodies: Array = []) -> Dictionary:
	var result := {"placed": 0, "sound": &"", "problem": &"", "finished": false, "grids": []}
	if is_complete():
		result["problem"] = &"done"
		return result
	var boxes := _body_boxes(bodies)
	var others := _other_grids()
	var budget := work_per_hit()
	var editing := {}
	var blocked := false
	for i in range(_cursor, _state.size()):
		if _state[i] != State.PENDING:
			continue
		var is_prop: bool = _keys[i] is int
		if is_prop and _blocks_left > 0:
			break
		if not _can_pay(i):
			continue
		if not is_prop and _under_body(i, boxes):
			blocked = true
			continue
		var grid := _grid(_grid_of[i])
		if grid == null:
			continue
		if not editing.has(grid):
			editing[grid] = true
			grid.begin_batch_edit()
		if not _place(i, grid, others):
			continue
		if result["placed"] == 0:
			result["sound"] = _sound_of(i)
		result["placed"] += 1
		budget -= maxi(1, _amounts[i])
		if budget <= 0.0:
			break
	for grid: GridBase in editing:
		grid.end_batch_edit()
	_advance_cursor()
	if result["placed"] == 0:
		result["problem"] = &"blocked" if blocked else &"missing"
	_refresh_ghost()
	if is_complete():
		result["finished"] = true
		result["grids"] = _complete()
	return result


func _can_pay(i: int) -> bool:
	if BuildingSystem.free_build:
		return true
	for id: StringName in _costs[i]:
		if int(deposited.get(id, 0)) < int(_costs[i][id]):
			return false
	return true


## Pone la entrada [i] en [grid]. Si su celda ya está ocupada, o no se puede, se salta sin cobrar.
func _place(i: int, grid: GridBase, others: Array) -> bool:
	var grid_data: Dictionary = _data["grids"][_grid_of[i]]
	var placed := false
	if _keys[i] is int:
		placed = GridBlueprint.place_prop(grid, grid_data["props"][_keys[i]])
	elif not grid.has_block(_cells[i]) and not _overlaps_other(grid, _cells[i], others):
		placed = GridBlueprint.place_block(grid, _cells[i], GridBlueprint.block_info(grid_data["blocks"][_keys[i]]))
	_left -= 1
	if _keys[i] is String:
		_blocks_left -= 1
	var work := maxi(1, _amounts[i])
	if not placed:
		_state[i] = State.SKIPPED
		_effective_work -= work
		for id: StringName in _costs[i]:
			BuildCost.add(_needed, id, -int(_costs[i][id]))
		return false
	_state[i] = State.DONE
	_done_work += work
	for id: StringName in _costs[i]:
		var amount: int = _costs[i][id]
		BuildCost.add(_used, id, amount)
		if not BuildingSystem.free_build:
			BuildCost.add(deposited, id, -amount)
			if int(deposited.get(id, 0)) <= 0:
				deposited.erase(id)
	return true


func _sound_of(i: int) -> StringName:
	if _keys[i] is String:
		var info: Dictionary = _data["grids"][_grid_of[i]]["blocks"][_keys[i]]
		var mat := BlockDatabase.get_material_by_id(str(info.get("material_id", "")))
		if mat != null:
			return mat.sound_material
	return &"wood"


## La grid [gi] de la obra; si se perdió (la desmontaron o convirtieron desde el menú), otra nueva en
## el mismo sitio.
func _grid(gi: int) -> GridBase:
	var grid: GridBase = _grids[gi] if gi < _grids.size() else null
	if grid != null and GridManager.get_grid(grid.grid_id) == grid:
		return grid
	if _planet == null or not is_inside_tree():
		return null
	grid = GridManager.create_grid_exact(_planet, global_transform.origin, global_transform.basis, _cell_sizes[gi])
	GridBlueprint._restore_materials(grid, _data["grids"][gi])
	while _grids.size() <= gi:
		_grids.append(null)
		_grid_ids.append("")
	_grids[gi] = grid
	_grid_ids[gi] = grid.grid_id
	return grid


func _is_own(grid: GridBase) -> bool:
	return _grids.has(grid)


## Las grids del planeta que no son de la obra y tocan su caja.
func _other_grids() -> Array:
	var out := []
	if _planet == null:
		return out
	for grid: GridBase in GridManager.get_grids_for_planet(_planet):
		if _is_own(grid) or grid.get_block_count() == 0:
			continue
		var cached: Array = _bounds_cache.get(grid.grid_id, [])
		if cached.is_empty() or cached[0] != grid.edit_version:
			cached = [grid.edit_version, BlueprintPlacer._grid_bounds(grid)]
			_bounds_cache[grid.grid_id] = cached
		var to_grid := grid.get_grid_world_transform().affine_inverse() * global_transform
		if (to_grid * _box).intersects(cached[1]):
			out.append(grid)
	return out


func _overlaps_other(grid: GridBase, cell: Vector3i, others: Array) -> bool:
	var center := grid.get_grid_world_transform() * ((Vector3(cell) + Vector3.ONE * 0.5) * grid.cell_size)
	for other: GridBase in others:
		if other.has_block(other.world_to_cell(center)):
			return true
	return false


## Cajas de los cuerpos en el espacio del blueprint (+Y arriba, como al colocarlo).
func _body_boxes(bodies: Array) -> Array[AABB]:
	var out: Array[AABB] = []
	if not is_inside_tree():
		return out
	var to_local := global_transform.affine_inverse()
	for feet: Vector3 in bodies:
		var p := to_local * feet
		out.append(AABB(p - Vector3(BODY_RADIUS, 0.0, BODY_RADIUS), Vector3(BODY_RADIUS * 2.0, BODY_HEIGHT, BODY_RADIUS * 2.0)))
	return out


func _under_body(i: int, boxes: Array[AABB]) -> bool:
	if boxes.is_empty():
		return false
	var cell_size := _cell_sizes[_grid_of[i]]
	var box := AABB(Vector3(_cells[i]) * cell_size, Vector3.ONE * cell_size).grow(-0.02)
	for body in boxes:
		if body.intersects(box):
			return true
	return false


## Con todo puesto: quita las grids que se quedaron vacías, la convierte en dinámica si toca y la obra
## desaparece. Devuelve las grids resultantes.
func _complete() -> Array:
	var built := []
	for gi in _grids.size():
		var grid: GridBase = _grids[gi]
		if grid == null or GridManager.get_grid(grid.grid_id) != grid:
			continue
		if grid.get_block_count() == 0 and grid.get_all_props().is_empty():
			GridManager.remove_grid(grid.grid_id)
		else:
			built.append(grid)
	var result := GridBlueprint.finish(_data, built, as_static)
	remove()
	return result


## Quita la obra (sin tocar sus grids).
func remove() -> void:
	remove_from_group(GROUP)
	_grids = []
	if get_parent():
		get_parent().remove_child(self)
	queue_free()


## Id de una de sus grids que sigue en pie (las demás van en su grupo: GridManager.get_grid_group), o "".
func get_grid_id() -> String:
	for grid: GridBase in _grids:
		if grid != null and GridManager.get_grid(grid.grid_id) == grid:
			return grid.grid_id
	return ""


func owns_grid(grid: GridBase) -> bool:
	return grid != null and _is_own(grid)


# --- Fantasma y puntería ----------------------------------------------------------------------------

func set_aimed(aimed: bool) -> void:
	if aimed == _aimed:
		return
	_aimed = aimed
	_ghost_material.albedo_color = GHOST_AIMED_COLOR if aimed else GHOST_COLOR


## Lo que queda por poner, en translúcido: la geometría de cada grid o, en una obra grande, la caja de
## lo que falta.
func _refresh_ghost() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			remove_child(child)
			child.queue_free()
	if _blocks_left <= 0:
		return
	if _keys.size() > GHOST_BLOCK_LIMIT:
		var low := Vector3.INF
		var high := -Vector3.INF
		for i in range(_cursor, _state.size()):
			if _state[i] == State.PENDING and _keys[i] is String:
				var cell_size := _cell_sizes[_grid_of[i]]
				low = low.min(Vector3(_cells[i]) * cell_size)
				high = high.max(Vector3(_cells[i] + Vector3i.ONE) * cell_size)
		var box := BoxMesh.new()
		box.size = high - low
		_add_ghost(box, (low + high) * 0.5)
		return
	if _ghost_blocks.is_empty():
		for grid_data: Dictionary in _data.get("grids", []):
			_ghost_blocks.append(GridBlueprint.blocks_dict(grid_data))
	for gi in _cells_by_grid.size():
		var pending := {}
		for cell: Vector3i in _cells_by_grid[gi]:
			if _state[_cells_by_grid[gi][cell]] == State.PENDING:
				pending[cell] = true
		if pending.is_empty():
			continue
		var mesh := ChunkMeshBuilder.build_mesh(_ghost_blocks[gi], _cell_sizes[gi], Transform3D.IDENTITY, {}, pending)
		if mesh:
			_add_ghost(mesh, Vector3.ZERO)


func _add_ghost(mesh: Mesh, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _ghost_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Distancia por el rayo (mundo) hasta el primer bloque de la obra, puesto o por poner; -1 si no la
## toca antes de [max_distance]. Recorre las celdas de cada grid del blueprint (DDA).
func ray_distance(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var to_local := global_transform.affine_inverse()
	var o := to_local * origin
	var d := (to_local.basis * direction).normalized()
	var span := _slab(o, d, _box.grow(0.01))
	if span.y < 0.0 or span.x > max_distance:
		return -1.0
	var best := -1.0
	for gi in _cells_by_grid.size():
		var t := _march(o, d, maxf(span.x, 0.0), minf(span.y, max_distance), _cell_sizes[gi], _cells_by_grid[gi])
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## Centro de la obra en el mundo y radio que la cubre.
func get_center() -> Vector3:
	return global_transform * _box.get_center()


func get_radius() -> float:
	return _box.size.length() * 0.5


## Tramo [entrada, salida] del rayo dentro de la caja; (-1, -1) si no la cruza.
static func _slab(o: Vector3, d: Vector3, box: AABB) -> Vector2:
	var t0 := -INF
	var t1 := INF
	for axis in 3:
		if absf(d[axis]) < 1e-9:
			if o[axis] < box.position[axis] or o[axis] > box.end[axis]:
				return Vector2(-1, -1)
			continue
		var a := (box.position[axis] - o[axis]) / d[axis]
		var b := (box.end[axis] - o[axis]) / d[axis]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	if t1 < maxf(t0, 0.0):
		return Vector2(-1, -1)
	return Vector2(t0, t1)


## Primera celda de [cells] que cruza el rayo entre [t0] y [t1] (Amanatides-Woo); -1 si ninguna.
static func _march(o: Vector3, d: Vector3, t0: float, t1: float, cell_size: float, cells: Dictionary) -> float:
	if cells.is_empty():
		return -1.0
	var p := o + d * t0
	var cell := Vector3i((p / cell_size).floor())
	var step := Vector3i(int(signf(d.x)), int(signf(d.y)), int(signf(d.z)))
	var t_max := Vector3.INF
	var t_delta := Vector3.INF
	for axis in 3:
		if step[axis] == 0:
			continue
		var boundary := float(cell[axis] + (1 if step[axis] > 0 else 0)) * cell_size
		t_max[axis] = t0 + (boundary - p[axis]) / d[axis]
		t_delta[axis] = cell_size / absf(d[axis])
	var t := t0
	var steps := ceili((t1 - t0) / cell_size) * 3 + 3
	for _i in steps:
		if t > t1:
			break
		if cells.has(cell):
			return t
		var axis := 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		t = t_max[axis]
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
	return -1.0


# --- Guardado -----------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var stored := {}
	for id: StringName in deposited:
		stored[str(id)] = int(deposited[id])
	return {
		"name": blueprint_name,
		"as_static": as_static,
		"planet_path": str(_planet.get_path()) if _planet else "",
		"transform": GridBase._transform_to_array(transform),
		"grid_ids": _grid_ids,
		"state": Marshalls.raw_to_base64(_state),
		"deposited": stored,
		"blueprint": _data,
	}


static func capture_all(tree: SceneTree) -> Array:
	var out := []
	for node in tree.get_nodes_in_group(GROUP):
		var site := node as BlueprintSite
		if site != null and not site.is_queued_for_deletion():
			out.append(site.get_save_data())
	return out


## Vuelve a poner las obras guardadas, con las grids ya restauradas.
static func restore_all(tree: SceneTree, entries: Array) -> void:
	for entry: Dictionary in entries:
		var planet := tree.root.get_node_or_null(str(entry.get("planet_path", ""))) as Node3D
		if planet == null:
			push_warning("[BlueprintSite] No se encontró el planeta de la obra '%s'" % entry.get("name", ""))
			continue
		var site := BlueprintSite.new()
		planet.add_child(site)
		site.transform = GridBase._array_to_transform(entry.get("transform", []))
		site._setup(entry.get("blueprint", {}), str(entry.get("name", "")), bool(entry.get("as_static", false)))
		site._restore(entry)


func _restore(entry: Dictionary) -> void:
	_grid_ids = (entry.get("grid_ids", []) as Array).duplicate()
	_grids = []
	for gi in _grid_ids.size():
		var grid := GridManager.get_grid(str(_grid_ids[gi]))
		if grid != null and gi < _cell_sizes.size():
			GridBlueprint._restore_materials(grid, _data["grids"][gi])
		_grids.append(grid)
	var state := Marshalls.base64_to_raw(str(entry.get("state", "")))
	if state.size() == _state.size():
		_state = state
	else:
		# El blueprint no casa con lo guardado: se da por puesto lo que ya está en sus grids.
		for i in _state.size():
			var grid: GridBase = _grids[_grid_of[i]] if _grid_of[i] < _grids.size() else null
			if grid != null and _keys[i] is String and grid.has_block(_cells[i]):
				_state[i] = State.DONE
	var stored: Dictionary = entry.get("deposited", {})
	deposited = {}
	for id: String in stored:
		deposited[StringName(id)] = int(stored[id])
	_recount()
	_refresh_ghost()


static func clear_all(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		(node as BlueprintSite).remove()
