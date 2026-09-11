class_name AmbientAnimal extends PlanetaryBody

## Base of every living creature: fish, birds and surface animals. Owns the pool lifecycle,
## the damage entry point and the hull impacts, so projectiles and boats reach all of them
## through one group. Locomotion and presentation belong to the subclasses.

## Active creatures, so projectiles can find them without a collision layer of their own.
const GROUP := &"creature"

## Assigned by the shared spawner before activation; subclasses consume their settings.
var profile: AmbientFaunaProfile

## Pool lifecycle. Subclasses implement movement and reset their own state in activate().
var active: bool = false
var habitat: AmbientFaunaHabitat
## Closing speed, in m/s, above which a hull or a projectile kills the creature.
@export var lethal_impact_speed: float = 5.0
## Half-size used for impacts: hull proximity sweeps and projectile paths.
var impact_radius: float = 0.4
## Optional child: a creature without one is fragile and any hit that reaches it is lethal.
@onready var health_component: HealthComponent = get_node_or_null("HealthComponent")


func activate(point: Vector3, environment: AmbientFaunaHabitat,
		_rng: RandomNumberGenerator) -> void:
	habitat = environment
	global_position = point
	velocity = Vector3.ZERO
	active = true
	process_mode = Node.PROCESS_MODE_INHERIT
	add_to_group(GROUP)
	if health_component != null:
		health_component.health = health_component.max_health
		health_component.is_dead = false
		if not health_component.died.is_connected(_on_health_depleted):
			health_component.died.connect(_on_health_depleted)
	show()
	reset_physics_interpolation()


func deactivate() -> void:
	active = false
	velocity = Vector3.ZERO
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED


## Sound family of the species: picks "fauna_burst_<family>" when that event has a clip,
## and falls back to the generic burst. Subclasses name their own.
func audio_family() -> StringName:
	return &""


## True while the node still occupies its slot: alive, or lying there as a corpse. The pool
## neither reuses it nor counts its slot as free until this goes false.
func in_play() -> bool:
	return active


## Detail level for the current distance to the observer, called by the spawner while the
## creature stays in play. Fish and birds are cheap and ignore it; heavy skeletal creatures
## use it to drop their physics and AI rate instead of being recycled.
func set_detail(_distance: float) -> void:
	pass


## Damage from a projectile, a hull or an attacker. Without a HealthComponent the creature
## is fragile: anything that reaches it kills it.
func take_damage(amount: float, source: Node = null) -> void:
	if not active or amount <= 0.0:
		return
	if health_component == null:
		die(global_position)
		return
	health_component.take_damage(amount, source)


## Death at [point]: blood cloud and back to the pool. Creatures that leave a corpse and
## play a death animation override this.
func die(point: Vector3) -> void:
	if not active:
		return
	if habitat != null:
		habitat.burst_blood(point)
	AudioManager.play_material(&"fauna_burst", audio_family(), point)
	deactivate()


func _on_health_depleted() -> void:
	die(global_position)


static func closing_speed(animal_velocity: Vector3, hull_velocity: Vector3, normal: Vector3) -> float:
	return maxf((hull_velocity - animal_velocity).dot(normal), 0.0)


static func _ship_velocity_at(body: DynamicGridBody, point: Vector3) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var mass_center := body.global_position
	if state != null:
		mass_center = state.transform.origin + state.center_of_mass
	return body.linear_velocity + body.angular_velocity.cross(point - mass_center)


## True when the contact was a violent hull impact, which kills the creature.
func _resolve_ship_hit(hit: KinematicCollision3D, incoming: Vector3) -> bool:
	if not active:
		return false
	for index in hit.get_collision_count():
		var body := hit.get_collider(index) as DynamicGridBody
		if body == null or body.movement_type != DynamicGridBody.MovementType.BOAT:
			continue
		var speed := closing_speed(incoming, _ship_velocity_at(body, hit.get_position(index)), hit.get_normal(index))
		if speed > lethal_impact_speed:
			# Keep the puff at the creature's position, on its side of the contact.
			die(global_position)
			return true
	return false


func _check_moving_ships(delta: float) -> bool:
	for node in DynamicGridBody.bodies_in_play(get_tree()):
		if not is_instance_valid(node) or not node is DynamicGridBody:
			continue
		var body := node as DynamicGridBody
		var hull_velocity := _ship_velocity_at(body, global_position)
		var relative_motion := (velocity - hull_velocity) * delta
		if not body.contains_point(global_position, impact_radius + relative_motion.length()):
			continue
		# Relative sweep detects a boat hitting a nearly stationary creature, including
		# its angular velocity, even when normal kinematic movement misses the impact.
		var hit := move_and_collide(relative_motion, true, 0.02, true, 4)
		if hit != null and _resolve_ship_hit(hit, velocity):
			return true
	return false
