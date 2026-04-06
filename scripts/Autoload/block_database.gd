extends Node

const config_ref = preload("res://scripts/config.gd")

const BLOCK_CUBE_ID := 0
const BLOCK_SLOPE_ID := 1
const BLOCK_CORNER_ID := 2
const BLOCK_INV_CORNER_ID := 3

signal materials_ready

var _blocks: Dictionary = {}
var _blocks_by_name: Dictionary = {}
var _block_items: Dictionary = {}

var build_materials: Array[BuildMaterial] = []
var _block_material_items: Array[ItemData] = []
var _icon_generator: BlockIconGenerator = null
var _materials_generated: bool = false

func _ready() -> void:
	_register_default_blocks()
	_register_default_materials()
	_icon_generator = BlockIconGenerator.new()
	add_child(_icon_generator)
	_generate_block_icons()
	_generate_block_material_items()
	
	print("[BlockDatabase] Registrados %d bloques." % _blocks.size())
	
func _generate_block_icons() -> void:
	for id in get_all_ids():
		var block := get_block(id)
		if block.preview_icon:
			continue
		var mat: Material = null
		if not build_materials.is_empty():
			mat = build_materials[0].surface_material
		var icon := await _icon_generator.generate_icon(block.mesh, mat)
		if icon:
			block.preview_icon = icon
			var item := _block_items.get(id) as ItemData
			if item:
				item.icon = icon
	print("[BlockDatabase] Generated icons for %d blocks." % _blocks.size())
	
	
func _register_default_materials() -> void:
	var stone := BuildMaterial.new()
	stone.material_id = "stone"
	stone.display_name = "Stone"
	stone.item = config_ref.get_item(&"stone_01")
	stone.base_cost = 1
	stone.surface_material = stone.item.surface_material
	build_materials.append(stone)

	var wood := BuildMaterial.new()
	wood.material_id = "wood"
	wood.display_name = "Wood"
	wood.item = config_ref.get_item(&"wood_01")
	wood.base_cost = 1
	wood.surface_material = wood.item.surface_material
	build_materials.append(wood)

	print("[BlockDatabase] Registered %d materials." % build_materials.size())

func _generate_block_material_items() -> void:
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

			var icon := await _icon_generator.generate_icon(block.mesh, mat.surface_material)
			if icon:
				item.icon = icon
				if not block.preview_icon:
					block.preview_icon = icon

			_block_material_items.append(item)

	_materials_generated = true
	materials_ready.emit()
	print("[BlockDatabase] Generated %d block+material items with icons." % _block_material_items.size())

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
