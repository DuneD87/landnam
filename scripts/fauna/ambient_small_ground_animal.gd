class_name AmbientSmallGroundAnimal extends AmbientAnimal

enum State { IDLE, WANDER, FLEE }
var state: State = State.IDLE
var _ground: SmallGroundFaunaHabitat
var _settings: SmallGroundFaunaProfile
var _rng := RandomNumberGenerator.new()
var _goal_local := Vector3.ZERO
var _timer: float = 0.0
var _decision_timer: float = 0.0
var _time: float = 0.0
var _hop_timer: float = 0.0
var _size: float = 1.0
@onready var _model: SimpleSmallAnimalModel = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


func activate(point: Vector3, environment: AmbientFaunaHabitat, rng: RandomNumberGenerator) -> void:
	super.activate(point, environment, rng)
	_ground = environment as SmallGroundFaunaHabitat
	_settings = profile as SmallGroundFaunaProfile
	if _ground == null or _settings == null:
		deactivate()
		return
	_rng.seed = rng.randi()
	_size = _rng.randf_range(0.85, 1.1)
	_model.set_species(_settings.species)
	_model.scale = Vector3.ONE * _size
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_model.animate(0.0, 0.0)
	var shape := CapsuleShape3D.new()
	shape.radius = SimpleSmallAnimalModel.RADII[_settings.species] * _size
	shape.height = SimpleSmallAnimalModel.HEIGHTS[_settings.species] * _size
	_collision.shape = shape
	_collision.position = Vector3.UP * shape.height * 0.5
	_collision.disabled = false
	impact_radius = _settings.clearance
	up_direction = _ground.up_at(point)
	var forward := up_direction.cross(Vector3.RIGHT if absf(up_direction.x) < 0.9 else Vector3.FORWARD).normalized()
	global_basis = Basis.looking_at(forward.rotated(up_direction, _rng.randf_range(0, TAU)), up_direction)
	floor_max_angle = deg_to_rad(_settings.max_slope_degrees)
	_goal_local = _ground.terrain.to_local(point)
	state = State.IDLE
	_timer = _rng.randf_range(0.5, 2.0)
	_decision_timer = 0.0
	_time = _rng.randf_range(0, TAU)
	_hop_timer = 0.0
	reset_physics_interpolation()


func deactivate() -> void:
	super.deactivate()
	if is_instance_valid(_collision):
		_collision.disabled = true


func _physics_process(delta: float) -> void:
	if not active or GameManager.current_state != GameManager.State.PLAYING:
		return
	var start := Time.get_ticks_usec()
	_step(delta)
	DebugStats.report_cost(&"fauna:small_ground", Time.get_ticks_usec() - start)


func _step(delta: float) -> void:
	if not is_instance_valid(_ground.terrain):
		deactivate()
		return
	up_direction = _ground.up_at(global_position)
	_timer -= delta
	_decision_timer -= delta
	_hop_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = 0.15
		# Remove instead of falling through a terrain chunk whose collider unloaded.
		if _ground.ground_at(global_position, 3.0, _settings).is_empty():
			deactivate()
			return
		_decide()
	if _check_moving_ships(delta):
		return
	var direction := (_ground.terrain.to_global(_goal_local) - global_position).slide(up_direction)
	var speed := 0.0 if state == State.IDLE else (_settings.flee_speed if state == State.FLEE else _settings.walk_speed)
	if direction.length() < 0.25:
		speed = 0.0
	var horizontal := velocity.slide(up_direction).move_toward(direction.normalized() * speed, delta * 16.0)
	var vertical := velocity.dot(up_direction)
	if is_on_floor():
		vertical = 0.0
		if SimpleSmallAnimalModel.BASE[_settings.species] == 0 and speed > 0.1 and _hop_timer <= 0.0:
			vertical = 2.4 if state == State.FLEE else 1.6
			_hop_timer = 0.48 if state == State.FLEE else 0.65
	vertical -= 12.0 * delta
	velocity = horizontal + up_direction * vertical
	var incoming := velocity
	move_and_slide()
	for index in get_slide_collision_count():
		if _resolve_ship_hit(get_slide_collision(index), incoming):
			return
	var facing := -global_basis.z.slide(up_direction).normalized()
	var turn := 0.0
	if horizontal.length() > 0.1:
		turn = facing.cross(horizontal.normalized()).dot(up_direction)
		facing = facing.lerp(horizontal.normalized(), 1.0 - exp(-delta * 10.0)).normalized()
	if not facing.is_zero_approx():
		global_basis = Basis.looking_at(facing, up_direction)
	var actual_speed := get_real_velocity().slide(up_direction).length()
	_time += delta
	_model.advance(delta, actual_speed / _size, is_on_floor(), velocity.dot(up_direction), turn)


func _decide() -> void:
	var away := Vector3.ZERO
	if is_instance_valid(_ground.observer):
		away = global_position - _ground.observer.global_position
		if away.length() < _settings.flee_distance:
			state = State.FLEE
			_timer = 1.8
			_choose_goal(away.slide(up_direction).normalized())
			return
	var direction := (_ground.terrain.to_global(_goal_local) - global_position).slide(up_direction)
	if state != State.IDLE and direction.length() > 0.25:
		var lookahead := maxf(0.45, velocity.slide(up_direction).length() * 0.25)
		if not _ground.can_step(global_position, global_position + direction.normalized() * lookahead, _settings):
			state = State.IDLE
			_timer = 0.3
			velocity = up_direction * velocity.dot(up_direction)
			return
	if _timer > 0.0 and (state == State.IDLE or direction.length() > 0.25):
		return
	if state != State.IDLE:
		state = State.IDLE
		_timer = _rng.randf_range(1.0, 3.5)
	else:
		state = State.WANDER
		_timer = _rng.randf_range(2.0, 5.0)
		_choose_goal((-global_basis.z).rotated(up_direction, _rng.randf_range(-PI, PI)))


func _choose_goal(direction: Vector3) -> void:
	if direction.is_zero_approx():
		direction = -global_basis.z
	var distance := _settings.wander_distance
	for angle in [0.0, 0.65, -0.65, 1.3, -1.3]:
		var heading := direction.rotated(up_direction, angle)
		var lookahead := maxf(0.65, _settings.flee_speed * 0.25)
		if _ground.can_step(global_position, global_position + heading * lookahead, _settings):
			_goal_local = _ground.terrain.to_local(global_position + heading * distance)
			return
	state = State.IDLE
	_timer = 0.3
	_goal_local = _ground.terrain.to_local(global_position)
	velocity = up_direction * velocity.dot(up_direction)


func _corpse_model() -> Node3D:
	return _model


func _up() -> Vector3:
	return up_direction
