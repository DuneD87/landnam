extends Node3D

## Con el menú de pausa, la consola o una ventana abiertos el cuerpo del jugador sigue en el mundo:
## va con el barco y cae, sin hacer caso de las teclas. Entrando en partida (suelo sin colisión)
## se queda quieto.
##   godot --headless --path . res://tests/player/test_menu_hands_off.tscn
class SeaData extends RefCounted:
	var has_water := false
	var radius := 1000.0
	var water_radius := 0.0

class TestPlanet extends Node3D:
	var global_pos := Vector3.ZERO
	var gravity_strength := 9.8
	var planet := SeaData.new()
	var water_sphere: OceanSystem
	func get_gravity_direction(_position: Vector3) -> Vector3:
		return Vector3.DOWN
	func get_wind_velocity(_position: Vector3) -> Vector3:
		return Vector3.ZERO

const DT := 1.0 / 60.0

var failures := 0
var checks := 0
var _planet: TestPlanet
var _player: PlayerController
var _body: DynamicGridBody


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
	_new_player()
	_new_deck()
	await get_tree().physics_frame
	await get_tree().physics_frame
	GameManager.current_state = GameManager.State.PLAYING

	# Menú de pausa: sin input ni ratón capturado.
	_player.input_enabled = false
	_player.mouse_captured = false
	_player.global_position = _body.global_transform * Vector3(2.5, 1.05, 2.5)
	await _steps(30)
	check(_player._platform_body == _body and _player.is_on_floor(),
		"con el menú abierto se queda de pie sobre la cubierta y la sigue")
	var offset := _deck_offset()
	await _sail(Vector3(3.0, 0.0, 0.0), 60)
	check(_deck_offset().distance_to(offset) < 0.1,
		"el barco se lo lleva con el menú abierto (se aparta %.2f m de su sitio en cubierta)"
		% _deck_offset().distance_to(offset))

	# Las teclas pulsadas con la consola abierta no son del jugador.
	offset = _deck_offset()
	Input.action_press("move_forward")
	Input.action_press("jump")
	await _steps(30)
	Input.action_release("move_forward")
	Input.action_release("jump")
	check(_deck_offset().distance_to(offset) < 0.05 and not _player.movement.is_jumping,
		"ni anda ni salta con las teclas mientras no manda (%.2f m)" % _deck_offset().distance_to(offset))
	check(not _player.movement.use_ai_input, "el paso sin mando no deja el movimiento en modo IA")

	# En el aire, cae.
	_player.global_position = _body.global_transform * Vector3(2.5, 4.0, 2.5)
	_player.velocity = Vector3.ZERO
	var height := _player.global_position.y
	await _steps(10)
	check(_player.global_position.y < height - 0.05, "en el aire cae aunque haya un menú abierto")
	await _steps(60)

	# Entrando en partida, el suelo de destino aún no tiene colisión: quieto como antes.
	_player._awaiting_ground = true
	var held := _player.global_position
	await _sail(Vector3(2.0, 0.0, 0.0), 30)
	check(_player.global_position.distance_to(held) < 0.01, "esperando al suelo el cuerpo no se mueve")
	_player._awaiting_ground = false

	_player.free()
	GameManager.player = null
	GridManager.clear_all()
	_planet.queue_free()
	await get_tree().process_frame
	print("MENU HANDS OFF: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _new_player() -> void:
	var menu := Control.new()
	add_child(menu)
	var button := Button.new()
	button.name = "btnSaveGame"
	menu.add_child(button)
	button.owner = menu
	_player = load("res://scenes/player/third_person_player.tscn").instantiate()
	_player.main_menu = menu
	add_child(_player)
	# Deshabilitado saldría del espacio físico: los pasos los da el test.
	_player.set_physics_process(false)
	_player.free_flight_enabled = false
	_player.visible = true
	_player.building_system.set_build_mode(false)
	_player.planet = _planet
	_player.gravity_direction = Vector3.DOWN


## Una cubierta de 5x5 bloques convertida en cuerpo dinámico, congelado: la mueve el test.
func _new_deck() -> void:
	var grid := GridManager.create_grid_exact(_planet, Vector3(0, 100, 0), Basis.IDENTITY, 1.0)
	for x in 5:
		for z in 5:
			var cell := Vector3i(x, 0, z)
			grid.place_block(cell, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
				Transform3D(Basis.IDENTITY, grid.grid_to_world(cell)), "wood")
	var dynamic: DynamicPlanetGrid = GridManager.convert_to_dynamic(grid.grid_id)[0]
	_body = dynamic._body
	_body.set_physics_process(false)
	_body.freeze = true


## Dónde está el jugador en la cubierta.
func _deck_offset() -> Vector3:
	return _body.global_transform.affine_inverse() * _player.global_position


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		_player._physics_step(DT)


## Desplaza la cubierta [shift] en [count] pasos, con un paso del jugador en cada uno.
func _sail(shift: Vector3, count: int) -> void:
	for i in count:
		_body.global_position += shift / count
		await get_tree().physics_frame
		_player._physics_step(DT)
