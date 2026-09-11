class_name AmbientBird extends AmbientAnimal

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
	_model.set_species(_rng.randi_range(0, 2) if bird_type < 0 else bird_type)
	_time = _rng.randf_range(0, TAU)
	_settings = profile as AmbientBirdProfile
	if _settings == null:
		_settings = AmbientBirdProfile.new()
	var minimum := maxf(0.1, minf(_settings.flight_speed_min, _settings.flight_speed_max))
	var maximum := maxf(minimum, maxf(_settings.flight_speed_min, _settings.flight_speed_max))
	_speed = _rng.randf_range(minimum, maximum)
	_stop_ambient_audio()
	_audio_timer = _next_audio_interval()
	_collision.disabled = false
	_seek_perch()
	reset_physics_interpolation()


func deactivate() -> void:
	_stop_ambient_audio()
	if _forest != null:
		_forest.release(get_instance_id())
	_perch.clear()
	super.deactivate()
	if is_instance_valid(_collision):
		_collision.disabled = true


func _exit_tree() -> void:
	_stop_ambient_audio()
	if _forest != null:
		_forest.release(get_instance_id())


func _seek_perch() -> void:
	_forest.release(get_instance_id())
	_route_local.clear()
	_perch = _forest.reserve(get_instance_id(), global_position, _rng)
	if _perch.is_empty():
		_takeoff()
		return
	var route := _forest.flight_route(global_position, _perch)
	if route.is_empty():
		_takeoff()
		return
	var length := 0.0
	var previous := global_position
	for waypoint in route:
		length += previous.distance_to(waypoint)
		previous = waypoint
		_route_local.append(_forest.terrain.to_local(waypoint))
	_goal_local = _route_local.pop_front()
	state = State.FLYING
	_timer = maxf(12.0, length / _speed + 4.0)
	_check_timer = 0


func _takeoff() -> void:
	_forest.release(get_instance_id())
	_route_local.clear()
	_model.rotation.y = 0
	_perch = {}
	state = State.TAKEOFF
	_collision.disabled = false
	var up := _forest.up_at(global_position)
	var away := (global_position - _forest.observer.global_position).slide(up).normalized()
	if away.is_zero_approx():
		away = global_basis.x
	_goal_local = _forest.terrain.to_local(global_position + up * 2.5 + away * 4.0)
	_timer = 2.0
	_check_timer = 0


func _physics_process(delta: float) -> void:
	if not active or GameManager.current_state != GameManager.State.PLAYING:
		_stop_ambient_audio()
		return
	var start := Time.get_ticks_usec()
	_step(delta)
	_update_ambient_audio(delta)
	DebugStats.report_cost(&"fauna:birds", Time.get_ticks_usec() - start)


func _next_audio_interval() -> float:
	var minimum := maxf(0.1, minf(_settings.ambient_interval_min, _settings.ambient_interval_max))
	var maximum := maxf(minimum, maxf(_settings.ambient_interval_min, _settings.ambient_interval_max))
	return _audio_rng.randf_range(minimum, maximum)


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


func _step(delta: float) -> void:
	_time += delta
	_timer -= delta
	_model.animate(_time, state != State.PERCHED, delta)
	var up := _forest.up_at(global_position)
	if not _perch.is_empty():
		var current := _forest.resolve(_perch)
		if current.is_empty():
			_takeoff()
			return
		_perch = current
	if state == State.PERCHED:
		global_position = _perch.point
		global_basis = _perch.basis
		_model.rotation.y = sin(_time * 0.75) * 0.12
		if _timer <= 0 or global_position.distance_to(_forest.observer.global_position) < 4.0:
			_model.rotation.y = 0
			_takeoff()
		return
	if _timer <= 0:
		_seek_perch()
		return
	var goal := _forest.terrain.to_global(_goal_local)
	if state == State.APPROACH:
		goal = _perch.point
	var distance := global_position.distance_to(goal)
	if state == State.FLYING and distance < 0.35:
		if not _route_local.is_empty():
			_goal_local = _route_local.pop_front()
			return
		state = State.APPROACH
		_timer = 5.0
		return
	if state == State.APPROACH and distance < 0.12:
		state = State.PERCHED
		velocity = Vector3.ZERO
		global_position = _perch.point
		global_basis = _perch.basis
		_collision.disabled = true
		var minimum := maxf(0.0, minf(_settings.perch_time_min, _settings.perch_time_max))
		var maximum := maxf(minimum, maxf(_settings.perch_time_min, _settings.perch_time_max))
		_timer = _rng.randf_range(minimum, maximum)
		return
	_check_timer -= delta
	var direction := (goal - global_position).normalized()
	if _check_timer <= 0:
		_check_timer = 0.20
		var nose := global_position + up * 0.20
		var lookahead := maxf(1.0, velocity.length() * 0.25)
		if not _forest.path_clear(nose, nose + direction * minf(distance, lookahead)):
			_takeoff()
			velocity = up * 2.0
			return
	# Brake before waypoints as well as landing, so faster cruise speeds do not
	# overshoot the ascent route or orbit the final approach point.
	var speed := minf(_speed, maxf(0.3, distance * 2.5))
	velocity = velocity.lerp(direction * speed, 1.0 - exp(-delta * 6.0))
	move_and_slide()
	if get_slide_collision_count() > 0:
		_takeoff()
		velocity = get_slide_collision(0).get_normal() * 2.0 + up
	if velocity.length_squared() > 0.02 and absf(velocity.normalized().dot(up)) < 0.98:
		global_basis = global_basis.slerp(Basis.looking_at(velocity.normalized(), up), 1.0 - exp(-delta * 6.0)).orthonormalized()
