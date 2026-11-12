extends Node3D

## godot --headless --path . res://tests/player/test_use_target.tscn
var failures := 0
var checks := 0
var player: PlayerController
var bed: Bedroll
var chest: Storage


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _look(from: Vector3, at: Vector3) -> void:
	player.camera.global_position = from
	player.camera.look_at(at)


func _press_e() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	check(event.is_action_pressed("action"), "E está asignada a la acción de usar")
	player._input(event)


func _close() -> void:
	player.inventory_ui.close()
	player.resting.close()
	player.capture_mouse(true)


func _run() -> void:
	var menu := Control.new()
	add_child(menu)
	var save := Button.new()
	save.name = "btnSaveGame"
	menu.add_child(save)
	save.owner = menu
	player = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	player.main_menu = menu
	add_child(player)
	player.free_flight_enabled = false
	player.input_enabled = true
	player.visible = true
	player.gravity_direction = Vector3.DOWN
	player.building_system.set_build_mode(false)
	player.camera.current = true
	player.capture_mouse(true)
	player.collision_model.disabled = false
	GameManager.current_state = GameManager.State.PLAYING
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(10, 1, 10)
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	bed = load("res://scenes/world/bedroll.tscn").instantiate()
	bed.position = Vector3(-1, 0, -1.6)
	add_child(bed)
	chest = load("res://scenes/world/wooden_chest.tscn").instantiate()
	chest.position = Vector3(1, 0, -1.6)
	add_child(chest)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3.DOWN
	player.move_and_slide()
	check(player.is_on_floor(), "el jugador está de pie en el suelo de la cabaña")

	var eye := Vector3(0, 1.7, 0)
	# Escenas reales juntas como en una cabaña: el radio de luz no es parte del objeto usable.
	var fire: Campfire = load("res://scenes/world/campfire.tscn").instantiate()
	fire.process_mode = Node.PROCESS_MODE_DISABLED
	fire.position = Vector3(1.8, 0, 0)
	add_child(fire)
	fire.inventory.add_item(ItemCatalog.get_item(&"wood_01"), 1)
	check(fire.ignite(), "la prueba incluye una hoguera encendida")
	var fire_box := UseTarget._local_box(fire)
	print("Campfire interaction bounds: ", fire_box)
	check(fire_box.size.length() < 4.0, "el volumen de interacción no incluye el alcance de la luz")
	var throne: Throne = load("res://scenes/world/throne.tscn").instantiate()
	throne.position = Vector3(0, 0, -2.2)
	add_child(throne)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_look(eye, throne.position + Vector3.UP * 1.0)
	player._perform_raycast()
	var center := get_viewport().get_visible_rect().size * 0.5
	check(UseTarget.aimed(player, player.camera.project_ray_origin(center),
		player.camera.project_ray_normal(center), player._ray_hit) == throne,
		"se apunta al trono con una hoguera encendida al lado")
	_press_e()
	check(player.throne_view.is_open() and player.throne_view._throne == throne,
		"E sienta al jugador en el trono con una hoguera encendida al lado")
	player.throne_view._force_close()
	player.global_position = Vector3.ZERO
	throne.free()
	_close()
	_look(eye, fire.position + Vector3.UP * 0.15)
	_press_e()
	check(player.inventory_ui._campfire == fire, "mirar la hoguera sigue abriendo esa hoguera")
	_close()

	_look(eye, bed.position + Vector3.UP * 0.1)
	player._perform_raycast()
	_press_e()
	check(player.resting.is_open() and player.resting._bed == bed,
		"mirando el lecho se abre ese lecho aunque haya un cofre al lado")
	_close()

	# Girar y pulsar antes del siguiente _process: la física guardada aún apunta al lecho.
	_look(eye, chest.position + Vector3.UP * 0.3)
	_press_e()
	check(player.inventory_ui.open_storage_node() == chest,
		"E usa la vista actual aunque todavía no se haya actualizado el rayo del fotograma")
	_close()

	_look(eye, Vector3(0, 4, -3))
	player._perform_raycast()
	_press_e()
	check(not player.resting.is_open() and not player.inventory_ui.visible,
		"mirar al aire no activa el lecho ni el cofre cercanos")
	_close()

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(4, 3, 0.2)
	wall.position = Vector3(0, 1, -0.8)
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_look(eye, chest.position + Vector3.UP * 0.3)
	player._perform_raycast()
	_press_e()
	check(not player.resting.is_open() and not player.inventory_ui.visible,
		"una pared impide usar objetos al otro lado")
	_close()
	# Los muebles de un barco cuelgan del mismo cuerpo que sus paredes: el parentesco no
	# permite atravesar el casco para usarlos.
	chest.reparent(wall, true)
	_press_e()
	check(not player.inventory_ui.visible,
		"la pared también bloquea un cofre que cuelga del mismo cuerpo físico")
	_close()
	chest.reparent(self, true)
	wall.free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	_look(Vector3(0, 3, 5), bed.position + Vector3.UP * 0.1)
	player._perform_raycast()
	_press_e()
	check(player.resting._bed == bed, "la cámara de tercera persona usa el lecho apuntado")
	_close()

	chest.position = Vector3(0, 0, -6)
	_look(eye, chest.position + Vector3.UP * 0.3)
	player._perform_raycast()
	_press_e()
	check(not player.resting.is_open() and not player.inventory_ui.visible,
		"un objeto fuera de alcance no activa otro cercano")
	_close()

	# También se apuntan objetos que no participan en el raycast físico.
	chest.position = Vector3(1, 0, -1.6)
	(chest.get_node("Body/Shape") as CollisionShape3D).disabled = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	_look(eye, chest.position + Vector3.UP * 0.3)
	_press_e()
	check(player.inventory_ui.open_storage_node() == chest,
		"se usa el objeto visible aunque no tenga colisión física")
	_look(eye, bed.position + Vector3.UP * 0.1)
	_press_e()
	check(not player.resting.is_open() and player.inventory_ui.open_storage_node() == chest,
		"con el inventario abierto E no activa otro objeto del mundo")
	_close()

	# Un intento fallido de recogida no debe abrir en su lugar el lecho cercano.
	player.inventory.clear()
	player.inventory.max_slots = 1
	var stone := ItemCatalog.get_item(&"stone_01")
	player.inventory.add_item(stone, stone.max_stack)
	var dropped := DroppedItem.new()
	dropped.process_mode = Node.PROCESS_MODE_DISABLED
	dropped.item_data = ItemCatalog.get_item(&"wood_01")
	dropped.quantity = 1
	dropped.position = Vector3(0, 0.2, -1)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = Vector3.ONE * 0.2
	dropped.add_child(mesh)
	add_child(dropped)
	_look(eye, dropped.position)
	_press_e()
	check(not dropped.is_queued_for_deletion() and dropped.quantity == 1
		and not player.resting.is_open() and not player.inventory_ui.visible,
		"sin hueco se conserva lo apuntado y no se activa otro objeto")
	_close()

	player.free()
	GameManager.player = null
	print("USE TARGET: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
