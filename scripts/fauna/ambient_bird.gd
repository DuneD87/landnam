class_name AmbientBird extends AmbientAnimal

## Tree and ground bird. Flight is steered, not interpolated: the bird carries its speed through
## waypoints, turns at a limited rate while banking into the turn, and only brakes to land. With
## nowhere to land it roams at canopy height and keeps looking, instead of hovering in place.

enum State { TAKEOFF, FLYING, APPROACH, PERCHED }
@export_enum("Aleatorio:-1", "Gorrión:0", "Petirrojo:1", "Herrerillo:2", "Gaviota:3", "Pato:4") var bird_type: int = -1
var state: State = State.FLYING
var _forest: AmbientBirdHabitat
var _settings: AmbientBirdProfile
var _perch: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _audio_rng := RandomNumberGenerator.new()
var _audio_timer: float = 0.0
var _audio_player: AudioStreamPlayer3D
var _goal_local := Vector3.ZERO
var _route_local: Array[Vector3] = []
var _timer: float = 0.0
var _check_timer: float = 0.0
var _time: float = 0.0
var _speed: float = 4.0

## Straight-line acceleration and braking, and the sideways acceleration that bounds the turn
## rate: a fast bird draws wide curves, a slow one pivots.
const ACCELERATION := 9.0
const BRAKING := 7.0
const LATERAL_ACCELERATION := 55.0
## Seconds without covering STALL_DISTANCE before a flying bird gives up on its current goal.
const STALL_TIME := 1.5
const STALL_DISTANCE := 0.5
## Perch searches are the expensive part of a bird (tree meshes, shape queries). Only a few
## birds search in any one physics frame; the rest keep flying and look a moment later.
const SEARCHES_PER_FRAME := 2
## Failed searches in a row before a bird gives up on the area and flies off to be recycled,
## instead of roaming around the player forever where there is nowhere to land.
const SEARCHES_BEFORE_LEAVING := 3
static var _search_frame: int = -1
static var _searches: int = 0

## Wing beat clock: runs faster on takeoff so the wings visibly work harder.
var _wing_time: float = 0.0
var _flapping: bool = true
var _flap_timer: float = 0.0
var _bank: float = 0.0
## Horizontal flight direction last frame, for the turn rate that sets the bank.
var _heading := Vector3.ZERO
## Visual rise and fall of the bounding flight, applied to the model only.
var _bob: float = 0.0
var _bob_speed: float = 0.0
## Resting pose: body yaw on the perch, head-down peck and hop arc (0..1 phases, -1 idle).
var _yaw: float = 0.0
var _yaw_target: float = 0.0
var _idle_timer: float = 0.0
var _peck: float = -1.0
var _hop: float = -1.0
## Personal flush distance multiplier: some birds sit tight, others bolt early.
var _boldness: float = 1.0
## Pending reaction to a neighbour's alarm (seconds; negative = none) and where it came from.
var _alarm_delay: float = -1.0
var _threat := Vector3.ZERO
var _fleeing: bool = false
## Countdown to the next perch search while roaming without one.
var _seek_timer: float = 0.0
var _failed_searches: int = 0
var _leaving: bool = false
var _stall_timer: float = 0.0
var _stall_origin := Vector3.ZERO
@onready var _model: SimpleBirdModel = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


func activate(point: Vector3, environment: AmbientFaunaHabitat, rng: RandomNumberGenerator) -> void:
	super.activate(point, environment, rng)
	_forest = environment as AmbientBirdHabitat
	if _forest == null:
		deactivate()
		return
	_rng.seed = rng.randi()
	_audio_rng.seed = _rng.seed ^ 0xB17D
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	_model.set_species(_rng.randi_range(0, 2) if bird_type < 0 else bird_type)
	_time = _rng.randf_range(0, TAU)
	_wing_time = _time
	_settings = profile as AmbientBirdProfile
	if _settings == null:
		_settings = AmbientBirdProfile.new()
	_speed = AmbientBirdProfile.span(_settings.flight_speed_min, _settings.flight_speed_max, _rng, 0.1)
	_boldness = _rng.randf_range(0.75, 1.3)
	_bank = 0.0
	_heading = Vector3.ZERO
	_bob = 0.0
	_bob_speed = 0.0
	_alarm_delay = -1.0
	_fleeing = false
	_failed_searches = 0
	_leaving = false
	_stop_ambient_audio()
	_audio_timer = _next_audio_interval()
	_collision.disabled = false
	impact_radius = 0.3
	var resting := _forest.claim_spawn_perch(get_instance_id(), point)
	if not resting.is_empty():
		# Spawned already resting, part-way through its stay.
		_land(resting)
		_timer *= _rng.randf_range(0.15, 1.0)
	else:
		_seek_perch()
		# Arrives in full flight rather than starting from a standstill in mid air.
		var ahead := (_forest.terrain.to_global(_goal_local) - global_position).normalized()
		velocity = ahead * _speed * 0.8
	reset_physics_interpolation()


func deactivate() -> void:
	_stop_ambient_audio()
	if _forest != null:
		_forest.release(get_instance_id())
	_perch.clear()
	super.deactivate()
	if is_instance_valid(_collision):
		_collision.disabled = true


func audio_family() -> StringName:
	return &"bird"


func _exit_tree() -> void:
	_stop_ambient_audio()
	if _forest != null:
		_forest.release(get_instance_id())


func startle(point: Vector3) -> void:
	if active and state == State.PERCHED:
		_alarm(point, _rng.randf_range(0.0, 0.25))


## Anochece o migra: despega si está posada y se aleja hasta perderse de vista (_leave).
func retire() -> void:
	if not active or retiring:
		return
	super.retire()
	_leaving = true
	if state == State.PERCHED:
		_takeoff()
	else:
		_leave()


func _alarm(point: Vector3, delay: float) -> void:
	if _alarm_delay >= 0.0 and _alarm_delay <= delay:
		return
	_threat = point
	_alarm_delay = delay


## Plans a flight to a new resting place, or roams when there is none.
func _seek_perch() -> void:
	if not _search_slot():
		# Busy frame: keep flying and look again in a few frames.
		_wander()
		_seek_timer = _rng.randf_range(0.05, 0.3)
		return
	_forest.release(get_instance_id())
	_route_local.clear()
	var near := global_position
	if _fleeing:
		# Settle well away from whatever scared it.
		var up := _forest.up_at(global_position)
		near += (global_position - _threat).slide(up).normalized() * 15.0
	_perch = {}
	if _rng.randf() < _settings.ground_chance:
		_perch = _forest.reserve_ground(get_instance_id(), near, _rng)
	if _perch.is_empty():
		_perch = _forest.reserve(get_instance_id(), near, _rng)
	var route: Array[Vector3] = []
	if not _perch.is_empty():
		route = _forest.flight_route(global_position, _perch)
	if route.is_empty():
		_failed_searches += 1
		if _failed_searches >= SEARCHES_BEFORE_LEAVING:
			_leave()
		else:
			_wander()
		return
	_failed_searches = 0
	var length := 0.0
	var previous := global_position
	for waypoint in route:
		length += previous.distance_to(waypoint)
		previous = waypoint
		_route_local.append(_forest.terrain.to_local(waypoint))
	_goal_local = _route_local.pop_front()
	state = State.FLYING
	_fleeing = false
	_timer = maxf(12.0, length / _speed * 1.5 + 4.0)
	_check_timer = 0
	_reset_stall()


## Leaves the perch. With a [threat] (a position) the bird bolts away from it, climbing hard,
## and warns the birds resting nearby; otherwise it simply launches toward its next stop.
func _takeoff(threat: Variant = null) -> void:
	_forest.release(get_instance_id())
	var was_perched := state == State.PERCHED
	var forward := -(global_basis * Basis(Vector3.UP, _yaw)).z
	_route_local.clear()
	_perch = {}
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	_peck = -1.0
	_hop = -1.0
	_alarm_delay = -1.0
	state = State.TAKEOFF
	_collision.disabled = false
	var up := _forest.up_at(global_position)
	var away := forward.slide(up).normalized()
	_fleeing = threat is Vector3
	if _fleeing:
		_threat = threat
		away = (global_position - _threat).slide(up).normalized()
		if away.is_zero_approx():
			away = forward.slide(up).normalized()
		away = away.rotated(up, _rng.randf_range(-0.6, 0.6))
		if was_perched:
			_warn_neighbours()
	if away.is_zero_approx():
		away = global_basis.x.slide(up).normalized()
	var climb := _rng.randf_range(3.0, 5.0) if _fleeing else _rng.randf_range(1.0, 2.0)
	var reach := _rng.randf_range(6.0, 10.0) if _fleeing else _rng.randf_range(2.0, 4.0)
	var goal := global_position + up * climb + away * reach
	var nose := global_position + up * 0.2
	if not _forest.path_clear(nose, goal + up * 0.2):
		# Boxed in by branches: straight up and out through the gap it came in by.
		goal = global_position + up * climb + away * 0.5
	_goal_local = _forest.terrain.to_local(goal)
	_timer = _rng.randf_range(0.9, 1.5) if _fleeing else _rng.randf_range(0.35, 0.6)
	# The first wingbeats throw the bird up and out, rather than accelerating from a hover.
	velocity = (up * 0.7 + away * 0.7).normalized() * _speed * (0.6 if _fleeing else 0.35)
	_flapping = true
	_flap_timer = _rng.randf_range(0.6, 1.0)
	_check_timer = 0
	_reset_stall()


## Whether this bird may run an expensive perch search in the current physics frame.
func _search_slot() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _search_frame:
		_search_frame = frame
		_searches = 0
	if _searches >= SEARCHES_PER_FRAME:
		return false
	_searches += 1
	return true


## Nowhere to land around here: fly off away from the observer, and back to the pool once
## far away and out of sight.
func _leave() -> void:
	_leaving = true
	_wander()


func _out_of_sight() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	for plane in camera.get_frustum():
		if plane.distance_to(global_position) > 1.0:
			return true
	return false


func _warn_neighbours() -> void:
	if _settings.alarm_radius <= 0.0:
		return
	var reach := _settings.alarm_radius * _settings.alarm_radius
	for node in get_tree().get_nodes_in_group(GROUP):
		var bird := node as AmbientBird
		if bird == null or bird == self or not bird.active or bird._forest != _forest:
			continue
		if bird.state == State.PERCHED and bird.global_position.distance_squared_to(global_position) < reach:
			# Chained reactions ripple out through the flock over a fraction of a second.
			bird._alarm(_threat, _rng.randf_range(0.08, 0.45))


## Roams at canopy height without a destination, checking for a perch every few seconds.
func _wander() -> void:
	_forest.release(get_instance_id())
	_perch = {}
	_route_local.clear()
	state = State.FLYING
	# Each failed search waits longer before the next one.
	_seek_timer = INF if _leaving else _rng.randf_range(1.2, 2.5) * (1 + _failed_searches)
	_timer = INF
	_pick_wander_goal()
	_check_timer = 0.2
	_reset_stall()


func _pick_wander_goal() -> void:
	var up := _forest.up_at(global_position)
	var heading := velocity.slide(up).normalized()
	if heading.is_zero_approx():
		heading = (-global_basis.z).slide(up).normalized()
	if heading.is_zero_approx():
		heading = global_basis.x.slide(up).normalized()
	# Drift back toward the observer before leaving the populated area, unless it is leaving.
	var home := (_forest.observer.global_position - global_position).slide(up)
	if _leaving and not home.is_zero_approx():
		heading = heading.slerp(-home.normalized(), 0.6).normalized()
	elif home.length() > profile.spawn_radius * 0.7:
		heading = heading.slerp(home.normalized(), 0.6).normalized()
	var nose := global_position + up * 0.2
	for angle in [_rng.randf_range(-40.0, 40.0), 70.0, -70.0, 120.0, -120.0, 180.0]:
		var direction := heading.rotated(up, deg_to_rad(angle))
		var target := global_position + direction * _rng.randf_range(10.0, 20.0)
		var hit := _forest.ground_below(target)
		if not hit.is_empty():
			target = (hit.position as Vector3) + up * _rng.randf_range(4.0, 9.0)
		if _forest.path_clear(nose, target + up * 0.2):
			_goal_local = _forest.terrain.to_local(target)
			return
	_goal_local = _forest.terrain.to_local(global_position + up * 4.0 - heading * 2.0)


func _land(perch: Dictionary) -> void:
	_perch = perch
	state = State.PERCHED
	_fleeing = false
	_failed_searches = 0
	velocity = Vector3.ZERO
	global_position = perch.point
	global_basis = perch.basis
	_collision.disabled = true
	_bank = 0.0
	_bob = 0.0
	_bob_speed = 0.0
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	# Branch birds sit across the branch, facing either side; ground birds face anywhere.
	_yaw = (PI if _rng.randf() < 0.5 else 0.0) if not perch.get("ground", false) else 0.0
	_yaw_target = _yaw
	_idle_timer = _rng.randf_range(0.3, 1.0)
	_peck = -1.0
	_hop = -1.0
	_alarm_delay = -1.0
	if _rng.randf() < _settings.long_rest_chance:
		_timer = AmbientBirdProfile.span(_settings.long_rest_time_min, _settings.long_rest_time_max, _rng)
	else:
		_timer = AmbientBirdProfile.span(_settings.perch_time_min, _settings.perch_time_max, _rng)


func _physics_process(delta: float) -> void:
	if not active or GameManager.current_state != GameManager.State.PLAYING:
		_stop_ambient_audio()
		return
	var start := Time.get_ticks_usec()
	_step(delta)
	_update_ambient_audio(delta)
	DebugStats.report_cost(&"fauna:birds", Time.get_ticks_usec() - start)


func _next_audio_interval() -> float:
	return AmbientBirdProfile.span(_settings.ambient_interval_min, _settings.ambient_interval_max, _audio_rng, 0.1)


func _stop_ambient_audio() -> void:
	if is_instance_valid(_audio_player):
		AudioManager.stop_source_voice(_audio_player, get_instance_id())
	_audio_player = null


func _update_ambient_audio(delta: float) -> void:
	if not _settings.ambient_audio_enabled or _settings.ambient_sound == null:
		_stop_ambient_audio()
		return
	if is_instance_valid(_audio_player) and _audio_player.playing and _audio_player.get_meta(&"source_id", 0) == get_instance_id():
		_audio_player.global_position = global_position
		return
	_audio_player = null
	# Let an existing call finish naturally if the bird takes off mid-recording.
	if _settings.ambient_only_perched and state != State.PERCHED:
		return
	_audio_timer -= delta
	if _audio_timer > 0.0:
		return
	_audio_timer = _next_audio_interval()
	_audio_player = AudioManager.play_event_3d(_settings.ambient_sound, global_position, {"source_id": get_instance_id()})


## Distance at which the observer flushes this bird: farther when the observer moves fast.
func _flush_distance() -> float:
	var hurry := clampf(_forest.observer_speed() / 6.0, 0.0, 1.0)
	return lerpf(_settings.flush_distance_min, _settings.flush_distance_max, hurry) * _boldness


func _step(delta: float) -> void:
	_time += delta
	_timer -= delta
	var perched := state == State.PERCHED
	_update_wings(delta)
	# A perched bird has no collider, so only a flying one can be swept by a hull.
	if not _collision.disabled and _check_moving_ships(delta):
		return
	var up := _forest.up_at(global_position)
	if not _perch.is_empty():
		var current := _forest.resolve(_perch)
		if current.is_empty():
			_takeoff()
			return
		_perch = current
	if perched:
		_rest_step(delta)
		return
	_stall_timer -= delta
	if _stall_timer <= 0.0:
		if global_position.distance_to(_stall_origin) < STALL_DISTANCE:
			# Pinned against something, or circling a goal it cannot reach: pick a new one.
			velocity += up * 2.0
			_wander()
			return
		_reset_stall()
	if state == State.TAKEOFF:
		if _timer <= 0.0:
			if _leaving:
				_leave()
			else:
				_seek_perch()
			return
	elif state == State.FLYING and _perch.is_empty():
		if _leaving:
			if global_position.distance_to(_forest.observer.global_position) > profile.spawn_radius and _out_of_sight():
				deactivate()
				return
		_seek_timer -= delta
		if _seek_timer <= 0.0:
			_seek_perch()
			if _perch.is_empty():
				return
	elif _timer <= 0.0:
		_seek_perch()
		return
	var goal := _forest.terrain.to_global(_goal_local)
	if state == State.APPROACH:
		goal = _perch.point
	var distance := global_position.distance_to(goal)
	var speed := velocity.length()
	if state != State.APPROACH and distance < maxf(0.6, speed * 0.25):
		if state == State.TAKEOFF:
			_seek_perch()
		elif not _route_local.is_empty():
			_goal_local = _route_local.pop_front()
		elif not _perch.is_empty():
			state = State.APPROACH
			# Keeps counting down on a retry, so a blocked approach ends in a new plan.
			_timer = minf(_timer, 6.0)
		else:
			_pick_wander_goal()
		return
	if state == State.APPROACH and distance < 0.12:
		_land(_perch)
		return
	var direction := (goal - global_position).normalized()
	_check_timer -= delta
	if _check_timer <= 0 and not (state == State.APPROACH and distance < 0.6):
		_check_timer = 0.20
		var nose := global_position + up * 0.20
		var lookahead := maxf(1.0, speed * 0.25)
		if not _forest.path_clear(nose, nose + direction * minf(distance, lookahead)):
			_avoid(direction, up)
			return
	var cruise := _speed * (1.15 if _fleeing else 1.0)
	var target_speed := cruise
	if not _perch.is_empty() and _route_local.is_empty():
		# Braking distance for the rest of the way in, so the bird neither stops at the
		# approach point nor overshoots the branch.
		var remaining := distance
		if state == State.FLYING:
			remaining += (goal as Vector3).distance_to(_perch.point)
		target_speed = minf(cruise, maxf(0.6, sqrt(2.0 * BRAKING * remaining)))
	if state == State.APPROACH and distance < 0.5:
		# Last flutter onto the perch: direct, so a tight turn cannot orbit the branch.
		velocity = velocity.lerp(direction * maxf(0.3, distance * 2.5), 1.0 - exp(-delta * 8.0))
	else:
		_steer(direction, target_speed, up, delta)
	var incoming_velocity := velocity
	move_and_slide()
	for index in get_slide_collision_count():
		if _resolve_ship_hit(get_slide_collision(index), incoming_velocity):
			return
	if get_slide_collision_count() > 0:
		if state == State.APPROACH and global_position.distance_to(_perch.point) < 0.3:
			_land(_perch)
			return
		var normal := get_slide_collision(0).get_normal()
		velocity = velocity.slide(normal) + normal * 2.0 + up
		_check_timer = 0.0
	_orient(up, delta)


## Turns the velocity toward [direction] at a rate bounded by the speed, and eases the speed
## toward [target_speed]. Sharp turns cost speed, which tightens them instead of orbiting.
func _steer(direction: Vector3, target_speed: float, up: Vector3, delta: float) -> void:
	var speed := velocity.length()
	var current := velocity / speed if speed > 0.3 else direction
	var angle := current.angle_to(direction)
	target_speed *= lerpf(1.0, 0.4, smoothstep(0.6, 2.2, angle))
	var rate := ACCELERATION if target_speed > speed else BRAKING
	speed = move_toward(speed, target_speed, rate * delta)
	var max_turn := clampf(LATERAL_ACCELERATION / maxf(speed, 0.1), 3.0, 14.0) * delta
	var heading := direction
	if angle > max_turn:
		if angle > 3.0:
			# Straight behind: slerp has no preferred side, so turn about the vertical.
			heading = current.rotated(up, max_turn)
		else:
			heading = current.slerp(direction, max_turn / angle).normalized()
	velocity = heading * speed


## Something is in the way of the current leg: slip over or around it, then resume.
func _avoid(direction: Vector3, up: Vector3) -> void:
	if state == State.TAKEOFF:
		_seek_perch()
		return
	if state == State.APPROACH:
		# Circle back out to the approach point and come in again.
		state = State.FLYING
		return
	var side := direction.cross(up).normalized()
	var nose := global_position + up * 0.2
	for offset in [up * 3.0 + direction * 1.5, up * 2.5 + side * 3.0, up * 2.5 - side * 3.0, up * 4.0 - direction * 2.0]:
		var detour: Vector3 = global_position + offset
		if _forest.path_clear(nose, detour + up * 0.2):
			if not _perch.is_empty():
				_route_local.push_front(_goal_local)
			_goal_local = _forest.terrain.to_local(detour)
			return
	if _perch.is_empty():
		_pick_wander_goal()
	else:
		_seek_perch()


func _reset_stall() -> void:
	_stall_timer = STALL_TIME
	_stall_origin = global_position


## Body attitude from the velocity: pitch limited to what a bird holds, bank from the turn rate.
func _orient(up: Vector3, delta: float) -> void:
	var horizontal := velocity.slide(up)
	if horizontal.length_squared() < 0.01:
		return
	var heading := horizontal.normalized()
	var previous := _heading.slide(up).normalized()
	_heading = heading
	if previous.is_zero_approx():
		previous = heading
	var pitch := clampf(atan2(velocity.dot(up), horizontal.length()), -0.6, 0.7)
	var forward := heading * cos(pitch) + up * sin(pitch)
	global_basis = global_basis.slerp(Basis.looking_at(forward, up), 1.0 - exp(-delta * 10.0)).orthonormalized()
	# Positive yaw rate is a left turn, which lowers the left wing (positive roll).
	var yaw_rate := atan2(up.dot(previous.cross(heading)), previous.dot(heading)) / maxf(delta, 0.001)
	var bank := clampf(atan(yaw_rate * horizontal.length() / 9.8), -1.1, 1.1)
	_bank = lerpf(_bank, bank, 1.0 - exp(-delta * 6.0))


## Flap bursts and glides, and the model's bank and bounding bob.
func _update_wings(delta: float) -> void:
	if state == State.PERCHED:
		_wing_time += delta
		_model.animate(_wing_time, false, delta)
		return
	var up := _forest.up_at(global_position)
	var climbing := velocity.dot(up) > 0.3 * maxf(velocity.length(), 0.1)
	var slow := velocity.length() < _speed * 0.6
	_flap_timer -= delta
	if _flap_timer <= 0.0:
		_flapping = not _flapping or _settings.glide_max <= 0.0
		_flap_timer = AmbientBirdProfile.span(_settings.flap_burst_min, _settings.flap_burst_max, _rng, 0.05) if _flapping \
			else AmbientBirdProfile.span(_settings.glide_min, _settings.glide_max, _rng, 0.05)
	# Takeoffs, climbs, landings and slow flight always need the wings.
	var flap := 1.0 if _flapping or state != State.FLYING or climbing or slow else 0.0
	_wing_time += delta * (1.3 if state == State.TAKEOFF else 1.0)
	_model.animate(_wing_time, true, delta, flap)
	if not _model.soars():
		# Bounding flight: rises on each burst, sinks with the wings shut.
		_bob_speed += (1.5 if flap > 0.5 else -2.5) * delta
		_bob_speed = clampf(_bob_speed, -0.6, 0.4)
		_bob = clampf(_bob + _bob_speed * delta, -0.2, 0.08)
		if _bob <= -0.2 or _bob >= 0.08:
			_bob_speed = 0.0
	else:
		_bob = move_toward(_bob, 0.0, delta)
	_model.position = Vector3.UP * _bob
	_model.rotation = Vector3(0.0, 0.0, _bank)


func _rest_step(delta: float) -> void:
	global_position = _perch.point
	global_basis = _perch.basis
	_idle(delta)
	if _alarm_delay >= 0.0:
		_alarm_delay -= delta
		if _alarm_delay < 0.0:
			_takeoff(_threat)
			return
	var observer := _forest.observer.global_position
	if global_position.distance_to(observer) < _flush_distance():
		_takeoff(observer)
		return
	if _timer <= 0:
		_takeoff()


## Resting fidgets: quick head and body turns, and pecking and hopping on the ground.
func _idle(delta: float) -> void:
	var ground: bool = _perch.get("ground", false)
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = _rng.randf_range(0.35, 1.6)
		var roll := _rng.randf()
		if ground and roll < 0.5:
			_peck = 0.0
		elif ground and roll < 0.75:
			_start_hop()
		elif not ground and roll < 0.12:
			_yaw_target = wrapf(_yaw_target + PI, -PI, PI) # turns round on the branch
		else:
			var centre := _yaw if ground else (PI if absf(_yaw) > PI * 0.5 else 0.0)
			_yaw_target = centre + _rng.randf_range(-0.5, 0.5)
	_yaw = wrapf(lerp_angle(_yaw, _yaw_target, 1.0 - exp(-delta * 14.0)), -PI, PI)
	var pitch := 0.0
	if _peck >= 0.0:
		_peck += delta / 0.28
		pitch = -sin(minf(_peck, 1.0) * PI) * 0.55
		if _peck >= 1.0:
			_peck = -1.0
	var lift := 0.0
	if _hop >= 0.0:
		_hop += delta / 0.2
		lift = sin(minf(_hop, 1.0) * PI) * 0.07
		if _hop >= 1.0:
			_hop = -1.0
	_model.rotation = Vector3(pitch, _yaw, 0.0)
	_model.position = Vector3.UP * lift


func _start_hop() -> void:
	var facing := (_perch.basis as Basis) * Vector3(0, 0, -1).rotated(Vector3.UP, _yaw)
	var turn := _rng.randf_range(-0.9, 0.9)
	var offset := facing.rotated(_perch.up, turn) * _rng.randf_range(0.12, 0.3)
	var moved := _forest.hop(_perch, offset)
	if moved.is_empty():
		_yaw_target = _yaw + PI * 0.6 * signf(turn)
		return
	_perch = moved
	_yaw_target = _yaw + turn
	_hop = 0.0


func _corpse_model() -> Node3D:
	return _model


func _up() -> Vector3:
	return _forest.up_at(global_position) if _forest != null else Vector3.ZERO
