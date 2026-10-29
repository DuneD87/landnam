class_name PlayerSailing
extends Node

## El jugador gobierna desde cubierta con las flechas: ↑/↓ cambian la marcha (ciar, parado, remar
## y los tercios de vela) y R alterna remar y parar. T echa el ancla con el barco parado y la leva;
## fondeado no hay marcha ni timón. Al abrir menús se suelta el timón, pero la marcha sigue: el
## aparejo trabaja con el viento y los remos siguen bogando.
## Segundos que el indicador avisa de que el barco va demasiado rápido para fondear.
const ANCHOR_REFUSED_TIME := 2.0

var _player: PlayerController
var _boat: DynamicGridBody
var hud: SailingHUD
var _anchor_refused := 0.0


func setup(player: PlayerController) -> void:
	_player = player
	name = "Sailing"
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = SailingHUD.new()
	layer.add_child(hud)
	hud.hide()


func can_control() -> bool:
	var p := _player
	return p.visible and p.input_enabled and p.mouse_captured and not p.free_flight_enabled \
		and GameManager.current_state == GameManager.State.PLAYING and not OptionsScreen.is_open() \
		and not p.inventory_ui.visible and not p.world_map_ui.visible and not p.build_menu.visible \
		and not p.grid_manipulator_menu.visible and not p.ship_spawn_menu.visible \
		and not p.blueprint_placer.is_active() and not p.building_system.build_mode \
		and not p.build_radial.is_open() and not p.resting.is_open() and not p.climb.is_active() \
		and not p.fishing.is_active() and p.combat.state == PlayerCombat.State.IDLE


func release_controls() -> void:
	if is_instance_valid(_boat):
		_boat.steering_input = 0.0


## Al bajarse nadie rema: al volver a subir el barco no debe arrancar solo.
func _leave_boat() -> void:
	release_controls()
	if is_instance_valid(_boat):
		_boat.sailing.row = 0


func _exit_tree() -> void:
	_leave_boat()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var body = _player._platform_body
	if not is_instance_valid(body):
		body = null
	if body != _boat:
		_leave_boat()
		_boat = body
	if not is_instance_valid(_boat) or _boat.movement_type != DynamicGridBody.MovementType.BOAT:
		hud.hide()
		return
	release_controls()
	if not can_control():
		hud.hide()
		return
	_boat.refresh_sails()
	var sailing: BoatSailing = _boat.sailing
	_anchor_refused = maxf(_anchor_refused - delta, 0.0)
	if Input.is_action_just_pressed("boat_anchor"):
		if _boat.anchored:
			_boat.weigh_anchor()
		elif not _boat.drop_anchor():
			_anchor_refused = ANCHOR_REFUSED_TIME
	if not _boat.anchored:
		if Input.is_action_just_pressed("boat_sail_raise"):
			sailing.shift(1)
		if Input.is_action_just_pressed("boat_sail_lower"):
			sailing.shift(-1)
		if Input.is_action_just_pressed("boat_row"):
			sailing.set_gear(0 if sailing.row != 0 else 1)
		_boat.steering_input = Input.get_axis("boat_steer_right", "boat_steer_left")
	hud.show()
	hud.navigation = sailing
	hud.anchored = _boat.anchored
	hud.anchor_refused = _anchor_refused > 0.0
	hud.speed = (_boat.linear_velocity - _boat.last_water_flow).length()
	hud.scale = Vector2.ONE * GameTheme.scale_for(get_viewport())
	hud.position = Vector2(get_viewport().get_visible_rect().size.x - 364.0 * hud.scale.x, 280.0 * hud.scale.y)
	hud.queue_redraw()
