class_name AmbientSmallGroundAnimal extends AmbientAnimal

enum State { IDLE, WANDER, FLEE }
## Lo que huye cada vez que se asusta (s), si el observador no sigue encima.
const FLEE_TIME := 1.8
## Hasta dónde busca el suelo por encima de los pies si se ha hundido (m), y lo que tolera hundido.
const SINK_PROBE := 0.6
const SINK_TOLERANCE := 0.06
## Lo rápido que el modelo sigue la inclinación del suelo (1/s).
const TILT_RATE := 8.0
var state: State = State.IDLE
var _ground: SmallGroundFaunaHabitat
var _settings: SmallGroundFaunaProfile
var _rng := RandomNumberGenerator.new()
var _goal_local := Vector3.ZERO
var _timer: float = 0.0
var _decision_timer: float = 0.0
var _time: float = 0.0
var _hop_timer: float = 0.0
## El modelo que se ve: el procedural (SimpleSmallAnimalModel) o, si el perfil trae model, el de un
## pack con esqueleto (SkinnedFaunaModel). Los dos se animan con animate y advance.
var _model: Node3D
@onready var _procedural: SimpleSmallAnimalModel = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D
var _skinned: SkinnedFaunaModel
## La normal del suelo que pisa, suavizada: hacia ella se inclina el modelo.
var _ground_up := Vector3.UP


func activate(point: Vector3, environment: AmbientFaunaHabitat, rng: RandomNumberGenerator) -> void:
	super.activate(point, environment, rng)
	_ground = environment as SmallGroundFaunaHabitat
	_settings = profile as SmallGroundFaunaProfile
	if _ground == null or _settings == null:
		deactivate()
		return
	_rng.seed = rng.randi()
	roll_variant(_rng)
	var shape := CapsuleShape3D.new()
	if _settings.model != null:
		if _skinned == null:
			_skinned = SkinnedFaunaModel.new()
			_skinned.name = "Skinned"
			add_child(_skinned)
		_skinned.set_data(_settings.model, _rng.randi())
		_model = _skinned
		shape.radius = _settings.model.collision_radius * body_size
		shape.height = _settings.model.collision_height * body_size
	else:
		_procedural.set_species(_settings.species)
		_model = _procedural
		shape.radius = SimpleSmallAnimalModel.RADII[_settings.species] * body_size
		shape.height = SimpleSmallAnimalModel.HEIGHTS[_settings.species] * body_size
	_procedural.visible = _model == _procedural
	if _skinned != null:
		_skinned.visible = _model == _skinned
	_model.transform = Transform3D(Basis.from_scale(Vector3.ONE * body_size), Vector3.ZERO)
	_model.animate(0.0, 0.0)
	_collision.shape = shape
	_collision.position = Vector3.UP * shape.height * 0.5
	_collision.disabled = false
	impact_radius = _settings.clearance
	up_direction = _ground.up_at(point)
	_ground_up = up_direction
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
		if not _keep_on_ground():
			deactivate()
			return
		_decide()
	if _check_moving_ships(delta):
		return
	var direction := (_ground.terrain.to_global(_goal_local) - global_position).slide(up_direction)
	var speed := 0.0 if state == State.IDLE \
		else (_settings.flee_speed if state == State.FLEE else _settings.walk_speed) * speed_scale
	if direction.length() < 0.25:
		speed = 0.0
	var horizontal := velocity.slide(up_direction).move_toward(direction.normalized() * speed, delta * 16.0)
	var vertical := velocity.dot(up_direction)
	if is_on_floor():
		vertical = 0.0
		# El conejo procedural salta con el cuerpo; el de un pack ya salta en su clip.
		if _model == _procedural and SimpleSmallAnimalModel.BASE[_settings.species] == 0 \
				and speed > 0.1 and _hop_timer <= 0.0:
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
	_tilt_model(delta)
	var actual_speed := get_real_velocity().slide(up_direction).length()
	_time += delta
	_model.advance(delta, actual_speed / body_size, is_on_floor(), velocity.dot(up_direction), turn)


## Si se ha quedado dentro del terreno lo saca encima: el colisionador del voxel es una malla sin
## dentro, y la cápsula que se cuela por una arista ya no sale sola. Devuelve si hay terreno debajo;
## si no, es que se ha descargado ese trozo. Una cuesta fuerte o el agua no cuentan: de eso ya se
## aparta al elegir camino (can_step), y retirarlo por pisar un triángulo empinado lo hacía
## desaparecer a la vista.
func _keep_on_ground() -> bool:
	var hit := _ground.terrain_under(global_position, SINK_PROBE, 3.0)
	if hit.is_empty():
		return false
	var surface: Vector3 = hit.position
	if (surface - global_position).dot(up_direction) > SINK_TOLERANCE:
		global_position = surface + up_direction * 0.02
		velocity = Vector3.ZERO
		reset_physics_interpolation()
	return true


## El cuerpo anda con la vertical del planeta, pero el modelo se inclina con el suelo que pisa: en
## cuesta, derecho, se le meterían la cabeza o la grupa en la ladera.
func _tilt_model(delta: float) -> void:
	var target := up_direction
	if is_on_floor():
		var normal := get_floor_normal()
		if normal.angle_to(up_direction) < deg_to_rad(_settings.max_slope_degrees + 10.0):
			target = normal
	_ground_up = _ground_up.slerp(target, 1.0 - exp(-delta * TILT_RATE)).normalized()
	var local := (global_basis.inverse() * _ground_up).normalized()
	_model.transform = Transform3D(Basis(Quaternion(Vector3.UP, local)).scaled(Vector3.ONE * body_size), Vector3.ZERO)


func _decide() -> void:
	var away := Vector3.ZERO
	if is_instance_valid(_ground.observer):
		away = global_position - _ground.observer.global_position
		if away.length() < _settings.flee_distance:
			state = State.FLEE
			_timer = FLEE_TIME
			# Lejos, lo que corre en todo ese rato: llegar antes y pararse en seco se ve a saltos.
			_choose_goal(away.slide(up_direction).normalized(), maxf(_settings.wander_distance, _settings.flee_speed * FLEE_TIME))
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


func _choose_goal(direction: Vector3, distance: float = -1.0) -> void:
	if direction.is_zero_approx():
		direction = -global_basis.z
	if distance <= 0.0:
		distance = _settings.wander_distance
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


func _corpse_death() -> Animation:
	return _settings.model.death if _model == _skinned and _settings != null and _settings.model != null else null


func _up() -> Vector3:
	return up_direction
