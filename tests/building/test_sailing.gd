extends Node3D

## godot --headless --path . res://tests/building/test_sailing.tscn
## Propulsión real, crafteo, conservación del aparejo y compatibilidad con partidas anteriores.
class SeaData extends RefCounted:
	var has_water := false
	var radius := 1000.0
	var water_radius := 0.0

class TestPlanet extends Node3D:
	var global_pos := Vector3.ZERO
	var gravity_strength := 0.0
	var planet := SeaData.new()
	var water_sphere: OceanSystem
	var voxel_terrain: VoxelLodTerrain
	var air := Vector3(0, 0, 8)
	func get_wind_velocity(_position: Vector3) -> Vector3:
		return air

class FlatWater extends WaterHeightSampler:
	func get_height_at(_point: Vector3, _time: float, _center: Vector3, _filter: float = 0.0) -> float:
		last_flow = Vector3.ZERO
		return 0.0

var failures := 0
var checks := 0
var _planet: TestPlanet
var _sail: ItemData


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_planet = TestPlanet.new()
	add_child(_planet)
	_sail = ItemCatalog.get_item(&"hide_sail")
	_check_design()
	await _check_custom_building()
	_check_wind_and_force()
	await _check_install_save_and_split()
	await _check_physics()
	await _check_heavy_ship_launch()
	await _check_weather_ship_launch("clear")
	await _check_weather_ship_launch("wind")
	await _check_controls()
	GridManager.clear_all()
	if _planet.water_sphere:
		_planet.water_sphere.mesh_manager.free()
		_planet.water_sphere.free()
	_planet.queue_free()
	await get_tree().process_frame
	print("SAILING: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _check_controls() -> void:
	var menu := Control.new()
	add_child(menu)
	var button := Button.new()
	button.name = "btnSaveGame"
	menu.add_child(button)
	button.owner = menu
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	player.free_flight_enabled = false
	player.input_enabled = true
	player.mouse_captured = true
	player.visible = true
	player.building_system.set_build_mode(false)
	GameManager.current_state = GameManager.State.PLAYING
	var grid: DynamicPlanetGrid = GridManager.convert_to_dynamic(_new_grid().grid_id)[0]
	var body := grid._body
	body.set_physics_process(false)
	_install(grid)
	player._platform_body = body
	body._is_being_controlled = true
	var controls := player.sailing
	check(controls.can_control(), "el jugador sobre cubierta puede gobernar")
	Input.action_press("boat_sail_raise")
	controls._physics_process(1.0 / 60.0)
	Input.action_release("boat_sail_raise")
	check(body.sailing.row == 1 and body.sailing.level == 0 and controls.hud.visible,
		"flecha arriba desde parado saca los remos y muestra el indicador")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_press("boat_sail_raise")
	controls._physics_process(1.0 / 60.0)
	Input.action_release("boat_sail_raise")
	check(body.sailing.level == 1 and body.sailing.row == 0, "otra vez arriba iza un tercio y mete los remos")
	await get_tree().process_frame
	await get_tree().process_frame
	for shift in 2:
		Input.action_press("boat_sail_lower")
		controls._physics_process(1.0 / 60.0)
		Input.action_release("boat_sail_lower")
		await get_tree().process_frame
		await get_tree().process_frame
	check(body.sailing.level == 0 and body.sailing.row == 0, "flecha abajo recoge la vela y para")
	Input.action_press("boat_steer_left")
	controls._physics_process(1.0 / 60.0)
	check(body.steering_input > 0, "flecha izquierda gobierna a babor")
	Input.action_release("boat_steer_left")
	Input.action_press("boat_sail_lower")
	controls._physics_process(1.0 / 60.0)
	Input.action_release("boat_sail_lower")
	check(body.sailing.row == -1 and body.sailing.level == 0, "bajo las velas recogidas está ciar")
	await get_tree().process_frame
	await get_tree().process_frame
	for shift in 2:
		Input.action_press("boat_sail_raise")
		controls._physics_process(1.0 / 60.0)
		Input.action_release("boat_sail_raise")
		await get_tree().process_frame
		await get_tree().process_frame
	check(body.sailing.row == 1 and body.sailing.level == 0, "entre parado y la vela está la marcha de remo")
	Input.action_press("boat_sail_raise")
	controls._physics_process(1.0 / 60.0)
	Input.action_release("boat_sail_raise")
	check(body.sailing.row == 0 and body.sailing.level == 1, "izar desde el remo mete los remos")
	await get_tree().process_frame
	await get_tree().process_frame
	var stamina := player.combat.stamina.stamina
	Input.action_press("boat_row")
	controls._physics_process(1.0 / 60.0)
	Input.action_release("boat_row")
	check(body.sailing.row == 1 and body.sailing.level == 0 and player.combat.stamina.stamina == stamina,
		"R pasa a remo sin gastar aguante")
	await get_tree().process_frame
	await get_tree().process_frame
	player.inventory_ui.visible = true
	controls._physics_process(1.0 / 60.0)
	check(body.sailing.row == 1 and body.steering_input == 0, "abrir inventario suelta el timón pero sigue remando")
	player.inventory_ui.visible = false
	Input.action_press("boat_row")
	controls._physics_process(1.0 / 60.0)
	Input.action_release("boat_row")
	check(body.sailing.row == 0, "R otra vez para los remos")
	await get_tree().process_frame
	await get_tree().process_frame
	body.sailing.set_gear(1)
	Input.action_press("boat_steer_right")
	controls._physics_process(1.0 / 60.0)
	player._platform_body = null
	controls._physics_process(1.0 / 60.0)
	check(body.steering_input == 0 and body.sailing.row == 0 and not controls.hud.visible,
		"abandonar el barco libera los mandos, deja de remar y oculta el indicador")
	Input.action_release("boat_steer_right")
	var hammer := ItemCatalog.get_item(&"stone_hammer_01")
	player.inventory.add_item(hammer, 1)
	player._equip_from_hotbar(null, hammer)
	player.building_system.pick_sail(SailDesign.DEFAULT)
	player._sync_build_mode()
	check(player.building_system.is_sail_mode() and player.building_system.build_mode,
		"sincronizar el inventario mantiene el diseño de vela en el martillo")
	player._unequip_right_hand()
	player._sync_build_mode()
	check(not player.building_system.is_sail_mode(), "dejar el martillo sale de la construcción naval")
	player.free()
	GameManager.player = null
	menu.queue_free()
	GridManager.clear_all()
	await get_tree().process_frame


func _check_design() -> void:
	check(_sail != null and _sail.get_trait(SailTrait) != null, "aparejo registrado para el constructor naval")
	check(not Recipes.all().any(func(recipe: RecipeData) -> bool: return recipe.result == SailDesign.ITEM),
		"la vela se construye en Naval y no se fabrica como objeto de tamaño fijo")
	var small := SailDesign.normalize({"width": 2.0, "height": 1.5, "mast_height": 3.0})
	var large := SailDesign.normalize({"width": 8.0, "height": 6.0, "mast_height": 9.0})
	check(is_equal_approx(SailDesign.area(large) / SailDesign.area(small), 16.0), "superficie calculada por ancho y alto reales")
	check(SailDesign.cost(large)[&"raw_hide"] > SailDesign.cost(small)[&"raw_hide"]
		and SailDesign.cost(large)[&"branch_01"] > SailDesign.cost(small)[&"branch_01"], "paño y aparejo grandes consumen más materiales")
	var fitted := SailDesign.normalize({"width": -2, "height": 8, "mast_height": 1})
	check(fitted["width"] > 0 and fitted["mast_height"] >= fitted["height"] + 0.75,
		"las medidas válidas dejan espacio al paño bajo el mástil")
	check(SailDesign.from_state({}) == SailDesign.LEGACY, "las velas antiguas conservan sus medidas originales")


func _check_custom_building() -> void:
	var builder := Node3D.new()
	add_child(builder)
	var inventory := Inventory.new(100)
	builder.add_child(inventory)
	var ghost := BuildPreview.new()
	builder.add_child(ghost)
	var building := BuildingSystem.new()
	builder.add_child(building)
	building.current_planet = _planet
	building.set_build_mode(true)
	var menu := BuildMenu.new()
	add_child(menu)
	menu.setup(building, inventory)
	menu.open()
	menu._set_material(BuildMenu.NAVAL_CATEGORY)
	var panel := menu._naval_panel
	panel._types[NavalBuildPanel.SAIL_KIND].pressed.emit()
	panel._dimensions[0].value = 6.0
	panel._dimensions[1].value = 4.0
	panel._dimensions[2].value = 7.25
	await get_tree().process_frame
	check(panel._dimensions[2].get_line_edit().text.replace(",", ".").contains("7.25"),
		"los campos muestran las medidas fraccionarias completas")
	var design := {"width": 6.0, "height": 4.0, "mast_height": 7.25}
	check(panel._sail.visible and not panel._mesh.visible and panel._sail._design == design,
		"B → Naval → Vela muestra el aparejo con las tres medidas elegidas")
	check(not panel._profile_option.visible and panel._reason.visible, "la ficha muestra coste y materiales que faltan")
	panel._pick()
	check(building.is_sail_mode() and building.sail_design == design and not menu.visible,
		"confirmar deja la vela a medida en el martillo y cierra el menú")
	check((ghost._prop_ghost as HideSailVisual)._design == design, "el fantasma usa el mismo diseño que la vista 3D")
	menu.open()
	check(panel._kind == NavalBuildPanel.SAIL_KIND and panel._dimensions[2].value == 7.25,
		"B reabre Naval y conserva el diseño de vela activo")
	building.set_cell_size_index(0)
	check(panel._dimensions[0].value == 6.0 and panel._dimensions[2].value == 7.25,
		"cambiar la celda del casco no cambia las dimensiones de la vela")
	menu.close()
	var grid := _new_grid(Vector3(60, 0, 0))
	_set_sail_target(building, grid)
	check(not building.can_afford_block() and not building.try_place_prop() and grid.get_all_props().is_empty(),
		"sin materiales no instala el aparejo")
	var cost := SailDesign.cost(design)
	for id: StringName in cost:
		inventory.add_item(ItemCatalog.get_item(id), cost[id])
	_set_sail_target(building, grid)
	check(building.try_place_prop(), "construye directamente con pieles, tendones, fibra y ramas")
	check(cost.keys().all(func(id: StringName) -> bool: return inventory.get_item_count(ItemCatalog.get_item(id)) == 0),
		"la colocación consume exactamente el coste del tamaño elegido")
	var info: Dictionary = grid.get_all_props().values()[0]
	check(info["state"]["design"] == design, "la instancia guarda sus propias medidas")
	var anchor: Node3D = info["node"]
	var collider := anchor.get_child(0) as CollisionShape3D
	check(is_equal_approx((collider.shape as BoxShape3D).size.y, 7.25), "la colisión del mástil se adapta a su altura")
	var sailing := BoatSailing.new()
	sailing.rebuild([grid])
	sailing.set_level(3)
	var drive := sailing.step(2.0, Vector3.BACK * 8, Vector3.ZERO, Vector3.BACK, Vector3.UP)
	check(sailing.area == 24.0 and drive.is_equal_approx(BoatSailing.drive_force(Vector3.BACK * 8, Vector3.BACK, 24.0 * 1.2)),
		"el empuje usa la superficie de esa vela y la eficiencia de las pieles")
	for id: StringName in cost:
		inventory.add_item(ItemCatalog.get_item(id), cost[id])
	_set_sail_target(building, grid)
	check(not building.try_place_prop() and cost.keys().all(func(id: StringName) -> bool:
		return inventory.get_item_count(ItemCatalog.get_item(id)) == cost[id]),
		"si falla el anclaje se devuelve todo lo pagado sin duplicar materiales")
	var blueprint := GridBlueprint.capture([grid])
	var blueprint_cost := BuildCost.of_blueprint(blueprint)
	check(blueprint_cost == BuildCost.of_grids([grid]) and not blueprint_cost.has(SailDesign.ITEM),
		"el blueprint cobra los materiales de cada vela personalizada")
	check(BuildCost.of_counts(JSON.parse_string(JSON.stringify(BuildCost.count_blueprint(blueprint)))) == blueprint_cost,
		"la ficha del blueprint conserva el precio del aparejo a medida")
	var saved := grid.serialize()
	var restored := PlanetGrid.new()
	restored.deserialize("custom_restore", _planet, saved)
	check(restored.get_all_props().values()[0]["state"]["design"] == design,
		"guardar y cargar conserva el tamaño personalizado")
	restored.clear()
	# Las obras deben pagar los cuatro materiales del aparejo, además del bloque de soporte.
	inventory.clear()
	for id: StringName in blueprint_cost:
		inventory.add_item(ItemCatalog.get_item(id), blueprint_cost[id])
	var site := BlueprintSite.create(blueprint, _planet, Transform3D(Basis.IDENTITY, Vector3(90, 999.5, 0)), "sail")
	check(site.get_cost() == blueprint_cost, "la obra pide el coste completo de la vela")
	site.deposit(inventory)
	var result := {}
	for hit in 50:
		result = site.work()
		if result["finished"]:
			break
	var constructed: Array = result.get("grids", [])
	check(result.get("finished", false) and not constructed.is_empty()
		and constructed[0].get_all_props().values()[0]["state"]["design"] == design,
		"martillear el blueprint reconstruye el aparejo con sus medidas")
	inventory.clear()
	check(building._try_remove_prop(anchor) and cost.keys().all(func(id: StringName) -> bool:
		return inventory.get_item_count(ItemCatalog.get_item(id)) == cost[id]),
		"desmontar recupera los materiales de esa vela")
	_set_sail_target(building, grid)
	check(building.try_place_prop(), "los materiales recuperados permiten reconstruirla")
	var removed := grid.remove_block(Vector3i.ZERO)
	building._refund_block(removed, grid.cell_size)
	check(cost.keys().all(func(id: StringName) -> bool: return inventory.get_item_count(ItemCatalog.get_item(id)) == cost[id]),
		"desmontar el soporte conserva el reembolso del tamaño de la vela")
	menu.queue_free()
	builder.queue_free()
	GridManager.clear_all()
	await get_tree().process_frame


func _set_sail_target(building: BuildingSystem, grid: GridBase) -> void:
	building._target_prop_grid = grid
	building._target_prop_cell = Vector3i.ZERO
	building._target_prop_face = Vector3i.UP
	building._target_prop_local = Transform3D(Basis.IDENTITY, Vector3(0.5, 1, 0.5))
	building._has_target = true
	building._has_prop_target = true
	building._can_place = true
	building._can_afford = building.can_afford_block()


func _check_wind_and_force() -> void:
	check(WindField.velocity(Vector3(2, 1, 0), 8, 1, Vector3.UP).dot(Vector3.UP) == 0.0,
		"viento siempre tangente al planeta")
	check(WindField.velocity(Vector3.ZERO, 8, 1, Vector3.UP).is_zero_approx()
		and WindField.velocity(Vector3.UP, 8, 1, Vector3.UP).is_zero_approx(), "sin dirección y en los polos no inventa viento")
	check(WindField.velocity(Vector3.RIGHT, 8, 0, Vector3.UP).is_zero_approx(), "la calma del clima elimina el viento")
	check(WindField.velocity(Vector3.RIGHT, 8, 2, Vector3.UP).is_equal_approx(Vector3(16, 0, 0)),
		"el temporal multiplica la velocidad física")
	var forward := Vector3.BACK
	var tail := BoatSailing.drive_force(forward * 8, forward, 12)
	var port := BoatSailing.drive_force(Vector3.RIGHT * 8, forward, 12)
	var starboard := BoatSailing.drive_force(Vector3.LEFT * 8, forward, 12)
	check(tail.z > 0 and port.z > 0 and is_equal_approx(port.z, starboard.z)
		and is_equal_approx(port.x, -starboard.x), "empopada y través impulsan con ambas amuras simétricas")
	check(BoatSailing.drive_force(-forward * 8, forward, 12).is_zero_approx(), "proa al viento no propulsa")
	check(BoatSailing.drive_force(Vector3.ZERO, forward, 12).is_zero_approx()
		and BoatSailing.drive_force(forward * 8, forward, 0).is_zero_approx(), "sin viento o superficie no hay empuje")
	check(BoatSailing.drive_force(forward * 16, forward, 12).is_equal_approx(tail * 4)
		and BoatSailing.drive_force(forward * 8, forward, 24).is_equal_approx(tail * 2),
		"empuje proporcional al área y al cuadrado del viento")
	check(BoatSailing.drive_force(-forward * 4, forward, 12).is_zero_approx(),
		"la velocidad propia en calma no genera autopropulsión")
	check(BoatSailing.rowing_acceleration(1, BoatSailing.ROW_SPEED) == 0.0
		and BoatSailing.rowing_acceleration(1, 0.0) > 0.0 and BoatSailing.rowing_acceleration(1, 5.0) == 0.0,
		"el remo empuja hasta su velocidad y no frena a un barco más rápido")
	check(BoatSailing.rowing_acceleration(-1, 0.0) < 0.0 and BoatSailing.rowing_acceleration(-1, 2.0) < 0.0
		and BoatSailing.rowing_acceleration(-1, -BoatSailing.BACK_SPEED) == 0.0
		and BoatSailing.rowing_acceleration(0, 0.0) == 0.0, "ciar frena y retrocede hasta su límite")
	var stations := BoatOars.stations(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.75, 0)]),
		PackedVector3Array([Vector3(1.5, 0.5, 4.5), Vector3(0.2, 0.25, 0.2)]))
	var pivots_ok := stations.size() == 6
	for station: Dictionary in stations:
		var pivot: Vector3 = station["pivot"]
		pivots_ok = pivots_ok and is_equal_approx(absf(pivot.x), 1.52) and is_equal_approx(pivot.y, 0.55) \
			and signf(pivot.x) == station["side"]
		for phase in [0.0, 0.25, 0.5, 0.75]:
			var oar := BoatOars.oar_basis(station["side"], station["pitch"], phase)
			pivots_ok = pivots_ok and oar.y.y < 0.0 and oar.y.x * station["side"] > 0.0 \
				and is_equal_approx(oar.determinant(), 1.0)
	check(pivots_ok, "remos en tres bancadas apoyados en la borda de cada costado, apuntando al agua")
	var stroke := BoatOars.oar_basis(1.0, 0.5, 0.0).y.z - BoatOars.oar_basis(1.0, 0.5, 0.49).y.z
	check(stroke > 0.5 and BoatOars.oar_basis(1.0, 0.5, 0.75).y.y > BoatOars.oar_basis(1.0, 0.5, 0.25).y.y,
		"la palada barre de proa a popa y la pala vuelve por encima")


func _new_grid(offset := Vector3.ZERO) -> PlanetGrid:
	var grid := GridManager.create_grid_exact(_planet, Vector3(0, 999.5, 0) + offset, Basis.IDENTITY, 1.0)
	grid.place_block(Vector3i.ZERO, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
		grid.get_grid_world_transform(), "wood")
	return grid


func _install(grid: GridBase, cell := Vector3i.ZERO, state: Dictionary = {}) -> bool:
	return grid.place_prop(cell, Vector3i.UP, &"hide_sail",
		Transform3D(Basis.IDENTITY, Vector3(cell) + Vector3(0.5, 1.0, 0.5)), state)


func _check_install_save_and_split() -> void:
	var static_grid := _new_grid()
	check(not static_grid.place_prop(Vector3i.ZERO, Vector3i.RIGHT, &"hide_sail", Transform3D.IDENTITY),
		"el mástil solo admite la cara superior de un bloque")
	check(not _install(static_grid, Vector3i(0, 2, 0)), "el mástil requiere un bloque de apoyo")
	check(_install(static_grid) and not _install(static_grid), "se instala una sola vela por punto de apoyo")
	var static_sailing := BoatSailing.new()
	static_sailing.rebuild([static_grid])
	static_sailing.set_level(3)
	static_sailing.step(2.0, Vector3.BACK * 8, Vector3.ZERO, Vector3.BACK, Vector3.UP)
	var visual: HideSailVisual = static_sailing.sails[0]["visual"]
	check(visual != null and is_equal_approx(visual._lower_yard.position.y, 1.5),
		"el paño y la verga se despliegan también sobre una grid estática")
	static_sailing.set_level(0)
	static_sailing.step(2.0, Vector3.ZERO, Vector3.ZERO, Vector3.BACK, Vector3.UP)
	var grids := GridManager.convert_to_dynamic(static_grid.grid_id)
	var grid: DynamicPlanetGrid = grids[0]
	var body := grid._body
	body.set_physics_process(false)
	body.refresh_sails()
	check(body.sailing.sails.size() == 1 and body.sailing.area == 12.0, "la conversión detecta el aparejo de cubierta")
	body.sailing.set_level(3)
	var force := body.sailing.step(1.0, Vector3.BACK * 8, Vector3.ZERO, Vector3.BACK, Vector3.UP)
	check(is_equal_approx(body.sailing.deployment, 0.5) and force.z > 0, "izar lleva dos segundos y aplica fuerza gradual")
	body._is_being_controlled = false
	body.sailing.step(1.0, Vector3.BACK * 8, Vector3.ZERO, Vector3.BACK, Vector3.UP)
	check(is_equal_approx(body.sailing.deployment, 1.0) and body.sailing.force.z > 0,
		"las velas siguen trabajando sin controlador")
	var blueprint := GridBlueprint.capture([grid])
	check(blueprint["grids"][0]["props"][0]["state"]["level"] == 3, "el blueprint conserva el estado del aparejo")
	var copies := GridBlueprint.instantiate(blueprint, _planet, Vector3(30, 999.5, 0), Basis.IDENTITY)
	var copy_body: DynamicGridBody = copies[0]._body
	copy_body.set_physics_process(false)
	copy_body.refresh_sails()
	check(copy_body.sailing.level == 3 and copy_body.sailing.sails.size() == 1,
		"reconstruir el blueprint restaura una vela funcional")
	copy_body.sailing.set_level(1)
	check(body.sailing.level == 3 and grid.get_all_props().values()[0]["state"]["level"] == 3,
		"el blueprint tiene un estado independiente del barco original")
	GridManager.remove_grid_group(copies[0].grid_id)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GridManager.get_save_data()))
	GridManager.restore_save_data(saved)
	await get_tree().process_frame
	grid = GridManager.get_grid(grid.grid_id) as DynamicPlanetGrid
	body = grid._body
	body.set_physics_process(false)
	body.refresh_sails()
	check(body.sailing.level == 3 and grid.get_all_props().values()[0]["state"]["deployment"] == 1.0,
		"guardar y cargar conserva despliegue y nivel")
	var piece_cells: Array[Vector3i] = []
	for x in range(5, 9):
		var cell := Vector3i(x, 0, 0)
		grid.place_block(cell, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
			Transform3D(Basis.IDENTITY, grid.grid_to_world(cell)), "wood")
		piece_cells.append(cell)
	_install(grid, piece_cells[0], {"level": 2, "deployment": 0.6,
		"design": {"width": 2.0, "height": 1.0, "mast_height": 3.0}})
	body._split_grids = [grid]
	var piece := {"count": 4, "centroid": Vector3(7, 0.5, 0.5), "groups": [{"grid_index": 0, "cells": piece_cells}]}
	body._spawn_piece(piece, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	body.refresh_sails()
	check(body.sailing.sails.size() == 1, "la rotura retira del casco original las velas de la pieza")
	var piece_found := false
	for other: GridBase in GridManager._grids.values():
		if other is DynamicPlanetGrid and other._body != body:
			other._body.set_physics_process(false)
			other._body.refresh_sails()
			piece_found = other._body.sailing.level == 2 and other._body.sailing.area == 2.0 \
				and other.get_all_props().values()[0]["state"]["deployment"] == 0.6
	check(piece_found, "el fragmento recibe su vela con sus medidas y su despliegue")
	var removed := grid.remove_block(Vector3i.ZERO)
	body.refresh_sails()
	check(removed["detached_props"] == [&"hide_sail"] and body.sailing.sails.is_empty(),
		"romper el soporte elimina el empuje y devuelve el id de la vela")
	GridManager.clear_all()
	await get_tree().process_frame
	# Las partidas antiguas no llevan state: la vela se crea recogida.
	static_grid = _new_grid(Vector3(20, 0, 0))
	static_grid._deserialize_props({"old": {"item_id": "hide_sail", "cell": [0, 0, 0], "face": [0, 1, 0],
		"local_transform": GridBase._transform_to_array(Transform3D(Basis.IDENTITY, Vector3(0.5, 1, 0.5)))}})
	grids = GridManager.convert_to_dynamic(static_grid.grid_id)
	body = grids[0]._body
	body.set_physics_process(false)
	body.refresh_sails()
	check(body.sailing.level == 0, "partidas sin estado de velas cargan con el aparejo recogido")
	GridManager.clear_all()
	await get_tree().process_frame


func _check_physics() -> void:
	_planet.water_sphere = OceanSystem.new()
	_planet.water_sphere.mesh_manager = QuadTreeMeshManager.new()
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform float water_time = 0.0;"
	mat.shader = shader
	_planet.water_sphere.mesh_manager.default_material = mat
	var grid: DynamicPlanetGrid = GridManager.convert_to_dynamic(_new_grid().grid_id)[0]
	var body := grid._body
	body.set_physics_process(false)
	body.gravity_scale = 0.0
	body.global_position.y = 999.95
	var sampler := FlatWater.new()
	body.add_child(sampler)
	body._water_sampler = sampler
	_planet.planet.has_water = true
	# Se llama al paso completo: flotación, resistencia y fuerzas enviadas al servidor de física.
	for frame in 6:
		body._physics_step(1.0 / 60.0)
		await get_tree().physics_frame
	check(absf(body.linear_velocity.z) < 0.001, "el barco sin velas no acelera aunque sople viento")
	_install(grid, Vector3i.ZERO, {"level": 3, "deployment": 1.0})
	for frame in 12:
		body._physics_step(1.0 / 60.0)
		await get_tree().physics_frame
	check(body.linear_velocity.z > 0.05, "la fuerza de la vela mueve el RigidBody3D sin controlador")
	check(body.linear_velocity.length() < 0.9, "un casco pequeño mantiene una arrancada acotada con la potencia nueva")
	grid.remove_prop(GridBase.prop_key(Vector3i.ZERO, Vector3i.UP))
	body.refresh_sails()
	var drift := body.linear_velocity.z
	for frame in 6:
		body._physics_step(1.0 / 60.0)
		await get_tree().physics_frame
	check(body.sailing.force.is_zero_approx() and body.linear_velocity.z <= drift + 0.001,
		"desmontar corta el empuje y conserva la inercia")
	body.mass = DynamicGridBody.MIN_MASS
	body.linear_velocity = Vector3.ZERO
	body._is_being_controlled = true
	body.sailing.set_gear(1)
	var rowing_peak := 0.0
	for frame in 6:
		body._physics_step(1.0 / 60.0)
		await get_tree().physics_frame
		rowing_peak = maxf(rowing_peak, body.linear_velocity.dot(body.global_basis.z))
	check(rowing_peak > 0.05 and rowing_peak <= BoatSailing.ROW_SPEED + 0.01,
		"el remo no rebasa su límite ni en un cuerpo de masa mínima (%.2f m/s)" % rowing_peak)
	check(body.sailing.rowing and body._oars != null and body._oars.visible and body._oars.get_child_count() >= 2,
		"remando asoman los remos")
	body.mass = 4000.0
	body.linear_velocity = Vector3.ZERO
	for frame in 240:
		body._physics_step(1.0 / 60.0)
		await get_tree().physics_frame
	var cruise := body.linear_velocity.dot(body.global_basis.z)
	check(cruise > BoatSailing.ROW_SPEED * 0.8 and cruise <= BoatSailing.ROW_SPEED + 0.01,
		"un casco pesado llega a la marcha de remo sin viento a favor (%.2f m/s)" % cruise)
	# Sin gravedad el bloque de prueba acaba saliendo del agua: se devuelve a flote antes de ciar.
	body.global_position.y = 999.7
	body.linear_velocity = Vector3.BACK
	body.sailing.set_gear(-1)
	for frame in 150:
		body._physics_step(1.0 / 60.0)
		await get_tree().physics_frame
	var astern := body.linear_velocity.dot(body.global_basis.z)
	check(astern < -BoatSailing.BACK_SPEED * 0.6 and astern >= -BoatSailing.BACK_SPEED - 0.01,
		"ciar frena y lleva el barco marcha atrás (%.2f m/s)" % astern)
	body._is_being_controlled = false
	body._physics_step(1.0 / 60.0)
	check(not body._oars.visible, "sin nadie a bordo los remos se recogen")
	_planet.planet.has_water = false
	GridManager.clear_all()
	await get_tree().process_frame


func _check_weather_ship_launch(event: String) -> void:
	# Carga similar al barco de varias rejillas de la partida, con el viento real del
	# catálogo proyectado sobre su latitud. La arrancada no debe quedarse en el tope antiguo.
	var static_grid := GridManager.create_grid_exact(_planet, Vector3(-3, 999.9, -10), Basis.IDENTITY, 1.0)
	static_grid.begin_bulk_edit()
	for x in 6:
		for y in 3:
			for z in 20:
				var cell := Vector3i(x, y, z)
				static_grid.place_block(cell, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
					Transform3D(Basis.IDENTITY, static_grid.grid_to_world(cell)), "wood")
	static_grid.end_bulk_edit()
	var grid: DynamicPlanetGrid = GridManager.convert_to_dynamic(static_grid.grid_id)[0]
	var body := grid._body
	body.set_physics_process(false)
	body._interior_dirty = false
	var sampler := FlatWater.new()
	body.add_child(sampler)
	body._water_sampler = sampler
	_install(grid, Vector3i(3, 2, 10), {"level": 3, "deployment": 1.0,
		"design": {"width": 5.5, "height": 7.0, "mast_height": 10.0}})
	var events: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/weather/weather_events.json"))
	var weather := WeatherState.new()
	weather.apply_overrides(events.events[event])
	var local_up := Vector3(0.626, 0.490, -0.607).normalized()
	var wind_speed := WindField.velocity(Vector3.RIGHT, 8.0, weather.wind_speed_multiplier, local_up).length()
	_planet.air = Vector3.BACK * wind_speed
	# Con velocidades de navegación necesita gravedad para seguir la superficie curva;
	# sin ella saldría del agua por la tangente del pequeño planeta de prueba.
	_planet.gravity_strength = 9.8
	_planet.planet.has_water = true
	var expected_wind := 10.0 if event == "clear" else 20.0
	check(is_equal_approx(body.mass, 18000.0) and absf(wind_speed - expected_wind) < 1.0,
		"weather %s proporciona unos %.0f m/s en la prueba del casco de 18 toneladas" % [event, expected_wind])
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 3.0
	for frame in 100:
		body._physics_step(3.0 / 60.0)
		await get_tree().physics_frame
	var launch_speed := body.linear_velocity.dot(body.global_basis.z)
	var minimum_launch := 7.0 if event == "clear" else 15.0
	check(launch_speed > minimum_launch and launch_speed < wind_speed,
		"con weather %s el casco pesado supera %.0f m/s tras cinco segundos (%.2f m/s)" % [event, minimum_launch, launch_speed])
	for frame in 100:
		body._physics_step(3.0 / 60.0)
		await get_tree().physics_frame
	var cruising_speed := body.linear_velocity.dot(body.global_basis.z)
	var minimum_cruise := 8.0 if event == "clear" else 17.0
	check(cruising_speed > minimum_cruise and cruising_speed > launch_speed and body.linear_velocity.length() < wind_speed,
		"weather %s mantiene velocidad de navegación sin superar su viento de empopada (%.2f m/s)" % [event, cruising_speed])
	Engine.time_scale = previous_time_scale
	_planet.planet.has_water = false
	_planet.gravity_strength = 0.0
	_planet.air = Vector3.BACK * 8.0
	GridManager.clear_all()
	await get_tree().process_frame


func _check_heavy_ship_launch() -> void:
	# Casco de 120 m³: 6 toneladas de entramado y 5 % sumergido. El área y el viento
	# reproducen el caso de una vela de 38,5 m² con brisa suave, sin depender de un save local.
	var static_grid := GridManager.create_grid_exact(_planet, Vector3(-3, 999.9, -5), Basis.IDENTITY, 1.0)
	static_grid.begin_bulk_edit()
	for x in 6:
		for y in 2:
			for z in 10:
				var cell := Vector3i(x, y, z)
				static_grid.place_block(cell, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
					Transform3D(Basis.IDENTITY, static_grid.grid_to_world(cell)), "wood")
	static_grid.end_bulk_edit()
	var grid: DynamicPlanetGrid = GridManager.convert_to_dynamic(static_grid.grid_id)[0]
	var body := grid._body
	body.set_physics_process(false)
	body._interior_dirty = false
	var sampler := FlatWater.new()
	body.add_child(sampler)
	body._water_sampler = sampler
	_install(grid, Vector3i(3, 1, 5), {"level": 3, "deployment": 1.0,
		"design": {"width": 5.5, "height": 7.0, "mast_height": 10.0}})
	_planet.planet.has_water = true
	_planet.air = Vector3.BACK * 3.75
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 10.0
	for frame in 60:
		body._physics_step(10.0 / 60.0)
		await get_tree().physics_frame
	Engine.time_scale = previous_time_scale
	var speed := body.linear_velocity.dot(body.global_basis.z)
	check(is_equal_approx(body.mass, 6000.0) and is_equal_approx(body.sailing.area, 38.5),
		"la prueba de arrancada usa un casco de 6 toneladas y una vela de 38,5 m²")
	check(speed > 2.0 and speed < 3.75,
		"con brisa de 3,75 m/s el casco pesado supera 2 m/s tras diez segundos (%.2f m/s)" % speed)
	_planet.planet.has_water = false
	_planet.air = Vector3.BACK * 8.0
	GridManager.clear_all()
	await get_tree().process_frame
