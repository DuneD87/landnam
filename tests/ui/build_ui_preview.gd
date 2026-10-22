extends Node

## Vista aislada de la interfaz de construir, sin partida: el menú de bloques, el de blueprints
## (biblioteca y construcción apuntada), la rueda del martillo y el panel de colocar un blueprint,
## sobre un poco de mundo. Con --capture guarda en build/building/preview/ esas pantallas (a
## 2560 × 1440, la escala base de Saga), los iconos de los bloques en una hoja y las miniaturas de
## los blueprints de prueba. Los blueprints de prueba se guardan con nombre «__preview_» y se borran
## al acabar.
##   godot --path . res://tests/ui/build_ui_preview.tscn -- --capture [--background]

const OUTPUT := "res://build/building/preview/"
const RESOLUTION := Vector2i(2560, 1440)
const PREVIEW_BLUEPRINTS := ["__preview_cabana", "__preview_torre"]

## Grid de prueba sin planeta, con sus mallas en [parent].
class PreviewGrid extends GridBase:
	var xform := Transform3D.IDENTITY
	var parent: Node3D

	func get_grid_world_transform() -> Transform3D:
		return xform

	func _get_mesh_local_transform() -> Transform3D:
		return Transform3D.IDENTITY

	func _get_mesh_parent() -> Node3D:
		return parent

	func _get_collision_parent() -> Node3D:
		return null

	func _create_block_node(_pos: Vector3i, _data: BlockData, _rot: Basis, _xf: Transform3D) -> Node3D:
		var node := Node3D.new()
		parent.add_child(node)
		return node


var _viewport: SubViewport
var _world: Node3D
var _player: Node3D
var _inventory: Inventory
var _building: BuildingSystem


func _ready() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	if capture and "--background" in OS.get_cmdline_user_args():
		get_window().mode = Window.MODE_WINDOWED
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)
	_build_viewport()
	if capture:
		_capture.call_deferred()


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = RESOLUTION
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_build_scene()
	_player = Node3D.new()
	_world.add_child(_player)
	_inventory = Inventory.new()
	_player.add_child(_inventory)
	_building = BuildingSystem.new()
	_player.add_child(_building)


## Cielo, suelo y unas cajas, para que el fondo desenfocado de los menús tenga algo detrás.
func _build_scene() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 3.0, 9)
	camera.rotation_degrees = Vector3(-12, 0, 0)
	_world.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	_world.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_SKY
	environment.environment.sky = Sky.new()
	environment.environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world.add_child(environment)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("566b3a")
	ground.material_override = grass
	_world.add_child(ground)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	while not BlockDatabase.are_materials_ready():
		await get_tree().process_frame
	_save_icon_sheet()

	_give(&"stone_01", 40)
	_give(&"wood_01", 3)
	_give(&"torch_placeable_01", 2)
	var grouped := BlockDatabase.get_block_items_by_material()
	_building.pick_block(grouped["wood"]["items"][1])
	_building.pick_block(grouped["glass"]["items"][4])
	_building.pick_block(grouped["stone"]["items"][1])

	# Menú de bloques: piedra con la rampa elegida, y el ratón sobre la esquina invertida.
	var build_menu: BuildMenu = BuildMenu.new()
	_viewport.add_child(build_menu)
	build_menu.setup(_building, _inventory)
	build_menu.open()
	build_menu._show(grouped["stone"]["items"][3])
	await _shot("01_bloques_piedra")
	build_menu._set_material("wood")
	_building.set_cell_size_index(3)
	await _shot("02_bloques_madera_2m")
	build_menu._set_material("glass")
	await _shot("03_bloques_vidrio")
	build_menu.close()
	_building.set_cell_size_index(2)

	# Blueprints de prueba (sin miniatura: la biblioteca las pinta) y la biblioteca.
	var cabin := _cabin_blueprint()
	GridBlueprint.save_to_disk(PREVIEW_BLUEPRINTS[0], cabin)
	GridBlueprint.save_to_disk(PREVIEW_BLUEPRINTS[1], _tower_blueprint())
	var thumbnails := BlueprintThumbnail.new()
	_viewport.add_child(thumbnails)
	var thumb := await thumbnails.render_data(cabin, "")
	if thumb:
		thumb.get_image().save_png(OUTPUT + "miniatura_cabana.png")
	var grid_menu: GridManipulatorMenu = GridManipulatorMenu.new()
	_viewport.add_child(grid_menu)
	grid_menu.setup(_building, _inventory)
	grid_menu.open(null)
	grid_menu._search.text = "__preview"
	grid_menu._rebuild_cards()
	grid_menu._select(PREVIEW_BLUEPRINTS[0])
	await _shot("04_biblioteca", 2.5)
	grid_menu._select(PREVIEW_BLUEPRINTS[1])
	await _shot("05_biblioteca_torre", 0.6)
	grid_menu.close()

	# La construcción apuntada: la cabaña puesta de verdad, con sus mallas.
	var grid := PreviewGrid.new()
	grid.grid_id = GridManager.generate_grid_id()
	grid.parent = Node3D.new()
	_world.add_child(grid.parent)
	grid.planet_node = _world
	grid.xform = Transform3D(Basis.IDENTITY, Vector3(-2.5, 0, -6))
	for mat_id in ["stone", "wood"]:
		grid.mesh_materials[mat_id] = BlockDatabase.get_material_by_id(mat_id).surface_material
	GridManager.register_runtime_grid(grid, _world)
	GridBlueprint._restore_blocks(grid, GridBlueprint.blocks_dict(cabin["grids"][0]))
	grid_menu.open(grid)
	grid_menu._name_edit.text = PREVIEW_BLUEPRINTS[0]
	grid_menu._refresh_save_state()
	await _shot("06_construccion", 1.5)
	grid_menu.close()

	# La rueda, apuntando a la simetría puesta en el eje Y.
	var radial := BuildRadialMenu.new()
	_viewport.add_child(radial)
	radial.set_process(false)
	radial.open(BuildRadialMenu.Option.ADD, _building.get_selected_block_item(), "Y")
	var index := BuildRadialMenu.OPTIONS.find(BuildRadialMenu.Option.SYMMETRY)
	var angle := index * TAU / BuildRadialMenu.OPTIONS.size()
	radial._input(_motion(Vector2(sin(angle), -cos(angle)) * 200.0))
	await _shot("07_rueda_simetria")
	radial._input(_motion(-Vector2(sin(angle), -cos(angle)) * 200.0))
	await _shot("08_rueda_centro")
	radial.close()

	# El panel de colocar, sin materiales suficientes.
	var placer := BlueprintPlacer.new()
	_world.add_child(placer)
	placer._name = PREVIEW_BLUEPRINTS[0]
	placer._inventory = _inventory
	placer._cost = BuildCost.of_blueprint(cabin)
	placer._problem = BlueprintPlacer.Problem.MISSING
	placer._show_hud()
	await _shot("09_colocar_panel")

	for bp_name in PREVIEW_BLUEPRINTS:
		GridBlueprint.delete_from_disk(bp_name)
	GridManager.remove_grid(grid.grid_id)
	print("BUILD UI PREVIEW DONE")
	get_tree().quit()


func _give(id: StringName, amount: int) -> void:
	_inventory.add_item(ItemCatalog.get_item(id), amount)


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


func _shot(shot_name: String, wait := 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var path := OUTPUT + shot_name + ".png"
	_viewport.get_texture().get_image().save_png(path)
	print("Captura: ", ProjectSettings.globalize_path(path))


## Los iconos de bloque tal como salen en partida, en una hoja: una fila por material.
func _save_icon_sheet() -> void:
	var grouped := BlockDatabase.get_block_items_by_material()
	var side := BlockIconGenerator.ICON_SIZE
	var columns := 0
	for mat_id in grouped:
		columns = maxi(columns, (grouped[mat_id]["items"] as Array).size())
	var sheet := Image.create(columns * side, grouped.size() * side, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1b1d21"))
	var row := 0
	for mat_id in grouped:
		var column := 0
		for item: ItemData in grouped[mat_id]["items"]:
			if item.icon:
				var image := item.icon.get_image()
				image.clear_mipmaps()
				image.convert(Image.FORMAT_RGBA8)
				sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(column * side, row * side))
				image.save_png(OUTPUT + "icono_%s.png" % item.id)
			column += 1
		row += 1
	sheet.save_png(OUTPUT + "00_iconos_bloques.png")


## Cabaña de 5 × 5: suelo de piedra, paredes de madera con puerta y ventana de cristal, y tejado de
## rampas a dos aguas.
func _cabin_blueprint() -> Dictionary:
	var blocks := {}
	var slope := Basis.IDENTITY
	for x in 5:
		for z in 5:
			blocks["%d,0,%d" % [x, z]] = _block(0, "stone")
			var edge := x == 0 or x == 4 or z == 0 or z == 4
			for y in [1, 2]:
				if edge and not (z == 4 and x == 2) and not (x == 0 and z == 2 and y == 2):
					blocks["%d,%d,%d" % [x, y, z]] = _block(0, "wood")
		blocks["%d,3,%d" % [x, 0]] = _block(1, "wood", slope.rotated(Vector3.UP, PI))
		blocks["%d,3,%d" % [x, 4]] = _block(1, "wood", slope)
		for z in [1, 2, 3]:
			blocks["%d,3,%d" % [x, z]] = _block(0, "wood")
	blocks["0,2,2"] = _block(4, "glass", Basis(Vector3.UP, PI * 0.5))
	return _data(blocks, Vector3(5, 4, 5))


## Torre de piedra de 3 × 3 × 7 con almenas.
func _tower_blueprint() -> Dictionary:
	var blocks := {}
	for x in 3:
		for z in 3:
			for y in 7:
				if y == 0 or x != 1 or z != 1:
					blocks["%d,%d,%d" % [x, y, z]] = _block(0, "stone")
			if (x + z) % 2 == 0:
				blocks["%d,7,%d" % [x, z]] = _block(0, "stone")
	return _data(blocks, Vector3(3, 8, 3))


func _block(block_id: int, mat_id: String, rot := Basis.IDENTITY) -> Dictionary:
	return {"block_id": block_id, "material_id": mat_id, "rotation_basis": GridBase._basis_to_array(rot),
		"mirrored": false, "mirror_axis": -1}


func _data(blocks: Dictionary, size: Vector3) -> Dictionary:
	return {"version": 1, "created": Time.get_datetime_string_from_system(), "dynamic": false,
		"bounds_min": [0, 0, 0], "bounds_max": [size.x, size.y, size.z], "block_count": blocks.size(),
		"prop_count": 0, "grids": [{"cell_size": 1.0, "blocks": blocks, "materials": {}, "props": []}]}
