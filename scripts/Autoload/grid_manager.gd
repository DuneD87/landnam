extends Node

## Autoload singleton que gestiona todas las grids (estáticas y dinámicas) de todos los planetas:
## las crea, busca, alinea, convierte a dinámicas y las serializa para guardado. Registrar en
## Project > AutoLoad como "GridManager".

# Distancia máxima (en celdas) para reutilizar una grid existente.
const MAX_REUSE_CELLS := 16

# Ángulo máximo (radianes) entre bases para considerar dos grids "alineadas".
const MAX_BASIS_ANGLE := deg_to_rad(5.0)
## Distancia máxima para considerar que un bloque pertenece a una grid existente.
@export var snap_distance: float = 5.0

var _grids: Dictionary = {}
var _planet_grids: Dictionary = {}
var _next_id: int = 0
var entity_id: String = "grid_manager"
var save_category: String = "grid"


func get_save_data() -> Dictionary:
	var grids_data: Dictionary = {}

	for grid_id in _grids:
		var grid: GridBase = _grids[grid_id]
		grids_data[grid_id] = grid.serialize()

	return {
		"next_id": _next_id,
		"grids": grids_data,
	}


func restore_save_data(data: Dictionary) -> void:
	clear_all()

	_next_id = data.get("next_id", 0)

	var grids_data: Dictionary = data.get("grids", {})

	var dynamic_grids: Dictionary = {}

	for grid_id in grids_data:
		var grid_data: Dictionary = grids_data[grid_id]
		var grid_type: String = grid_data.get("type", "static")

		if grid_type == "dynamic":
			var bid: String = grid_data.get("body_id", grid_id)
			if not dynamic_grids.has(bid):
				dynamic_grids[bid] = []
			dynamic_grids[bid].append({"grid_id": grid_id, "data": grid_data})
		else:
			var planet_path: String = grid_data.get("planet_path", "")
			var planet: Node3D = get_tree().root.get_node_or_null(planet_path)
			if not planet:
				push_warning("[GridManager] No se encontró planeta '%s' al cargar grid '%s'" % [planet_path, grid_id])
				continue

			var grid := PlanetGrid.new()
			grid.deserialize(grid_id, planet, grid_data)
			_grids[grid_id] = grid
			if not _planet_grids.has(planet):
				_planet_grids[planet] = []
			_planet_grids[planet].append(grid)

	for bid in dynamic_grids:
		var group: Array = dynamic_grids[bid]
		var shared_body: DynamicGridBody = null

		for i in group.size():
			var entry: Dictionary = group[i]
			var grid_id: String = entry["grid_id"]
			var grid_data: Dictionary = entry["data"]

			var planet_path: String = grid_data.get("planet_path", "")
			var planet: Node3D = get_tree().root.get_node_or_null(planet_path)
			if not planet:
				push_warning("[GridManager] No se encontró planeta '%s' al cargar grid '%s'" % [planet_path, grid_id])
				continue

			var dyn := DynamicPlanetGrid.new()

			if i == 0:
				dyn.deserialize(grid_id, planet, grid_data, null)
				shared_body = dyn._body
			else:
				dyn.deserialize(grid_id, planet, grid_data, shared_body)

			_grids[grid_id] = dyn
			if not _planet_grids.has(planet):
				_planet_grids[planet] = []
			_planet_grids[planet].append(dyn)

	for grid_id in _grids:
		var grid: GridBase = _grids[grid_id]
		if grid is DynamicPlanetGrid and (grid as DynamicPlanetGrid)._body:
			(grid as DynamicPlanetGrid)._body.update_mass_from_grids()

	print("[GridManager] Restauradas %d grids" % _grids.size())

func _ready() -> void:
	add_to_group(GameManager.SAVEABLE_GROUP)
	_init_uniform_buffers()


const MAX_WAKES := 8
const MAX_WAKE_POINTS := 512
# Holgura (m) de la esfera de culling de cada estela; ver dónde se construye.
const WAKE_BOUNDS_MARGIN := 12.0
# Opacidad de la espuma de estela recién nacida.
const WAKE_ALPHA := 0.35
const MAX_INTERIORS := 64
# Margen (m) alrededor del casco dentro del cual se activa la máscara de interiores.
const INTERIOR_MASK_MARGIN := 12.0
# Radio (m) alrededor de la cámara cuyas cajas entran en el presupuesto antes que ninguna otra.
const INTERIOR_NEAR_RADIUS := 24.0

## Interruptor de la espuma de estela, para aislar su coste en pantalla. Lo mueve el comando 'wake'.
var wake_enabled: bool = true
## Última cuenta de estelas y puntos subidos al shader; la lee el comando 'wake'.
var wake_stat_wakes: int = 0
var wake_stat_points: int = 0

var _wake_materials_active: Array = []
var _interior_materials_active: Array = []
var _interior_counts: Dictionary = {}
var _interior_overflow_warned: bool = false

# Buffers de uniforms reutilizados entre frames: el shader solo lee las primeras 'count'
# entradas, así que la cola obsoleta no molesta y evitamos realojarlos 60 veces por segundo.
var _interior_centers := PackedVector4Array()
var _interior_axis_x := PackedVector4Array()
var _interior_axis_y := PackedVector4Array()
var _interior_axis_z := PackedVector4Array()
var _wake_points_buf := PackedVector4Array()
var _wake_alphas_buf := PackedFloat32Array()
var _wake_bounds_buf := PackedVector4Array()
var _wake_ranges_buf := PackedVector2Array()


func _init_uniform_buffers() -> void:
	_interior_centers.resize(MAX_INTERIORS)
	_interior_axis_x.resize(MAX_INTERIORS)
	_interior_axis_y.resize(MAX_INTERIORS)
	_interior_axis_z.resize(MAX_INTERIORS)
	_wake_points_buf.resize(MAX_WAKE_POINTS)
	_wake_alphas_buf.resize(MAX_WAKE_POINTS)
	_wake_bounds_buf.resize(MAX_WAKES)
	_wake_ranges_buf.resize(MAX_WAKES)


func _physics_process(_delta: float) -> void:
	var bodies := get_tree().get_nodes_in_group("dynamic_grid_body")
	if bodies.is_empty() and _interior_materials_active.is_empty():
		return
	_update_interior_uniforms(bodies)


## La estela se empuja por frame renderizado y no de física: el casco se dibuja con la transform
## interpolada, y a ritmo de física la estela iba un paso por detrás, tanto más cuanto más rápido.
func _process(_delta: float) -> void:
	if not wake_enabled:
		for mat in _wake_materials_active:
			if is_instance_valid(mat):
				mat.set_shader_parameter("wake_count", 0)
		_wake_materials_active = []
		wake_stat_wakes = 0
		wake_stat_points = 0
		return
	var bodies := get_tree().get_nodes_in_group("dynamic_grid_body")
	if bodies.is_empty() and _wake_materials_active.is_empty():
		return
	_update_wake_uniforms(bodies)

## Copia las cajas de compartimentos secos de los DynamicGridBody al agua de su planeta:
## dentro el shader descarta el agua; lo inundado no se empuja y el océano entra normal.
func _update_interior_uniforms(bodies: Array) -> void:
	var per_mat: Dictionary = {}
	for node in bodies:
		var body := node as DynamicGridBody
		if not body or not body.planet_node or not body.planet_node.planet.has_water:
			continue
		var mat := body.planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
		if not mat:
			continue
		if not per_mat.has(mat):
			per_mat[mat] = []
		per_mat[mat].append(body)

	for mat in _interior_materials_active:
		if is_instance_valid(mat) and not per_mat.has(mat):
			mat.set_shader_parameter("interior_count", 0)
			_interior_counts.erase(mat)
	_interior_materials_active = per_mat.keys()

	var camera := get_viewport().get_camera_3d()

	for mat: ShaderMaterial in per_mat:
		var count := 0
		for body: DynamicGridBody in per_mat[mat]:
			if count >= MAX_INTERIORS:
				break
			# El bucle del shader se paga por píxel: solo con la cámara a bordo o pegada al casco.
			if camera and not body.contains_point(camera.global_position, INTERIOR_MASK_MARGIN):
				continue
			var xf := body.global_transform
			var boxes: Array = body.get_dry_interior_boxes()

			# El presupuesto se gasta primero en las cajas que rodean a la cámara: si sobran
			# cajas, lo que se cae es interior lejano y no la sala donde estás mirando.
			if camera:
				var cam_local: Vector3 = xf.affine_inverse() * camera.global_position
				var near_r2: float = INTERIOR_NEAR_RADIUS * INTERIOR_NEAR_RADIUS
				count = _push_interior_boxes(boxes, xf, cam_local, near_r2, true, count)
				count = _push_interior_boxes(boxes, xf, cam_local, near_r2, false, count)
			else:
				count = _push_interior_boxes(boxes, xf, Vector3.ZERO, -1.0, false, count)

			if boxes.size() > MAX_INTERIORS and not _interior_overflow_warned:
				_interior_overflow_warned = true
				push_warning("[GridManager] '%s' tiene %d cajas de interior seco y MAX_INTERIORS es %d: la máscara del agua se trunca." % [body.name, boxes.size(), MAX_INTERIORS])

		# Con la cámara lejos de todo casco (el caso normal) no hay nada que empujar y el
		# contador ya está a cero: ni un set_shader_parameter por frame.
		if count == 0 and _interior_counts.get(mat, 0) == 0:
			continue
		_interior_counts[mat] = count

		mat.set_shader_parameter("interior_count", count)
		if count == 0:
			continue
		mat.set_shader_parameter("interior_center", _interior_centers)
		mat.set_shader_parameter("interior_axis_x", _interior_axis_x)
		mat.set_shader_parameter("interior_axis_y", _interior_axis_y)
		mat.set_shader_parameter("interior_axis_z", _interior_axis_z)

## Vuelca cajas de interior seco en los buffers de uniforms. Con near_pass true solo entran las
## que están a menos de near_r2 (distancia al cuerpo de la caja, en espacio local) de la cámara;
## con false, solo el resto. Devuelve el nuevo count.
func _push_interior_boxes(boxes: Array, xf: Transform3D, cam_local: Vector3, near_r2: float,
		near_pass: bool, count: int) -> int:
	for box: Dictionary in boxes:
		if count >= MAX_INTERIORS:
			return count
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["half"]
		var d: Vector3 = ((cam_local - pos).abs() - half).max(Vector3.ZERO)
		if (d.length_squared() <= near_r2) != near_pass:
			continue

		var c: Vector3 = xf * pos
		_interior_centers[count] = Vector4(c.x, c.y, c.z, 0.0)
		_interior_axis_x[count] = Vector4(xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, half.x)
		_interior_axis_y[count] = Vector4(xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, half.y)
		_interior_axis_z[count] = Vector4(xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, half.z)
		count += 1
	return count


## Copia los puntos de estela de todos los DynamicGridBody a los uniforms del agua de su planeta.
func _update_wake_uniforms(bodies: Array) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var per_mat: Dictionary = {}

	for node in bodies:
		var body := node as DynamicGridBody
		if not body or not body.planet_node or body.get_wake_points().is_empty():
			continue
		if not body.planet_node.planet.has_water:
			continue
		var mat := body.planet_node.water_sphere.mesh_manager.default_material as ShaderMaterial
		if not mat:
			continue
		if not per_mat.has(mat):
			per_mat[mat] = []
		per_mat[mat].append(body)

	for mat in _wake_materials_active:
		if is_instance_valid(mat) and not per_mat.has(mat):
			mat.set_shader_parameter("wake_count", 0)
	_wake_materials_active = per_mat.keys()

	for mat: ShaderMaterial in per_mat:
		var wake_i := 0
		var point_i := 0
		for body: DynamicGridBody in per_mat[mat]:
			if wake_i >= MAX_WAKES or point_i >= MAX_WAKE_POINTS:
				break
			var planet_pos: Vector3 = body.planet_node.global_pos
			var start := point_i
			var bmin := Vector3.INF
			var bmax := -Vector3.INF

			var points: Array = body.get_wake_points()
			# La cabeza se recoloca donde el casco se está dibujando este frame; el resto ya está
			# quieto en el mar y no necesita interpolarse.
			var head_offset: Vector3 = body.get_wake_head_offset()
			var head_i: int = points.size() - 1

			for pi in points.size():
				if point_i >= MAX_WAKE_POINTS:
					break
				var p: Dictionary = points[pi]
				var age: float = clampf((now - p["birth"]) / DynamicGridBody.WAKE_LIFETIME, 0.0, 1.0)
				var offset: Vector3 = p["offset"]
				if pi == head_i and not head_offset.is_zero_approx():
					offset = head_offset
					age = 0.0
				var world: Vector3 = planet_pos + offset
				var radius: float = p["width"] * (1.0 + age * 1.5)
				_wake_points_buf[point_i] = Vector4(world.x, world.y, world.z, radius)
				_wake_alphas_buf[point_i] = (1.0 - smoothstep(0.2, 1.0, age)) * WAKE_ALPHA
				bmin = bmin.min(world - Vector3.ONE * radius)
				bmax = bmax.max(world + Vector3.ONE * radius)
				point_i += 1

			if point_i == start:
				continue
			var center := (bmin + bmax) * 0.5
			_wake_ranges_buf[wake_i] = Vector2(start, point_i - start)
			# Margen para la ola: los puntos viven en el radio de reposo y los píxeles del agua en la
			# superficie desplazada, así que sin él el culling se come la estela entera con oleaje.
			_wake_bounds_buf[wake_i] = Vector4(center.x, center.y, center.z,
				(bmax - center).length() + WAKE_BOUNDS_MARGIN)
			wake_i += 1

		wake_stat_wakes = wake_i
		wake_stat_points = point_i
		mat.set_shader_parameter("wake_count", wake_i)
		if wake_i == 0:
			continue
		mat.set_shader_parameter("wake_bounds", _wake_bounds_buf)
		mat.set_shader_parameter("wake_ranges", _wake_ranges_buf)
		mat.set_shader_parameter("wake_points", _wake_points_buf)
		mat.set_shader_parameter("wake_alphas", _wake_alphas_buf)


## true si el punto está dentro de un compartimento SECO de algún barco: ahí el agua no
## existe (mismo criterio que la máscara del océano). En un compartimento inundado hay
## océano real y sí se nada.
func is_point_in_dry_interior(point: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("dynamic_grid_body"):
		var body := node as DynamicGridBody
		if body and body.contains_point(point) and body.is_point_in_dry_interior(point):
			return true
	return false


## Convierte una PlanetGrid estática (y sus alineadas) a dinámicas; devuelve las nuevas grids.
func convert_to_dynamic(grid_id: String) -> Array:
	var source: PlanetGrid = _grids.get(grid_id, null) as PlanetGrid
	if source.get_block_count() == 0:
		return []

	var planet := source.planet_node

	var aligned: Array[PlanetGrid] = []
	for grid: GridBase in get_grids_for_planet(planet):
		if grid is PlanetGrid and grid.is_same_origin_basis(source):
			if grid.get_block_count() > 0:
				aligned.append(grid as PlanetGrid)

	if aligned.is_empty():
		return []

	var grid_world_xform := source.get_grid_world_transform()
	var shared_body := DynamicGridBody.new()
	shared_body.set_meta("grid_id", grid_id)
	shared_body.name = "DynGrid_%s" % grid_id
	shared_body.planet_node = planet
	shared_body.mass = DynamicGridBody.MIN_MASS
	shared_body.gravity_scale = 0.0
	shared_body.set_meta("grid_id", grid_id)
	planet.get_tree().current_scene.add_child(shared_body)
	shared_body.global_transform = grid_world_xform

	var result: Array = []

	for i in aligned.size():
		var static_grid: PlanetGrid = aligned[i]
		var sid: String = static_grid.grid_id
		var dyn := DynamicPlanetGrid.new()

		if i == 0:
			dyn._body = shared_body
			dyn._owns_body = true
			dyn.grid_id = sid
			dyn.body_id = sid
			dyn.planet_node = planet
			dyn.cell_size = static_grid.cell_size
			dyn.mesh_materials = static_grid.mesh_materials
			_migrate_blocks_to_dynamic(dyn, static_grid, shared_body)
			dyn.block_placed.connect(shared_body.on_block_placed.bind(dyn))
			dyn.block_removed.connect(shared_body.on_block_removed.bind(dyn))
		else:
			dyn.setup_from_static_shared(sid, planet, static_grid, shared_body)

		_grids[sid] = dyn
		if _planet_grids.has(planet):
			var arr: Array = _planet_grids[planet]
			var idx := arr.find(static_grid)
			if idx >= 0:
				arr[idx] = dyn
			else:
				arr.append(dyn)

		result.append(dyn)

	shared_body.update_mass_from_grids()

	var total_blocks := 0
	for dyn in result:
		total_blocks += dyn.get_block_count()
	print("[GridManager] Convertidas %d grids alineadas a dinámicas (%d bloques total)" % [result.size(), total_blocks])
	return result


func _migrate_blocks_to_dynamic(dyn: DynamicPlanetGrid, static_grid: PlanetGrid, body: DynamicGridBody) -> void:
	var all_blocks := static_grid.get_all_blocks()
	for grid_pos: Vector3i in all_blocks:
		var info: Dictionary = all_blocks[grid_pos]
		var old_node: Node3D = info["node"]

		var local_xform := Transform3D.IDENTITY
		if old_node and is_instance_valid(old_node):
			local_xform = body.global_transform.affine_inverse() * old_node.global_transform

		var block_data: BlockData = BlockDatabase.get_block(info["block_id"])
		if not block_data:
			continue

		var rotation_basis: Basis = info.get("rotation_basis", Basis.IDENTITY)
		var col: Node3D = null
		if not ChunkMeshBuilder._is_solid(block_data.block_id):
			col = dyn._make_block_wrapper(grid_pos, block_data, rotation_basis, local_xform)
			body.add_child(col)

		dyn._blocks[grid_pos] = {
			"block_id": info["block_id"],
			"rotation_basis": rotation_basis,
			"node": col,
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}

	dyn._migrate_props_from(static_grid)
	static_grid.clear()
	body.register_grid(dyn)
	dyn.rebuild_mesh()

func _register_grid(grid: GridBase, planet: Node3D, grid_id: String) -> void:
	if not _planet_grids.has(planet):
		_planet_grids[planet] = []
	_planet_grids[planet].append(grid)
	_grids[grid_id] = grid

func _generate_id() -> String:
	var grid_id := "grid_%d" % _next_id
	_next_id += 1

	return grid_id

## Crea una grid alineada al origin/basis de otra grid existente.
func create_grid_aligned(planet: Node3D, ref_grid: GridBase, target_cell: float) -> GridBase:
	if ref_grid is DynamicPlanetGrid:
		var dyn_ref := ref_grid as DynamicPlanetGrid
		var grid := DynamicPlanetGrid.new()
		var grid_id := _generate_id()
		grid.grid_id = grid_id
		grid.planet_node = planet
		grid.cell_size = target_cell
		grid._body = dyn_ref._body
		grid._owns_body = false
		grid.body_id = dyn_ref.body_id
		dyn_ref._body.register_grid(grid)
		_register_grid(grid, planet, grid_id)
		grid.block_placed.connect(dyn_ref._body.on_block_placed.bind(grid))
		grid.block_removed.connect(dyn_ref._body.on_block_removed.bind(grid))
		return grid
	else:
		var grid := PlanetGrid.new()
		var grid_id := _generate_id()
		grid.setup_aligned(grid_id, planet, (ref_grid as PlanetGrid).origin_local, (ref_grid as PlanetGrid).basis_local, target_cell)
		_register_grid(grid, planet, grid_id)
		return grid

## Crea una nueva grid anclada a un planeta (origin/basis en mundo se convierten a local).
func create_grid(planet: Node3D, origin_world: Vector3, basis_world: Basis, cell_size: float = 1.0) -> GridBase:
	var grid := PlanetGrid.new()
	var grid_id = _generate_id()

	var reference := find_any_nearest_grid(planet, origin_world)

	if reference:
		grid.setup_aligned(grid_id, planet, reference.origin_local, reference.basis_local, cell_size)
	else:
		grid.setup(grid_id, planet, origin_world, basis_world, cell_size)

	_register_grid(grid, planet, grid_id)
	print("[GridManager] Grid '%s' creada en planeta '%s' (total: %d)" % [grid_id, planet.name, _grids.size()])
	return grid


## Crea una grid en una pose exacta, sin alinearla a ninguna grid cercana (para instanciar
## blueprints, donde la pose la decide quien lo coloca y no el vecindario).
func create_grid_exact(planet: Node3D, origin_world: Vector3, basis_world: Basis, cell_size: float = 1.0) -> GridBase:
	var grid := PlanetGrid.new()
	var grid_id := _generate_id()
	grid.setup(grid_id, planet, origin_world, basis_world, cell_size)
	_register_grid(grid, planet, grid_id)
	return grid


## Todas las grids que forman la misma estructura que 'grid_id': las que comparten cuerpo
## dinámico, o las estáticas con el mismo origin/basis (los distintos cell_size de un barco).
func get_grid_group(grid_id: String) -> Array:
	var source: GridBase = _grids.get(grid_id, null)
	if not source:
		return []

	var group: Array = []
	for grid: GridBase in get_grids_for_planet(source.planet_node):
		if grid == source or grid.is_same_origin_basis(source):
			group.append(grid)
	return group


## Resumen del grupo de grids para la UI: bloques, props, dimensiones en metros y, si es
## dinámico, masa e inundación. Devuelve {} si el id no existe.
func get_group_stats(grid_id: String) -> Dictionary:
	var group := get_grid_group(grid_id)
	if group.is_empty():
		return {}

	var blocks := 0
	var props := 0
	var volume := 0.0
	var cells: Array = []
	var min_m := Vector3.INF
	var max_m := -Vector3.INF

	for grid: GridBase in group:
		blocks += grid.get_block_count()
		props += grid.get_all_props().size()
		volume += grid.get_total_volume()
		if not cells.has(grid.cell_size):
			cells.append(grid.cell_size)
		for grid_pos: Vector3i in grid.get_all_blocks():
			var corner := Vector3(grid_pos) * grid.cell_size
			min_m = min_m.min(corner)
			max_m = max_m.max(corner + Vector3.ONE * grid.cell_size)
	cells.sort()

	var stats := {
		"grid_id": grid_id,
		"grids": group.size(),
		"blocks": blocks,
		"props": props,
		"volume": volume,
		"cell_sizes": cells,
		"size": (max_m - min_m) if blocks > 0 else Vector3.ZERO,
		"planet": group[0].planet_node.name if group[0].planet_node else "?",
		"dynamic": group[0] is DynamicPlanetGrid,
	}

	if group[0] is DynamicPlanetGrid:
		var body: DynamicGridBody = (group[0] as DynamicPlanetGrid)._body
		if body and is_instance_valid(body):
			stats["body_id"] = (group[0] as DynamicPlanetGrid).body_id
			stats["mass"] = body.mass
			stats["flood"] = body.get_flood_state()

	return stats


## Elimina el grupo entero al que pertenece grid_id y devuelve cuántas grids se han borrado.
## La grid propietaria del DynamicGridBody va la última: al limpiarse libera el cuerpo, y las
## hermanas se quedarían apuntando a un nodo muerto.
func remove_grid_group(grid_id: String) -> int:
	var group := get_grid_group(grid_id)
	var owner_grid: GridBase = null
	var removed := 0

	for grid: GridBase in group:
		if grid is DynamicPlanetGrid and (grid as DynamicPlanetGrid)._owns_body:
			owner_grid = grid
			continue
		if remove_grid(grid.grid_id):
			removed += 1

	if owner_grid and remove_grid(owner_grid.grid_id):
		removed += 1

	return removed


## Elimina una grid y todos sus bloques.
func remove_grid(grid_id: String) -> bool:
	if not _grids.has(grid_id):
		return false

	var grid: GridBase = _grids[grid_id]
	grid.clear()

	if _planet_grids.has(grid.planet_node):
		var arr: Array = _planet_grids[grid.planet_node]
		arr.erase(grid)
		if arr.is_empty():
			_planet_grids.erase(grid.planet_node)

	_grids.erase(grid_id)
	print("[GridManager] Grid '%s' eliminada (total: %d)" % [grid_id, _grids.size()])
	return true

## True si un bloque de cell_size en grid_pos solapa con bloques de otra grid del planeta.
## Como las grids comparadas comparten origin/basis, consulta solo el rango de celdas de la
## otra grid que cubre el bloque nuevo, en vez de escanear todos sus bloques.
func check_overlap(planet: Node3D, grid_pos: Vector3i, cell_size: float, source_grid: GridBase) -> bool:
	var eps := 0.001
	var min_a := Vector3(grid_pos) * cell_size
	var max_a := min_a + Vector3.ONE * cell_size

	for grid: GridBase in get_grids_for_planet(planet):
		if grid == source_grid:
			continue
		if not grid.is_same_origin_basis(source_grid):
			continue

		var lo := Vector3i(
			floori((min_a.x + eps) / grid.cell_size),
			floori((min_a.y + eps) / grid.cell_size),
			floori((min_a.z + eps) / grid.cell_size)
		)
		var hi := Vector3i(
			ceili((max_a.x - eps) / grid.cell_size) - 1,
			ceili((max_a.y - eps) / grid.cell_size) - 1,
			ceili((max_a.z - eps) / grid.cell_size) - 1
		)

		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					if grid.has_block(Vector3i(x, y, z)):
						return true

	return false

static func _same_origin_basis(a: GridBase, b: GridBase) -> bool:
	return a.is_same_origin_basis(b)


## Obtiene una grid por ID.
func get_grid(grid_id: String) -> GridBase:
	return _grids.get(grid_id, null)


## Obtiene todas las grids de un planeta.
func get_grids_for_planet(planet: Node3D) -> Array:
	return _planet_grids.get(planet, [])

func find_any_nearest_grid(planet: Node3D, world_pos: Vector3, max_dist: float = -1.0) -> GridBase:
	if max_dist < 0:
		max_dist = snap_distance

	var grids: Array = get_grids_for_planet(planet)
	var best_grid: GridBase = null
	var best_dist: float = max_dist

	for grid in grids:
		var dist: float = grid.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best_grid = grid

	return best_grid

func find_nearest_grid(planet: Node3D, world_pos: Vector3, target_cell_size: float, required_basis: Basis = Basis.IDENTITY, check_basis: bool = false) -> PlanetGrid:
	var best: GridBase = null
	var best_dist := INF
	var max_dist := target_cell_size * MAX_REUSE_CELLS

	for grid: GridBase in get_grids_for_planet(planet):
		if not is_equal_approx(grid.cell_size, target_cell_size):
			continue

		var dist := grid.distance_to(world_pos)

		if dist > max_dist:
			continue

		if check_basis and not _basis_aligned(grid.get_basis_world(), required_basis):
			continue

		if dist < best_dist:
			best_dist = dist
			best = grid

	return best


## Comprueba si dos bases están alineadas (cada eje apunta ±igual).
static func _basis_aligned(a: Basis, b: Basis) -> bool:
	for i in 3:
		var dot: float = abs(a[i].normalized().dot(b[i].normalized()))
		if dot < cos(MAX_BASIS_ANGLE):
			return false
	return true

## Busca una grid con cell_size dado, alineada al mismo origin/basis que ref_grid.
func find_aligned_grid(planet: Node3D, target_cell: float, ref_grid: GridBase) -> GridBase:
	for grid: GridBase in get_grids_for_planet(planet):
		if not is_equal_approx(grid.cell_size, target_cell):
			continue
		if grid.is_same_origin_basis(ref_grid):
			return grid
		if grid is DynamicPlanetGrid and ref_grid is DynamicPlanetGrid:
			if (grid as DynamicPlanetGrid)._body == (ref_grid as DynamicPlanetGrid)._body:
				return grid
	return null


func _basis_equal(a: Basis, b: Basis) -> bool:
	for i in 3:
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


## Obtiene la grid a la que pertenece un bloque, por su metadata grid_id.
func get_grid_for_block(block_node: Node3D) -> GridBase:
	if block_node.has_meta("grid_id"):
		return get_grid(block_node.get_meta("grid_id"))
	if block_node is DynamicGridBody and block_node.has_meta("grid_id"):
		return get_grid(block_node.get_meta("grid_id"))
	return null


## Reutiliza una grid cercana compatible o crea una nueva.
func get_or_create_grid(planet: Node3D, world_pos: Vector3, basis_world: Basis, cell_size: float = 1.0) -> GridBase:
	var existing := find_nearest_grid(planet, world_pos, cell_size)
	if existing:
		return existing
	return create_grid(planet, world_pos, basis_world, cell_size)


func get_grid_count() -> int:
	return _grids.size()


func get_total_block_count() -> int:
	var total := 0
	for grid in _grids.values():
		total += grid.get_block_count()
	return total


func get_all_grids() -> Array:
	return _grids.values()


## Elimina todas las grids de un planeta.
func clear_planet(planet: Node3D) -> void:
	var grids: Array = get_grids_for_planet(planet).duplicate()
	for grid in grids:
		remove_grid(grid.grid_id)


## Elimina todas las grids.
func clear_all() -> void:
	for grid_id in _grids.keys():
		remove_grid(grid_id)
