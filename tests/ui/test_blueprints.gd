extends Node

## Lo que cuesta construir y los blueprints: precio de un blueprint (BuildCost), pagar, devolver con
## el inventario lleno, la ficha y los ficheros del blueprint (guardar, leer, renombrar, borrar),
## desmontar una construcción, construir gratis, el colocador viendo si choca con otra construcción
## y el menú de blueprints (biblioteca con el coste frente a lo que se lleva, y la pestaña de la
## construcción apuntada).
##   godot --headless --path . res://tests/ui/test_blueprints.tscn

## Grid de prueba sin planeta: en el origen y sin nodos de escena.
class TestGrid extends GridBase:
	var xform := Transform3D.IDENTITY

	func get_grid_world_transform() -> Transform3D:
		return xform

	func _get_mesh_local_transform() -> Transform3D:
		return Transform3D.IDENTITY

	func _get_mesh_parent() -> Node3D:
		return null

	func _get_collision_parent() -> Node3D:
		return null

	func _create_block_node(_pos: Vector3i, _data: BlockData, _rot: Basis, _xf: Transform3D) -> Node3D:
		return Node3D.new()


var failures := 0
var _planet: Node3D
var _player: Node3D
var _inventory: Inventory
var _building: BuildingSystem
var _bp_name := "__test_blueprint_%d" % Time.get_ticks_usec()


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_planet = Node3D.new()
	_planet.name = "TestPlanet"
	add_child(_planet)
	_player = Node3D.new()
	add_child(_player)
	_inventory = Inventory.new()
	_player.add_child(_inventory)
	_building = BuildingSystem.new()
	_player.add_child(_building)
	await get_tree().process_frame

	_check_costs()
	_check_pay_and_give()
	_check_files()
	_check_dismantle()
	_check_free_build()
	_check_overlap()
	await _check_menu()

	GridBlueprint.delete_from_disk(_bp_name)
	GridBlueprint.delete_from_disk(_bp_name + "_b")
	BuildingSystem.free_build = false
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Un blueprint a mano: 3 cubos de piedra de 1 m, 2 de madera de 0,25 m (cuestan 1 cada uno:
## el mínimo), uno de un id que ya no existe, uno sin material y una antorcha.
func _blueprint() -> Dictionary:
	var big := {
		"0,0,0": {"block_id": 0, "material_id": "stone"},
		"1,0,0": {"block_id": 0, "material_id": "stone"},
		"2,0,0": {"block_id": 1, "material_id": "stone"},
		"3,0,0": {"block_id": 999, "material_id": "stone"},
		"4,0,0": {"block_id": 0, "material_id": ""},
	}
	var small := {
		"0,4,0": {"block_id": 0, "material_id": "wood"},
		"1,4,0": {"block_id": 4, "material_id": "wood"},
	}
	return {
		"version": 1, "created": "2026-10-22T12:00:00", "dynamic": false,
		"bounds_min": [0, 0, 0], "bounds_max": [5, 1.25, 1], "block_count": 7, "prop_count": 1,
		"grids": [
			{"cell_size": 1.0, "blocks": big, "materials": {},
				"props": [{"item_id": "torch_placeable_01", "cell": [0, 0, 0], "face": [0, 1, 0],
					"local_transform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0.5, 1, 0.5]}]},
			{"cell_size": 0.25, "blocks": small, "materials": {}, "props": []},
		],
	}


func _check_costs() -> void:
	var cost := BuildCost.of_blueprint(_blueprint())
	check(cost.get(&"stone_01", 0) == 3, "3 bloques de piedra de 1 m cuestan 3 piedras (%s)" % cost)
	check(cost.get(&"wood_01", 0) == 2, "2 de madera de 0,25 m, el mínimo: 2 maderas")
	check(cost.get(&"torch_placeable_01", 0) == 1, "la antorcha puesta cuesta una antorcha")
	check(cost.size() == 3, "el de id desconocido y el genérico no cuestan nada")
	check(BuildCost.total(cost) == 6, "6 unidades en total")
	var counts := BuildCost.count_blueprint(_blueprint())
	check(JSON.parse_string(JSON.stringify(counts)) is Dictionary
		and BuildCost.of_counts(JSON.parse_string(JSON.stringify(counts))) == cost,
		"el recuento sobrevive al JSON de la ficha y da el mismo precio")


func _give(id: StringName, amount: int) -> void:
	_inventory.add_item(ItemCatalog.get_item(id), amount)


func _check_pay_and_give() -> void:
	_inventory.clear()
	var cost := BuildCost.of_blueprint(_blueprint())
	check(BuildCost.missing(cost, _inventory).size() == 3, "con el inventario vacío falta todo")
	_give(&"stone_01", 2)
	check(not BuildCost.pay(cost, _inventory) and _inventory.get_item_count(ItemCatalog.get_item(&"stone_01")) == 2,
		"si no alcanza no se paga nada")
	_give(&"stone_01", 1)
	_give(&"wood_01", 5)
	_give(&"torch_placeable_01", 1)
	check(BuildCost.missing(cost, _inventory).is_empty(), "con lo justo no falta nada")
	check(BuildCost.pay(cost, _inventory), "y se paga")
	check(_inventory.get_item_count(ItemCatalog.get_item(&"stone_01")) == 0
		and _inventory.get_item_count(ItemCatalog.get_item(&"wood_01")) == 3, "sale lo que cuesta, ni más ni menos")

	# Inventario lleno: lo que no cabe cae al suelo.
	_inventory.clear()
	var junk := ItemCatalog.get_item(&"stone_hammer_01")
	for i in _inventory.max_slots:
		_inventory.items[i] = InventoryItem.new(junk, 1)
	var before := get_tree().current_scene.get_child_count()
	BuildCost.give({&"stone_01": 4}, _inventory, _player, Vector3.DOWN)
	var dropped := 0
	for child in get_tree().current_scene.get_children():
		if child is DroppedItem and (child as DroppedItem).item_data.id == &"stone_01":
			dropped += (child as DroppedItem).quantity
			child.queue_free()
	check(get_tree().current_scene.get_child_count() > before and dropped == 4,
		"con el inventario lleno, lo devuelto cae al suelo (%d)" % dropped)
	_inventory.clear()


func _check_files() -> void:
	var data := _blueprint()
	check(GridBlueprint.save_to_disk(_bp_name, data), "se guarda el blueprint")
	check(FileAccess.file_exists(GridBlueprint.info_path_for(_bp_name)), "y su ficha al lado")
	var info := GridBlueprint.load_info(_bp_name)
	check(info.get("name") == _bp_name and int(info.get("blocks", 0)) == 7, "la ficha dice su nombre y sus bloques")
	check(info.get("size") is Vector3 and (info["size"] as Vector3).is_equal_approx(Vector3(5, 1.25, 1)),
		"y sus medidas")
	check(int(info.get("unknown_blocks", 0)) == 1, "y cuenta el bloque que no se va a poder poner")
	check(BuildCost.of_counts(info["counts"]) == BuildCost.of_blueprint(data), "su recuento da el mismo precio")

	# Sin ficha (un blueprint de antes): se saca del blueprint y se guarda.
	DirAccess.remove_absolute(GridBlueprint.info_path_for(_bp_name))
	info = GridBlueprint.load_info(_bp_name)
	check(not info.is_empty() and FileAccess.file_exists(GridBlueprint.info_path_for(_bp_name)),
		"un blueprint sin ficha la recupera")
	check(GridBlueprint.list_infos().any(func(i: Dictionary) -> bool: return i["name"] == _bp_name),
		"y sale en la biblioteca")

	var renamed := _bp_name + "_b"
	check(GridBlueprint.rename_on_disk(_bp_name, renamed) and GridBlueprint.exists(renamed)
		and not GridBlueprint.exists(_bp_name) and FileAccess.file_exists(GridBlueprint.info_path_for(renamed)),
		"renombrar se lleva la ficha")
	check(not GridBlueprint.rename_on_disk(renamed, renamed), "no se renombra a sí mismo")
	GridBlueprint.rename_on_disk(renamed, _bp_name)
	GridBlueprint.save_to_disk(renamed, data)
	check(not GridBlueprint.rename_on_disk(_bp_name, renamed), "ni pisa otro que ya existe")
	check(GridBlueprint.delete_from_disk(renamed) and not FileAccess.file_exists(GridBlueprint.info_path_for(renamed)),
		"borrar se lleva la ficha")


func _make_grid(origin := Vector3.ZERO) -> TestGrid:
	var grid := TestGrid.new()
	grid.grid_id = GridManager.generate_grid_id()
	grid.planet_node = _planet
	grid.xform = Transform3D(Basis.IDENTITY, origin)
	GridManager.register_runtime_grid(grid, _planet)
	return grid


func _place(grid: GridBase, pos: Vector3i, mat_id: String, block_id: int = 0) -> void:
	var block := BlockDatabase.get_block(block_id)
	grid.place_block(pos, block, Basis.IDENTITY, Transform3D(Basis.IDENTITY, grid.grid_to_world(pos)), mat_id)


func _check_dismantle() -> void:
	_inventory.clear()
	var grid := _make_grid()
	_place(grid, Vector3i(0, 0, 0), "stone")
	_place(grid, Vector3i(1, 0, 0), "stone")
	_place(grid, Vector3i(2, 0, 0), "wood")
	# Con la mitad de la vida devuelve la mitad, redondeando hacia arriba (1 de 1).
	grid.get_all_blocks()[Vector3i(1, 0, 0)]["hp"] = 0.5
	check(BuildCost.of_grids([grid]) == {&"stone_01": 2, &"wood_01": 1}, "una construcción vale lo que costó")
	var refund := _building.dismantle_group(grid.grid_id)
	check(refund == {&"stone_01": 2, &"wood_01": 1}, "desmontarla devuelve cada bloque (%s)" % refund)
	check(_inventory.get_item_count(ItemCatalog.get_item(&"stone_01")) == 2
		and _inventory.get_item_count(ItemCatalog.get_item(&"wood_01")) == 1, "al inventario")
	check(GridManager.get_grid(grid.grid_id) == null, "y la construcción ya no está")
	_inventory.clear()


func _check_free_build() -> void:
	_inventory.clear()
	BuildingSystem.free_build = true
	check(_building.can_afford_block(), "construyendo gratis siempre alcanza")
	var grid := _make_grid()
	_place(grid, Vector3i(0, 0, 0), "stone")
	var refund := _building.dismantle_group(grid.grid_id)
	check(refund.is_empty() and _inventory.get_item_count(ItemCatalog.get_item(&"stone_01")) == 0,
		"y desmontar no devuelve nada (no hay material infinito)")
	BuildingSystem.free_build = false
	check(not _building.can_afford_block(), "sin construir gratis y sin piedra no alcanza")


func _check_overlap() -> void:
	var grid := _make_grid(Vector3(100, 0, 0))
	_place(grid, Vector3i(0, 0, 0), "stone")
	var placer := BlueprintPlacer.new()
	add_child(placer)
	placer._planet = _planet
	placer._block_centers = BlueprintPlacer._collect_block_centers(_blueprint())
	placer._size = GridBlueprint.get_size(_blueprint())
	placer._placement = Transform3D(Basis.IDENTITY, Vector3(100, 0, 0))
	check(placer._overlaps(-1), "un blueprint encima de otra construcción choca")
	placer._placement = Transform3D(Basis.IDENTITY, Vector3(100, 3, 0))
	check(not placer._overlaps(-1), "subido por encima ya no")
	placer._placement = Transform3D(Basis.IDENTITY, Vector3(99.5, -0.5, -0.5))
	check(placer._overlaps(-1), "medio bloque al lado, sí")
	placer.queue_free()
	GridManager.remove_grid(grid.grid_id)


func _check_menu() -> void:
	_inventory.clear()
	GridBlueprint.save_to_disk(_bp_name, _blueprint())
	var menu := GridManipulatorMenu.new()
	add_child(menu)
	menu.setup(_building, _inventory)
	var requested: Array = []
	menu.load_requested.connect(func(bp_name: String, as_static: bool) -> void: requested.append([bp_name, as_static]))
	menu.open(null)
	check(menu.visible and menu._library.visible and not menu._construction.visible, "sin apuntar abre la biblioteca")
	menu._search.text = _bp_name
	menu._rebuild_cards()
	check(menu._cards.get_child_count() == 1, "la búsqueda deja solo el blueprint de prueba")
	menu._select(_bp_name)
	check(menu._detail.visible and menu._detail_name.text == _bp_name, "su ficha a la derecha")
	check(menu._detail_costs.get_child_count() == 3, "con sus tres materiales")
	check(menu._place_btn.disabled, "sin materiales no se puede colocar")
	_give(&"stone_01", 3)
	_give(&"wood_01", 2)
	_give(&"torch_placeable_01", 1)
	menu._refresh_library()
	check(not menu._place_btn.disabled, "con ellos, sí")
	menu._on_place_pressed()
	check(requested == [[_bp_name, false]], "colocar pide el blueprint al jugador")
	menu._search.text = "zz-no-existe-zz"
	menu._rebuild_cards()
	check(menu._cards.get_child_count() == 1 and menu._cards.get_child(0) is Label, "sin coincidencias, un aviso")
	menu.close()

	# La construcción apuntada.
	_inventory.clear()
	var grid := _make_grid(Vector3(0, 50, 0))
	_place(grid, Vector3i(0, 0, 0), "stone")
	_place(grid, Vector3i(0, 1, 0), "wood")
	menu.open(grid)
	check(menu._construction.visible and menu._grid_body.visible, "apuntando a una construcción abre en ella")
	check(menu._grid_value.get_child_count() == 2, "con lo que vale: piedra y madera")
	menu._name_edit.text = _bp_name
	menu._refresh_save_state()
	check(menu._overwrite_hint.visible, "avisa de que ese nombre ya existe")
	await menu._on_save_pressed()
	check(GridBlueprint.load_info(_bp_name).get("blocks") == 7, "el primer clic no lo sustituye")
	await menu._on_save_pressed()
	check(GridBlueprint.load_info(_bp_name).get("blocks") == 2, "el segundo, sí")
	var notices: Array = []
	menu.notice.connect(func(text: String) -> void: notices.append(text))
	menu._on_dismantle_pressed()
	check(GridManager.get_grid(grid.grid_id) != null, "desmontar pide confirmación")
	menu._on_dismantle_pressed()
	check(GridManager.get_grid(grid.grid_id) == null and not menu.visible and notices.size() == 1,
		"y con ella desmonta, cierra y avisa")
	check(_inventory.get_item_count(ItemCatalog.get_item(&"stone_01")) == 1
		and _inventory.get_item_count(ItemCatalog.get_item(&"wood_01")) == 1, "devolviendo los materiales")
	menu.queue_free()
	_inventory.clear()
