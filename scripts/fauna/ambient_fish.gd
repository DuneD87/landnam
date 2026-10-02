class_name AmbientFish extends AmbientAnimal

const CLEARANCE: float = 0.95
## -1 mixes all species; select one in the scene Inspector for a dedicated population.
@export_enum("Aleatorio:-1", "Sardina:0", "Dorada:1", "Pez payaso:2", "Pez mariposa:3", "Cirujano azul:4", "Lábrido:5") var fish_type: int = -1
var current_type: int = 0
var _water: WaterFaunaHabitat
var _rng := RandomNumberGenerator.new()
var _target_local := Vector3.ZERO
var _speed: float = 1.0
var _turn_timer: float = 0.0
var _check_timer: float = 0.0
var _surface_radius: float = 0.0
@onready var _visual: MeshInstance3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_visual.mesh = SimpleFishMesh.mesh()
	_visual.material_override = SimpleFishMesh.material()
	_collision.shape = _collision.shape.duplicate()


func activate(point: Vector3, environment: AmbientFaunaHabitat,
		rng: RandomNumberGenerator) -> void:
	super.activate(point, environment, rng)
	_water = environment as WaterFaunaHabitat
	if _water == null:
		deactivate()
		return
	_rng.seed = rng.randi()
	_configure_visual()
	_surface_radius = _water.surface_radius(point)
	_check_timer = _rng.randf_range(0.0, 0.25)
	_pick_target()
	var direction := (_water.terrain.to_global(_target_local) - global_position).normalized()
	global_basis = _swim_basis(direction, (point - _water.center()).normalized())
	velocity = direction * _speed
	reset_physics_interpolation()


func _configure_visual() -> void:
	current_type = _rng.randi_range(0, SimpleFishMesh.TYPES.size() - 1) if fish_type < 0 else clampi(fish_type, 0, SimpleFishMesh.TYPES.size() - 1)
	_speed = _rng.randf_range(0.8, 1.4) * float(SimpleFishMesh.TYPES[current_type].speed)
	var size := _rng.randf_range(0.75, SimpleFishMesh.MAX_SCALE)
	_visual.mesh = SimpleFishMesh.mesh(current_type)
	_visual.scale = Vector3.ONE * size
	var bounds := SimpleFishMesh.collision_bounds(current_type)
	(_collision.shape as BoxShape3D).size = bounds.size * size
	_collision.position = bounds.get_center() * size
	_collision.disabled = false
	impact_radius = CLEARANCE
	_visual.set_instance_shader_parameter("fish_type", current_type)
	_visual.set_instance_shader_parameter("fish_color", Color.from_hsv(_rng.randf(), _rng.randf_range(0.015, 0.09), _rng.randf_range(0.88, 1.0)))
	_visual.set_instance_shader_parameter("swim_phase", _rng.randf_range(0.0, TAU))
	_visual.set_instance_shader_parameter("swim_frequency", _speed * 6.0)


func deactivate() -> void:
	super.deactivate()
	if is_instance_valid(_collision):
		_collision.disabled = true


func audio_family() -> StringName:
	return &"fish"


func _physics_process(delta: float) -> void:
	if not active:
		return
	if GameManager.current_state != GameManager.State.PLAYING:
		return
	var start := Time.get_ticks_usec()
	_swim(delta)
	DebugStats.report_cost(&"fauna:fish", Time.get_ticks_usec() - start)


func _swim(delta: float) -> void:
	if _check_moving_ships(delta):
		return
	# Interior fallback uses the actual envelope, not the expanded spawn exclusion:
	# approaching fish must get a chance to collide with the real hull first.
	if _water.intersects_ship(global_position, -0.5):
		deactivate()
		return
	_turn_timer -= delta
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.25
		if not _in_habitat():
			_leave_habitat()
			return
		_surface_radius = _water.surface_radius(global_position)
	var target := _water.terrain.to_global(_target_local)
	if _turn_timer <= 0.0 or global_position.distance_squared_to(target) < 2.0:
		_pick_target()
		target = _water.terrain.to_global(_target_local)
	var up := (global_position - _water.center()).normalized()
	var direction := (target - global_position).normalized()
	var depth := _surface_radius - global_position.distance_to(_water.center())
	if depth < _cruise_depth():
		_surface_radius = _water.surface_radius(global_position)
		depth = _surface_radius - global_position.distance_to(_water.center())
		direction = (direction.slide(up) - up * 0.8).normalized()
	velocity = _steer(direction, up, delta)
	# Box sweep and penetration recovery handle normal contact with terrain and hulls.
	# Never teleport a swimming fish to its destination or force it through the surface.
	var incoming_velocity := velocity
	move_and_slide()
	for index in get_slide_collision_count():
		if _resolve_ship_hit(get_slide_collision(index), incoming_velocity):
			return
	if get_slide_collision_count() > 0:
		var normal := get_slide_collision(0).get_normal()
		velocity = (normal + up.cross(normal) * 0.7).normalized() * _speed
		_target_local = _water.terrain.to_local(global_position + velocity * 5.0)
		_turn_timer = 1.5
	if _surface_radius - global_position.distance_to(_water.center()) < _surface_clearance() + 0.6:
		_leave_habitat()
		return
	if velocity.length_squared() > 0.01:
		var forward := velocity.normalized()
		if absf(forward.dot(up)) < 0.98:
			global_basis = global_basis.slerp(_swim_basis(forward, up), 1.0 - exp(-delta * 4.0)).orthonormalized()


func _in_habitat() -> bool:
	return _water.is_swimmable(global_position, impact_radius)


## Depth below which the swimmer is steered back down, away from the surface.
func _cruise_depth() -> float:
	return maxf(5.0, _surface_clearance() + 2.0)


## New velocity towards `direction`. Small fish may dart; large bodies override this.
func _steer(direction: Vector3, _up: Vector3, delta: float) -> Vector3:
	return velocity.lerp(direction * _speed, 1.0 - exp(-delta * 1.8))


func _surface_clearance() -> float:
	return impact_radius


## The swimmer no longer fits its water. Small fish vanish; large bodies may fade out.
func _leave_habitat() -> void:
	deactivate()


func _swim_basis(forward: Vector3, up: Vector3) -> Basis:
	return Basis.looking_at(forward, up)


func _pick_target() -> void:
	var up := (global_position - _water.center()).normalized()
	var tangent := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	tangent = tangent.rotated(up, _rng.randf_range(0.0, TAU))
	var target := global_position + tangent * _rng.randf_range(5.0, 12.0) + up * _rng.randf_range(-2.0, 2.0)
	_target_local = _water.terrain.to_local(target)
	_turn_timer = _rng.randf_range(3.0, 7.0)


## Underwater the blood is a cloud, and nothing is left behind.
func _death_fx(point: Vector3) -> void:
	if habitat != null:
		habitat.burst_blood(point)
