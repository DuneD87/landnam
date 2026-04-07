extends Node

## Autoload singleton que gestiona todas las PlanetGrid de todos los planetas.
## Añadir a Project > AutoLoad como "GridManager".
##
## Uso:
##   var grid = GridManager.create_grid(planet, origin, basis)
##   var grid = GridManager.find_nearest_grid(planet, world_pos)
##   var grid = GridManager.get_grid_for_block(collider_node)
##   var grids = GridManager.get_grids_for_planet(planet)
## Distancia máxima (en celdas) para reutilizar una grid existente.
const MAX_REUSE_CELLS := 16

## Ángulo máximo (radianes) entre bases para considerar dos grids "alineadas".
const MAX_BASIS_ANGLE := deg_to_rad(5.0)
## Distancia máxima para considerar que un bloque pertenece a una grid existente.
@export var snap_distance: float = 5.0

## Todas las grids por ID.
var _grids: Dictionary = {}  # String → PlanetGrid

## Índice de grids por planeta (para búsqueda rápida).
var _planet_grids: Dictionary = {}  # Node3D → Array[PlanetGrid]

## Contador para generar IDs únicos.
var _next_id: int = 0
var entity_id: String = "grid_manager"
# ============================================================
#  SAVE / LOAD (integración con GameManager)
# ============================================================

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

	# Primero restaurar estáticas, luego dinámicas agrupadas por body_id
	var dynamic_grids: Dictionary = {}  # body_id → Array[{grid_id, grid_data}]

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

	# Dinámicas: un body por grupo
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
				# Primera del grupo: crea el body
				dyn.deserialize(grid_id, planet, grid_data, null)
				shared_body = dyn._body
			else:
				# Resto: comparte el body
				dyn.deserialize(grid_id, planet, grid_data, shared_body)

			_grids[grid_id] = dyn
			if not _planet_grids.has(planet):
				_planet_grids[planet] = []
			_planet_grids[planet].append(dyn)

	# Actualizar masa total por body
	var body_blocks: Dictionary = {}  # DynamicGridBody → int
	for grid_id in _grids:
		var grid: GridBase = _grids[grid_id]
		if grid is DynamicPlanetGrid:
			var dyn := grid as DynamicPlanetGrid
			if dyn._body:
				body_blocks[dyn._body] = body_blocks.get(dyn._body, 0) + dyn.get_block_count()

	for body: DynamicGridBody in body_blocks:
		body.mass = maxf(DynamicPlanetGrid.MASS_PER_BLOCK, body_blocks[body] * DynamicPlanetGrid.MASS_PER_BLOCK)

	print("[GridManager] Restauradas %d grids" % _grids.size())
	
func _ready() -> void:
	add_to_group(GameManager.SAVEABLE_GROUP)


# ============================================================
#  CREAR / ELIMINAR GRIDS
# ============================================================
## Convierte una PlanetGrid estática a DynamicPlanetGrid.
## Retorna la nueva grid dinámica, o null si falla.
func convert_to_dynamic(grid_id: String) -> Array:
	var source: PlanetGrid = _grids.get(grid_id, null) as PlanetGrid
	if source.get_block_count() == 0:
		return []

	var planet := source.planet_node

	# Encontrar todas las grids alineadas (mismo origin/basis, cualquier cell_size)
	var aligned: Array[PlanetGrid] = []
	for grid: GridBase in get_grids_for_planet(planet):
		if grid is PlanetGrid and grid.is_same_origin_basis(source):
			if grid.get_block_count() > 0:
				aligned.append(grid as PlanetGrid)

	if aligned.is_empty():
		return []

	# Crear un solo body compartido usando el transform de la primera grid
	var grid_world_xform := source.get_grid_world_transform()
	var shared_body := DynamicGridBody.new()
	shared_body.set_meta("grid_id", grid_id)
	shared_body.name = "DynGrid_%s" % grid_id
	shared_body.planet_node = planet
	shared_body.mass = DynamicPlanetGrid.MASS_PER_BLOCK
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
			# Primera: crea y posee el body
			dyn._body = shared_body
			dyn._owns_body = true
			dyn.grid_id = sid
			dyn.planet_node = planet
			dyn.cell_size = static_grid.cell_size
			dyn.mesh_materials = static_grid.mesh_materials
			# Migrar bloques
			_migrate_blocks_to_dynamic(dyn, static_grid, shared_body)
			dyn.block_placed.connect(shared_body.on_block_placed)
			dyn.block_removed.connect(shared_body.on_block_removed)
		else:
			dyn.setup_from_static_shared(sid, planet, static_grid, shared_body)

		# Reemplazar en registros
		_grids[sid] = dyn
		if _planet_grids.has(planet):
			var arr: Array = _planet_grids[planet]
			var idx := arr.find(static_grid)
			if idx >= 0:
				arr[idx] = dyn
			else:
				arr.append(dyn)

		result.append(dyn)

	# Actualizar masa total
	var total_blocks := 0
	for dyn in result:
		total_blocks += dyn.get_block_count()
	shared_body.mass = maxf(DynamicPlanetGrid.MASS_PER_BLOCK, total_blocks * DynamicPlanetGrid.MASS_PER_BLOCK)

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
		var col := dyn._make_block_wrapper(grid_pos, block_data, rotation_basis, local_xform)
		body.add_child(col)

		dyn._blocks[grid_pos] = {
			"block_id": info["block_id"],
			"rotation_basis": rotation_basis,
			"node": col,
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}

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
		grid.block_placed.connect(dyn_ref._body.on_block_placed)
		grid.block_removed.connect(dyn_ref._body.on_block_removed)
		return grid
	else:
		var grid := PlanetGrid.new()
		var grid_id := _generate_id()
		grid.setup_aligned(grid_id, planet, (ref_grid as PlanetGrid).origin_local, (ref_grid as PlanetGrid).basis_local, target_cell)
		_register_grid(grid, planet, grid_id)
		return grid
	
## Crea una nueva grid anclada a un planeta.
## origin_world y basis_world se convierten a local del planeta.
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


## Elimina una grid y todos sus bloques.
func remove_grid(grid_id: String) -> bool:
	if not _grids.has(grid_id):
		return false
	
	var grid: PlanetGrid = _grids[grid_id]
	grid.clear()
	
	# Quitar del índice de planeta
	if _planet_grids.has(grid.planet_node):
		var arr: Array = _planet_grids[grid.planet_node]
		arr.erase(grid)
		if arr.is_empty():
			_planet_grids.erase(grid.planet_node)
	
	_grids.erase(grid_id)
	print("[GridManager] Grid '%s' eliminada (total: %d)" % [grid_id, _grids.size()])
	return true

## Comprueba si un bloque de tamaño cell_size en world_pos colisiona
## con bloques existentes en CUALQUIER grid del planeta.
func check_overlap(planet: Node3D, grid_pos: Vector3i, cell_size: float, source_grid: GridBase) -> bool:
	var grids: Array = get_grids_for_planet(planet)
	var min_a := Vector3(grid_pos) * cell_size
	var max_a := min_a + Vector3.ONE * cell_size

	for grid: GridBase in grids:
		if grid == source_grid:
			continue
		if not grid.is_same_origin_basis(source_grid):
			continue

		for other_pos in grid.get_all_blocks():
			var min_b: Vector3 = Vector3(other_pos) * grid.cell_size
			var max_b: Vector3 = min_b + Vector3.ONE * grid.cell_size

			if _aabb_overlap(min_a, max_a, min_b, max_b):
				return true

	return false

static func _aabb_overlap(min_a: Vector3, max_a: Vector3, min_b: Vector3, max_b: Vector3) -> bool:
	# Usamos un pequeño epsilon para evitar falsos positivos en bordes compartidos
	var eps := 0.001
	return (
		min_a.x < max_b.x - eps and max_a.x > min_b.x + eps and
		min_a.y < max_b.y - eps and max_a.y > min_b.y + eps and
		min_a.z < max_b.z - eps and max_a.z > min_b.z + eps
	)

static func _same_origin_basis(a: GridBase, b: GridBase) -> bool:
	return a.is_same_origin_basis(b)
# ============================================================
#  BÚSQUEDA DE GRIDS
# ============================================================

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

		# Descartar grids demasiado lejos
		if dist > max_dist:
			continue

		# Comprobar alineación de basis si se pide
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
		# Mismo origin/basis (estáticas)
		if grid.is_same_origin_basis(ref_grid):
			return grid
		# Mismo body (dinámicas)
		if grid is DynamicPlanetGrid and ref_grid is DynamicPlanetGrid:
			if (grid as DynamicPlanetGrid)._body == (ref_grid as DynamicPlanetGrid)._body:
				return grid
	return null


func _basis_equal(a: Basis, b: Basis) -> bool:
	for i in 3:
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


	
## Obtiene la grid a la que pertenece un bloque (usando su metadata).
## Útil cuando el raycast impacta un bloque colocado.
func get_grid_for_block(block_node: Node3D) -> GridBase:
	# StaticBody3D o wrapper Node3D con meta
	if block_node.has_meta("grid_id"):
		return get_grid(block_node.get_meta("grid_id"))
	# DynamicGridBody (el RigidBody3D mismo)
	if block_node is DynamicGridBody and block_node.has_meta("grid_id"):
		return get_grid(block_node.get_meta("grid_id"))
	return null


## Obtiene o crea una grid para colocar un bloque.
## Si hay una grid cercana compatible, la reutiliza. Si no, crea una nueva.
func get_or_create_grid(planet: Node3D, world_pos: Vector3, basis_world: Basis, cell_size: float = 1.0) -> GridBase:
	var existing := find_nearest_grid(planet, world_pos, cell_size)
	if existing:
		return existing
	return create_grid(planet, world_pos, basis_world, cell_size)


# ============================================================
#  ESTADÍSTICAS
# ============================================================

func get_grid_count() -> int:
	return _grids.size()


func get_total_block_count() -> int:
	var total := 0
	for grid in _grids.values():
		total += grid.get_block_count()
	return total


func get_all_grids() -> Array:
	return _grids.values()


# ============================================================
#  LIMPIEZA
# ============================================================

## Elimina todas las grids de un planeta.
func clear_planet(planet: Node3D) -> void:
	var grids: Array = get_grids_for_planet(planet).duplicate()
	for grid in grids:
		remove_grid(grid.grid_id)


## Elimina todas las grids.
func clear_all() -> void:
	for grid_id in _grids.keys():
		remove_grid(grid_id)
