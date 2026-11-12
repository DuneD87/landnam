extends Node3D

## Puertas y trampillas de madera (WoodenDoor, DoorDesign): los objetos, lo que cuestan según sus
## medidas y la celda, y su malla; cómo encajan en el hueco de un muro apuntando a una jamba, al suelo
## o al dintel, a ras de la cara de quien la pone o, girada, de la otra, también en un muro sobre el
## terreno y en celdas de 0,5 m; una puerta ancha; que no caben en un hueco ocupado ni encima de otra
## hoja; elegirlas en el menú de bloques y ponerlas con el martillo; lo que valen puestas y en un
## blueprint; abrirlas hacia el otro lado (el hueco queda libre y el collider gira con la hoja) y
## cerrarlas; guardar y cargar, y en un barco. La trampilla, en el hueco de un techo y en una ventana,
## y girada para caber en un hueco alargado.
##   godot --headless --path . res://tests/building/test_doors.tscn

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

const ORIGIN := Vector3(0, 500, 0)
## Dónde queda el plano de la hoja en el grueso de un muro de una celda (de 0 a 1), a ras de la cara de
## delante o de la de detrás.
const FRONT := 1.0 - DoorMesh.THICKNESS * 0.5
const BACK := DoorMesh.THICKNESS * 0.5
const EPS := 0.001
const DOOR_CELLS := Vector2i(1, 3)
const TRAP_CELLS := Vector2i(1, 1)

var failures := 0
var _planet: TestPlanet


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_check_items()
	_planet = TestPlanet.new()
	_planet.name = "DoorTestPlanet"
	add_child(_planet)
	BuildingSystem.free_build = true
	_check_fit()
	_check_panel()
	await _check_place_and_swing()
	await _check_trapdoor()
	BuildingSystem.free_build = false
	_finish()


func _check_items() -> void:
	var door := WoodenDoor.door_of(&"wooden_door")
	var trapdoor := WoodenDoor.door_of(&"wooden_trapdoor")
	check(door != null and door.cells == Vector2i(1, 3) and door.upright, "la puerta cierra 1 × 3 celdas, de pie")
	check(trapdoor != null and trapdoor.cells == Vector2i(1, 1) and not trapdoor.upright,
		"la trampilla, 1 × 1 en el plano del hueco")
	for id in DoorDesign.KINDS:
		var item := ItemCatalog.get_item(id)
		check(not item.placeable and item.placed_solid and item.icon != null
			and not Recipes.all().any(func(r: RecipeData) -> bool: return r.result == id),
			"%s no se fabrica ni va en la barra: sale del menú de bloques, y choca" % id)
	check(DoorDesign.normalize({}, DoorDesign.DOOR) == {"width": 1, "height": 3}
		and DoorDesign.normalize({"width": 9, "height": 0}, DoorDesign.TRAPDOOR) == {"width": 4, "height": 1},
		"las medidas salen de las de cada una y no pasan de sus límites")
	check(DoorDesign.cost({"width": 1, "height": 3}, 1.0) == {&"wood_01": 6, &"raw_hide": 1}
		and DoorDesign.cost({"width": 2, "height": 3}, 1.0) == {&"wood_01": 12, &"raw_hide": 2}
		and DoorDesign.cost({"width": 1, "height": 3}, 0.5) == {&"wood_01": 2, &"raw_hide": 1},
		"cuesta según lo que mide en metros")
	check(BuildCost.prop_cost({"item_id": &"wooden_trapdoor", "state": {"width": 2, "height": 2, "cell": 1.0}})
		== {&"wood_01": 8, &"raw_hide": 2}, "y puesta, devuelve lo de sus medidas")
	var mesh := DoorMesh.make(Vector2i(1, 3))
	var box := mesh.get_aabb()
	check(mesh.get_surface_count() == 3 and box.size.x <= 1.0 + EPS and box.size.y <= 3.0 + EPS
		and box.position.y >= 0.0 and box.size.z < 0.2, "la malla de la puerta cabe en su hueco (%s)" % box)
	check(DoorMesh.make(Vector2i(1, 3), -1) != mesh and DoorMesh.make(Vector2i(1, 3)) == mesh,
		"una malla por lado de las bisagras, compartida")


## Un muro a lo largo de X sobre un suelo, con un hueco de [hole] × 3 desde x = 0.
func _wall(cell: float, with_floor: bool = true, hole: int = 1) -> GridBase:
	var grid := GridManager.create_grid_exact(_planet, ORIGIN, Basis.IDENTITY, cell)
	var wood := BlockDatabase.get_block(0)
	grid.begin_bulk_edit()
	for x in range(-2, hole + 2):
		if with_floor:
			_put(grid, wood, Vector3i(x, -1, 0))
		for y in 4:
			if x < 0 or x >= hole or y == 3:
				_put(grid, wood, Vector3i(x, y, 0))
	grid.end_bulk_edit()
	grid.mesh_materials["wood"] = BlockDatabase.get_material_by_id("wood").surface_material
	return grid


func _put(grid: GridBase, block: BlockData, cell: Vector3i) -> void:
	grid.place_block(cell, block, Basis.IDENTITY, Transform3D(grid.get_basis_world(), grid.grid_to_world(cell)), "wood")


func _check_fit() -> void:
	var grid := _wall(1.0)
	# Desde delante (+Z), apuntando a la jamba de +X: bisagras en ella y la puerta baja hasta el suelo.
	var fit := WoodenDoor.fit(grid, Vector3i(1, 1, 0), Vector3i.LEFT, Vector3(1.0, 1.5, 0.5), Vector3.FORWARD, DOOR_CELLS, true)
	var xform: Transform3D = fit.get("transform", Transform3D())
	check(fit.get("ok", false) and fit["hinge"] == 1, "apuntando a una jamba, las bisagras van en ella")
	check(xform.origin.is_equal_approx(Vector3(0.5, 0.0, FRONT)) and xform.basis.is_equal_approx(Basis.IDENTITY),
		"de pie en el suelo del hueco, de frente y a ras de la cara de delante del muro (%s)" % xform)
	check(WoodenDoor.slot_cells(xform, DOOR_CELLS, 1.0) == [Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 2, 0)],
		"cierra las tres celdas del hueco")
	# Desde detrás, la cara de delante mira hacia atrás.
	fit = WoodenDoor.fit(grid, Vector3i(1, 2, 0), Vector3i.LEFT, Vector3(1.0, 2.5, 0.5), Vector3.BACK, DOOR_CELLS, true)
	xform = fit["transform"]
	check(xform.basis.z.is_equal_approx(Vector3.FORWARD) and xform.origin.is_equal_approx(Vector3(0.5, 0.0, BACK))
		and fit["hinge"] == -1, "desde detrás, a ras de la cara de detrás, de cara a quien la pone y con las bisagras en la misma jamba")
	# Girada, desde delante: como puesta desde detrás.
	fit = WoodenDoor.fit(grid, Vector3i(1, 1, 0), Vector3i.LEFT, Vector3(1.0, 1.5, 0.5), Vector3.FORWARD, DOOR_CELLS, true, true)
	xform = fit["transform"]
	check(xform.basis.z.is_equal_approx(Vector3.FORWARD) and xform.origin.is_equal_approx(Vector3(0.5, 0.0, BACK))
		and (xform.basis.x * fit["hinge"]).is_equal_approx(Vector3.RIGHT),
		"girada, a ras de la otra cara y con las bisagras en la misma jamba")
	# Al suelo: las bisagras en el lado de la celda que se apunta.
	fit = WoodenDoor.fit(grid, Vector3i(0, -1, 0), Vector3i.UP, Vector3(0.2, 0.0, 0.5), Vector3(0, -0.5, -1), DOOR_CELLS, true)
	check(fit["ok"] and fit["hinge"] == -1 and (fit["transform"] as Transform3D).origin.is_equal_approx(Vector3(0.5, 0, FRONT)),
		"apuntando al suelo, las bisagras en el lado apuntado")
	fit = WoodenDoor.fit(grid, Vector3i(0, -1, 0), Vector3i.UP, Vector3(0.2, 0.0, 0.5), Vector3(0, -0.5, -1), DOOR_CELLS, true, true)
	check(fit["ok"] and ((fit["transform"] as Transform3D).basis.x * fit["hinge"]).is_equal_approx(Vector3.LEFT),
		"y girada, también")
	# Al dintel: cuelga de él hasta el suelo.
	fit = WoodenDoor.fit(grid, Vector3i(0, 3, 0), Vector3i.DOWN, Vector3(0.8, 3.0, 0.5), Vector3(0, 0.5, -1), DOOR_CELLS, true)
	check(fit["ok"] and fit["hinge"] == 1 and (fit["transform"] as Transform3D).origin.is_equal_approx(Vector3(0.5, 0, FRONT)),
		"apuntando al dintel, cuelga de él hasta el suelo")
	# Con el hueco a medio tapar no cabe; delante de una cara tapada, nada.
	_put(grid, BlockDatabase.get_block(0), Vector3i(0, 2, 0))
	check(not WoodenDoor.fit(grid, Vector3i(0, -1, 0), Vector3i.UP, Vector3(0.5, 0, 0.5), Vector3.FORWARD, DOOR_CELLS, true)["ok"],
		"en un hueco de dos no cabe")
	check(WoodenDoor.fit(grid, Vector3i(1, 2, 0), Vector3i.LEFT, Vector3(1, 2.5, 0.5), Vector3.FORWARD, DOOR_CELLS, true).is_empty(),
		"delante de un bloque no hay hueco")
	GridManager.remove_grid(grid.grid_id)

	# Un muro sobre el terreno: baja hasta el pie de la jamba, no por debajo.
	grid = _wall(0.5, false)
	fit = WoodenDoor.fit(grid, Vector3i(-1, 2, 0), Vector3i.RIGHT, Vector3(0, 1.25, 0.25), Vector3.FORWARD, DOOR_CELLS, true)
	xform = fit["transform"]
	check(fit["ok"] and xform.origin.is_equal_approx(Vector3(0.25, 0.0, FRONT * 0.5)),
		"sobre el terreno, hasta el pie del muro; en celdas de 0,5 m (%s)" % xform.origin)
	GridManager.remove_grid(grid.grid_id)

	# Una puerta de 2 × 3 en un hueco de dos: apuntando al suelo de la celda de la izquierda, por su
	# mitad derecha, no cabe con las bisagras a la derecha y las lleva a la izquierda.
	grid = _wall(1.0, true, 2)
	var wide := Vector2i(2, 3)
	fit = WoodenDoor.fit(grid, Vector3i(0, -1, 0), Vector3i.UP, Vector3(0.8, 0.0, 0.5), Vector3.FORWARD, wide, true)
	xform = fit["transform"]
	check(fit["ok"] and (xform.basis.x * fit["hinge"]).is_equal_approx(Vector3.LEFT)
		and xform.origin.is_equal_approx(Vector3(1.0, 0.0, FRONT)), "una puerta ancha cierra el hueco entero")
	fit = WoodenDoor.fit(grid, Vector3i(2, 1, 0), Vector3i.LEFT, Vector3(2.0, 1.5, 0.5), Vector3.FORWARD, wide, true)
	check(fit["ok"] and ((fit["transform"] as Transform3D).basis.x * fit["hinge"]).is_equal_approx(Vector3.RIGHT),
		"y apuntando a una jamba, las bisagras en ella")
	check(not WoodenDoor.fit(grid, Vector3i(2, 1, 0), Vector3i.LEFT, Vector3(2.0, 1.5, 0.5), Vector3.FORWARD,
		Vector2i(3, 3), true)["ok"], "más ancha que el hueco no cabe")
	GridManager.remove_grid(grid.grid_id)


## Elegirla en el menú de bloques la deja en el martillo con sus medidas.
func _check_panel() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var building := BuildingSystem.new()
	holder.add_child(building)
	var panel := DoorBuildPanel.new()
	add_child(panel)
	panel.configure(building, null)
	panel._types[1].pressed.emit()
	panel._fields[0].value = 2
	panel._fields[1].value = 3
	panel._pick()
	check(building.is_door_mode() and building.selected_placeable.id == DoorDesign.TRAPDOOR
		and building.door_design == {"width": 2, "height": 3}, "el menú deja la trampilla de 2 × 3 en el martillo")
	check(building.door_cost() == {&"wood_01": 12, &"raw_hide": 2}, "con lo que cuesta a la celda del martillo")
	building.rotate_block_x()
	check(building.door_lying and building.current_rotation_basis == Basis.IDENTITY, "el 4 la tumba")
	building.set_action_mode(BuildingSystem.ActionMode.DESTROY)
	check(building.current_action_mode == BuildingSystem.ActionMode.DESTROY, "y con ella el martillo puede quitar")
	panel.configure(building, null)
	check(panel._kind == DoorDesign.TRAPDOOR and panel._fields[0].value == 2,
		"al volver al menú sigue con la elegida")
	panel.queue_free()
	var menu := BuildMenu.new()
	add_child(menu)
	menu.setup(building)
	menu.open()
	check(menu._material_id == BuildMenu.DOORS_CATEGORY and menu._door_panel.visible and not menu._center.visible,
		"con una puerta en el martillo, el menú de bloques abre en «Puertas»")
	menu._set_material("wood")
	check(not menu._door_panel.visible and menu._center.visible, "y en un material vuelve a los bloques")
	menu.queue_free()
	holder.queue_free()


func _check_place_and_swing() -> void:
	var grid := _wall(1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Con el martillo, como en la partida: apuntando a la jamba de +X desde delante.
	var holder := Node3D.new()
	holder.position = ORIGIN + Vector3(0.5, 1.0, 3.0)
	add_child(holder)
	var building := BuildingSystem.new()
	holder.add_child(building)
	building.current_planet = _planet
	building.pick_door(DoorDesign.DOOR, {})
	var hit := _ray(ORIGIN + Vector3(0.2, 1.5, 1.6), ORIGIN + Vector3(1.4, 1.5, 0.4))
	check(not hit.is_empty() and (hit["normal"] as Vector3).is_equal_approx(Vector3.LEFT),
		"el rayo da en la cara de dentro de la jamba")
	building.process_raycast(hit["collider"], hit["normal"], hit["position"], hit)
	check(building._can_place and building.get_prop_state().get("hinge") == 1, "el martillo la encaja en el hueco")
	building.rotate_block_y()
	building.process_raycast(hit["collider"], hit["normal"], hit["position"], hit)
	check(building._can_place and is_equal_approx(building._target_prop_local.origin.z, BACK),
		"girar en Y la pasa a la otra cara del muro")
	building.rotate_block_y()
	building.process_raycast(hit["collider"], hit["normal"], hit["position"], hit)
	check(building.try_place_block(), "y la pone")
	check(not building._can_place or not building.try_place_block(), "no pone otra encima")
	holder.queue_free()
	# Lo que vale: los 22 bloques de madera del muro y lo de la puerta, también en su blueprint.
	var value := BuildCost.of_grids([grid])
	check(value == {&"wood_01": 28, &"raw_hide": 1}
		and BuildCost.of_blueprint(GridBlueprint.capture(GridManager.get_grid_group(grid.grid_id))) == value,
		"puesta y en un blueprint, cuesta lo de sus medidas (%s)" % value)

	var key: String = grid.get_all_props().keys()[0]
	var info: Dictionary = grid.get_all_props()[key]
	var anchor: StaticBody3D = info["node"]
	var door := _door_of(anchor)
	check(door != null and door.is_in_group(WoodenDoor.GROUP) and is_equal_approx(door.cell, 1.0) and door.hinge == 1,
		"puesta, se abre y lleva su estado")
	check(anchor.collision_layer == PhysicsLayers.WORLD and _box_of(anchor).size.is_equal_approx(Vector3(1, 3, DoorMesh.THICKNESS)),
		"cerrada choca con todo el hueco")
	# Otra hoja apuntando al suelo del mismo hueco no cabe.
	check(not WoodenDoor.fit(grid, Vector3i(0, -1, 0), Vector3i.UP, Vector3(0.5, 0, 0.5), Vector3.FORWARD,
		DOOR_CELLS, true)["ok"], "en un hueco con puerta no cabe otra")

	await get_tree().physics_frame
	var through := [ORIGIN + Vector3(0.5, 1.5, 2.0), ORIGIN + Vector3(0.5, 1.5, -1.5)]
	var blocked := _ray(through[0], through[1])
	check(WoodenDoor.aimed(blocked) == door, "se apunta la puerta cerrada")

	# Empujándola desde delante se abre hacia atrás, y el hueco queda libre.
	door.toggle(ORIGIN + Vector3(0.5, 1.0, 2.0))
	door._process(1.0)
	check(door.open_side == -1 and grid.get_all_props()[key]["state"].get("open") == -1,
		"se abre hacia el lado contrario y lo guarda")
	var center := anchor.position - ORIGIN
	check(absf(anchor.basis.z.dot(Vector3.RIGHT)) > 0.99 and center.x > 0.9 and center.z < 0.5,
		"abierta, la hoja gira por sus bisagras hacia atrás, por dentro del hueco (%s)" % center)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(_ray(through[0], through[1]).is_empty(), "y el hueco queda libre")
	var side_hit := _ray(ORIGIN + Vector3(0.1, 1.5, 0.2), ORIGIN + Vector3(1.5, 1.5, 0.2))
	check(WoodenDoor.aimed(side_hit) == door, "abierta se apunta (y choca) donde está")

	# Guardar y cargar: sigue abierta.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GridManager.get_save_data()))
	var id := grid.grid_id
	GridManager.restore_save_data(saved)
	await get_tree().process_frame
	grid = GridManager.get_grid(id)
	info = grid.get_all_props().values()[0]
	anchor = info["node"]
	door = _door_of(anchor)
	check(door.open_side == -1 and door.hinge == 1 and absf(anchor.basis.z.dot(Vector3.RIGHT)) > 0.99,
		"guardar y cargar la deja abierta y en su sitio")
	door.toggle(ORIGIN + Vector3(0.5, 1.0, 2.0))
	door._process(1.0)
	check(door.open_side == 0 and anchor.basis.is_equal_approx(Basis.IDENTITY)
		and (anchor.position - ORIGIN).is_equal_approx(Vector3(0.5, 1.5, FRONT)), "y se vuelve a cerrar")
	await _check_use_while_climbing(door)
	door._process(1.0)

	# En un barco: la forma del casco gira con ella.
	var dynamic: DynamicPlanetGrid = GridManager.convert_to_dynamic(grid.grid_id)[0]
	dynamic._body.set_physics_process(false)
	var shape := dynamic.get_all_props().values()[0]["node"] as CollisionShape3D
	door = _door_of(shape)
	check(shape != null and shape.get_parent() == dynamic._body and door != null and door.hinge == 1,
		"en un barco va en una forma del casco con su estado")
	door.toggle(dynamic._body.global_transform * Vector3(0.5, 1.0, -2.0))
	door._process(1.0)
	check(door.open_side == 1 and absf(shape.transform.basis.z.dot(Vector3.RIGHT)) > 0.99
		and shape.transform.origin.z > 0.5, "y empujándola desde detrás se abre hacia delante")
	GridManager.clear_all()


func _check_trapdoor() -> void:
	var grid := GridManager.create_grid_exact(_planet, ORIGIN, Basis.IDENTITY, 1.0)
	var wood := BlockDatabase.get_block(0)
	# Un techo a y = 3 con un hueco en (0, 3, 0) y, en la pared z = 2, una ventana en (0, 1, 2).
	for x in range(-1, 2):
		for z in range(-1, 2):
			if x != 0 or z != 0:
				_put(grid, wood, Vector3i(x, 3, z))
		for y in 3:
			if x != 0 or y != 1:
				_put(grid, wood, Vector3i(x, y, 2))
	var fit := WoodenDoor.fit(grid, Vector3i(1, 3, 0), Vector3i.LEFT, Vector3(1, 3.5, 0.5), Vector3(0.3, 1, 0), TRAP_CELLS, false)
	var xform: Transform3D = fit["transform"]
	check(fit["ok"] and xform.basis.z.is_equal_approx(Vector3.UP) and fit["hinge"] == 1
		and WoodenDoor.slot_cells(xform, TRAP_CELLS, 1.0) == [Vector3i(0, 3, 0)],
		"en el hueco del techo, tumbada, con las tablas arriba y las bisagras en el bloque apuntado")
	check(is_equal_approx((xform * Vector3(0, 0.5, 0)).y, 3.0 + FRONT), "a ras de arriba, para pisarla")
	fit = WoodenDoor.fit(grid, Vector3i(1, 3, 0), Vector3i.LEFT, Vector3(1, 3.5, 0.5), Vector3(0.3, 1, 0),
		TRAP_CELLS, false, true)
	check((fit["transform"] as Transform3D).basis.z.is_equal_approx(Vector3.DOWN)
		and is_equal_approx(((fit["transform"] as Transform3D) * Vector3(0, 0.5, 0)).y, 3.0 + BACK),
		"girada, a ras de abajo")
	# Apuntando al techo por debajo o al suelo de arriba, junto al borde del agujero: va en el agujero.
	for aimed: Array in [[Vector3i.DOWN, Vector3(1.15, 3.0, 0.5)], [Vector3i.UP, Vector3(1.15, 4.0, 0.5)]]:
		fit = WoodenDoor.fit(grid, Vector3i(1, 3, 0), aimed[0], aimed[1], Vector3(0, 1, 0.2), TRAP_CELLS, false)
		check(fit.get("ok", false) and fit["hinge"] == 1
			and WoodenDoor.slot_cells(fit["transform"], TRAP_CELLS, 1.0) == [Vector3i(0, 3, 0)]
			and (fit["transform"] as Transform3D).basis.z.is_equal_approx(Vector3.UP),
			"apuntando al forjado por %s junto al agujero, lo cierra tumbada" % ("abajo" if aimed[0].y < 0 else "arriba"))
	fit = WoodenDoor.fit(grid, Vector3i(1, 3, 0), Vector3i.DOWN, Vector3(1.85, 3.0, 0.5), Vector3(0, 1, 0.2), TRAP_CELLS, false)
	check(fit.is_empty() or not WoodenDoor.slot_cells(fit["transform"], TRAP_CELLS, 1.0).has(Vector3i(2, 3, 0)),
		"junto al borde de fuera del techo no hay agujero")
	# Una puerta tumbada con el 4 también va en el agujero; sin agujero cerca, no va.
	fit = WoodenDoor.fit(grid, Vector3i(1, 3, 0), Vector3i.DOWN, Vector3(1.15, 3.0, 0.5), Vector3(0, 1, 0.2),
		TRAP_CELLS, true, false, true)
	check(fit.get("ok", false) and (fit["transform"] as Transform3D).basis.z.is_equal_approx(Vector3.UP),
		"una puerta tumbada cierra el agujero del techo")
	check(WoodenDoor.fit(grid, Vector3i(-1, 3, -1), Vector3i.DOWN, Vector3(-0.5, 3.0, -0.5), Vector3(0, 1, 0.2),
		DOOR_CELLS, true, false, true).is_empty(), "tumbada, lejos de un agujero no va")
	fit = WoodenDoor.fit(grid, Vector3i(-1, 1, 2), Vector3i.RIGHT, Vector3(0, 1.5, 2.5), Vector3.FORWARD, TRAP_CELLS, false)
	xform = fit["transform"]
	check(fit["ok"] and xform.basis.z.is_equal_approx(Vector3.BACK) and xform.basis.y.is_equal_approx(Vector3.UP)
		and fit["hinge"] == -1, "en una ventana, una contraventana de pie con las bisagras en la jamba")
	fit = WoodenDoor.fit(grid, Vector3i(0, 2, 2), Vector3i.DOWN, Vector3(0.5, 2, 2.5), Vector3.FORWARD, TRAP_CELLS, false)
	xform = fit["transform"]
	check(fit["ok"] and xform.basis.z.is_equal_approx(Vector3.BACK)
		and (xform.basis.x * fit["hinge"]).is_equal_approx(Vector3.UP), "apuntando al dintel, colgada de él")
	# Sin construir gratis: ponerla con el martillo cobra lo de sus medidas y quitarla lo devuelve.
	BuildingSystem.free_build = false
	var holder := Node3D.new()
	holder.position = ORIGIN + Vector3(0.5, 1.0, 0.5)
	add_child(holder)
	var inventory := Inventory.new()
	holder.add_child(inventory)
	var building := BuildingSystem.new()
	holder.add_child(building)
	building.current_planet = _planet
	inventory.add_item(ItemCatalog.get_item(&"wood_01"), 3)
	inventory.add_item(ItemCatalog.get_item(&"raw_hide"), 1)
	building.pick_door(DoorDesign.TRAPDOOR, {})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := _ray(ORIGIN + Vector3(0.3, 2.5, 0.5), ORIGIN + Vector3(1.6, 3.8, 0.5))
	building.process_raycast(hit["collider"], hit["normal"], hit["position"], hit)
	check(building.try_place_block() and inventory.get_item_count(ItemCatalog.get_item(&"wood_01")) == 1
		and inventory.get_item_count(ItemCatalog.get_item(&"raw_hide")) == 0, "ponerla cobra 2 maderas y 1 piel")
	building.set_action_mode(BuildingSystem.ActionMode.DESTROY)
	var placed: StaticBody3D = grid.get_all_props().values()[0]["node"]
	await get_tree().physics_frame
	building.try_remove_block(_ray(ORIGIN + Vector3(0.5, 1.0, 0.5), placed.global_position))
	check(grid.get_all_props().is_empty() and inventory.get_item_count(ItemCatalog.get_item(&"wood_01")) == 3
		and inventory.get_item_count(ItemCatalog.get_item(&"raw_hide")) == 1, "y quitarla lo devuelve")
	holder.queue_free()
	BuildingSystem.free_build = true

	# Una de 2 × 1 en un hueco de 1 × 2 se pone girada.
	grid.remove_block(Vector3i(0, 3, 1))
	fit = WoodenDoor.fit(grid, Vector3i(1, 3, 0), Vector3i.LEFT, Vector3(1, 3.5, 0.5), Vector3(0.3, 1, 0),
		Vector2i(2, 1), false)
	check(fit["ok"] and fit["cells"] == Vector2i(1, 2), "una trampilla alargada se gira para caber en el hueco")
	_put(grid, wood, Vector3i(0, 3, 1))
	check(grid.place_prop(Vector3i(1, 3, 0), Vector3i.LEFT, &"wooden_trapdoor",
		WoodenDoor.fit(grid, Vector3i(1, 3, 0), Vector3i.LEFT, Vector3(1, 3.5, 0.5), Vector3(0.3, 1, 0), TRAP_CELLS, false)["transform"],
		{"hinge": 1}), "se pone en el techo")
	var anchor: StaticBody3D = grid.get_all_props().values()[0]["node"]
	var door := _door_of(anchor)
	door.toggle(ORIGIN + Vector3(0.5, 1.0, 0.5))
	door._process(1.0)
	check(door.open_side == 1 and (anchor.position - ORIGIN).y > 4.2, "desde abajo se abre hacia arriba")
	GridManager.clear_all()


## Colgado de una escala (o de una pared), USAR apuntando a [door] la abre y la cierra.
func _check_use_while_climbing(door: WoodenDoor) -> void:
	var menu := Control.new()
	add_child(menu)
	var save_button := Button.new()
	save_button.name = "btnSaveGame"
	menu.add_child(save_button)
	save_button.owner = menu
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	player.gravity_direction = Vector3.DOWN
	player.input_enabled = true
	player.free_flight_enabled = false
	player.global_position = ORIGIN + Vector3(0.5, 0.0, 2.0)
	player.capture_mouse(true)
	player.camera.current = true
	player.camera.global_position = ORIGIN + Vector3(0.5, 1.5, 2.5)
	player.camera.look_at(ORIGIN + Vector3(0.5, 1.5, -1.0))
	player.climb.mode = ClimbController.Mode.LADDER
	await get_tree().physics_frame
	var use := InputEventAction.new()
	use.action = &"action"
	use.pressed = true
	player._input(use)
	check(door.open_side != 0, "trepando, USAR abre la puerta que se apunta")
	player._input(use)
	check(door.open_side == 0, "y la vuelve a cerrar")
	player.climb.mode = ClimbController.Mode.NONE
	player.free()
	menu.free()
	GameManager.player = null


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


func _door_of(anchor: Node) -> WoodenDoor:
	for child in anchor.get_children():
		if child is WoodenDoor:
			return child
	return null


func _box_of(anchor: Node) -> BoxShape3D:
	for child in anchor.get_children():
		if child is CollisionShape3D:
			return child.shape
	return null


func _finish() -> void:
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)
