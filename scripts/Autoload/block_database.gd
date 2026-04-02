extends Node

## Autoload singleton que registra todos los tipos de bloque.
## Añadir a Project > AutoLoad como "BlockDatabase".
##
## Uso:
##   var block = BlockDatabase.get_block(0)
##   var block = BlockDatabase.get_block_by_name("slope")
##   var all = BlockDatabase.get_all_blocks()

const BLOCK_CUBE_ID := 0
const BLOCK_SLOPE_ID := 1
const BLOCK_CORNER_ID := 2
const BLOCK_INV_CORNER_ID := 3
var _blocks: Dictionary = {}  # id -> BlockData
var _blocks_by_name: Dictionary = {}  # name -> BlockData


func _ready() -> void:
	_register_default_blocks()
	print("[BlockDatabase] Registrados %d bloques." % _blocks.size())


func _register_default_blocks() -> void:
	# --- CUBE ---
	var cube := BlockData.new()
	cube.block_id = BLOCK_CUBE_ID
	cube.block_name = "cube"
	cube.block_description = "Bloque cúbico estándar 1x1x1"
	cube.mesh = BlockMeshGenerator.generate_cube()
	cube.collision_shape = BlockMeshGenerator.generate_cube_collision()
	cube.can_rotate = false
	cube.rotation_steps = 4
	register_block(cube)
	
	# --- SLOPE ---
	var slope := BlockData.new()
	slope.block_id = BLOCK_SLOPE_ID
	slope.block_name = "slope"
	slope.block_description = "Rampa diagonal"
	slope.mesh = BlockMeshGenerator.generate_slope()
	slope.collision_shape = BlockMeshGenerator.generate_slope_collision()
	slope.can_rotate = true
	slope.rotation_steps = 4
	register_block(slope)
	
	# --- CORNER ---
	var corner := BlockData.new()
	corner.block_id = BLOCK_CORNER_ID
	corner.block_name = "corner"
	corner.block_description = "Esquina entre dos rampas"
	corner.mesh = BlockMeshGenerator.generate_corner()
	corner.collision_shape = BlockMeshGenerator.generate_corner_collision()
	corner.can_rotate = true
	corner.rotation_steps = 4
	register_block(corner)
	var inv_corner := BlockData.new()
	inv_corner.block_id = BLOCK_INV_CORNER_ID # Asegúrate de declarar esta constante arriba (ej. = 3)
	inv_corner.block_name = "inv_corner"
	inv_corner.block_description = "Esquina invertida (cóncava)"
	inv_corner.mesh = BlockMeshGenerator.generate_inv_corner()
	inv_corner.collision_shape = BlockMeshGenerator.generate_inv_corner_collision()
	inv_corner.can_rotate = true
	inv_corner.rotation_steps = 4
	register_block(inv_corner)


## Registra un BlockData. Sobrescribe si ya existe el ID.
func register_block(block: BlockData) -> void:
	_blocks[block.block_id] = block
	_blocks_by_name[block.block_name] = block


## Obtiene un bloque por ID. Retorna null si no existe.
func get_block(id: int) -> BlockData:
	return _blocks.get(id, null)


## Obtiene un bloque por nombre. Retorna null si no existe.
func get_block_by_name(block_name: String) -> BlockData:
	return _blocks_by_name.get(block_name, null)


## Retorna todos los bloques registrados.
func get_all_blocks() -> Array[BlockData]:
	var result: Array[BlockData] = []
	for block in _blocks.values():
		result.append(block)
	return result


## Retorna el número de bloques registrados.
func get_block_count() -> int:
	return _blocks.size()


## Retorna todos los IDs registrados.
func get_all_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in _blocks.keys():
		ids.append(id)
	ids.sort()
	return ids
