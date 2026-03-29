extends Node

## Autoload singleton que gestiona todas las PlanetGrid de todos los planetas.
## Añadir a Project > AutoLoad como "GridManager".
##
## Uso:
##   var grid = GridManager.create_grid(planet, origin, basis)
##   var grid = GridManager.find_nearest_grid(planet, world_pos)
##   var grid = GridManager.get_grid_for_block(collider_node)
##   var grids = GridManager.get_grids_for_planet(planet)

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
		var grid: PlanetGrid = _grids[grid_id]
		grids_data[grid_id] = grid.serialize()
	
	return {
		"next_id": _next_id,
		"grids": grids_data,
	}


func restore_save_data(data: Dictionary) -> void:
	# Limpiar todo lo existente
	clear_all()
	
	_next_id = data.get("next_id", 0)
	
	var grids_data: Dictionary = data.get("grids", {})
	for grid_id in grids_data:
		var grid_data: Dictionary = grids_data[grid_id]
		
		# Buscar el planeta por su path guardado
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
	
	print("[GridManager] Restauradas %d grids" % _grids.size())
	
func _ready() -> void:
	add_to_group(GameManager.SAVEABLE_GROUP)


# ============================================================
#  CREAR / ELIMINAR GRIDS
# ============================================================

## Crea una nueva grid anclada a un planeta.
## origin_world y basis_world se convierten a local del planeta.
func create_grid(planet: Node3D, origin_world: Vector3, basis_world: Basis, cell_size: float = 1.0) -> PlanetGrid:
	var grid := PlanetGrid.new()
	var grid_id := "grid_%d" % _next_id
	_next_id += 1
	
	grid.setup(grid_id, planet, origin_world, basis_world, cell_size)
	
	_grids[grid_id] = grid
	
	if not _planet_grids.has(planet):
		_planet_grids[planet] = []
	_planet_grids[planet].append(grid)
	
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


# ============================================================
#  BÚSQUEDA DE GRIDS
# ============================================================

## Obtiene una grid por ID.
func get_grid(grid_id: String) -> PlanetGrid:
	return _grids.get(grid_id, null)


## Obtiene todas las grids de un planeta.
func get_grids_for_planet(planet: Node3D) -> Array:
	return _planet_grids.get(planet, [])


## Busca la grid más cercana a una posición world dentro de un planeta.
## Retorna null si no hay ninguna dentro de max_dist.
func find_nearest_grid(planet: Node3D, world_pos: Vector3, max_dist: float = -1.0) -> PlanetGrid:
	if max_dist < 0:
		max_dist = snap_distance
	
	var grids: Array = get_grids_for_planet(planet)
	if grids.is_empty():
		return null
	
	var best_grid: PlanetGrid = null
	var best_dist: float = max_dist
	
	for grid in grids:
		var dist: float = grid.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best_grid = grid
	
	return best_grid


## Obtiene la grid a la que pertenece un bloque (usando su metadata).
## Útil cuando el raycast impacta un bloque colocado.
func get_grid_for_block(block_node: Node3D) -> PlanetGrid:
	if block_node.has_meta("grid_id"):
		var grid_id: String = block_node.get_meta("grid_id")
		return get_grid(grid_id)
	return null


## Obtiene o crea una grid para colocar un bloque.
## Si hay una grid cercana compatible, la reutiliza. Si no, crea una nueva.
func get_or_create_grid(planet: Node3D, world_pos: Vector3, basis_world: Basis, cell_size: float = 1.0) -> PlanetGrid:
	var existing := find_nearest_grid(planet, world_pos)
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
