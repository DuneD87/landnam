class_name AmbientFish extends AmbientAnimal

const CLEARANCE: float = 0.95
## -1 mixes all species; select one in the scene Inspector for a dedicated population.
@export_enum("Aleatorio:-1", "Sardina:0", "Dorada:1", "Pez payaso:2", "Pez mariposa:3", "Cirujano azul:4", "Lábrido:5") var fish_type: int = -1
var current_type: int = 0
@export var lethal_ship_impact_speed: float = 5.0
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
	current_type = _rng.randi_range(0, SimpleFishMesh.TYPES.size() - 1) if fish_type < 0 else clampi(fish_type, 0, SimpleFishMesh.TYPES.size() - 1)
	_speed = _rng.randf_range(0.8, 1.4) * float(SimpleFishMesh.TYPES[current_type].speed)
	var size := _rng.randf_range(0.75, SimpleFishMesh.MAX_SCALE)
	_visual.mesh = SimpleFishMesh.mesh(current_type)
	_visual.scale = Vector3.ONE * size
	var bounds := SimpleFishMesh.collision_bounds(current_type)
	(_collision.shape as BoxShape3D).size = bounds.size * size
	_collision.position = bounds.get_center() * size
	_collision.disabled = false
	_visual.set_instance_shader_parameter("fish_type", current_type)
	_visual.set_instance_shader_parameter("fish_color", Color.from_hsv(_rng.randf(), _rng.randf_range(0.015, 0.09), _rng.randf_range(0.88, 1.0)))
	_visual.set_instance_shader_parameter("swim_phase", _rng.randf_range(0.0, TAU))
	_visual.set_instance_shader_parameter("swim_frequency", _speed * 6.0)
	_surface_radius = _water.surface_radius(point)
	_check_timer = _rng.randf_range(0.0, 0.25)
	_pick_target()
	var direction := (_water.terrain.to_global(_target_local) - global_position).normalized()
	global_basis = Basis.looking_at(direction, (point - _water.center()).normalized())
	velocity = direction * _speed
	reset_physics_interpolation()


func deactivate() -> void:
	super.deactivate()
	if is_instance_valid(_collision):
		_collision.disabled = true


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
		if not _water.is_swimmable(global_position, CLEARANCE):
			deactivate()
			return
		_surface_radius = _water.surface_radius(global_position)
	var target := _water.terrain.to_global(_target_local)
	if _turn_timer <= 0.0 or global_position.distance_squared_to(target) < 2.0:
		_pick_target()
		target = _water.terrain.to_global(_target_local)
	var up := (global_position - _water.center()).normalized()
	var direction := (target - global_position).normalized()
	var depth := _surface_radius - global_position.distance_to(_water.center())
	if depth < 5.0:
		_surface_radius = _water.surface_radius(global_position)
		depth = _surface_radius - global_position.distance_to(_water.center())
		direction = (direction.slide(up) - up * 0.8).normalized()
	velocity = velocity.lerp(direction * _speed, 1.0 - exp(-delta * 1.8))
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
	if _surface_radius - global_position.distance_to(_water.center()) < CLEARANCE + 0.6:
		deactivate()
		return
	if velocity.length_squared() > 0.01:
		var forward := velocity.normalized()
		if absf(forward.dot(up)) < 0.98:
			global_basis = global_basis.slerp(Basis.looking_at(forward, up), 1.0 - exp(-delta * 4.0)).orthonormalized()


static func closing_speed(fish_velocity: Vector3, hull_velocity: Vector3, normal: Vector3) -> float:
	return maxf((hull_velocity - fish_velocity).dot(normal), 0.0)


func _resolve_ship_hit(hit: KinematicCollision3D, incoming: Vector3) -> bool:
	if not active:
		return false
	for index in hit.get_collision_count():
		var body := hit.get_collider(index) as DynamicGridBody
		if body == null or body.movement_type != DynamicGridBody.MovementType.BOAT:
			continue
		var speed := closing_speed(incoming, _ship_velocity_at(body, hit.get_position(index)), hit.get_normal(index))
		if speed > lethal_ship_impact_speed:
			# Keep the puff on the water side of the contact, at the fish's position.
			_water.burst_blood(global_position)
			deactivate()
			return true
	return false


func _check_moving_ships(delta: float) -> bool:
	for node in _water.nearby_ships():
		if not is_instance_valid(node) or not node is DynamicGridBody:
			continue
		var body := node as DynamicGridBody
		var hull_velocity := _ship_velocity_at(body, global_position)
		var relative_motion := (velocity - hull_velocity) * delta
		if not body.contains_point(global_position, CLEARANCE + relative_motion.length()):
			continue
		# Relative sweep detects a boat hitting a nearly stationary fish, including
		# its angular velocity, even when normal kinematic movement misses the impact.
		var hit := move_and_collide(relative_motion, true, 0.02, true, 4)
		if hit != null and _resolve_ship_hit(hit, velocity):
			return true
	return false


static func _ship_velocity_at(body: DynamicGridBody, point: Vector3) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var mass_center := body.global_position
	if state != null:
		mass_center = state.transform.origin + state.center_of_mass
	return body.linear_velocity + body.angular_velocity.cross(point - mass_center)


func _pick_target() -> void:
	var up := (global_position - _water.center()).normalized()
	var tangent := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	tangent = tangent.rotated(up, _rng.randf_range(0.0, TAU))
	var target := global_position + tangent * _rng.randf_range(5.0, 12.0) + up * _rng.randf_range(-2.0, 2.0)
	_target_local = _water.terrain.to_local(target)
	_turn_timer = _rng.randf_range(3.0, 7.0)
