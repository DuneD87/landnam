extends Node

## Construir con el martillo: el objeto y su receta, la rueda del clic derecho (huecos, soltar,
## toque corto), poner/quitar con un colocable en la mano y el menú de bloques eligiendo el bloque
## del martillo.
##   godot --headless --path . res://tests/ui/test_build_hammer.tscn

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_check_item()
	_check_sectors()
	_check_radial_input()
	await _check_radial_draw()
	var building := _make_building_system()
	await get_tree().process_frame
	_check_action_modes(building)
	_check_build_menu(building)
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_item() -> void:
	var hammer := ItemCatalog.get_item(&"stone_hammer_01")
	check(hammer != null, "el martillo está en el catálogo")
	if hammer == null:
		return
	check(hammer.category == ItemData.Category.TOOL and hammer.tool_type == ItemData.ToolType.HAMMER,
		"es una herramienta de tipo martillo")
	check(hammer.armor_slot == ItemData.ArmorSlot.RIGHT_HAND, "va en la mano derecha")
	var scene := load(hammer.scene_path) as PackedScene
	check(scene != null, "su escena carga (%s)" % hammer.scene_path)
	if scene:
		var node := scene.instantiate()
		check(node.get_meta(&"grip_aligned", false), "y va en el marco de agarre de las herramientas")
		node.free()
	var recipe: RecipeData = null
	for r in Recipes.all():
		if r.result == &"stone_hammer_01":
			recipe = r
	check(recipe != null and recipe.station == Recipes.HAND, "se fabrica a mano")


## Dirección hacia el centro del hueco [index] de la rueda (en píxeles de pantalla).
func _toward(index: int, length: float = 300.0) -> Vector2:
	var angle := index * TAU / BuildRadialMenu.OPTIONS.size()
	return Vector2(sin(angle), -cos(angle)) * length


func _check_sectors() -> void:
	var dz := 10.0
	var options := BuildRadialMenu.OPTIONS
	check(options == [BuildRadialMenu.Option.ADD, BuildRadialMenu.Option.REMOVE, BuildRadialMenu.Option.SYMMETRY,
		BuildRadialMenu.Option.BLUEPRINTS, BuildRadialMenu.Option.SELECT_BLOCK],
		"cinco huecos: añadir, quitar, simetría, blueprints y elegir bloque")
	for i in options.size():
		check(BuildRadialMenu.sector_at(_toward(i, 50.0), dz) == i, "hacia el centro del hueco %d, ese" % i)
	check(BuildRadialMenu.sector_at(Vector2(0, -50), dz) == 0, "arriba: añadir")
	check(BuildRadialMenu.sector_at(Vector2(50, 0), dz) == 1, "derecha: quitar")
	check(BuildRadialMenu.sector_at(Vector2(3, 4), dz) == -1, "en la zona muerta, nada")


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


func _button(index: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	return event


func _check_radial_input() -> void:
	var radial := BuildRadialMenu.new()
	add_child(radial)
	var chosen: Array = []
	radial.option_chosen.connect(func(option: BuildRadialMenu.Option) -> void: chosen.append(option))

	# Mantener, apuntar a la derecha y soltar: quitar.
	radial.open(BuildRadialMenu.Option.ADD, null)
	radial._input(_motion(Vector2(400, 0)))
	radial._input(_button(MOUSE_BUTTON_RIGHT, false))
	check(not radial.is_open() and chosen == [BuildRadialMenu.Option.REMOVE], "soltar sobre quitar lo elige")

	# Toque corto sin apuntar: se queda abierta; luego se apunta a elegir bloque y el izquierdo elige.
	chosen.clear()
	radial.open(BuildRadialMenu.Option.REMOVE, null)
	radial._input(_button(MOUSE_BUTTON_RIGHT, false))
	check(radial.is_open() and chosen.is_empty(), "un toque corto la deja abierta")
	radial._input(_motion(_toward(BuildRadialMenu.OPTIONS.find(BuildRadialMenu.Option.SELECT_BLOCK))))
	radial._input(_button(MOUSE_BUTTON_LEFT, true))
	check(not radial.is_open() and chosen == [BuildRadialMenu.Option.SELECT_BLOCK],
		"con la rueda fija, el izquierdo elige lo apuntado")

	# Mantener mucho rato sin apuntar y soltar: se cierra sin elegir.
	chosen.clear()
	radial.open(BuildRadialMenu.Option.ADD, null)
	radial._opened_at -= 1000
	radial._input(_button(MOUSE_BUTTON_RIGHT, false))
	check(not radial.is_open() and chosen.is_empty(), "soltar en el centro tras mantener no elige nada")

	# Fija y otro clic derecho sobre blueprints: lo elige.
	chosen.clear()
	radial.open(BuildRadialMenu.Option.ADD, null)
	radial._input(_button(MOUSE_BUTTON_RIGHT, false))
	radial._input(_motion(_toward(BuildRadialMenu.OPTIONS.find(BuildRadialMenu.Option.BLUEPRINTS))))
	radial._input(_button(MOUSE_BUTTON_RIGHT, true))
	check(chosen == [BuildRadialMenu.Option.BLUEPRINTS], "con la rueda fija, otro clic derecho elige")

	# La simetría: se elige como las demás y su nombre lleva el eje puesto.
	chosen.clear()
	radial.open(BuildRadialMenu.Option.ADD, null, "Y")
	check(radial._label(BuildRadialMenu.Option.SYMMETRY) == tr("BUILD_RADIAL_SYMMETRY_AXIS") % "Y",
		"con simetría puesta, su hueco dice el eje")
	radial._input(_motion(_toward(BuildRadialMenu.OPTIONS.find(BuildRadialMenu.Option.SYMMETRY))))
	radial._input(_button(MOUSE_BUTTON_RIGHT, false))
	check(chosen == [BuildRadialMenu.Option.SYMMETRY], "soltar sobre simetría la elige")

	# El movimiento no pasa de la rueda (la cámara no gira) y el cursor no se sale del borde.
	radial.open(BuildRadialMenu.Option.ADD, null)
	radial._input(_motion(Vector2(5000, 0)))
	check(radial._cursor.length() <= BuildRadialMenu.OUTER_RADIUS * radial._ui_scale + 0.01,
		"el cursor virtual se queda dentro de la rueda")
	radial.close()
	radial.queue_free()


## La rueda se dibuja abierta, con y sin opción apuntada y con el icono de un bloque. Sin ratón
## capturado (headless) se cerraría sola: se le quita el _process para que siga abierta.
func _check_radial_draw() -> void:
	var radial := BuildRadialMenu.new()
	add_child(radial)
	radial.set_process(false)
	var drawn := [0]
	radial._canvas.draw.connect(func() -> void: drawn[0] += 1)
	var block: ItemData = BlockDatabase.get_block_items_by_material().values()[0]["items"][0]
	radial.open(BuildRadialMenu.Option.REMOVE, block, "X")
	await get_tree().process_frame
	radial._input(_motion(_toward(BuildRadialMenu.OPTIONS.find(BuildRadialMenu.Option.SYMMETRY))))
	await get_tree().process_frame
	radial.open(BuildRadialMenu.Option.ADD, null)
	await get_tree().process_frame
	check(drawn[0] >= 2, "la rueda se dibuja (%d veces)" % drawn[0])
	radial.queue_free()


func _make_building_system() -> BuildingSystem:
	var owner_node := Node3D.new()
	add_child(owner_node)
	var building := BuildingSystem.new()
	owner_node.add_child(building)
	return building


func _check_action_modes(building: BuildingSystem) -> void:
	building.set_action_mode(BuildingSystem.ActionMode.DESTROY)
	check(building.current_action_mode == BuildingSystem.ActionMode.DESTROY, "el martillo pasa a quitar")
	var torch := ItemCatalog.get_item(&"torch_placeable_01")
	building.select_placeable(torch)
	check(building.current_action_mode == BuildingSystem.ActionMode.BUILD, "con un colocable se pone")
	building.toggle_action_mode()
	building.set_action_mode(BuildingSystem.ActionMode.DESTROY)
	check(building.current_action_mode == BuildingSystem.ActionMode.BUILD,
		"y con él en la mano no se puede pasar a quitar")
	building.select_placeable(null)
	building.toggle_action_mode()
	check(building.current_action_mode == BuildingSystem.ActionMode.DESTROY, "sin colocable vuelve a poder quitar")
	building.set_action_mode(BuildingSystem.ActionMode.BUILD)

	var item := building.get_selected_block_item()
	var mat := building.get_current_material()
	check(item != null and item.block_id == building.selected_block_id \
		and mat != null and item.build_material_id == mat.material_id,
		"el item del bloque elegido casa con el bloque y el material activos")


func _check_build_menu(building: BuildingSystem) -> void:
	var menu := BuildMenu.new()
	add_child(menu)
	menu.setup(building)
	var closed := [false]
	menu.closed.connect(func() -> void: closed[0] = true)
	menu.open()
	building.set_action_mode(BuildingSystem.ActionMode.DESTROY)

	var grouped := BlockDatabase.get_block_items_by_material()
	var pick: ItemData = null
	for mat_id in grouped:
		for candidate: ItemData in grouped[mat_id]["items"]:
			if candidate.block_id != building.selected_block_id:
				pick = candidate
	check(pick != null, "hay otro bloque que elegir")
	if pick == null:
		return
	check(menu._tile_buttons.size() > 0, "el menú enseña los bloques del material (%d)" % menu._tile_buttons.size())
	menu._set_material(pick.build_material_id)
	check(menu._tile_buttons.has(pick), "al cambiar de material salen sus bloques")
	(menu._tile_buttons[pick] as Button).pressed.emit()
	var mat := building.get_current_material()
	check(building.selected_block_id == pick.block_id and mat.material_id == pick.build_material_id,
		"elegir un bloque en el menú lo pone en el martillo con su material")
	check(building.current_action_mode == BuildingSystem.ActionMode.BUILD, "y vuelve a poner")
	check(not menu.visible and closed[0], "y el menú se cierra avisando")
	check(not building.recent_blocks.is_empty() and building.recent_blocks[0] == pick, "y queda entre los recientes")

	# El tamaño de celda se cambia desde arriba del menú.
	menu.open()
	menu._cell_buttons[0].pressed.emit()
	check(building.cell_size == BuildingSystem.CELL_SIZES[0], "los botones de celda cambian el tamaño de celda")
	building.set_cell_size_index(2)
	menu.close()
	menu.queue_free()
