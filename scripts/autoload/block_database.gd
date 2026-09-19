extends Node

const config_ref = preload("res://scripts/config.gd")

const BLOCK_CUBE_ID := 0
const BLOCK_SLOPE_ID := 1
const BLOCK_CORNER_ID := 2
const BLOCK_INV_CORNER_ID := 3
const BLOCK_PANE_ID := 4
const BLOCK_PANE_SLOPE_ID := 5

signal materials_ready
## Salta cada vez que un item estrena icono, para que la UI ya pintada se refresque sobre la
## marcha en vez de esperar al final de una tanda que dura segundos.
signal icon_generated

var _blocks: Dictionary = {}
var _blocks_by_name: Dictionary = {}
var _block_items: Dictionary = {}

var build_materials: Array[BuildMaterial] = []
var _block_material_items: Array[ItemData] = []
var _icon_generator: BlockIconGenerator = null
var _materials_generated: bool = false
var _translucent_materials: Array[Material] = []

func _ready() -> void:
	_register_default_blocks()
	_register_default_materials()
	_icon_generator = BlockIconGenerator.new()
	add_child(_icon_generator)
	_create_block_material_items()
	_generate_all_icons()

	print("[BlockDatabase] Registrados %d bloques." % _blocks.size())


## Si los iconos ya están renderizados. Quien pinte items antes de tiempo tiene que repintarlos
## con icon_generated, o se queda con la textura vacía para siempre.
func are_materials_ready() -> bool:
	return _materials_generated


## Renderiza en serie todos los iconos del juego. Un único coroutine a propósito: el generador
## comparte viewport y MeshInstance, y dos cadenas de iconos a la vez se pisan el render entre
## await y await, de modo que cada una acaba capturando el bloque de la otra.
func _generate_all_icons() -> void:
	await _generate_material_item_icons()
	await _generate_block_material_icons()
	_assign_generic_block_icons()
	_materials_generated = true
	materials_ready.emit()

	var missing := 0
	for item in _block_material_items:
		if not item.icon:
			missing += 1
	if missing > 0:
		push_warning("[BlockDatabase] %d de %d items bloque+material se quedaron sin icono." % [missing, _block_material_items.size()])
	print("[BlockDatabase] Generated icons for %d block+material items." % _block_material_items.size())


## El icono del bloque genérico es el del mismo bloque en el primer material, que ya está
## renderizado: se reutiliza en vez de volver a pasar por el viewport. Cada render cuesta dos
## frames y en el arranque, con el terreno streameando, esos frames son décimas de segundo.
func _assign_generic_block_icons() -> void:
	if build_materials.is_empty():
		return
	var first_id := build_materials[0].material_id
	for item in _block_material_items:
		if item.build_material_id != first_id or not item.icon:
			continue
		var block := get_block(item.block_id)
		if block and not block.preview_icon:
			block.preview_icon = item.icon
		var generic := _block_items.get(item.block_id) as ItemData
		if generic and not generic.icon:
			generic.icon = item.icon


func _register_default_materials() -> void:
	var stone := BuildMaterial.new()
	stone.material_id = "stone"
	stone.display_name = "Stone"
	stone.item = config_ref.get_item(&"stone_01")
	stone.base_cost = 1
	stone.sound_material = &"rock"
	stone.surface_material = stone.item.surface_material
	build_materials.append(stone)

	var wood := BuildMaterial.new()
	wood.material_id = "wood"
	wood.display_name = "Wood"
	wood.item = config_ref.get_item(&"wood_01")
	wood.base_cost = 1
	wood.sound_material = &"wood"
	wood.surface_material = wood.item.surface_material
	build_materials.append(wood)

	var glass := BuildMaterial.new()
	glass.material_id = "glass"
	glass.display_name = "Glass"
	glass.item = config_ref.get_item(&"glass_01")
	glass.base_cost = 1
	glass.sound_material = &"tile"
	glass.surface_material = glass.item.surface_material
	glass.preview_color = Color(0.60, 0.85, 0.95)
	glass.translucent = true
	# El icono se renderiza sobre fondo transparente y con el shader del cristal saldría un
	# fantasma; se dibuja con un sucedáneo opaco del mismo color.
	var glass_icon := StandardMaterial3D.new()
	glass_icon.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_icon.albedo_color = Color(0.74, 0.85, 0.87, 0.7)
	glass_icon.roughness = 0.25
	glass.icon_material = glass_icon
	build_materials.append(glass)

	_publish_translucent_materials()
	print("[BlockDatabase] Registered %d materials." % build_materials.size())


## Publica al mallador qué materiales dejan ver lo que hay detrás. La opacidad de un ShaderMaterial
## no se puede leer del recurso y el culling de caras depende de ella.
func _publish_translucent_materials() -> void:
	var ids: Dictionary = {}
	_translucent_materials.clear()
	for mat in build_materials:
		if not mat.translucent:
			continue
		ids[mat.material_id] = true
		if mat.surface_material:
			_translucent_materials.append(mat.surface_material)
	ChunkMeshBuilder.translucent_material_ids = ids


## Materiales de construcción traslúcidos. Los usa el sistema de agua para empujarles los
## parámetros de niebla cada frame (un cristal sumergido se nieblea a sí mismo), así que devuelve
## el array cacheado y no uno nuevo.
func get_translucent_materials() -> Array[Material]:
	return _translucent_materials

## Material con el que dibujar el icono de un material de construcción.
func _icon_material_of(mat: BuildMaterial) -> Material:
	return mat.icon_material if mat.icon_material else mat.surface_material


## Rellena el icono de los items de material que no traen uno pintado, renderizando un cubo con su
## material. Los que ya tienen icono (piedra, madera) se dejan como están.
func _generate_material_item_icons() -> void:
	var cube := get_block(BLOCK_CUBE_ID)
	if not cube:
		return
	for mat in build_materials:
		if not mat.item or mat.item.icon:
			continue
		var icon := await _icon_generator.generate_icon(cube.mesh, _icon_material_of(mat))
		if icon:
			mat.item.icon = icon
			icon_generated.emit()

## Crea el ItemData de cada combinación bloque+material. Síncrono a propósito: el hotbar restaura
## sus huecos por (block_id, material_id) y, si los items todavía no existen, cae al bloque
## genérico —que no lleva material— y acaba colocando el que hubiera seleccionado.
func _create_block_material_items() -> void:
	_block_material_items.clear()
	for mat in build_materials:
		for block_id in get_all_ids():
			var block := get_block(block_id)
			var item := ItemData.new()
			item.id = StringName("block_%s_%s" % [block.block_name, mat.material_id])
			item.display_name = "%s %s" % [mat.display_name, block.block_name.capitalize()]
			item.description = block.block_description
			item.category = ItemData.Category.BLOCK
			item.block_id = block.block_id
			item.build_material_id = mat.material_id
			item.surface_material = mat.surface_material
			item.stackable = false
			item.max_stack = 1
			_block_material_items.append(item)


## Rellena el icono de los items bloque+material, ya creados.
func _generate_block_material_icons() -> void:
	for item in _block_material_items:
		var block := get_block(item.block_id)
		var mat := get_material_by_id(item.build_material_id)
		if not block or not mat:
			continue
		var icon := await _icon_generator.generate_icon(block.mesh, _icon_material_of(mat))
		if icon:
			item.icon = icon
			icon_generated.emit()


func get_block_items_by_material() -> Dictionary:
	var result := {}
	for mat in build_materials:
		result[mat.material_id] = {
			"display_name": mat.display_name,
			"items": [] as Array[ItemData]
		}
	for item in _block_material_items:
		if result.has(item.build_material_id):
			result[item.build_material_id]["items"].append(item)
	return result

func get_material_by_id(mat_id: String) -> BuildMaterial:
	for mat in build_materials:
		if mat.material_id == mat_id:
			return mat
	return null

func get_material_at(index: int) -> BuildMaterial:
	if index >= 0 and index < build_materials.size():
		return build_materials[index]
	return null

func get_material_count() -> int:
	return build_materials.size()

func _register_default_blocks() -> void:
	var cube := BlockData.new()
	cube.block_id = BLOCK_CUBE_ID
	cube.block_name = "cube"
	cube.block_description = "Bloque cúbico estándar 1x1x1"
	cube.mesh = BlockMeshGenerator.generate_cube()
	cube.collision_shape = BlockMeshGenerator.generate_cube_collision()
	cube.can_rotate = false
	cube.rotation_steps = 4
	register_block(cube)

	var slope := BlockData.new()
	slope.block_id = BLOCK_SLOPE_ID
	slope.block_name = "slope"
	slope.block_description = "Rampa diagonal"
	slope.mesh = BlockMeshGenerator.generate_slope()
	slope.collision_shape = BlockMeshGenerator.generate_slope_collision()
	slope.can_rotate = true
	slope.rotation_steps = 4
	register_block(slope)

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
	inv_corner.block_id = BLOCK_INV_CORNER_ID
	inv_corner.block_name = "inv_corner"
	inv_corner.block_description = "Esquina invertida (cóncava)"
	inv_corner.mesh = BlockMeshGenerator.generate_inv_corner()
	inv_corner.collision_shape = BlockMeshGenerator.generate_inv_corner_collision()
	inv_corner.can_rotate = true
	inv_corner.rotation_steps = 4
	register_block(inv_corner)

	var pane := BlockData.new()
	pane.block_id = BLOCK_PANE_ID
	pane.block_name = "pane"
	pane.block_description = "Panel plano de una sola lámina, para ventanas"
	pane.mesh = BlockMeshGenerator.generate_pane()
	pane.collision_shape = BlockMeshGenerator.generate_pane_collision()
	pane.can_rotate = true
	pane.rotation_steps = 4
	register_block(pane)

	var pane_slope := BlockData.new()
	pane_slope.block_id = BLOCK_PANE_SLOPE_ID
	pane_slope.block_name = "pane_slope"
	pane_slope.block_description = "Panel plano inclinado, en el plano de la rampa"
	pane_slope.mesh = BlockMeshGenerator.generate_pane_slope()
	pane_slope.collision_shape = BlockMeshGenerator.generate_pane_slope_collision()
	pane_slope.can_rotate = true
	pane_slope.rotation_steps = 4
	register_block(pane_slope)

func _create_block_item(block: BlockData) -> ItemData:
	var item := ItemData.new()
	item.id = StringName("block_%s" % block.block_name)
	item.display_name = block.block_name.capitalize()
	item.description = block.block_description
	item.icon = block.preview_icon
	item.category = ItemData.Category.BLOCK
	item.block_id = block.block_id
	item.stackable = false
	item.max_stack = 1
	return item

func get_block_item(block_id: int) -> ItemData:
	return _block_items.get(block_id, null)

func get_all_block_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for id in get_all_ids():
		if _block_items.has(id):
			result.append(_block_items[id])
	return result

func register_block(block: BlockData) -> void:
	_blocks[block.block_id] = block
	_blocks_by_name[block.block_name] = block
	_block_items[block.block_id] = _create_block_item(block)

func get_block(id: int) -> BlockData:
	return _blocks.get(id, null)

func get_block_by_name(block_name: String) -> BlockData:
	return _blocks_by_name.get(block_name, null)

func get_all_blocks() -> Array[BlockData]:
	var result: Array[BlockData] = []
	for block in _blocks.values():
		result.append(block)
	return result

func get_block_count() -> int:
	return _blocks.size()

func get_all_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in _blocks.keys():
		ids.append(id)
	ids.sort()
	return ids
