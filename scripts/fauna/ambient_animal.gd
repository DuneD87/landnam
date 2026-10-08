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
## Sobra con la actividad de ahora (anochece, migra, hiberna): se está yendo y el spawner lo retira
## en cuanto deja de verse. Ver retire().
var retiring: bool = false
var habitat: AmbientFaunaHabitat
## A death scares the birds resting around it.
const DEATH_STARTLE_RADIUS := 12.0

## Closing speed, in m/s, above which a hull or a projectile kills the creature.
@export var lethal_impact_speed: float = 5.0
## Half-size used for impacts: hull proximity sweeps and projectile paths.
var impact_radius: float = 0.4
## Optional child: a creature without one is fragile and any hit that reaches it is lethal.
@onready var health_component: HealthComponent = get_node_or_null("HealthComponent")

## Su tamaño (roll_variant): la variante que le ha tocado al salir (null = la de la especie tal
## cual), la escala de su cuerpo y lo que cambia con ello. Cada especie lo aplica a lo suyo (modelo,
## colisión, velocidad, mordisco) al montarse.
var variant: CreatureVariant
var body_size: float = 1.0
var damage_scale: float = 1.0
var speed_scale: float = 1.0
var voice_pitch: float = 1.0


func activate(point: Vector3, environment: AmbientFaunaHabitat,
		_rng: RandomNumberGenerator) -> void:
	habitat = environment
	global_position = point
	velocity = Vector3.ZERO
	active = true
	retiring = false
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


## Sale con [leader] en un grupo (group_size del perfil), justo después de activate(). Las
## criaturas que viven en manada comparten su casa y su reparto de variantes; el resto, nada.
func join_group(_leader: AmbientAnimal) -> void:
	pass


## De qué tamaños sale su especie: las variantes de su perfil. Las criaturas con escena propia
## (NPCController) y los peces de varias especies (AmbientFish) las sacan de otro sitio.
func get_variants() -> Array[CreatureVariant]:
	return profile.variants if profile != null else ([] as Array[CreatureVariant])


## Sortea su variante (por peso, entre las que _variant_allowed deja) y su tamaño dentro de ella, y
## se la pone (apply_variant). Sin variantes, la especie tal cual. [rng] null = uno propio al azar.
func roll_variant(rng: RandomNumberGenerator) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var picked := CreatureVariant.pick(get_variants(), rng, _variant_allowed)
	apply_variant(picked, picked.roll_size(rng) if picked != null else 1.0)


## Le pone la variante [v] con el cuerpo a escala [size] (<= 0: la media de la variante). null = la
## especie tal cual, a escala 1. Aquí solo los números; cada especie los aplica al montarse.
func apply_variant(v: CreatureVariant, size: float = -1.0) -> void:
	variant = v
	body_size = size if size > 0.0 else (v.mid_size() if v != null else 1.0)
	damage_scale = v.damage * v.strength(body_size) if v != null else 1.0
	speed_scale = v.speed if v != null else 1.0
	voice_pitch = v.voice_pitch if v != null else 1.0


## La variante y el tamaño, para la consola: "grande ×1,18". Vacío sin variante.
func describe_variant() -> String:
	if variant == null:
		return ""
	return "%s ×%.2f" % [variant.id, body_size]


## Si puede salir de la variante [v] (NPCController: sin pasar del tope de su manada).
func _variant_allowed(_v: CreatureVariant) -> bool:
	return true


## Point the player's lock-on frames and aims at: the middle of the body, not the feet.
func lock_point() -> Vector3:
	var shape := get_node_or_null("CollisionShape3D") as Node3D
	return shape.global_position if shape != null else global_position


## Whether the player can lock onto it right now: alive and in the world.
func lockable() -> bool:
	return active and is_inside_tree() and visible


## El spawner le pide que se vaya porque sobra (noche, estación) y está a la vista. Por defecto
## solo queda marcado y sigue a lo suyo hasta salir de cámara; las aves echan a volar y se van.
func retire() -> void:
	retiring = true


## Something alarming happened at [point] (an arrow striking, a death). Timid creatures override
## this to flee; the rest ignore it.
func startle(_point: Vector3) -> void:
	pass


## Startles every active creature within [radius] of [point].
static func startle_near(tree: SceneTree, point: Vector3, radius: float) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		var creature := node as AmbientAnimal
		if creature != null and creature.active \
				and creature.global_position.distance_squared_to(point) < radius * radius:
			creature.startle(point)


## Damage from a projectile, a hull or an attacker. Without a HealthComponent the creature
## is fragile: anything that reaches it kills it.
func take_damage(amount: float, source: Node = null) -> void:
	if not active or amount <= 0.0:
		return
	if health_component == null:
		die(global_position)
		return
	health_component.take_damage(amount, source)


## Death at [point]: blood, a corpse when the species leaves one (FaunaCorpse, apart from the
## creature) and back to the pool. Creatures that play a death animation override this.
func die(point: Vector3) -> void:
	if not active:
		return
	_death_fx(point)
	AudioManager.play_material(&"fauna_burst", audio_family(), point)
	var model := _corpse_model()
	if model != null and model.is_visible_in_tree() and SettingsManager.gore_level() != SettingsManager.GORE_OFF:
		var host := get_tree().current_scene
		if host != null:
			var up := _up()
			if up != Vector3.ZERO:
				FaunaCorpse.spawn(host, model, velocity, -up * 9.8, 1, _corpse_death())
	deactivate()
	startle_near(get_tree(), point, DEATH_STARTLE_RADIUS)


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


## Blood where it dies: the combat effects (spray, droplets, splats on the ground and on the grass),
## scaled to the creature. Swimmers override it with the underwater cloud.
func _death_fx(point: Vector3) -> void:
	var up := _up()
	if up == Vector3.ZERO:
		return
	var dir := (up + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).slide(up) * 0.6).normalized()
	CombatFx.blood(self, point, dir, ItemData.DamageKind.BLUNT, clampf(impact_radius * 50.0, 10.0, 35.0))


## The visual model the corpse copies, or null to leave none (fish, a duck on the water).
func _corpse_model() -> Node3D:
	return null


## La animación de muerte que hace el cadáver (pistas desde su esqueleto), o null.
func _corpse_death() -> Animation:
	return null


## Arriba donde está, el mismo con el que se mueve (cada especie lo lleva a su manera). ZERO si no
## lo sabe: entonces ni cadáver ni chorro.
func _up() -> Vector3:
	return Vector3.ZERO
