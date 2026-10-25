class_name PlayerFishing
extends Node

## Ciclo de pesca del jugador. Los peces son los del hábitat, con reserva exclusiva de la boya.
enum State { IDLE, CHARGING, CASTING, WAITING, BITE, HOOKED, REELING }
const CAST_TIME := 0.65
const FLIGHT_TIME := 0.65
const CATCH_DISTANCE := 4.0
const BITE_DISTANCE := 1.25
const WaterQuery = preload("res://scripts/player/water_access.gd")

var state := State.IDLE
var _player: PlayerController
var _rod: FishingRodTrait
var _float: FishingFloat
var _fish: AmbientFish
var _terrain: VoxelLodTerrain
var _planet_host: Node3D
var _ocean: OceanSystem
var _sampler: WaterHeightSampler
var _sea_radius := 0.0
var _charge := 0.0
var _elapsed := 0.0
var _scan_left := 0.0
var _slack_left := 0.0
var _reel_held := false
var _valid_target := false
var _target_local := Vector3.ZERO
var _flight_local := Vector3.ZERO
var _mounted_hook: ItemData
var _rng := RandomNumberGenerator.new()
var _hud: Label
var _meter: ProgressBar


func setup(player: PlayerController) -> void:
	_player = player
	name = "Fishing"
	_rng.randomize()
	_sampler = WaterHeightSampler.new()
	add_child(_sampler)
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	var panel := VBoxContainer.new()
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -245
	panel.offset_bottom = -180
	panel.custom_minimum_size.x = 480
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud = Label.new()
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_outline_size", 5)
	panel.add_child(_hud)
	_meter = ProgressBar.new()
	_meter.show_percentage = false
	_meter.custom_minimum_size.y = 8
	panel.add_child(_meter)
	_hud.hide()
	_meter.hide()


func equipped_rod() -> FishingRodTrait:
	var data := _player.combat.weapon()
	return data.get_trait(FishingRodTrait) as FishingRodTrait if data != null else null


func is_active() -> bool:
	return state != State.IDLE


func _can_fish() -> bool:
	var p := _player
	return p.visible and p.input_enabled and not p.free_flight_enabled and p.is_mouse_captured() \
		and not p.inventory_ui.visible and not p.building_system.build_mode \
		and not p.world_map_ui.visible and not p.build_menu.visible and not p.grid_manipulator_menu.visible \
		and not p.blueprint_placer.is_active() and not p.resting.is_open() \
		and not p.climb.is_active() and not p.movement.is_swimming and not p.movement.is_falling \
		and p.combat.state == PlayerCombat.State.IDLE and not p.combat.upper_busy()


## Se llama antes del combate: la caña es dueña de ambos botones del ratón.
func handle_input(event: InputEvent) -> bool:
	if equipped_rod() == null:
		return false
	if not _can_fish():
		cancel()
		return not _player.inventory_ui.visible and (event.is_action("attack_1") or event.is_action("attack_2"))
	if event.is_action_pressed("attack_2"):
		cancel()
		return true
	if event.is_action("attack_2"):
		return true
	if event.is_action_pressed("attack_1"):
		match state:
			State.IDLE:
				_begin_charge()
			State.WAITING, State.BITE:
				cancel()
			State.HOOKED, State.REELING:
				_reel_held = true
				state = State.REELING
		return true
	if event.is_action_released("attack_1"):
		_reel_held = false
		if state == State.CHARGING:
			_cast()
		elif state == State.REELING:
			state = State.HOOKED
		return true
	return false


func _begin_charge() -> void:
	_rod = equipped_rod()
	if not _has_tackle():
		return
	var core := _player.planet.get("planet") as Planet if _player.planet != null else null
	if core == null or not core.has_water or core.voxel_terrain == null:
		_notify("FISH_NEED_WATER")
		return
	_terrain = core.voxel_terrain
	_planet_host = _player.planet
	_ocean = _planet_host.get("water_sphere") as OceanSystem
	if _ocean != null:
		_sampler.setup(_ocean.quadtree_material as ShaderMaterial,
			_planet_host.get("world_map") as PlanetWorldMap, _ocean.radius)
	_sea_radius = core.radius - core.water_radius
	_float = FishingFloat.new()
	_terrain.add_child(_float)
	_charge = 0.0
	_elapsed = 0.0
	state = State.CHARGING
	_update_target()


func _has_tackle() -> bool:
	for id in [_rod.hook_id, _rod.bait_id]:
		var item := ItemCatalog.get_item(id)
		if item == null or _player.inventory.get_item_count(item) <= 0:
			_notify("FISH_NEED_HOOK" if id == _rod.hook_id else "FISH_NEED_BAIT")
			return false
	return true


func _cast() -> void:
	_update_target()
	if not _valid_target or not _has_tackle():
		if not _valid_target:
			_notify("FISH_INVALID")
		cancel()
		return
	# Se comprueban ambos antes de gastar: cancelar la carga nunca consume materiales.
	_mounted_hook = ItemCatalog.get_item(_rod.hook_id)
	_player.inventory.remove_item(_mounted_hook, 1)
	_player.inventory.remove_item(ItemCatalog.get_item(_rod.bait_id), 1)
	_flight_local = _terrain.to_local(_tip())
	state = State.CASTING
	_elapsed = 0.0
	_reel_held = false


func _physics_process(delta: float) -> void:
	if _player == null or GameManager.current_state != GameManager.State.PLAYING:
		return
	if is_active() and (not _can_fish() or equipped_rod() != _rod or not is_instance_valid(_terrain)
			or _player.planet != _planet_host):
		cancel()
	if not is_active():
		_update_pose(delta)
		return
	_elapsed += delta
	match state:
		State.CHARGING:
			_charge = minf(_charge + delta, _rod.charge_time)
			_update_target()
		State.CASTING:
			_update_cast()
		State.WAITING, State.BITE:
			_float.position = _target_local
			_float.global_position = _surface_point(_float.global_position)
			_update_bite(delta)
		State.HOOKED, State.REELING:
			_update_reel(delta)
	if not is_active():
		_update_pose(delta)
		return
	if state != State.CASTING and _float.global_position.distance_to(_player.global_position) > _rod.max_distance + 5.0:
		_notify("FISH_TOO_FAR")
		cancel()
		return
	_update_pose(delta)
	_float.present(delta, state == State.CHARGING, _valid_target, state == State.BITE,
		state in [State.HOOKED, State.REELING], state == State.CASTING)
	_float.draw_line(_tip(), state == State.CASTING)
	_update_hud()


func _update_target() -> void:
	var up := (_player.global_position - _terrain.global_position).normalized()
	var forward := (-_player.camera.global_basis.z).slide(up).normalized()
	if forward.length_squared() < 0.01:
		forward = _player.player_model.global_basis.z.slide(up).normalized()
	var projected := _player.global_position + forward * _rod.distance_at(_charge)
	var point := _surface_point(projected)
	_valid_target = _water_at(point)
	# En seco el marcador se apoya sobre el suelo, siempre visible y rojo.
	if not _valid_target:
		var query := PhysicsRayQueryParameters3D.create(point + up * 15.0, point - up * 8.0, PhysicsLayers.WORLD)
		query.exclude = [_player.get_rid()]
		var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			point = hit.position
	_target_local = _terrain.to_local(point)
	_float.global_transform = Transform3D(_surface_frame(point), point)


func _surface_point(point: Vector3) -> Vector3:
	var up := (point - _terrain.global_position).normalized()
	var height := 0.0
	if is_instance_valid(_ocean):
		var material := _ocean.quadtree_material as ShaderMaterial
		_sampler.world_map = _planet_host.get("world_map") as PlanetWorldMap
		height = _sampler.get_height_at(point, WaterHeightSampler.get_water_time(material), _terrain.global_position)
	return _terrain.global_position + up * (_sea_radius + height)


func _surface_frame(point: Vector3) -> Basis:
	var up := (point - _terrain.global_position).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return Basis(right, up, right.cross(up))


func _water_at(point: Vector3) -> bool:
	var up := (point - _terrain.global_position).normalized()
	var tool := _terrain.get_voxel_tool() as VoxelToolLodTerrain
	tool.channel = VoxelBuffer.CHANNEL_SDF
	# El anzuelo necesita agua hasta su profundidad; los vóxeles sin cargar no son agua.
	for depth in [0.0, FishingFloat.HOOK_DEPTH * 0.5, FishingFloat.HOOK_DEPTH + 0.35]:
		if not WaterQuery._has_water(_terrain, tool, _terrain.global_position + up * (_sea_radius - depth)):
			return false
	var query := PhysicsRayQueryParameters3D.create(point + up * 0.3,
		point - up * FishingFloat.HOOK_DEPTH, PhysicsLayers.WORLD)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _update_cast() -> void:
	var t := clampf((_elapsed - CAST_TIME * 0.35) / FLIGHT_TIME, 0.0, 1.0)
	var from := _terrain.to_global(_flight_local)
	var to := _terrain.to_global(_target_local)
	var point := from.lerp(to, t)
	point += (to - _terrain.global_position).normalized() * sin(t * PI) * 3.0
	var previous := _float.global_position if t > 0.0 else from
	# La boya arranca en la mano, no en el marcador del fotograma anterior.
	if _elapsed - CAST_TIME * 0.35 <= get_physics_process_delta_time():
		previous = from
	if t > 0.0:
		var query := PhysicsRayQueryParameters3D.create(previous, point, PhysicsLayers.WORLD)
		query.exclude = [_player.get_rid()]
		if not _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			_notify("FISH_BLOCKED")
			cancel()
			return
	_float.global_transform = Transform3D(_surface_frame(to), point)
	if t >= 1.0:
		if not _water_at(to):
			_notify("FISH_INVALID")
			cancel()
			return
		state = State.WAITING
		_elapsed = 0.0
		_scan_left = 0.0


func _update_bite(delta: float) -> void:
	if not is_instance_valid(_fish):
		_fish = null
	if is_instance_valid(_fish) and (not _fish.active or not _fish.follows_lure(_float.hook)):
		_fish = null
		state = State.WAITING
	_scan_left -= delta
	if _fish == null and _scan_left <= 0.0:
		_scan_left = 0.5
		var best := _rod.attraction_radius * _rod.attraction_radius
		for node in get_tree().get_nodes_in_group(AmbientAnimal.GROUP):
			var fish := node as AmbientFish
			if fish == null or not fish.can_be_fished() or fish.habitat.host() != _terrain:
				continue
			var distance := fish.global_position.distance_squared_to(_float.hook.global_position)
			if distance < best and fish.can_follow_lure(_float.hook):
				best = distance
				_fish = fish
		if _fish != null:
			_fish.follow_lure(_float.hook)
	if _fish == null:
		return
	if _fish.global_position.distance_to(_float.hook.global_position) > BITE_DISTANCE:
		state = State.WAITING
		_elapsed = 0.0
		return
	if state == State.WAITING:
		state = State.BITE
		_elapsed = 0.0
	elif _elapsed >= _rod.bite_time:
		if _rng.randf() < _rod.hook_chance:
			state = State.HOOKED
			_slack_left = _rod.response_time
			_notify("FISH_HOOKED")
		else:
			_notify("FISH_MISSED")
			cancel()


func _update_reel(delta: float) -> void:
	if not is_instance_valid(_fish) or not _fish.active or not _fish.follows_lure(_float.hook):
		_notify("FISH_ESCAPED")
		cancel()
		return
	if _reel_held:
		_slack_left = _rod.response_time
		var to := _surface_point(_player.global_position)
		var next := _surface_point(_float.global_position.move_toward(to, _rod.reel_speed * delta))
		var distance := _float.global_position.distance_to(_player.global_position)
		if distance <= CATCH_DISTANCE and _fish.global_position.distance_to(_float.hook.global_position) < 2.0:
			_land_catch()
			return
		if not _water_at(next):
			# Llegar a la orilla recoge el pez; lejos del jugador sería un obstáculo.
			if distance <= CATCH_DISTANCE + 1.5:
				# Un pez lento aún puede ir detrás de la boya. Mantener el aparejo aquí
				# le deja alcanzar el anzuelo antes de sacarlo, sin arrastrarlo por tierra.
				if _fish.global_position.distance_to(_float.hook.global_position) < 2.0:
					_land_catch()
			else:
				_notify("FISH_BLOCKED")
				cancel()
			return
		# La boya solo recoge lo que el pez ha podido nadar: no lo atraviesa por el terreno.
		if _fish.global_position.distance_to(_float.hook.global_position) < 2.5:
			_float.global_transform = Transform3D(_surface_frame(next), next)
			_target_local = _float.position
	else:
		_slack_left -= delta
		if _slack_left <= 0.0:
			_notify("FISH_ESCAPED")
			cancel()


func _land_catch() -> void:
	var item := ItemCatalog.get_item(_rod.catch_id)
	if item == null:
		cancel()
		return
	# Retirar al pez antes de emitir inventory_changed impide recogerlo dos veces.
	_fish.deactivate()
	_fish = null
	_give_back(item)
	_notify("FISH_CAUGHT")
	cancel()


func cancel() -> void:
	if is_instance_valid(_fish):
		_fish.release_lure()
	_fish = null
	state = State.IDLE
	_reel_held = false
	if is_instance_valid(_float):
		_float.queue_free()
	_float = null
	if _mounted_hook != null:
		var hook := _mounted_hook
		_mounted_hook = null
		_give_back(hook)
	if _hud != null:
		_hud.hide()
		_meter.hide()
	if _player != null and _player.combat != null:
		_player.combat.pose.fishing.weight = 0.0
		var visual := _player.combat.weapon_node() as FishingRodVisual
		if visual != null:
			visual.update_tension(0.0)


func _give_back(item: ItemData) -> void:
	if _player.inventory.add_item(item, 1) > 0:
		DroppedItem.spawn(_player, item, 1, _player.gravity_direction)


func _update_pose(delta: float) -> void:
	var pose := _player.combat.pose.fishing
	pose.weight = move_toward(pose.weight, 1.0 if is_active() else 0.0, delta * 8.0)
	pose.direction = (_float.global_position - _player.global_position).normalized() if is_instance_valid(_float) \
		else _player.player_model.global_basis.z
	pose.cast_phase = clampf(_elapsed / CAST_TIME, 0.0, 1.0) if state == State.CASTING else -1.0
	pose.pull = 0.65 + sin(_elapsed * 14.0) * 0.15 if state in [State.HOOKED, State.REELING] else 0.0
	var visual := _player.combat.weapon_node() as FishingRodVisual
	if visual != null:
		visual.update_tension(pose.pull)


func _tip() -> Vector3:
	var visual := _player.combat.weapon_node() as FishingRodVisual
	return visual.tip_world() if visual != null else _player.global_position - _player.gravity_direction * 1.4


func facing_direction() -> Vector3:
	return (_float.global_position - _player.global_position).slide(-_player.gravity_direction).normalized() \
		if is_instance_valid(_float) else Vector3.ZERO


func _update_hud() -> void:
	_hud.show()
	_meter.visible = state in [State.CHARGING, State.HOOKED, State.REELING]
	match state:
		State.CHARGING:
			_hud.text = tr("FISH_AIM") % _rod.distance_at(_charge) if _valid_target else tr("FISH_INVALID")
			_meter.value = 100.0 * _charge / maxf(_rod.charge_time, 0.01)
		State.CASTING:
			_hud.text = tr("FISH_CASTING")
		State.WAITING, State.BITE:
			_hud.text = tr("FISH_WAITING" if state == State.WAITING else "FISH_NIBBLING")
		State.HOOKED, State.REELING:
			_hud.text = tr("FISH_REEL")
			_meter.value = 100.0 * _slack_left / maxf(_rod.response_time, 0.01)


func _notify(key: String) -> void:
	_player.hotbar.notify(tr(key))


func _exit_tree() -> void:
	# Al cargar o cambiar de escena se recupera la reserva sin dejar una boya huérfana.
	if is_instance_valid(_fish):
		_fish.release_lure()
	if is_instance_valid(_float):
		_float.queue_free()
	# Si solo se retira el componente (el jugador sigue), devolver también el montaje.
	if _mounted_hook != null and is_instance_valid(_player) and _player.is_inside_tree():
		var hook := _mounted_hook
		_mounted_hook = null
		_give_back(hook)
