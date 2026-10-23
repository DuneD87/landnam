extends Node

## La tala contra árboles hundidos en el suelo: el instancer los entierra un poco, y en las
## laderas a veces tanto que la colisión del tronco queda entera bajo los pies. El hachazo los busca
## también por debajo (TreeFelling.strike_query) y cuenta el tronco desde donde sale del suelo
## (TreeFelling.trunk_base). Los cuerpos del instancer no se pueden crear a mano: los árboles son
## cuerpos estáticos con el mismo cilindro.
##   godot --headless --path . res://tests/planet/test_tree_felling.tscn

const HEIGHT := 8.0

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	# Suelo llano con la cara de arriba en y = 0.
	var ground := StaticBody3D.new()
	ground.collision_layer = PhysicsLayers.WORLD
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 2.0, 40.0)
	ground_shape.shape = box
	ground.add_child(ground_shape)
	ground.position.y = -1.0
	add_child(ground)
	# Uno como suele quedar (0,4 m bajo tierra), otro hundido 3 m, con el cilindro del tronco
	# (1,6 m) entero bajo tierra, y otro que flota medio metro.
	var normal := _tree(Vector3(6.0, -0.4, 0.0))
	var buried := _tree(Vector3(0.0, -3.0, 0.0))
	var floating := _tree(Vector3(-6.0, 0.5, 0.0))
	for i in 3:
		await get_tree().physics_frame
	var space := get_viewport().get_world_3d().direct_space_state

	check(is_equal_approx(snappedf(_base(space, normal), 0.01), 0.4), "el tronco normal sale del suelo a 0,4 m de su base")
	check(is_equal_approx(snappedf(_base(space, buried), 0.01), 3.0), "el hundido, a 3 m")
	check(_base(space, floating) == 0.0, "el que flota, desde su base")
	check(_base(space, buried) + TreeFelling.REACH_HEIGHT > 3.0 + TreeFelling.STRIKE_HEIGHT,
		"el pecho de quien tala junto al hundido queda en el tramo del tronco que cuenta")

	var found := _bodies(space, Vector3(6.9, 0.0, 0.0))
	check(normal in found, "el tajo encuentra el tronco normal")
	found = _bodies(space, Vector3(0.9, 0.0, 0.0))
	check(buried in found, "y el hundido, aunque su colisión esté bajo tierra")

	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Un árbol con la base en [base]: un cuerpo estático con el cilindro del tronco, de 1,6 m.
func _tree(base: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.25
	cylinder.height = 1.6
	shape.shape = cylinder
	shape.position.y = 0.8
	body.add_child(shape)
	add_child(body)
	body.global_position = base
	return body


func _base(space: PhysicsDirectSpaceState3D, tree: StaticBody3D) -> float:
	return TreeFelling.trunk_base(space, tree.global_transform, HEIGHT, tree.get_rid())


## Lo que toca el tajo de quien está en [feet] mirando hacia -X.
func _bodies(space: PhysicsDirectSpaceState3D, feet: Vector3) -> Array:
	return space.intersect_shape(TreeFelling.strike_query(feet, Vector3.LEFT, Vector3.UP), 32) \
		.map(func(result: Dictionary) -> Object: return result.collider)
