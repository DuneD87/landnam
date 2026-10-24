extends Node3D

## godot --headless --path . res://tests/building/test_thatch_roof.tscn
const Preview = preload("res://tests/building/thatch_roof_preview.gd")
var failures := 0
var _grids: Array[GridBase] = []


## Se prueba la conversión y sus formas reales sin arrancar gravedad ni flotación de un planeta.
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
	_check_catalog_and_menu()
	_check_geometry()
	_check_gable_fit()
	_check_panels_against_solids()
	_check_costs()
	await _check_collisions()
	await _check_gable_panels()
	_check_dynamic_conversion()
	_check_save_and_blueprint()
	for grid in _grids:
		grid.clear()
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_catalog_and_menu() -> void:
	var thatch := BlockDatabase.get_material_by_id("thatch")
	check(thatch != null and thatch.item == ItemCatalog.get_item(&"plant_fiber"),
		"la paja se construye con la fibra vegetal existente")
	check(thatch.surface_material is ORMMaterial3D and thatch.surface_material.normal_enabled,
		"el material carga sus mapas de color y relieve")
	var groups := BlockDatabase.get_block_items_by_material()
	check(groups["thatch"]["items"].size() == 2, "Paja ofrece faldón y cumbrera")
	for id in ["stone", "glass"]:
		check(groups[id]["items"].size() == 6, "%s conserva sus seis formas" % id)
	check(groups["wood"]["items"].size() == 7, "Madera ofrece también el panel triangular")
	var triangle := BlockDatabase.get_block_material_item(BlockDatabase.BLOCK_PANE_TRIANGLE_ID, "wood")
	check(triangle != null and triangle.get_display_name() != triangle.display_name,
		"el panel triangular de madera tiene nombre traducido")
	var player := Node3D.new()
	add_child(player)
	var inventory := Inventory.new()
	player.add_child(inventory)
	var ghost := BuildPreview.new()
	player.add_child(ghost)
	var building := BuildingSystem.new()
	player.add_child(building)
	var menu := BuildMenu.new()
	add_child(menu)
	menu.setup(building, inventory)
	menu.open()
	menu._set_material("thatch")
	check(menu._tile_buttons.size() == 2, "el menú del martillo muestra las dos piezas de paja")
	for item: ItemData in groups["thatch"]["items"]:
		building.pick_block(item)
		check(building.get_selected_block_item() == item and building.get_selected_block().can_rotate,
			"el martillo selecciona y permite girar " + item.get_display_name())
		check(item.get_display_name() != item.display_name, "el nombre del tejado está traducido")
	menu._set_material("wood")
	check(menu._tile_buttons.has(triangle), "el triángulo aparece bajo Madera en el menú")
	(menu._tile_buttons[triangle] as Button).pressed.emit()
	check(building.get_selected_block_item() == triangle, "elegir el triángulo lo pone en el martillo")
	menu.close()
	menu.queue_free()
	player.queue_free()


func _check_geometry() -> void:
	for id in [BlockDatabase.BLOCK_THATCH_SLOPE_ID, BlockDatabase.BLOCK_THATCH_RIDGE_ID, BlockDatabase.BLOCK_PANE_TRIANGLE_ID]:
		var block := BlockDatabase.get_block(id)
		var icon := block.mesh.surface_get_arrays(0)
		var blocks := {Vector3i.ZERO: {"block_id": id, "material_id": "wood" if id == BlockDatabase.BLOCK_PANE_TRIANGLE_ID else "thatch"}}
		var mesh := ChunkMeshBuilder.build_mesh(blocks, 1.0, Transform3D.IDENTITY)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var same_shape := vertices.size() == (icon[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var volume := 0.0
		var normals_ok := true
		for i in vertices.size():
			same_shape = same_shape and vertices[i].is_equal_approx(icon[Mesh.ARRAY_VERTEX][i] + Vector3(0.5, 0, 0.5))
		for i in range(0, vertices.size(), 3):
			var a := vertices[i]
			var b := vertices[i + 1]
			var c := vertices[i + 2]
			var outward := (c - a).cross(b - a)
			normals_ok = normals_ok and outward.length_squared() > 1e-10 and outward.normalized().dot(normals[i]) > 0.99
			volume += a.dot(b.cross(c)) / 6.0
		check(same_shape, "%s: el fantasma y la pieza construida tienen la misma forma" % block.block_name)
		check(normals_ok, "%s: caras sin degenerados y normales hacia fuera" % block.block_name)
		check(is_equal_approx(absf(volume), GridBase._block_volume_factor(id)),
			"%s: la masa usa el volumen de la geometría cerrada" % block.block_name)
		blocks[Vector3i.ZERO]["mirrored"] = true
		blocks[Vector3i.ZERO]["mirror_axis"] = 2
		var mirrored := ChunkMeshBuilder.build_mesh(blocks, 1.0, Transform3D.IDENTITY)
		check(mirrored.get_aabb().size.is_equal_approx(mesh.get_aabb().size),
			"%s: el espejo conserva grosor y dimensiones" % block.block_name)


## Regresión del encaje real: plano exterior, continuidad de UV y altura de la madera
## frente a la cara inferior de la malla de paja, además del cierre físico del hueco.
func _check_gable_fit() -> void:
	var blocks := GridBlueprint.blocks_dict(Preview.cabin_blueprint()["grids"][0])
	var roof := {}
	for cell: Vector3i in blocks:
		if blocks[cell]["material_id"] == "thatch":
			roof[cell] = blocks[cell]
	var roof_arrays := ChunkMeshBuilder.build_mesh(roof, 1.0, Transform3D.IDENTITY).surface_get_arrays(0)
	var coplanar := true
	var fit := true
	var seams := true
	for x in [0, 6]:
		var normal := Vector3.LEFT if x == 0 else Vector3.RIGHT
		var wall_x := 1.0 if x == 0 else 6.0
		for cell: Vector3i in blocks:
			if cell.x != x or blocks[cell]["material_id"] != "wood":
				continue
			var arrays := _block_arrays(cell, blocks[cell])
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in vertices.size():
				if normals[i].dot(normal) < 0.999:
					continue
				var p := vertices[i]
				coplanar = coplanar and absf(p.x - wall_x) < 0.0001
				var bottom := _roof_bottom(roof_arrays, Vector3(wall_x - normal.x * 0.01, 0, p.z))
				fit = fit and is_finite(bottom) and p.y <= bottom + 0.0001
		for z in [1, 2]:
			var panel := Vector3i(x, 3, z)
			var wall := Vector3i(1 if x == 0 else 5, 2, z)
			var point := Vector3(wall_x, 3, z + 0.5)
			var panel_uv := _face_uv(_block_arrays(panel, blocks[panel]), point, normal)
			var wall_uv := _face_uv(_block_arrays(wall, blocks[wall]), point, normal)
			seams = seams and panel_uv.is_finite() and wall_uv.is_finite() and panel_uv.is_equal_approx(wall_uv)
		var point := Vector3(wall_x, 3.5, 2)
		var a := _face_uv(_block_arrays(Vector3i(x, 3, 1), blocks[Vector3i(x, 3, 1)]), point, normal)
		var b := _face_uv(_block_arrays(Vector3i(x, 3, 2), blocks[Vector3i(x, 3, 2)]), point, normal)
		seams = seams and a.is_finite() and b.is_finite() and a.is_equal_approx(b)
	check(coplanar, "triángulos y paneles cuadrados continúan exactamente el plano de las paredes")
	check(seams, "la textura de madera continúa sin saltos entre muros, paneles y triángulos")
	check(fit, "la madera termina bajo la cara inferior del tejado sin atravesar la paja")
	var pane := BlockDatabase.get_block(BlockDatabase.BLOCK_PANE_ID)
	check(pane.for_material("wood").mesh != pane.mesh and pane.for_material("glass") == pane,
		"el ajuste del panel de madera conserva la geometría de las ventanas de cristal")


func _check_panels_against_solids() -> void:
	for id in [BlockDatabase.BLOCK_PANE_ID, BlockDatabase.BLOCK_PANE_TRIANGLE_ID]:
		var blocks := {
			Vector3i(0, 0, -1): {"block_id": BlockDatabase.BLOCK_CUBE_ID, "material_id": "stone"},
			Vector3i.ZERO: {"block_id": id, "material_id": "wood"},
		}
		var mesh := ChunkMeshBuilder.build_mesh(blocks, 1.0, Transform3D.IDENTITY)
		var outer_planes := {}
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in vertices.size():
				if normals[i].z > 0.999:
					outer_planes[roundi(vertices[i].z * 10000)] = true
		check(outer_planes.has(0) and outer_planes.has(roundi(BlockMeshGenerator.PANE_INSET * 10000)),
			"panel %d: la cara de madera no es coplanar con el cubo sobre el que se coloca" % id)


func _block_arrays(cell: Vector3i, info: Dictionary) -> Array:
	return ChunkMeshBuilder.build_mesh({cell: info}, 1.0, Transform3D.IDENTITY).surface_get_arrays(0)


func _roof_bottom(arrays: Array, point: Vector3) -> float:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bottom := INF
	for i in range(0, vertices.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(point + Vector3.UP * 10, point + Vector3.DOWN,
			vertices[i], vertices[i + 1], vertices[i + 2])
		if hit is Vector3:
			bottom = minf(bottom, hit.y)
	return bottom


func _face_uv(arrays: Array, point: Vector3, normal: Vector3) -> Vector2:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in range(0, vertices.size(), 3):
		if normals[i].dot(normal) < 0.999 or absf((point - vertices[i]).dot(normal)) > 0.0001:
			continue
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		var cross := (b - a).cross(c - a)
		var wa := (b - point).cross(c - point).dot(cross) / cross.length_squared()
		var wb := (c - point).cross(a - point).dot(cross) / cross.length_squared()
		var wc := 1.0 - wa - wb
		if minf(wa, minf(wb, wc)) >= -0.0001:
			return uvs[i] * wa + uvs[i + 1] * wb + uvs[i + 2] * wc
	return Vector2(INF, INF)


func _check_costs() -> void:
	var player := Node3D.new()
	add_child(player)
	var inventory := Inventory.new()
	player.add_child(inventory)
	player.add_child(BuildPreview.new())
	var building := BuildingSystem.new()
	player.add_child(building)
	building.set_material_by_id("thatch")
	var fiber := ItemCatalog.get_item(&"plant_fiber")
	var block := BlockDatabase.get_block(BlockDatabase.BLOCK_THATCH_SLOPE_ID)
	for size in BuildingSystem.CELL_SIZES:
		inventory.clear()
		building.cell_size = size
		var cost := BlockDatabase.get_material_by_id("thatch").get_cost_for_size(size)
		inventory.add_item(fiber, cost - 1)
		check(not building._consume_block_cost(block) and inventory.get_item_count(fiber) == cost - 1,
			"%.2f m: si falta fibra no se consume nada" % size)
		inventory.add_item(fiber, 1)
		check(building._consume_block_cost(block) and inventory.get_item_count(fiber) == 0,
			"%.2f m: se paga el coste exacto" % size)
		building._refund_block({"material_id": "thatch", "hp": 0.5}, size)
		check(inventory.get_item_count(fiber) == ceili(cost * 0.5),
			"%.2f m: desmontar devuelve la fibra según la vida" % size)
	player.queue_free()


func _make_grid(origin: Vector3, size: float = 1.0) -> PlanetGrid:
	var grid := PlanetGrid.new()
	grid.setup(GridManager.generate_grid_id(), self, origin, Basis.IDENTITY, size)
	grid.mesh_materials["thatch"] = BlockDatabase.get_material_by_id("thatch").surface_material
	_grids.append(grid)
	return grid


func _check_collisions() -> void:
	var cases := []
	for size in BuildingSystem.CELL_SIZES:
		for id in [BlockDatabase.BLOCK_THATCH_SLOPE_ID, BlockDatabase.BLOCK_THATCH_RIDGE_ID]:
			for rotation in [Basis.IDENTITY, Basis(Vector3.UP, PI * 0.5), Basis(Vector3.RIGHT, PI * 0.5)]:
				for axis in [-1, 0, 1, 2]:
					var grid := _make_grid(Vector3(cases.size() * 8, 0, 0), size)
					grid.place_block(Vector3i.ZERO, BlockDatabase.get_block(id), rotation,
						Transform3D(rotation, grid.origin_local), "thatch", {"mirrored": axis >= 0, "mirror_axis": axis})
					cases.append([grid, rotation, id, axis])
	var joined := _make_grid(Vector3(0, 0, 60))
	for x in 2:
		for z in 5:
			var pos := Vector3i(x, mini(z, 4 - z), z)
			var id := BlockDatabase.BLOCK_THATCH_RIDGE_ID if z == 2 else BlockDatabase.BLOCK_THATCH_SLOPE_ID
			var rot := Basis(Vector3.UP, PI) if z > 2 else Basis.IDENTITY
			joined.place_block(pos, BlockDatabase.get_block(id), rot,
				Transform3D(rot, joined.grid_to_world(pos)), "thatch")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hits := 0
	var hollow := true
	var aligned := true
	for entry: Array in cases:
		var grid: PlanetGrid = entry[0]
		var rot: Basis = entry[1]
		var reflection := Vector3.ONE
		if entry[3] >= 0:
			reflection[entry[3]] = -1.0
		var center := grid.origin_local + Vector3.ONE * grid.cell_size * 0.5
		var offset := Vector3(0, 0, 0.3)
		var query := PhysicsRayQueryParameters3D.create(center + rot * ((offset + Vector3.UP * 2) * reflection) * grid.cell_size,
			center + rot * ((offset + Vector3.DOWN * 2) * reflection) * grid.cell_size)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider.get_meta("grid_id", "") == grid.grid_id:
			hits += 1
			var local_hit: Vector3 = (rot.inverse() * (hit.position - center) / grid.cell_size) * reflection + Vector3.ONE * 0.5
			var expected_y := (0.8 if entry[2] == BlockDatabase.BLOCK_THATCH_SLOPE_ID else 0.31) + ThatchRoofMesh.THICKNESS
			aligned = aligned and absf(local_hit.y - expected_y) < 0.06
		if entry[2] == BlockDatabase.BLOCK_THATCH_SLOPE_ID:
			var local := Vector3(0, -0.45, 0.3) * grid.cell_size
			query = PhysicsRayQueryParameters3D.create(center + rot * ((local + Vector3.LEFT * grid.cell_size) * reflection),
				center + rot * ((local + Vector3.RIGHT * grid.cell_size) * reflection))
			hollow = hollow and get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	check(hits == cases.size(), "colisión en cuatro tamaños y tres orientaciones con los tres espejos (%d/%d)" % [hits, cases.size()])
	check(aligned, "la superficie física coincide con el tejado también al reflejarlo")
	check(hollow, "el faldón deja libre el espacio interior bajo la pendiente")
	var sealed := true
	for x in [0.5, 0.9999, 1.0001]:
		for z in [0.9999, 1.0001, 1.9999, 2.0001, 2.9999, 3.0001, 3.9999, 4.0001]:
			var point := joined.origin_local + Vector3(x, 0, z)
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 5, point + Vector3.DOWN)
			sealed = sealed and not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	check(sealed, "sin huecos en las juntas laterales y entre faldones y cumbrera")


## Rayos desde ambos extremos: el cerramiento de madera debe interceptarlos antes de entrar
## en el hueco. Un triángulo aislado debe dejar pasar el rayo por la mitad que falta.
func _check_gable_panels() -> void:
	var cabin := _make_grid(Vector3(0, 0, 100))
	var data := Preview.cabin_blueprint()["grids"][0] as Dictionary
	GridBlueprint._restore_materials(cabin, data)
	GridBlueprint._restore_blocks(cabin, GridBlueprint.blocks_dict(data))
	var cases := []
	for size in BuildingSystem.CELL_SIZES:
		for rot in [Basis.IDENTITY, Basis(Vector3.UP, PI * 0.5)]:
			for mirrored in [false, true]:
				var grid := _make_grid(Vector3(20 + cases.size() * 8, 0, 100), size)
				grid.mesh_materials["wood"] = BlockDatabase.get_material_by_id("wood").surface_material
				grid.place_block(Vector3i.ZERO, BlockDatabase.get_block(BlockDatabase.BLOCK_PANE_TRIANGLE_ID),
					rot, Transform3D(rot, grid.origin_local), "wood", {"mirrored": mirrored, "mirror_axis": 0})
				cases.append([grid, rot, mirrored])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var closed := true
	for z in [1.25, 1.5, 1.75, 2.25, 2.5, 2.75, 3.25, 3.5, 3.75, 4.25, 4.5, 4.75, 5.25, 5.5, 5.75]:
		var roof_y: float = 2.0 + z if z < 3 else (9.0 - z if z > 4 else 5.0)
		var y := 3.02
		while y < roof_y - 0.2:
			for x in [-1.0, 8.0]:
				var query := PhysicsRayQueryParameters3D.create(cabin.origin_local + Vector3(x, y, z),
					cabin.origin_local + Vector3(3.5, y, z))
				var hit := get_world_3d().direct_space_state.intersect_ray(query)
				closed = closed and not hit.is_empty() and hit.collider.get_meta("block_id", -1) in [BlockDatabase.BLOCK_PANE_ID, BlockDatabase.BLOCK_PANE_TRIANGLE_ID]
			y += 0.2
	check(closed, "ambos frontones quedan cerrados con madera hasta la cumbrera")
	var triangular := true
	for entry: Array in cases:
		var grid: PlanetGrid = entry[0]
		var rot: Basis = entry[1]
		var reflection := Vector3(-1, 1, 1) if entry[2] else Vector3.ONE
		var center := grid.origin_local + Vector3.ONE * grid.cell_size * 0.5
		for xy in [0.2, 0.8]:
			var local := Vector3(xy - 0.5, xy - 0.5, 0)
			var query := PhysicsRayQueryParameters3D.create(center + rot * ((local + Vector3.BACK * 2) * reflection) * grid.cell_size,
				center + rot * ((local + Vector3.FORWARD * 2) * reflection) * grid.cell_size)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			triangular = triangular and (hit.is_empty() if xy > 0.5 else not hit.is_empty())
	check(triangular, "la colisión conserva la mitad triangular en todos los tamaños con giro y espejo")


func _check_dynamic_conversion() -> void:
	var stable := true
	var persisted := true
	var cases := 0
	for mode in ["primary", "shared", "collapse"]:
		for size in BuildingSystem.CELL_SIZES:
			for id in [BlockDatabase.BLOCK_THATCH_SLOPE_ID, BlockDatabase.BLOCK_THATCH_RIDGE_ID,
				BlockDatabase.BLOCK_PANE_TRIANGLE_ID, BlockDatabase.BLOCK_PANE_ID]:
				for mirrored in [false, true]:
					var source := _make_grid(Vector3(cases * 8, 0, 140), size)
					var mat_id := "wood" if id in [BlockDatabase.BLOCK_PANE_TRIANGLE_ID, BlockDatabase.BLOCK_PANE_ID] else "thatch"
					var rot := Basis(Vector3.UP, PI * 0.5)
					source.place_block(Vector3i.ZERO, BlockDatabase.get_block(id), rot,
						Transform3D(rot, source.origin_local), mat_id, {"mirrored": mirrored, "mirror_axis": 2})
					var before := _collision_points(source.get_all_blocks()[Vector3i.ZERO]["node"])
					var body := TestBody.new()
					body.freeze = true
					body.set_meta("grid_id", GridManager.generate_grid_id())
					add_child(body)
					body.global_transform = source.get_grid_world_transform()
					var dynamic := DynamicPlanetGrid.new()
					dynamic.grid_id = GridManager.generate_grid_id()
					dynamic.planet_node = self
					dynamic.cell_size = size
					dynamic.mesh_materials = source.mesh_materials.duplicate()
					dynamic._body = body
					if mode == "collapse":
						GridManager._migrate_cell_to_dynamic(source, dynamic, body, Vector3i.ZERO)
					elif mode == "primary":
						GridManager._migrate_blocks_to_dynamic(dynamic, source, body)
					else:
						dynamic.setup_from_static_shared(GridManager.generate_grid_id(), self, source, body)
					var after := _collision_points(dynamic.get_all_blocks()[Vector3i.ZERO]["node"])
					stable = stable and before.size() == after.size()
					for i in mini(before.size(), after.size()):
						stable = stable and before[i].distance_to(after[i]) < 0.0001
					var saved: Dictionary = JSON.parse_string(JSON.stringify(dynamic.serialize()))
					var loaded_body := TestBody.new()
					loaded_body.freeze = true
					add_child(loaded_body)
					loaded_body.global_transform = body.global_transform
					var loaded := DynamicPlanetGrid.new()
					loaded.deserialize(GridManager.generate_grid_id(), self, saved, loaded_body)
					var restored := _collision_points(loaded.get_all_blocks()[Vector3i.ZERO]["node"])
					persisted = persisted and before.size() == restored.size()
					for i in mini(before.size(), restored.size()):
						persisted = persisted and before[i].distance_to(restored[i]) < 0.0001
					loaded.clear()
					loaded_body.queue_free()
					dynamic.clear()
					body.queue_free()
					cases += 1
	check(stable, "conversión y derrumbe conservan colisiones, material, giro y espejo en los cuatro tamaños (%d casos)" % cases)
	check(persisted, "guardar y cargar dinámicas conserva tamaño y posición de las formas sin duplicar la escala (%d casos)" % cases)


func _collision_points(node: Node3D) -> PackedVector3Array:
	var collider := node as CollisionShape3D
	if collider == null:
		collider = node.get_child(0) as CollisionShape3D
	var points: PackedVector3Array = (collider.shape as ConvexPolygonShape3D).points
	for i in points.size():
		points[i] = collider.global_transform * points[i]
	return points


func _check_save_and_blueprint() -> void:
	var grid := _make_grid(Vector3(0, 0, 20))
	var data := Preview.cabin_blueprint()
	GridBlueprint._restore_materials(grid, data["grids"][0])
	GridBlueprint._restore_blocks(grid, GridBlueprint.blocks_dict(data["grids"][0]))
	var captured: Dictionary = JSON.parse_string(JSON.stringify(GridBlueprint.capture([grid])))
	var costs := BuildCost.of_blueprint(captured)
	check(costs.get(&"plant_fiber", 0) == 70, "el blueprint de la cabaña incluye la fibra de los 35 módulos")
	check(costs.get(&"wood_01", 0) == 46, "el blueprint incluye la madera de paredes y cerramientos")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(grid.serialize()))
	var restored := PlanetGrid.new()
	restored.deserialize(GridManager.generate_grid_id(), self, saved)
	_grids.append(restored)
	check(restored.get_block_count() == grid.get_block_count()
		and restored.mesh_materials["thatch"] == grid.mesh_materials["thatch"],
		"guardar y cargar conserva el tejado y su material")
	var copy := _make_grid(Vector3(0, 0, 40))
	GridBlueprint._restore_materials(copy, captured["grids"][0])
	GridBlueprint._restore_blocks(copy, GridBlueprint.blocks_dict(captured["grids"][0]))
	check(BuildCost.of_grids([copy]) == costs and copy.get_block_count() == grid.get_block_count(),
		"el blueprint reconstruye todas las piezas con sus costes")
