class_name BuildGridHelper
extends RefCounted

## Utilidades estáticas para calcular la grid de construcción
## alineada a la superficie de un planeta esférico.
##
## El sistema funciona así:
##   1. Se calcula el "local up" (normal desde el centro del planeta)
##   2. Se construye un Basis ortogonal con ese up
##   3. Se usa ese Basis para convertir posiciones world <-> grid
##   4. Se snapean posiciones a la grid para colocar bloques


# ============================================================
#  LOCAL BASIS
# ============================================================

## Calcula el vector "arriba" local: dirección desde el centro del planeta
## hacia la posición dada. Este es el eje Y del sistema local.
static func get_local_up(planet_center: Vector3, world_position: Vector3) -> Vector3:
	return (world_position - planet_center).normalized()


## Construye un Basis ortogonal a partir del local up.
## El Basis resultante tiene:
##   - Y = local_up (hacia fuera del planeta)
##   - X = right (tangente a la superficie)
##   - Z = forward (tangente a la superficie)
##
## Usamos un vector de referencia para evitar degeneración en los polos.
static func get_local_basis(local_up: Vector3) -> Basis:
	# Elegir un vector de referencia que no sea paralelo al up
	var ref_vector := Vector3.FORWARD
	if abs(local_up.dot(ref_vector)) > 0.99:
		ref_vector = Vector3.RIGHT
	
	# Calcular los ejes tangentes
	var local_right := local_up.cross(ref_vector).normalized()
	var local_forward := local_right.cross(local_up).normalized()
	
	# Basis: columnas son los ejes (X=right, Y=up, Z=forward)
	return Basis(local_right, local_up, local_forward)


# ============================================================
#  CONVERSIONES WORLD <-> GRID
# ============================================================

## Convierte una posición world a coordenadas de grid (Vector3i).
## grid_origin es el punto de referencia de la grid en world space
## (normalmente la posición del primer bloque o la posición del player
## al entrar en modo construcción).
static func world_to_grid(
	world_pos: Vector3,
	local_basis: Basis,
	grid_origin: Vector3,
	cell_size: float = 1.0
) -> Vector3i:
	# Pasar la posición al espacio local de la grid
	var relative := world_pos - grid_origin
	var local_pos := local_basis.inverse() * relative
	
	# Discretizar a celdas
	return Vector3i(
		floori(local_pos.x / cell_size),
		floori(local_pos.y / cell_size),
		floori(local_pos.z / cell_size)
	)


## Convierte coordenadas de grid (Vector3i) a posición world.
## Retorna la posición de la esquina inferior de la celda
## (alineada con el origen de mesh que está en la base).
static func grid_to_world(
	grid_pos: Vector3i,
	local_basis: Basis,
	grid_origin: Vector3,
	cell_size: float = 1.0
) -> Vector3:
	# Posición local en el espacio de la grid
	var local_pos := Vector3(
		grid_pos.x * cell_size,
		grid_pos.y * cell_size,
		grid_pos.z * cell_size
	)
	
	# Convertir de local a world
	return grid_origin + local_basis * local_pos


## Snapea una posición world a la grid: convierte a grid, redondea,
## y vuelve a world. Es la función principal para posicionar el ghost block.
static func snap_to_grid(
	world_pos: Vector3,
	local_basis: Basis,
	grid_origin: Vector3,
	cell_size: float = 1.0
) -> Vector3:
	var grid_pos := world_to_grid(world_pos, local_basis, grid_origin, cell_size)
	return grid_to_world(grid_pos, local_basis, grid_origin, cell_size)


# ============================================================
#  TRANSFORM COMPLETO PARA BLOQUES
# ============================================================

## Genera el Transform3D completo para colocar un bloque en la grid.
## Incluye posición snapeada + rotación alineada a la superficie.
## rotation_y es la rotación adicional del bloque (0, 90, 180, 270).
static func get_block_transform(
	world_pos: Vector3,
	local_basis: Basis,
	grid_origin: Vector3,
	cell_size: float = 1.0,
	rotation_y_deg: float = 0.0
) -> Transform3D:
	var snapped_pos := snap_to_grid(world_pos, local_basis, grid_origin, cell_size)
	
	# Basis del bloque = basis de la grid + rotación local en Y
	var block_basis := local_basis
	if rotation_y_deg != 0.0:
		# Rotar alrededor del eje Y local (que es el local_up)
		block_basis = block_basis * Basis(Vector3.UP, deg_to_rad(rotation_y_deg))
	
	return Transform3D(block_basis, snapped_pos)


# ============================================================
#  VECINOS EN LA GRID
# ============================================================

## Retorna las 6 posiciones vecinas de una celda en la grid.
## Útil para detectar adyacencia, snap a cara, etc.
static func get_neighbors(grid_pos: Vector3i) -> Array[Vector3i]:
	return [
		grid_pos + Vector3i(1, 0, 0),   # +X (right)
		grid_pos + Vector3i(-1, 0, 0),  # -X (left)
		grid_pos + Vector3i(0, 1, 0),   # +Y (up)
		grid_pos + Vector3i(0, -1, 0),  # -Y (down)
		grid_pos + Vector3i(0, 0, 1),   # +Z (forward)
		grid_pos + Vector3i(0, 0, -1),  # -Z (back)
	]


## Dada una cara impactada por un raycast (normal), retorna la celda
## adyacente donde se colocaría un nuevo bloque.
## hit_normal debe estar en world space, se convierte a grid space.
static func get_adjacent_cell_from_normal(
	grid_pos: Vector3i,
	hit_normal_world: Vector3,
	local_basis: Basis
) -> Vector3i:
	# Convertir la normal del hit a espacio local de la grid
	var local_normal := local_basis.inverse() * hit_normal_world
	
	# Redondear al eje más cercano
	var abs_normal := local_normal.abs()
	var offset := Vector3i.ZERO
	
	if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z:
		offset.x = 1 if local_normal.x > 0 else -1
	elif abs_normal.y >= abs_normal.x and abs_normal.y >= abs_normal.z:
		offset.y = 1 if local_normal.y > 0 else -1
	else:
		offset.z = 1 if local_normal.z > 0 else -1
	
	return grid_pos + offset
