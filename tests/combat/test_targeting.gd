extends Node3D

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _animal(at: Vector3) -> AmbientAnimal:
	var animal := AmbientAnimal.new()
	animal.process_mode = Node.PROCESS_MODE_DISABLED
	animal.position = at
	add_child(animal)
	animal.active = true
	animal.add_to_group(AmbientAnimal.GROUP)
	return animal


func _run() -> void:
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
	player.camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))
	var middle := _animal(Vector3(0, 2, -10))
	var side := _animal(Vector3(5, 2, -10))
	var combat := player.combat
	combat.lock_on()
	check(combat.lock_target == middle, "Se prefiere la criatura centrada en la cámara")
	combat._targeting.update(0.1)
	check(player.camera_controller.lock_point == middle.lock_point(), "La cámara recibe el punto del cuerpo")
	middle.active = false
	combat._targeting.update(0.1)
	check(combat.lock_target == null, "Una criatura reciclada deja de ser objetivo")
	combat.lock_on()
	check(combat.lock_target == side, "Se puede elegir otra criatura activa")
	side.position.z = -50
	combat._targeting.update(0.1)
	check(combat.lock_target == null, "El objetivo se pierde al salir de alcance")
	side.position.z = -10
	middle.active = true
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(2, 4, 0.2)
	wall.position = Vector3(0, 2, -4)
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	combat.lock_on()
	check(combat.lock_target == side, "Una pared impide fijar la criatura centrada")
	side.free()
	combat._targeting.update(0.1)
	check(combat.lock_target == null and player.camera_controller.lock_point == null,
		"Liberar el objetivo limpia también el punto de la cámara")
	GameManager.player = null
	print("COMBAT TARGETING: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
