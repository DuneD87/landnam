extends Node3D

## godot --headless --path . res://tests/building/test_building_mass.tscn
## Masa por material, conservación en ediciones y separación del volumen de flotación.
class PassiveBody extends DynamicGridBody:
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
		pass

var checks := 0
var failures := 0
var _planet: Node3D


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
	_planet = Node3D.new()
	add_child(_planet)
	_check_materials_and_sizes()
	_check_conversion_and_transfer()
	_planet.queue_free()
	await get_tree().process_frame
	print("BUILDING MASS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _grid(size := 1.0) -> PlanetGrid:
	var grid := PlanetGrid.new()
	grid.setup("mass_test", _planet, Vector3.ZERO, Basis.IDENTITY, size)
	return grid


func _put(grid: GridBase, cell: Vector3i, material: String, block_id := 0) -> void:
	check(grid.place_block(cell, BlockDatabase.get_block(block_id).for_material(material), Basis.IDENTITY,
		Transform3D(grid.get_basis_world(), grid.grid_to_world(cell)), material), "coloca %s de %s" % [cell, material])


func _body() -> PassiveBody:
	var body := PassiveBody.new()
	body.gravity_scale = 0.0
	add_child(body)
	body.set_meta("grid_id", "mass_body")
	return body


func _check_materials_and_sizes() -> void:
	for entry in [["wood", 250.0], ["stone", 2400.0], ["glass", 2500.0], ["thatch", 80.0]]:
		var material := BlockDatabase.get_material_by_id(entry[0])
		check(is_equal_approx(material.get_mass_for_volume(1.0), entry[1]), "peso de construcción por m³: %s = %s kg" % entry)
		check(material.buoyant == (entry[0] == "wood"), "solo la madera de construcción está habilitada para flotar")
	for size: float in [0.25, 0.5, 1.0, 2.0]:
		var grid := _grid(size)
		_put(grid, Vector3i.ZERO, "wood")
		check(is_equal_approx(grid.get_total_mass(), 250.0 * pow(size, 3))
			and is_equal_approx(grid.get_total_volume(), pow(size, 3)), "la celda de %s m conserva masa y volumen por separado" % size)
		grid.clear()
		check(grid.get_total_mass() == 0.0 and grid.get_total_volume() == 0.0, "limpiar no deja masa residual")
	var grid := _grid()
	_put(grid, Vector3i.ZERO, "wood", 1)
	check(is_equal_approx(grid.get_total_mass(), 125.0) and is_equal_approx(grid.get_total_volume(), 0.5),
		"una rampa de madera cuenta solo su fracción de volumen")
	grid.clear()
	_put(grid, Vector3i.ZERO, "")
	check(is_equal_approx(grid.get_total_mass(), 500.0), "bloques antiguos sin material mantienen la densidad de respaldo")
	grid.clear()
	_put(grid, Vector3i.ZERO, "wood")
	_put(grid, Vector3i.RIGHT, "stone")
	check(is_equal_approx(grid.get_total_mass(), 2650.0), "la piedra y la madera no pesan igual aunque ocupen lo mismo")
	grid.rebuild_mesh()
	check(is_equal_approx(grid.get_total_mass(), 2650.0), "reconstruir la malla resincroniza la masa")
	grid.remove_block(Vector3i.RIGHT)
	check(is_equal_approx(grid.get_total_mass(), 250.0), "quitar piedra descuenta su masa y deja la de la madera")
	grid.clear()


func _check_conversion_and_transfer() -> void:
	var source := _grid()
	_put(source, Vector3i.ZERO, "wood")
	_put(source, Vector3i.RIGHT, "stone")
	var body := _body()
	var dynamic := DynamicPlanetGrid.new()
	dynamic.setup_from_static_shared("mass_dynamic", _planet, source, body)
	check(is_equal_approx(body.mass, 2650.0), "convertir a dinámica mantiene la masa de cada material")
	check(source.get_total_mass() == 0.0, "la conversión vacía la masa de la estática")
	body._recalculate_buoyancy_boxes()
	var displaced := 0.0
	for volume: float in body._box_vol:
		displaced += volume
	check(is_equal_approx(displaced, 2.0), "aligerar madera no altera el volumen estanco de las colisiones")
	var restored_body := _body()
	var restored := DynamicPlanetGrid.new()
	restored.deserialize("mass_restored", _planet, JSON.parse_string(JSON.stringify(dynamic.serialize())), restored_body)
	check(is_equal_approx(restored_body.mass, 2650.0), "cargar recalcula la masa con los materiales actuales")
	var small := DynamicPlanetGrid.new()
	small.grid_id = "mass_small"
	small._body = body
	small.planet_node = _planet
	small.cell_size = 0.5
	body.register_grid(small)
	_put(small, Vector3i(10, 0, 0), "wood")
	check(is_equal_approx(body.mass, 2681.25), "varias grids de distinto tamaño suman su masa al mismo cuerpo")
	small.clear()
	check(is_equal_approx(body.mass, 2650.0), "retirar una grid descuenta su masa del cuerpo compartido")
	var fragment_body := _body()
	var fragment := DynamicPlanetGrid.new()
	fragment.grid_id = "mass_fragment"
	fragment._body = fragment_body
	fragment.planet_node = _planet
	fragment_body.register_grid(fragment)
	fragment.attach_block(Vector3i.RIGHT, dynamic.detach_block(Vector3i.RIGHT))
	check(is_equal_approx(body.mass, 250.0) and is_equal_approx(fragment_body.mass, 2400.0),
		"desprender piedra traslada su peso al fragmento correcto")
	check(is_equal_approx(body.mass + fragment_body.mass, 2650.0), "una separación conserva la masa total")
	dynamic.clear()
	fragment.clear()
	restored.clear()
	body.queue_free()
	fragment_body.queue_free()
	restored_body.queue_free()
