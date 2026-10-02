class_name AmbientWaterBird extends AmbientBird

var _cruising := false
var _cruise_remaining := 0.0
var _cruise_distance := 0.0
var _cruise_height := 0.0
var _turn_sign := 1.0
var _goal_valid := false


func _seek_perch() -> void:
	# Spawn and failed approaches start a flight, rather than immediately landing.
	_start_cruise()


func _takeoff(threat: Variant = null) -> void:
	if threat is Vector3 and state == State.PERCHED:
		# The whole raft goes up together, and the first leg heads away from the threat.
		_threat = threat
		_warn_neighbours()
		var up := _forest.up_at(global_position)
		var away := (global_position - _threat).slide(up).normalized()
		if not away.is_zero_approx():
			velocity = (away + up).normalized() * _speed * 0.5
	_start_cruise()


func _idle(_delta: float) -> void:
	# Afloat, the body follows the swimming direction; only a gentle sway on the water.
	_model.rotation = Vector3(0.0, sin(_time * 0.75) * 0.12, 0.0)
	_model.position = Vector3.ZERO


## Water birds roam by cruising: broad legs over the water instead of canopy hops.
func _wander() -> void:
	_start_cruise()


## Their landing search is a handful of water probes, cheap enough to skip the frame budget,
## and a failed one simply means another cruise.
func _search_slot() -> bool:
	return true


func _leave() -> void:
	_start_cruise()


func deactivate() -> void:
	_cruising = false
	super.deactivate()


func _start_cruise() -> void:
	var water := _forest as WaterBirdHabitat
	if water == null:
		return
	water.release(get_instance_id())
	_perch = {}
	_route_local.clear()
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	_collision.disabled = false
	state = State.FLYING
	_cruising = true
	_cruise_distance = 0.0
	var settings := water.settings
	_cruise_remaining = _rng.randf_range(maxf(0.0, minf(settings.flight_time_min, settings.flight_time_max)),
		maxf(0.0, maxf(settings.flight_time_min, settings.flight_time_max)))
	_cruise_height = _rng.randf_range(minf(settings.flight_height_min, settings.flight_height_max),
		maxf(settings.flight_height_min, settings.flight_height_max))
	_turn_sign = -1.0 if _rng.randf() < 0.5 else 1.0
	_check_timer = 0.0
	_flapping = true
	_flap_timer = _rng.randf_range(0.8, 1.5)
	_reset_stall()
	_choose_cruise_goal(water)


func _choose_cruise_goal(water: WaterBirdHabitat) -> void:
	var up := water.up_at(global_position)
	var heading := velocity.slide(up).normalized()
	if heading.is_zero_approx():
		heading = (-global_basis.z).slide(up).normalized()
	if heading.is_zero_approx():
		heading = global_basis.x.slide(up).normalized()
	var home := (water.observer.global_position - global_position).slide(up)
	var radius := maxf(profile.recycle_distance, profile.spawn_radius + 5.0) * 0.8
	if _leaving:
		# Se va (retire): rumbo contrario al observador y sin el límite de la zona poblada.
		if not home.is_zero_approx():
			heading = -home.normalized()
		radius = INF
	elif home.length() > radius * 0.7:
		heading = home.normalized()
	_goal_valid = false
	# Linked waypoints make broad turns inside the population area. Keep moving
	# through them; only the final water approach uses the base bird's braking.
	for angle in [30.0, 0.0, -30.0, 60.0, -60.0, 100.0, -100.0, 150.0, 180.0]:
		var direction := heading.rotated(up, deg_to_rad(angle * _turn_sign))
		var target := water.surface_point(global_position + direction * maxf(18.0, _speed * 2.5))
		target += water.up_at(target) * _cruise_height
		if target.distance_to(water.observer.global_position) > radius:
			continue
		if water.point_free(target, profile.clearance) and water.path_clear(global_position + up * 0.2, target):
			_goal_local = water.terrain.to_local(target)
			_goal_valid = true
			return
	# A narrow river or a nearby hull can obstruct every long leg. Rise to clear
	# it, retry at a bounded rate, and never interpret waiting as distance flown.
	var rise := global_position + up * 3.0
	if rise.distance_to(water.terrain.global_position) <= water._water.surface_radius(rise) + maxf(water.settings.flight_height_max, 3.0) + 3.0:
		if water.point_free(rise, profile.clearance) and water.path_clear(global_position, rise):
			_goal_local = water.terrain.to_local(rise)
			_goal_valid = true


func _step(delta: float) -> void:
	var water := _forest as WaterBirdHabitat
	if water == null:
		return
	if _cruising:
		_cruise_step(water, delta)
		return
	if state == State.PERCHED and not _perch.is_empty():
		water.drift(_perch, delta)
	super._step(delta)


func _cruise_step(water: WaterBirdHabitat, delta: float) -> void:
	_time += delta
	_cruise_remaining -= delta
	_update_wings(delta)
	# Gulls cruise low over the shipping lanes: a hull can catch one in mid air.
	if not _collision.disabled and _check_moving_ships(delta):
		return
	if _leaving:
		# Sin posarse: vuelve al pool en cuanto está lejos y fuera de cámara.
		if global_position.distance_to(water.observer.global_position) > profile.spawn_radius and _out_of_sight():
			deactivate()
			return
	elif _cruise_remaining <= 0.0 and _cruise_distance >= water.settings.flight_distance_min:
		_cruising = false
		super._seek_perch()
		return
	var up := water.up_at(global_position)
	var goal := water.terrain.to_global(_goal_local)
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.2
		var nose := global_position + up * 0.2
		var direction := (goal - global_position).normalized()
		if not _goal_valid or global_position.distance_to(goal) < maxf(3.0, _speed * 0.6) or not water.path_clear(nose, nose + direction * maxf(2.0, _speed * 0.4)):
			_choose_cruise_goal(water)
			goal = water.terrain.to_global(_goal_local)
	var heading := (goal - global_position).normalized()
	if not _goal_valid:
		# No open leg right now: hold altitude in a wide turn instead of stalling in mid air.
		heading = velocity.slide(up).normalized()
		if heading.is_zero_approx():
			heading = (-global_basis.z).slide(up).normalized()
		heading = heading.rotated(up, deg_to_rad(35.0) * _turn_sign)
	_steer(heading, _speed, up, delta)
	var before := global_position
	var incoming_velocity := velocity
	move_and_slide()
	for index in get_slide_collision_count():
		if _resolve_ship_hit(get_slide_collision(index), incoming_velocity):
			return
	_cruise_distance += (global_position - before).slide(up).length()
	if get_slide_collision_count() > 0:
		_goal_valid = false
		var normal := get_slide_collision(0).get_normal()
		velocity = velocity.slide(normal) + normal * 2.0 + up * 2.0
	_orient(up, delta)


## Afloat it would sink: no corpse on the water, only blood.
func _corpse_model() -> Node3D:
	return null if state == State.PERCHED else _model
