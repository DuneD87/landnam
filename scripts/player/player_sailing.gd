class_name PlayerSailing
extends Node

## El jugador gobierna desde cubierta con las flechas; R permite remar gastando aguante.
## Al abrir menús se sueltan los controles, pero el aparejo sigue trabajando con el viento.
var _player: PlayerController
var _boat: DynamicGridBody
var hud: SailingHUD


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
		_boat.rowing_input = false


func _exit_tree() -> void:
	release_controls()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var body = _player._platform_body
	if not is_instance_valid(body):
		body = null
	if body != _boat:
		release_controls()
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
	if Input.is_action_just_pressed("boat_sail_raise"):
		sailing.set_level(sailing.level + 1)
	if Input.is_action_just_pressed("boat_sail_lower"):
		sailing.set_level(sailing.level - 1)
	_boat.steering_input = Input.get_axis("boat_steer_right", "boat_steer_left")
	if Input.is_action_pressed("boat_row") and _boat.last_displaced_mass > 0.0:
		var forward := _boat.global_basis.z
		var speed := (_boat.linear_velocity - _boat.last_water_flow).dot(forward)
		if speed < BoatSailing.ROW_SPEED:
			_boat.rowing_input = _player.combat.stamina.drain(BoatSailing.ROW_STAMINA, delta)
	hud.show()
	hud.navigation = sailing
	hud.speed = (_boat.linear_velocity - _boat.last_water_flow).length()
	hud.scale = Vector2.ONE * GameTheme.scale_for(get_viewport())
	hud.position = Vector2(get_viewport().get_visible_rect().size.x - 364.0 * hud.scale.x, 280.0 * hud.scale.y)
	hud.queue_redraw()
