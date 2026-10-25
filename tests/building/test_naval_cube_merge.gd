extends Node3D

## godot --headless --path . res://tests/building/test_naval_cube_merge.tscn
var failures := 0
var _building: BuildingSystem
var _inventory: Inventory
var _player: Node3D
var _cube := BlockDatabase.get_block(0)
var _wood := ItemCatalog.get_item(&"wood_01")


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
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_check_boolean()
	_check_rotated_floor()
	_player = Node3D.new()
	add_child(_player)
	_inventory = Inventory.new(100)
	_player.add_child(_inventory)
	_player.add_child(BuildPreview.new())
	_building = BuildingSystem.new()
	_building.current_planet = self
	_player.add_child(_building)
	_building.set_build_mode(true)
	_building.pick_block(BlockDatabase.get_block_material_item(0, "wood"))
	_inventory.add_item(_wood, 1)
	var hull := _make_hull(Vector3(0, 30, 0))
	await _check_target(hull)
	_check_same_size(hull)
	_check_sizes(hull)
	_check_save(hull)
	_check_mirror_and_rotations()
	await _check_dynamic_and_mirror()
	GridManager.clear_all()
	_player.queue_free()
	await get_tree().process_frame
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_boolean() -> void:
	var solid := BlockBoolean.box()
	check(is_equal_approx(BlockBoolean.shape(solid)["volume"], 1.0), "el cubo inicial tiene volumen uno")
	var shifted := BlockBoolean.from_block({"block_id": 0}, 1.0, Vector3(0.5, 0, 0))
	var cut := BlockBoolean.subtract(solid, shifted)
	check(is_equal_approx(BlockBoolean.shape(cut)["volume"], 0.5), "restar dos cubos solapados descuenta la intersección")
	check(BlockBoolean.subtract(solid, solid).is_empty(), "un cubo completamente ocupado no aporta volumen")
	var inner := BlockBoolean.from_block({"block_id": 0}, 0.5, Vector3.ONE * 0.25)
	check(is_equal_approx(BlockBoolean.shape(BlockBoolean.subtract(solid, inner))["volume"], 0.875),
		"la resta conserva los huecos interiores")
	var bow_cell: Dictionary = NavalPiece.generate(NavalPiece.Kind.BOW, Vector3i(12, 6, 12), NavalPiece.Profile.STRAIGHT)[Vector3i(8, 1, 2)]
	var bow_fill := BlockBoolean.shape(BlockBoolean.subtract(solid, BlockBoolean.from_block(bow_cell, 1.0, Vector3.ZERO)))
	check(absf(float(bow_fill["volume"]) + float(bow_cell["naval_shape"]["volume"]) - 1.0) < 0.001,
		"las caras no planas de la proa se restan sin desbordar la pila")


func _check_rotated_floor() -> void:
	var hull_cell: Dictionary = NavalPiece.generate(NavalPiece.Kind.HULL, Vector3i(7, 5, 6))[Vector3i(1, 0, 2)]
	var fill := BlockBoolean.shape(BlockBoolean.subtract(BlockBoolean.box(), BlockBoolean.from_block(hull_cell, 1.0, Vector3.ZERO)))
	var hull_mesh := ChunkMeshBuilder.build_mesh({Vector3i.ZERO: hull_cell}, 1.0, Transform3D.IDENTITY)
	var holes := 0
	var outside := 0
	for rx in 4:
		for ry in 4:
			for rz in 4:
				var rotation := Basis(Vector3.RIGHT, rx * PI * 0.5) * Basis(Vector3.UP, ry * PI * 0.5) * Basis(Vector3.BACK, rz * PI * 0.5)
				var blocks := {Vector3i.ZERO: {"block_id": 9, "naval_shape": fill},
					Vector3i(1, 0, 0): {"block_id": 0, "rotation_basis": rotation},
					Vector3i(2, 0, 0): {"block_id": 0, "rotation_basis": rotation}}
				var mesh := ChunkMeshBuilder.build_mesh(blocks, 1.0, Transform3D.IDENTITY)
				for surface in mesh.get_surface_count():
					for point: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						if point.x < -0.00001 or point.x > 3.00001 or point.y < -0.00001 or point.y > 1.00001 or point.z < -0.00001 or point.z > 1.00001:
							outside += 1
				for x in [0.02, 0.5, 0.98, 1.02, 1.5, 1.98, 2.02, 2.5, 2.98]:
					for z in [0.02, 0.5, 0.98]:
						var point := Vector3(x, 1, z)
						if not _surface_at(mesh, point, Vector3.UP) and not _surface_at(hull_mesh, point, Vector3.UP):
							holes += 1
	check(outside == 0, "los cubos girados permanecen dentro de sus celdas junto al relleno naval")
	check(holes == 0, "el suelo no abre agujeros entre rellenos y cubos normales en los tres ejes de giro")


func _surface_at(mesh: ArrayMesh, point: Vector3, normal: Vector3) -> bool:
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for i in range(0, vertices.size(), 3):
			if (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).dot(normal) <= 0.0:
				continue
			var hit = Geometry3D.ray_intersects_triangle(point + normal * 0.01, -normal, vertices[i], vertices[i + 1], vertices[i + 2])
			if hit != null and (hit - point).length_squared() < 0.00000001:
				return true
	return false


func _make_hull(origin: Vector3) -> GridBase:
	var grid := GridManager.create_grid_exact(self, origin, Basis.IDENTITY, 0.25)
	grid.mesh_materials["wood"] = BlockDatabase.get_material_by_id("wood").surface_material
	grid.begin_bulk_edit()
	var blocks := NavalPiece.generate(NavalPiece.Kind.HULL, Vector3i(7, 5, 6))
	for cell: Vector3i in blocks:
		var info: Dictionary = blocks[cell]
		grid.place_block(cell, BlockDatabase.get_block(int(info["block_id"])), Basis.IDENTITY,
			Transform3D(Basis.IDENTITY, grid.grid_to_world(cell)), "wood", info)
	grid.end_bulk_edit()
	return grid


func _target(grid: GridBase, position: Vector3i, size_index: int) -> void:
	_building.set_cell_size_index(size_index)
	_building._target_grid = grid if is_equal_approx(grid.cell_size, _building.cell_size) else null
	_building._cached_grid_for_placement = _building._target_grid
	_building._hit_grid_for_alignment = grid
	_building._target_grid_pos = position
	_building._target_world_pos = grid.get_grid_world_transform() * (Vector3(position) * _building.cell_size)
	_building._target_basis = grid.get_basis_world()
	_building._has_target = true
	_building._can_place = true
	_building._can_afford = true


func _check_target(hull: GridBase) -> void:
	_player.global_position = hull.get_origin_world() + Vector3(0.8, 2, 0.6)
	_building.set_cell_size_index(0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var origin := hull.get_origin_world()
	var ray := PhysicsRayQueryParameters3D.create(origin + Vector3(0.4, 3, 0.6), origin + Vector3(0.4, -1, 0.6))
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty(), "el rayo alcanza el suelo curvo real")
	if hit.is_empty():
		return
	_building.process_raycast(hit.collider, hit.normal, hit.position, hit)
	var preview := _player.get_child(1) as BuildPreview
	check(_building._can_place and _building._can_afford and _building._cube_merge_plan.get("allowed", false)
		and preview._ghost_material.albedo_color == preview.ghost_color_valid,
		"apuntar al hueco de una celda curva muestra el fantasma verde")
	check(hull.has_block(_building._target_grid_pos), "el cubo puede rellenar la misma celda parcialmente ocupada")


func _partial_cell(hull: GridBase) -> Vector3i:
	for cell: Vector3i in hull.get_all_blocks():
		var info := hull.get_block(cell)
		var volume := GridBase._info_volume_factor(info)
		if volume > 0.1 and volume < 0.9:
			return cell
	return Vector3i.ZERO


func _check_same_size(hull: GridBase) -> void:
	var position := _partial_cell(hull)
	var original := hull.get_block(position).duplicate(true)
	var original_volume := hull.get_total_volume()
	_target(hull, position, 0)
	var plan := _building._cube_merger.resolve(hull, position, 0.25, "wood")
	check(plan.get("allowed", false), "un cubo normal admite solapamiento parcial con el casco")
	if not plan.get("allowed", false):
		return
	var expected := 1.0 - GridBase._info_volume_factor(original)
	check(absf(plan["info"]["naval_shape"]["volume"] - expected) < 0.0002,
		"el relleno ocupa exactamente el hueco que no ocupa la madera del casco")
	_inventory.clear()
	var before := GridManager.get_grid_group(hull.grid_id).size()
	check(not _building.try_place_block() and GridManager.get_grid_group(hull.grid_id).size() == before,
		"sin materiales no se crea una grid vacía ni se toca el casco")
	_inventory.add_item(_wood, 1)
	check(_building.try_place_block(), "coloca el cubo completo dentro de la estructura")
	var group := GridManager.get_grid_group(hull.grid_id)
	var volume := 0.0
	var infill: GridBase
	for grid: GridBase in group:
		volume += grid.get_total_volume()
		if grid != hull and grid.has_block(position):
			infill = grid
	check(infill != null and group.size() == 2, "el relleno queda alineado y unido al mismo grupo de construcción")
	check(absf(volume - original_volume - expected * pow(0.25, 3)) < 0.00001,
		"la masa del barco suma solo el volumen nuevo del cubo")
	check(_inventory.get_item_count(_wood) == 0, "el relleno gasta un solo bloque de material")
	_target(hull, position, 0)
	_inventory.add_item(_wood, 1)
	check(not _building.try_place_block() and _inventory.get_item_count(_wood) == 1,
		"un relleno ya construido sigue bloqueando cubos duplicados")
	if infill:
		var removed := infill.remove_block(position)
		_building._refund_block(removed, infill.cell_size)
		check(hull.get_block(position) == original and is_equal_approx(hull.get_total_volume(), original_volume),
			"desmontar el cubo conserva intacta la curva original")
		check(_inventory.get_item_count(_wood) == 2, "desmontar recupera el material del relleno")
	var full := Vector3i.ZERO
	for cell: Vector3i in hull.get_all_blocks():
		if int(hull.get_block(cell)["block_id"]) == NavalHullMesh.FULL_ID:
			full = cell
			break
	_target(hull, full, 0)
	check(not _building.try_place_block(), "una celda de casco completamente maciza permanece bloqueada")
	for material_id: String in ["wood", "stone"]:
		var material := BlockDatabase.get_material_by_id(material_id)
		var material_plan := _building._cube_merger.resolve(hull, position, 0.25, material_id)
		var mesh := ChunkMeshBuilder.build_mesh({Vector3i.ZERO: material_plan["info"]}, 1.0, Transform3D.IDENTITY,
			{material_id: material.surface_material})
		check(mesh.surface_get_material(0) == material.surface_material,
			"el cubo fusionado conserva el material normal elegido: " + material_id)


func _check_sizes(hull: GridBase) -> void:
	_target(hull, Vector3i.ZERO, 2)
	var plan := _building._cube_merger.resolve(hull, Vector3i.ZERO, 1.0, "wood")
	check(plan.get("allowed", false), "un cubo de un metro se fusiona con un casco de bloques de 0,25 m")
	if not plan.get("allowed", false):
		return
	var occupied := 0.0
	for cell: Vector3i in hull.get_all_blocks():
		if cell.x < 4 and cell.y < 4 and cell.z < 4:
			occupied += GridBase._info_volume_factor(hull.get_block(cell)) * pow(0.25, 3)
	check(absf(plan["info"]["naval_shape"]["volume"] + occupied - 1.0) < 0.001,
		"la unión de distintos tamaños descuenta todas las intersecciones del casco")
	_inventory.add_item(_wood, 1)
	check(_building.try_place_block(), "el cubo de un metro se coloca con su coste normal")
	var saved := GridBlueprint.capture(GridManager.get_grid_group(hull.grid_id))
	var cost := BuildCost.of_blueprint(saved)
	check(cost.get(&"wood_01", 0) == hull.get_block_count() + 1,
		"el blueprint cuenta cada pieza de casco y cada cubo añadido una vez")


func _check_save(hull: GridBase) -> void:
	var data := GridBlueprint.capture(GridManager.get_grid_group(hull.grid_id))
	var copy: Dictionary = JSON.parse_string(JSON.stringify(data))
	var restored := GridBlueprint.instantiate(copy, self, Vector3(20, 30, 0), Basis.IDENTITY, true)
	var infills := 0
	var volume := 0.0
	for grid: GridBase in restored:
		volume += grid.get_total_volume()
		for info: Dictionary in grid.get_all_blocks().values():
			if info.get("naval_shape", {}).get("infill", false):
				infills += 1
	var expected := 0.0
	for grid: GridBase in GridManager.get_grid_group(hull.grid_id):
		expected += grid.get_total_volume()
	check(infills == 1 and absf(volume - expected) < 0.00001,
		"blueprint y JSON conservan la unión y su volumen sin duplicarlo")


func _check_mirror_and_rotations() -> void:
	var hull := _make_hull(Vector3(40, 30, 0))
	var position := _partial_cell(hull)
	_target(hull, position, 0)
	_building._mirror_active = true
	_building.mirror_grid = hull
	_building.mirror_axis = BuildingSystem.MirrorAxis.X
	_building.mirror_center_world = hull.get_origin_world() + Vector3(3.5, 0.5, 0.5) * hull.cell_size
	_inventory.clear()
	_inventory.add_item(_wood, 2)
	check(_building.try_place_block(), "el cubo se fusiona con simetría activada")
	var count := 0
	for grid: GridBase in GridManager.get_grid_group(hull.grid_id):
		for info: Dictionary in grid.get_all_blocks().values():
			if info.get("naval_shape", {}).get("infill", false):
				count += 1
	check(count == 2 and _inventory.get_item_count(_wood) == 0,
		"la simetría coloca y paga los dos rellenos en el casco")
	_building._mirror_active = false
	_building.mirror_grid = null
	_building.mirror_axis = BuildingSystem.MirrorAxis.NONE
	var rotated := GridManager.create_grid_exact(self, Vector3(60, 30, 0), Basis.IDENTITY, 0.5)
	var info: Dictionary = hull.get_block(position).duplicate()
	var rotation := Basis(Vector3.UP, PI * 0.5)
	info["rotation_basis"] = rotation
	info["mirrored"] = true
	info["mirror_axis"] = 2
	rotated.place_block(Vector3i.ZERO, BlockDatabase.get_block(int(info["block_id"])), rotation,
		Transform3D(rotation, rotated.get_origin_world()), "wood", info)
	var plan := _building._cube_merger.resolve(rotated, Vector3i.ZERO, 0.5, "wood")
	check(plan.get("allowed", false) and absf(plan["info"]["naval_shape"]["volume"] + GridBase._info_volume_factor(info) - 1.0) < 0.001,
		"la fusión respeta piezas curvas giradas y reflejadas")


func _check_dynamic_and_mirror() -> void:
	var source := _make_hull(Vector3(0, 50, 0))
	var body := TestBody.new()
	add_child(body)
	body.global_transform = source.get_grid_world_transform()
	body.set_meta("grid_id", "cube_merge_dynamic")
	var dynamic := DynamicPlanetGrid.new()
	dynamic.setup_from_static_shared("cube_merge_dynamic", self, source, body)
	GridManager._register_grid(dynamic, self, dynamic.grid_id)
	body.update_mass_from_grids()
	var old_volume := dynamic.get_total_volume()
	_target(dynamic, Vector3i.ZERO, 2)
	_inventory.add_item(_wood, 1)
	var plan := _building._cube_merger.resolve(dynamic, Vector3i.ZERO, 1.0, "wood")
	check(plan.get("allowed", false) and _building.try_place_block(), "se puede rellenar el casco de un barco dinámico")
	var group := GridManager.get_grid_group(dynamic.grid_id)
	var same_body := true
	for grid: GridBase in group:
		same_body = same_body and grid is DynamicPlanetGrid and (grid as DynamicPlanetGrid)._body == body
	check(same_body and group.size() == 2, "el cubo añadido se mueve en el mismo cuerpo físico que el barco")
	body._recalculate_buoyancy_boxes()
	var displaced := 0.0
	for part: float in body._box_vol:
		displaced += part
	var expected: float = old_volume + plan["info"]["naval_shape"]["volume"]
	check(absf(body.mass - expected * DynamicGridBody.BLOCK_DENSITY) < 0.01 and absf(displaced - expected) < 0.00001,
		"masa y flotación del barco dinámico cuentan una sola vez el solapamiento")
	body.queue_free()
