extends Node3D

## godot --headless --path . res://tests/building/test_boat_water.tscn
## Madera, lastre, hundimiento y giro real del RigidBody3D con agua plana.
class SeaData extends RefCounted:
	var has_water := false
	var radius := 1000.0
	var water_radius := 0.0

class TestPlanet extends Node3D:
	var global_pos := Vector3.ZERO
	var gravity_strength := 9.8
	var planet := SeaData.new()
	var water_sphere: OceanSystem
	func get_wind_velocity(_position: Vector3) -> Vector3:
		return Vector3.ZERO

class FlatWater extends WaterHeightSampler:
	var samples := 0
	var max_height := 0.0
	var flow := Vector3.ZERO
	func max_wave_height() -> float:
		return max_height
	func get_height_at(_point: Vector3, _time: float, _center: Vector3, _filter: float = 0.0) -> float:
		samples += 1
		last_flow = flow
		return 0.0

var _planet: TestPlanet
var checks := 0
var failures := 0


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
	_planet.water_sphere = OceanSystem.new()
	_planet.water_sphere.mesh_manager = QuadTreeMeshManager.new()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform float water_time = 0.0;"
	material.shader = shader
	_planet.water_sphere.mesh_manager.default_material = material
	await _check_materials()
	await _check_wave_reach()
	await _check_steering()
	GridManager.clear_all()
	_planet.water_sphere.mesh_manager.free()
	_planet.water_sphere.free()
	_planet.queue_free()
	await get_tree().process_frame
	print("BOAT WATER: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _body(origin: Vector3, blocks: Array) -> DynamicPlanetGrid:
	var grid := GridManager.create_grid_exact(_planet, origin, Basis.IDENTITY, 1.0)
	grid.begin_bulk_edit()
	for spec: Array in blocks:
		var cell: Vector3i = spec[0]
		var block_id: int = spec[2] if spec.size() > 2 else 0
		grid.place_block(cell, BlockDatabase.get_block(block_id).for_material(spec[1]), Basis.IDENTITY,
			Transform3D(Basis.IDENTITY, grid.grid_to_world(cell)), spec[1])
	grid.end_bulk_edit()
	# Se inyecta FlatWater: no inicializar el sampler real con el material mínimo del test.
	var has_water := _planet.planet.has_water
	_planet.planet.has_water = false
	var dynamic: DynamicPlanetGrid = GridManager.convert_to_dynamic(grid.grid_id)[0]
	_planet.planet.has_water = has_water
	var body := dynamic._body
	body.set_physics_process(false)
	body._interior_dirty = false
	var sampler := FlatWater.new()
	body.add_child(sampler)
	body._water_sampler = sampler
	return dynamic


func _buoyant_volume(body: DynamicGridBody, distant := false) -> float:
	body._recalculate_buoyancy_boxes()
	var volumes := body._agg_vol if distant else body._box_vol
	var floating := body._agg_buoyant if distant else body._box_buoyant
	var total := 0.0
	for i in volumes.size():
		if floating[i]:
			total += volumes[i]
	return total


func _check_materials() -> void:
	var bodies: Array[DynamicGridBody] = []
	for entry in [["wood", 0], ["stone", 0], ["glass", 0], ["thatch", 6], ["", 0]]:
		var grid := _body(Vector3(bodies.size() * 8.0, 996, 0), [[Vector3i.ZERO, entry[0], entry[1]]])
		bodies.append(grid._body)
	var wood_blocks: Array = []
	for x in 3:
		for z in 3:
			wood_blocks.append([Vector3i(x, 0, z), "wood"])
	wood_blocks.append([Vector3i(1, 1, 1), "stone"])
	var loaded := _body(Vector3(40, 996, 0), wood_blocks)
	var overloaded := _body(Vector3(48, 996, 0), [[Vector3i.ZERO, "wood"], [Vector3i.UP, "stone"]])
	bodies.append(loaded._body)
	bodies.append(overloaded._body)
	check(is_equal_approx(_buoyant_volume(loaded._body), 9.0), "solo los nueve bloques de madera aportan empuje al barco cargado")
	check(is_equal_approx(_buoyant_volume(loaded._body, true), 9.0), "el LOD lejano conserva la flotabilidad exclusiva de la madera")
	check(is_equal_approx(_buoyant_volume(overloaded._body), 1.0), "una caja de madera junto a piedra no transmite flotabilidad al lastre")
	check(_buoyant_volume(bodies[1]) == 0.0 and _buoyant_volume(bodies[2]) == 0.0
		and _buoyant_volume(bodies[3]) == 0.0 and _buoyant_volume(bodies[4]) == 0.0,
		"piedra, vidrio, paja y materiales desconocidos no generan empuje")
	_planet.planet.has_water = true
	for frame in 6:
		for body: DynamicGridBody in bodies:
			body._physics_step(1.0 / 60.0)
		await get_tree().physics_frame
	check(bodies[0].linear_velocity.y > 0.1, "la madera sumergida asciende hacia la superficie")
	check(bodies[1].linear_velocity.y < -0.05, "la piedra sumergida se hunde")
	check(bodies[2].linear_velocity.y < -0.05 and bodies[3].linear_velocity.y < -0.05,
		"el resto de materiales se hunde si no lo sostiene la madera")
	check(loaded._body.linear_velocity.y > 0.05, "un casco con madera suficiente sostiene carga de piedra")
	check(overloaded._body.linear_velocity.y < -0.05, "el lastre excesivo hunde una estructura de madera")
	# Guardado/carga no puede convertir el lastre en un material flotante.
	_planet.planet.has_water = false
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GridManager.get_save_data()))
	var loaded_id := loaded.grid_id
	GridManager.restore_save_data(saved)
	await get_tree().process_frame
	var restored := GridManager.get_grid(loaded_id) as DynamicPlanetGrid
	for grid: GridBase in GridManager._grids.values():
		if grid is DynamicPlanetGrid:
			grid._body.set_physics_process(false)
	check(is_equal_approx(_buoyant_volume(restored._body), 9.0), "la partida conserva qué materiales aportan flotación")
	GridManager.clear_all()
	await get_tree().process_frame


func _advance(body: DynamicGridBody, frames: int, delta: float) -> void:
	for frame in frames:
		body._physics_step(delta)
		await get_tree().physics_frame


func _check_wave_reach() -> void:
	var grid := _body(Vector3(0, 1030, 0), [[Vector3i.ZERO, "wood"]])
	var body := grid._body
	var sampler := body._water_sampler as FlatWater
	sampler.max_height = 2.0
	_planet.planet.has_water = true
	await _advance(body, 6, 1.0 / 60.0)
	check(sampler.samples == 0 and body.last_wave_samples == 0,
		"un bloque seco por encima de las olas no consulta el oleaje")
	check(body.linear_velocity.y < -0.05, "descartar el agua conserva la gravedad del bloque seco")
	body.freeze = true

	sampler.max_height = 35.0
	body._physics_step(1.0 / 60.0)
	check(sampler.samples == 4, "una subida del oleaje reactiva las sondas sin mover el cuerpo")
	sampler.max_height = 2.0
	sampler.samples = 0
	body.global_position = Vector3(0, 999, 0)
	sampler.flow = Vector3.RIGHT * 2.0
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0, 1000, -10)
	camera.current = true
	body._physics_step(1.0 / 60.0)
	check(not camera.is_position_in_frustum(body.get_hull_center_world())
		and sampler.samples == 4 and body.last_displaced_mass > 0.0,
		"al entrar en el agua sigue flotando aunque quede fuera de cámara")
	check(body.last_water_flow.is_equal_approx(sampler.flow), "el casco mojado conserva la corriente del agua")
	camera.queue_free()

	body.global_position = Vector3(0, 1030, 0)
	body._flood_volume = 1.0
	body._flood_dirty = true
	body._wake_active = true
	body._wake_points.clear()
	body._wake_points.append({"birth": Time.get_ticks_msec() / 1000.0 - body.WAKE_LIFETIME - 1.0})
	sampler.samples = 0
	body._physics_step(1.0 / 60.0)
	check(sampler.samples == 0 and body.last_displaced_mass == 0.0
		and body.last_water_flow == Vector3.ZERO and body.last_wave_samples == 0,
		"al salir del agua deja de muestrear y borra las lecturas de inmersión anteriores")
	check(body._flood_volume == 0.0 and not body._wake_active and body._wake_points.is_empty(),
		"el descarte conserva el vaciado y la caducidad de la estela")
	var shift := Vector3(18000, -9000, 21000)
	check(body._above_wave_reach(body.global_transform.translated(shift), shift, 1002.0),
		"el descarte seco respeta el rebase del planeta")
	body.global_position = Vector3.ZERO
	body._physics_step(1.0 / 60.0)
	check(body.last_wave_samples == 0, "el centro del planeta no genera sondas ni una normal inválida")

	# El origen puede estar seco mientras una pieza del casco llega al agua.
	var low := _body(Vector3(0, 1030, 0), [[Vector3i(0, -31, 0), "wood"]])
	low._body.freeze = true
	low._body._physics_step(1.0 / 60.0)
	check(low._body.last_wave_samples == 4 and low._body.last_displaced_mass > 0.0,
		"se comprueba el volumen completo, incluso con bloques lejos del origen del cuerpo")
	check(not low._body._above_wave_reach(low._body.global_transform.translated(shift), shift, 1000.0),
		"el rebase tampoco descarta un casco que toca el agua")
	var tall := _body(Vector3(0, 1030, 0), [[Vector3i(0, 30, 0), "wood"]])
	tall._body.freeze = true
	tall._body._physics_step(1.0 / 60.0)
	check(tall._body.last_wave_samples == 0, "una pieza alta permanece fuera del alcance del agua")
	tall._body.global_basis = Basis(Vector3.FORWARD, PI)
	tall._body._physics_step(1.0 / 60.0)
	check(tall._body.last_wave_samples == 4 and tall._body.last_displaced_mass > 0.0,
		"al volcar el casco se reactivan las sondas para su extremo sumergido")
	_planet.planet.has_water = false
	GridManager.clear_all()
	await get_tree().process_frame


func _check_steering() -> void:
	_planet.gravity_strength = 0.0
	# Sin gravedad el bloque se queda donde se ponga: a su calado de equilibrio, para que el timón
	# y el freno de balance vean el casco entero a flote (masa desplazada = masa).
	var draft := BlockDatabase.get_material_by_id("wood").get_mass_for_volume(1.0) / DynamicGridBody.WATER_DENSITY
	var grid := _body(Vector3(0, 1000.0 - draft, 0), [[Vector3i.ZERO, "wood"]])
	var body := grid._body
	_planet.planet.has_water = true
	body._is_being_controlled = true
	body.steering_input = 1.0
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 10.0
	await _advance(body, 18, 10.0 / 60.0)
	var left := Vector3.BACK.signed_angle_to(body.global_basis.z, Vector3.UP)
	check(left > deg_to_rad(8) and left < deg_to_rad(40), "desde parado gira a babor de forma gradual (%.1f°)" % rad_to_deg(left))
	body.global_basis = Basis.IDENTITY
	body.angular_velocity = Vector3.ZERO
	body.steering_input = -1.0
	await _advance(body, 18, 10.0 / 60.0)
	var right := Vector3.BACK.signed_angle_to(body.global_basis.z, Vector3.UP)
	check(right < deg_to_rad(-8) and absf(absf(right) - absf(left)) < deg_to_rad(5),
		"desde parado gira también a estribor con respuesta simétrica (%.1f°)" % rad_to_deg(right))
	body.global_basis = Basis.IDENTITY
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3.BACK
	body.steering_input = 1.0
	await _advance(body, 18, 10.0 / 60.0)
	var moving := Vector3.BACK.signed_angle_to(body.global_basis.z, Vector3.UP)
	check(moving > left * 1.2 and body.angular_velocity.length() < deg_to_rad(26),
		"con arrancada el timón responde más sin superar su velocidad de giro")
	body.steering_input = 0.0
	await _advance(body, 12, 10.0 / 60.0)
	check(absf(body.angular_velocity.dot(Vector3.UP)) < deg_to_rad(1.0), "soltar el timón amortigua el giro")
	body.angular_velocity = Vector3.ZERO
	body.steering_input = 1.0
	body._is_being_controlled = false
	await _advance(body, 6, 10.0 / 60.0)
	check(absf(body.angular_velocity.dot(Vector3.UP)) < deg_to_rad(1.0), "sin tripulante no sigue obedeciendo el último mando")
	body.angular_velocity = Vector3(0, 0.2, -0.3)
	body._is_being_controlled = true
	body._apply_boat_steering(Vector3.RIGHT, Vector3.BACK, Vector3.ZERO, body.mass, 0.2)
	check(body.angular_velocity.x > 0 and is_equal_approx(body.angular_velocity.y, 0.2)
		and is_equal_approx(body.angular_velocity.z, -0.3), "el timón respeta el eje radial del planeta y conserva balance y cabeceo")
	_planet.planet.has_water = false
	GridManager.clear_all()
	await get_tree().process_frame
	var blocks: Array = []
	for x in 6:
		for y in 2:
			for z in 10:
				blocks.append([Vector3i(x, y, z), "wood"])
	var large := _body(Vector3(-3, 999.9, -5), blocks)
	_planet.planet.has_water = true
	large._body._is_being_controlled = true
	large._body.steering_input = 1.0
	await _advance(large._body, 18, 10.0 / 60.0)
	var large_turn := Vector3.BACK.signed_angle_to(large._body.global_basis.z, Vector3.UP)
	check(is_equal_approx(large._body.mass, 30000.0) and large_turn > deg_to_rad(8),
		"el casco de treinta toneladas también puede maniobrar desde parado (%.1f°)" % rad_to_deg(large_turn))
	Engine.time_scale = previous_time_scale
	_planet.planet.has_water = false
	GridManager.clear_all()
	await get_tree().process_frame
