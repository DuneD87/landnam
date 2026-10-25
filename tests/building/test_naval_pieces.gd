extends Node3D

## godot --headless --path . res://tests/building/test_naval_pieces.tscn
var failures := 0
var _building: BuildingSystem
var _inventory: Inventory
var _ghost: BuildPreview
var _player: Node3D


class TestBody extends DynamicGridBody:
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_check_shells()
	_check_rotations()
	_check_interior()
	_check_water_mask()
	_setup_player()
	_check_menu()
	_check_placement()
	_check_symmetry()
	await _check_join_and_physics()
	_check_save()
	GridManager.clear_all()
	_player.queue_free()
	await get_tree().process_frame
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_shells() -> void:
	for kind in NavalPiece.NAME_KEYS.size():
		for size: Vector3i in [Vector3i(3, 2, 3), Vector3i(7, 5, 11), Vector3i(12, 4, 3), Vector3i(4, 7, 19)]:
			for profile in [NavalPiece.Profile.STRAIGHT, NavalPiece.Profile.ROUND]:
				var blocks := NavalPiece.generate(kind, size, profile)
				var symmetric := true
				var bounds := AABB()
				for cell: Vector3i in blocks:
					symmetric = symmetric and blocks.has(Vector3i(size.x - 1 - cell.x, cell.y, cell.z))
					bounds = bounds.merge(AABB(Vector3(cell), Vector3.ONE))
				check(symmetric and bounds.position == Vector3.ZERO and bounds.size == Vector3(size),
					"%s %s perfil %d: medidas exteriores exactas y ambos costados simétricos" % [NavalPiece.NAME_KEYS[kind], size, profile])
	var size := Vector3i(7, 5, 9)
	var hull := NavalPiece.generate(NavalPiece.Kind.HULL, size)
	var hollow := true
	for z in size.z:
		hollow = hollow and hull.has(Vector3i(size.x / 2, 0, z))
		for y in range(1, size.y):
			hollow = hollow and not hull.has(Vector3i(size.x / 2, y, z))
	check(hollow, "tramo redondeado: fondo de una capa, centro y extremos abiertos, sin techo")
	var curved := false
	var volume := 0.0
	for info: Dictionary in hull.values():
		curved = curved or info.has("naval_shape")
		volume += GridBase._info_volume_factor(info)
	check(curved and volume < hull.size(), "las celdas del contorno conservan la geometría y el volumen curvos")
	_check_mesh_volume(hull, volume)
	for part in [[NavalPiece.Kind.BOW, NavalPiece.Profile.STRAIGHT], [NavalPiece.Kind.BOW, NavalPiece.Profile.ROUND], [NavalPiece.Kind.STERN, NavalPiece.Profile.ROUND]]:
		var blocks := NavalPiece.generate(part[0], Vector3i(9, 6, 11), part[1])
		var part_volume := 0.0
		for info: Dictionary in blocks.values():
			part_volume += GridBase._info_volume_factor(info)
		_check_mesh_volume(blocks, part_volume)
	check(NavalPiece.generate(-1, size).is_empty(), "una pieza desconocida no genera bloques")


func _check_mesh_volume(blocks: Dictionary, expected: float) -> void:
	var mesh := ChunkMeshBuilder.build_mesh(blocks, 1.0, Transform3D.IDENTITY)
	var volume := 0.0
	var valid := true
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, vertices.size(), 3):
			var normal := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i])
			valid = valid and normal.length_squared() > 1e-12 and normal.normalized().dot(normals[i]) > 0.99
			volume += vertices[i].dot(vertices[i + 1].cross(vertices[i + 2])) / 6.0
	check(valid and absf(absf(volume) - expected) < 0.005,
		"la malla curva está cerrada, tiene normales exteriores y su volumen coincide con la masa (%s / %s)" % [absf(volume), expected])


func _check_rotations() -> void:
	var size := Vector3i(5, 3, 9)
	var original := NavalPiece.generate(NavalPiece.Kind.BOW, size)
	var valid := true
	for x in 4:
		for y in 4:
			for z in 4:
				var rotation := Basis(Vector3.RIGHT, x * PI * 0.5) * Basis(Vector3.UP, y * PI * 0.5) * Basis(Vector3.BACK, z * PI * 0.5)
				for axis in 3:
					rotation[axis] = rotation[axis].round()
				var blocks := NavalPiece.rotated(original, size, rotation)
				var mesh := ChunkMeshBuilder.build_mesh(blocks, 0.25, Transform3D.IDENTITY)
				valid = valid and blocks.size() == original.size()
				valid = valid and mesh.get_aabb().position.is_zero_approx()
				valid = valid and mesh.get_aabb().size.is_equal_approx(Vector3(NavalPiece.rotated_size(size, rotation)) * 0.25)
	check(valid, "giros XYZ: fantasma y bloques conservan medidas, esquina y número de celdas")


func _check_interior() -> void:
	for profile in [NavalPiece.Profile.STRAIGHT, NavalPiece.Profile.ROUND]:
		var ship := {}
		for part in [[NavalPiece.Kind.STERN, Vector3i(9, 6, 3), 0], [NavalPiece.Kind.HULL, Vector3i(9, 6, 8), 3], [NavalPiece.Kind.BOW, Vector3i(9, 6, 11), 11]]:
			var blocks := NavalPiece.generate(part[0], part[1], profile)
			for cell: Vector3i in blocks:
				ship[cell + Vector3i(0, 0, part[2])] = blocks[cell]
		var compartments := ShipInteriorAnalyzer.analyze([{"cells": ship.keys(), "cell_size": 0.25}])
		check(compartments.size() == 1 and compartments[0]["volume"] > 0.0,
			"popa + tramo + proa perfil %d: una bodega estanca continua bajo la borda" % profile)
		var intact_volume: float = compartments[0]["volume"] if not compartments.is_empty() else 0.0
		ship.erase(Vector3i(0, 4, 6))
		var flooded := ShipInteriorAnalyzer.analyze([{"cells": ship.keys(), "cell_size": 0.25}])
		var damaged_volume: float = flooded[0]["volume"] if not flooded.is_empty() else 0.0
		check(damaged_volume < intact_volume, "una vía de agua por debajo de la borda abre la bodega")


## La máscara del agua llega hasta la cara interior del casco curvo y no se mete en el mar del costado.
## En un casco estrecho el pantoque ocupa dos o tres celdas parciales: antes solo se tapaba la primera.
func _check_water_mask() -> void:
	var ship := {}
	for part in [[NavalPiece.Kind.STERN, Vector3i(6, 4, 3), 0], [NavalPiece.Kind.HULL, Vector3i(6, 4, 10), 3], [NavalPiece.Kind.BOW, Vector3i(6, 4, 12), 13]]:
		var blocks := NavalPiece.generate(part[0], part[1])
		for cell: Vector3i in blocks:
			ship[cell + Vector3i(0, 0, part[2])] = blocks[cell]
	var cells: Array = ship.keys()
	var full: Array[bool] = []
	var shapes: Array = []
	for cell: Vector3i in cells:
		var info: Dictionary = ship[cell]
		full.append(ChunkMeshBuilder._is_solid(info["block_id"]))
		shapes.append(info if info.has("naval_shape") else null)
	var boxes := []
	for comp: Dictionary in ShipInteriorAnalyzer.analyze([{"cells": cells, "full": full, "shapes": shapes, "cell_size": 1.0}]):
		boxes.append_array(comp["boxes"])
	# Sección por la mitad del tramo: cruces de cada fila con las caras reales del casco.
	var z := 8.5
	var hold := 0
	var dry := 0
	var sea := 0
	var masked_sea := 0
	for row in 30:
		var y := 1.03 + row * 0.1
		var crossings: Array[float] = []
		for cell: Vector3i in ship:
			if cell.y != floori(y) or cell.z != floori(z):
				continue
			var info: Dictionary = ship[cell]
			for face: BlockBoolean.Face in BlockBoolean.from_block(info, 1.0, Vector3(cell)):
				var polygon := PackedVector2Array()
				for point in face.points:
					polygon.append(Vector2(point.y, point.z))
				if absf(face.normal.x) > 0.000001 and Geometry2D.is_point_in_polygon(Vector2(y, z), polygon):
					crossings.append((face.distance - face.normal.y * y - face.normal.z * z) / face.normal.x)
		crossings.sort()
		if crossings.size() < 2:
			continue
		for i in 160:
			var point := Vector3(-1.0 + i * 0.05 + 0.0013, y, z)
			var before := 0
			for cross in crossings:
				if cross < point.x:
					before += 1
			if point.x < crossings[0] or point.x > crossings[-1]:
				sea += 1
				masked_sea += int(_in_mask(point, boxes))
			elif before % 2 == 0:
				hold += 1
				dry += int(_in_mask(point, boxes))
	check(hold > 0 and dry == hold, "la máscara del agua tapa la bodega hasta el casco curvo (%d de %d)" % [dry, hold])
	check(sea > 0 and masked_sea == 0, "la máscara del agua no recorta el mar junto al costado")


func _in_mask(point: Vector3, boxes: Array) -> bool:
	for box: Dictionary in boxes:
		var d: Vector3 = (point - (box["pos"] as Vector3)).abs()
		var half: Vector3 = box["half"]
		if d.x < half.x and d.y < half.y and d.z < half.z:
			return true
	return false


func _setup_player() -> void:
	_player = Node3D.new()
	add_child(_player)
	_inventory = Inventory.new(100)
	_player.add_child(_inventory)
	_ghost = BuildPreview.new()
	_player.add_child(_ghost)
	_building = BuildingSystem.new()
	_building.current_planet = self
	_player.add_child(_building)
	_building.build_mode = true
	_building.set_cell_size_index(0)


func _check_menu() -> void:
	var menu := BuildMenu.new()
	add_child(menu)
	menu.setup(_building, _inventory)
	menu.open()
	menu._set_material(BuildMenu.NAVAL_CATEGORY)
	check(menu._naval_panel.visible and not menu._center.visible and not menu._detail_box.visible,
		"B → Naval abre el editor con vista 3D")
	var panel := menu._naval_panel
	panel._dimensions[0].value = 2.25
	panel._dimensions[1].value = 1.0
	panel._dimensions[2].value = 3.25
	panel._pick()
	check(_building.is_naval_mode() and _building.naval_size == Vector3i(9, 4, 13) and not menu.visible,
		"las tres medidas independientes pasan al martillo al confirmar")
	check(_ghost._ghost_mesh_instance.mesh.get_aabb().size == Vector3(9, 4, 13),
		"el fantasma contiene la proa entera")
	menu.open()
	check(menu._naval_panel.visible, "B vuelve a las medidas de la pieza naval activa")
	menu._cell_buttons[1].pressed.emit()
	check(is_equal_approx(panel._dimensions[0].value, 4.5), "el tamaño del bloque cambia medidas y grosor juntos")
	_building.set_cell_size_index(0)
	menu._set_material("wood")
	var cube := BlockDatabase.get_block_material_item(0, "wood")
	menu._pick(cube)
	check(not _building.is_naval_mode(), "elegir un bloque normal sale del modo naval")
	_building.pick_naval_piece(NavalPiece.Kind.BOW, Vector3i(9, 4, 13))
	_building.select_placeable(ItemCatalog.get_item(&"torch_placeable_01"))
	_building.select_placeable(null)
	check(not _building.is_naval_mode() and _ghost._ghost_mesh_instance.mesh == BlockDatabase.get_block(0).for_material("wood").mesh,
		"alternar entre naval, colocable y martillo restaura el fantasma del bloque normal")
	menu.queue_free()


func _target(grid: GridBase, cell: Vector3i) -> void:
	_building._target_grid = grid
	_building._cached_grid_for_placement = grid
	_building._hit_grid_for_alignment = null
	_building._target_grid_pos = cell
	_building._target_world_pos = grid.grid_to_world(cell) if grid else Vector3(0, 30, 0)
	_building._target_basis = Basis.IDENTITY
	_building._can_place = true
	_building._has_target = true


func _check_placement() -> void:
	var wood := ItemCatalog.get_item(&"wood_01")
	_building.pick_naval_piece(NavalPiece.Kind.HULL, Vector3i(5, 4, 6))
	_target(null, Vector3i.ZERO)
	var count := _building.get_naval_blocks().size()
	_inventory.add_item(wood, count - 1)
	check(not _building.try_place_block() and GridManager.get_grids_for_planet(self).is_empty(),
		"sin material para toda la pieza no paga ni coloca una parte")
	_inventory.add_item(wood, 1)
	check(_building.try_place_block(), "coloca el tramo completo con el material justo")
	var grid: GridBase = GridManager.get_grids_for_planet(self)[0]
	check(grid.get_block_count() == count and _inventory.get_item_count(wood) == 0,
		"el coste coincide exactamente con los bloques construidos")
	var volume := 0.0
	for info: Dictionary in grid.get_all_blocks().values():
		volume += GridBase._info_volume_factor(info) * pow(0.25, 3)
	check(is_equal_approx(grid.get_total_volume(), volume) and volume < count * pow(0.25, 3), "masa y volumen cuentan el contorno real de la madera")
	_target(grid, Vector3i.ZERO)
	_inventory.add_item(wood, count)
	check(not _building.try_place_block() and _inventory.get_item_count(wood) == count,
		"el clic revalida el solapamiento sin gastar material")
	var removed_cell: Vector3i = grid.get_all_blocks().keys()[0]
	var removed := grid.remove_block(removed_cell)
	_building._refund_block(removed, grid.cell_size)
	check(_inventory.get_item_count(wood) == count + 1, "desmontar recupera la madera por bloque")
	var cube := BlockDatabase.get_block(0)
	grid.place_block(removed_cell, BlockDatabase.get_block(int(removed["block_id"])), Basis.IDENTITY,
		Transform3D(Basis.IDENTITY, grid.grid_to_world(removed_cell)), "wood", removed)
	# Una celda de 0,25 m escondida dentro de un bloque de 0,5 m también cuenta como choque.
	var finer := GridManager.create_grid_aligned(self, grid, 0.125)
	finer.place_block(Vector3i(1, 0, 13), cube, Basis.IDENTITY,
		Transform3D(Basis.IDENTITY, finer.grid_to_world(Vector3i(1, 0, 13))), "wood")
	_target(grid, Vector3i(0, 0, 6))
	check(not _building.naval_has_space(_building.get_naval_plan(), grid), "se detectan obstáculos en otras grids de menor celda")
	GridManager.remove_grid_group(finer.grid_id)


func _check_join_and_physics() -> void:
	# La comprobación anterior retira el grupo completo. Se crea un tramo limpio.
	var grid := GridManager.create_grid_exact(self, Vector3(0, 30, 0), Basis.IDENTITY, 0.25)
	BuildingSystem.free_build = true
	_building.pick_naval_piece(NavalPiece.Kind.HULL, Vector3i(7, 5, 8))
	_target(grid, Vector3i.ZERO)
	_building.try_place_block()
	_building.pick_naval_piece(NavalPiece.Kind.BOW, Vector3i(7, 5, 9))
	_building._target_grid = grid
	_building._target_grid_pos = Vector3i(6, 3, 8)
	_building._target_world_pos = grid.grid_to_world(_building._target_grid_pos)
	_building._target_basis = Basis.IDENTITY
	_building._align_naval_target(grid, Vector3i(6, 3, 7), Vector3i.BACK)
	check(_building._target_grid_pos == Vector3i(0, 0, 8), "apuntar al costado del extremo alinea fondo y ancho de la proa")
	_target(grid, _building._target_grid_pos)
	check(_building.try_place_block(), "proa y tramo encajan sin solapar ni cerrar el paso interior")
	_building.pick_naval_piece(NavalPiece.Kind.STERN, Vector3i(7, 5, 3))
	_target(grid, Vector3i(0, 0, -1))
	_building._align_naval_target(grid, Vector3i.ZERO, Vector3i.FORWARD)
	check(_building._target_grid_pos.z == -3, "construir hacia -Z deja toda la popa fuera del tramo")
	_target(grid, _building._target_grid_pos)
	check(_building.try_place_block(), "la popa cierra el otro extremo")
	BuildingSystem.free_build = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var origin := grid.get_origin_world()
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3(0.875, 4, 1), origin + Vector3(0.875, -1, 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and absf(hit.position.y - (origin.y + 0.25)) < 0.01,
		"el interior es transitable: el rayo alcanza el fondo de un bloque, sin techo invisible")
	query = PhysicsRayQueryParameters3D.create(origin + Vector3(-2, 0.15, 1), origin + Vector3(0.875, 0.15, 1))
	hit = get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.position.x - origin.x > 0.20 and hit.position.x - origin.x < 0.30,
		"la colisión sigue la unión redondeada entre fondo y costado")
	var body := TestBody.new()
	add_child(body)
	body.global_transform = grid.get_grid_world_transform()
	body.set_meta("grid_id", "naval_test")
	var dyn := DynamicPlanetGrid.new()
	dyn.setup_from_static_shared("naval_dynamic", self, grid, body)
	body.update_mass_from_grids()
	check(is_equal_approx(body.mass, dyn.get_total_volume() * DynamicGridBody.BLOCK_DENSITY),
		"el casco dinámico conserva la masa real de los bloques")
	body._recalculate_buoyancy_boxes()
	var displaced := 0.0
	for volume: float in body._box_vol:
		displaced += volume
	check(is_equal_approx(displaced, dyn.get_total_volume()), "la flotación utiliza el volumen de la cáscara curva")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(dyn.serialize()))
	var restored_body := TestBody.new()
	add_child(restored_body)
	restored_body.global_transform = body.global_transform
	restored_body.set_meta("grid_id", "curved_restored")
	var restored := DynamicPlanetGrid.new()
	restored.deserialize("curved_restored", self, saved, restored_body)
	check(is_equal_approx(restored.get_total_volume(), dyn.get_total_volume()) and _curved_cells(restored) == _curved_cells(dyn),
		"guardar y cargar una dinámica conserva las caras curvas y su volumen")
	restored.clear()
	restored_body.queue_free()
	var compartments := ShipInteriorAnalyzer.analyze([{"cells": dyn.get_all_blocks().keys(), "cell_size": dyn.cell_size}])
	check(compartments.size() == 1, "convertir en dinámico conserva la bodega estanca")
	# Se vuelve a una estática con un blueprint para comprobar también el ciclo de guardado.
	var data := GridBlueprint.capture([dyn])
	dyn.clear()
	body.queue_free()
	GridBlueprint.instantiate(data, self, Vector3(20, 30, 0), Basis.IDENTITY, true)


func _check_symmetry() -> void:
	var grid := GridManager.create_grid_exact(self, Vector3(0, 50, 0), Basis.IDENTITY, 0.25)
	_building.pick_naval_piece(NavalPiece.Kind.HULL, Vector3i(5, 3, 5))
	_building._mirror_active = true
	_building.mirror_grid = grid
	_building.mirror_axis = BuildingSystem.MirrorAxis.X
	_building.mirror_center_world = grid.get_origin_world() + Vector3(2.5, 0.5, 0.5) * grid.cell_size
	_target(grid, Vector3i.ZERO)
	var plan := _building.get_naval_plan()
	var symmetric := true
	for cell: Vector3i in plan:
		symmetric = symmetric and plan.has(Vector3i(4 - cell.x, cell.y, cell.z))
	check(symmetric and not plan.is_empty() and plan.size() == _building.get_naval_blocks().size(),
		"la simetría refleja el módulo completo y cuenta una sola vez las celdas compartidas")
	var wood := ItemCatalog.get_item(&"wood_01")
	_inventory.clear()
	_inventory.add_item(wood, plan.size())
	check(_building.try_place_block() and _inventory.get_item_count(wood) == 0 and grid.get_block_count() == plan.size(),
		"la colocación simétrica paga exactamente el plan visible")
	_target(grid, Vector3i.ZERO)
	_building.mirror_center_world = grid.get_origin_world() + Vector3.ONE * grid.cell_size * 0.5
	check(_building.get_naval_plan().is_empty(), "la simetría rechaza recortes diferentes que se pisan dentro de una misma celda")
	_building._mirror_active = false
	_building.mirror_axis = BuildingSystem.MirrorAxis.NONE
	_building.mirror_grid = null
	GridManager.remove_grid_group(grid.grid_id)


func _check_save() -> void:
	var grids := GridManager.get_grids_for_planet(self)
	var grid: GridBase
	for candidate: GridBase in grids:
		if candidate.get_block_count() > 0:
			grid = candidate
	if not grid:
		check(false, "hay un casco reconstruido para guardar")
		return
	var data := GridBlueprint.capture([grid])
	var restored: Dictionary = JSON.parse_string(JSON.stringify(data))
	var clone := GridBlueprint.instantiate(restored, self, Vector3(40, 30, 0), Basis.IDENTITY, true)
	check(clone.size() == 1 and clone[0].get_block_count() == grid.get_block_count(),
		"blueprint → JSON → reconstrucción conserva todas las piezas sin un formato especial")
	check(BuildCost.of_blueprint(restored).get(&"wood_01", 0) == grid.get_block_count(),
		"el blueprint cobra la misma madera que la construcción")
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(grid.serialize()))
	var loaded := PlanetGrid.new()
	loaded.deserialize("curved_static_save", self, serialized)
	check(is_equal_approx(loaded.get_total_volume(), grid.get_total_volume()) and _curved_cells(loaded) == _curved_cells(grid),
		"guardar y cargar una estática conserva todas las celdas curvas")
	loaded.clear()


func _curved_cells(grid: GridBase) -> int:
	var count := 0
	for info: Dictionary in grid.get_all_blocks().values():
		if info.has("naval_shape") and info["node"] != null:
			count += 1
	return count
