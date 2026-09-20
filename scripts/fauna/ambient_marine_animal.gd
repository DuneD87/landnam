class_name AmbientMarineAnimal extends AmbientFish

const FADE_IN := 2.5
const FADE_OUT := 1.5
## Tightest turning circle, in body lengths. Heading changes at speed / radius, so
## a whale takes several times longer than a turtle to swing its body around.
const TURN_RADIUS_LENGTHS := 1.0
## Wander headings stay within this angle of the current course.
const WANDER_ANGLE := PI * 0.4
## Depth changes stay responsive, so the body can still dodge the surface.
const DEPTH_RESPONSE := 1.8

enum Attack { NONE, CHARGE, RETREAT }
## Seconds between scans for boats while wandering.
const PREY_SCAN_INTERVAL := 0.5
## A charge is abandoned when the boat outruns it past this multiple of attack_radius.
const PREY_ESCAPE_FACTOR := 2.5
## Longest charge before turning away, so a circling shark does not orbit forever.
const CHARGE_TIMEOUT := 45.0
## Minimum retreat time; the retreat also lasts until the body is back in deep water.
const RETREAT_TIME := 10.0
## Retreat never lasts longer than this, even when the sea is too shallow to dive.
const RETREAT_LIMIT := 40.0
## Pause after an attack ends before another boat can be chosen.
const ATTACK_REST := 8.0
## How close the snout must come to the hull bounding box to bite.
const BITE_REACH := 0.8
## A charge aims this far ahead at biting depth, so the body is level with the hull
## before it arrives instead of passing underneath.
const CHARGE_LOOKAHEAD := 15.0
## Velocity change of the hull struck by a bite, for boats up to BITE_JOLT_MASS.
const BITE_JOLT := 0.8
const BITE_JOLT_MASS := 20000.0
## A hull deeper than this under the surface has already sunk.
const SUNK_DEPTH := 4.0

@export_enum("Tiburón", "Ballena", "Orca", "Tortuga") var species: int = 0
var _fade: float = 1.0
## Fade change per second: positive while appearing, negative while leaving.
var _fade_step: float = 0.0
## Layer the player collides with; withheld while the body is not fully visible.
var _solid_layer: int = 0
## Tightest turning circle of this individual, in metres; yaw rate is speed / radius.
var _turn_radius: float = 1.0
var _cruise_speed: float = 1.0
var _attack := Attack.NONE
var _prey: DynamicGridBody
var _attack_timer: float = 0.0
var _scan_timer: float = 0.0
## Snout tip in the body's local space.
var _snout := Vector3.ZERO


func _ready() -> void:
	_solid_layer = collision_layer
	_collision.shape = _collision.shape.duplicate()
	_visual.mesh = SimpleMarineMesh.mesh(species)
	_visual.material_override = SimpleMarineMesh.material()


func _configure_visual() -> void:
	var size := _rng.randf_range(0.85, 1.0)
	_speed = float(SimpleMarineMesh.SPEEDS[species]) * _rng.randf_range(0.85, 1.15)
	_visual.scale = Vector3.ONE * size * SimpleMarineMesh.MODEL_SCALES[species]
	var bounds := SimpleMarineMesh.collision_bounds(species)
	(_collision.shape as BoxShape3D).size = bounds.size * size
	_collision.position = bounds.get_center() * size
	_collision.disabled = false
	impact_radius = SimpleMarineMesh.clearance(species)
	var mesh_bounds := SimpleMarineMesh.mesh(species).get_aabb()
	var model_size: float = size * SimpleMarineMesh.MODEL_SCALES[species]
	_turn_radius = TURN_RADIUS_LENGTHS * mesh_bounds.size.z * model_size
	_snout = Vector3(0.0, 0.0, mesh_bounds.position.z * model_size)
	_cruise_speed = _speed
	_attack = Attack.NONE
	_prey = null
	_scan_timer = _rng.randf_range(0.0, PREY_SCAN_INTERVAL)
	_visual.set_instance_shader_parameter("species", species)
	_visual.set_instance_shader_parameter("swim_phase", _rng.randf_range(0.0, TAU))
	_visual.set_instance_shader_parameter("swim_frequency", SimpleMarineMesh.swim_frequency(species, _speed))
	_turn_timer = 0.0
	# Large bodies spawn close to the frustum; dissolve in instead of popping.
	_set_fade(0.0)
	_fade_step = 1.0 / FADE_IN
	collision_layer = 0


func _swim(delta: float) -> void:
	if _fade_step != 0.0:
		_set_fade(clampf(_fade + _fade_step * delta, 0.0, 1.0))
		if _fade_step < 0.0 and _fade <= 0.0:
			deactivate()
			return
		if _fade_step > 0.0 and _fade >= 1.0:
			_fade_step = 0.0
			collision_layer = _solid_layer
	_update_attack(delta)
	super._swim(delta)


func _leave_habitat() -> void:
	# Keep swimming while dissolving out from the current opacity.
	if _fade_step >= 0.0:
		_fade_step = -1.0 / FADE_OUT
		collision_layer = 0
	_attack = Attack.NONE
	_prey = null
	_speed = _cruise_speed


func _set_fade(value: float) -> void:
	_fade = value
	_visual.set_instance_shader_parameter("fade", value)


func _pick_target() -> void:
	if _attack != Attack.NONE:
		return # The attack sets the destination every frame.
	var up := (global_position - _water.center()).normalized()
	var tangent := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var marine := _water as MarineFaunaHabitat
	var course := velocity.slide(up)
	for attempt in 8:
		# Wander gently around the current course; the last attempts accept any
		# heading so a body cornered by the coast can still find open water.
		var heading := tangent.rotated(up, _rng.randf_range(0.0, TAU))
		if attempt < 5 and course.length_squared() > 0.01:
			heading = course.normalized().rotated(up, _rng.randf_range(-WANDER_ANGLE, WANDER_ANGLE))
		var distance := _rng.randf_range(maxf(8.0, impact_radius * 2.0), maxf(20.0, impact_radius * 4.0))
		var target := global_position + heading * distance + up * _rng.randf_range(-1.5, 1.5)
		# Steer large bodies towards deep water instead of fading out over shoals.
		if marine.habitat_allowed(target) and (not marine.settings.use_bathymetry or marine.bathymetry_is_clear(target, marine.settings.bathymetry_margin)):
			_target_local = _water.terrain.to_local(target)
			# Time to swim there, so slow turners are not handed a new course mid-turn.
			_turn_timer = distance / maxf(_speed, 0.1) * _rng.randf_range(0.8, 1.2)
			return
	# Activation starts at zero velocity: keep a nonzero, nonradial heading even
	# when every sampled destination is rejected at a narrow habitat boundary.
	var fallback := -velocity if velocity.length_squared() > 0.01 else tangent - up
	_target_local = _water.terrain.to_local(global_position + fallback)
	_turn_timer = 1.0


func _steer(direction: Vector3, up: Vector3, delta: float) -> Vector3:
	# Yaw is limited by the turning circle; depth and speed are adjusted separately.
	var course := velocity.slide(up)
	var wanted := direction.slide(up)
	var vertical := lerpf(velocity.dot(up), direction.dot(up) * _speed, 1.0 - exp(-delta * DEPTH_RESPONSE))
	if wanted.length_squared() < 0.0001:
		return course + up * vertical
	if course.length_squared() < 0.0001:
		# Activation starts from rest: face the course at once, then accelerate.
		course = wanted.normalized() * 0.1
	var angle := course.signed_angle_to(wanted, up)
	var turn := _speed / _turn_radius * delta
	var heading := course.normalized().rotated(up, clampf(angle, -turn, turn))
	var speed := lerpf(course.length(), _speed * wanted.length(), 1.0 - exp(-delta * 1.8))
	return heading * speed + up * vertical


func _surface_clearance() -> float:
	# An attacker rises to the hull and may break the surface with its back.
	if _attack != Attack.NONE:
		return 0.0
	return (_water as MarineFaunaHabitat).surface_clearance(global_position)


func _cruise_depth() -> float:
	return 0.0 if _attack != Attack.NONE else super._cruise_depth()


func _in_habitat() -> bool:
	if _attack == Attack.NONE:
		return super._in_habitat()
	# Near the surface only the sea itself and the seabed below still apply.
	var marine := _water as MarineFaunaHabitat
	return marine.habitat_allowed(global_position) and (not marine.settings.use_bathymetry or marine.bathymetry_is_clear(global_position, 0.0))


## Charge any boat that comes close, bite its hull below the waterline, swim off
## and come back while it stays near. Bites open holes; flooding does the rest.
func _update_attack(delta: float) -> void:
	var settings := (_water as MarineFaunaHabitat).settings
	if settings.attack_radius <= 0.0 or _fade_step < 0.0:
		return
	if _prey != null and not (is_instance_valid(_prey) and _prey.is_inside_tree() and _prey_afloat(_prey)):
		# Sunk or gone: still dive back to deep water before wandering again.
		_prey = null
		if _attack == Attack.CHARGE:
			_start_retreat()
	match _attack:
		Attack.NONE:
			_scan_timer -= delta
			if _scan_timer > 0.0 or _fade < 1.0:
				return
			_scan_timer = PREY_SCAN_INTERVAL
			_prey = _find_prey(settings.attack_radius)
			if _prey != null:
				_attack = Attack.CHARGE
				_attack_timer = CHARGE_TIMEOUT
				_speed = _cruise_speed * settings.charge_speed_factor
		Attack.CHARGE:
			_attack_timer -= delta
			var hull := _prey.get_hull_center_world()
			if _attack_timer <= 0.0 or hull.distance_to(global_position) > settings.attack_radius * PREY_ESCAPE_FACTOR:
				_start_retreat()
				return
			var aim := _bite_aim(hull)
			var up := (global_position - _water.center()).normalized()
			var ahead := (aim - global_position).slide(up)
			var course := -global_basis.z.slide(up)
			# Prey abeam inside the turning circle cannot be reached by turning:
			# hold the course to open the distance, then come about (a teardrop).
			if ahead.length() < _turn_radius * 2.0 and absf(course.signed_angle_to(ahead, up)) > PI / 3.0:
				ahead = course.normalized() * CHARGE_LOOKAHEAD
			if ahead.length() > CHARGE_LOOKAHEAD:
				ahead = ahead.normalized() * CHARGE_LOOKAHEAD
			# Aim at biting depth right ahead, so the body levels out before it arrives.
			_set_destination(global_position + ahead + up * (aim.distance_to(_water.center()) - global_position.distance_to(_water.center())))
			var snout := global_transform * _snout
			if _prey.contains_point(snout, BITE_REACH):
				_bite(snout)
		Attack.RETREAT:
			_attack_timer -= delta
			# Without prey, keep swimming straight ahead, away from where it was.
			var hull := _prey.get_hull_center_world() if _prey != null else global_position + global_basis.z * settings.retreat_distance
			var up := (global_position - _water.center()).normalized()
			var away := (global_position - hull).slide(up)
			away = away.normalized() if away.length_squared() > 0.01 else -global_basis.z
			var ahead := global_position + away * settings.retreat_distance
			var depth := maxf(settings.min_swim_depth, (settings.min_swim_depth + settings.max_swim_depth) * 0.5)
			_set_destination(_water.center() + (ahead - _water.center()).normalized() * (_water.surface_radius(ahead) - depth))
			var clear := hull.distance_to(global_position) >= settings.retreat_distance and super._in_habitat()
			if (_attack_timer <= 0.0 and clear) or _attack_timer <= RETREAT_TIME - RETREAT_LIMIT:
				if _prey != null and hull.distance_to(global_position) <= settings.attack_radius * PREY_ESCAPE_FACTOR:
					_attack = Attack.CHARGE
					_attack_timer = CHARGE_TIMEOUT
				else:
					_end_attack()


func _find_prey(radius: float) -> DynamicGridBody:
	var marine := _water as MarineFaunaHabitat
	var nearest: DynamicGridBody = null
	var nearest_distance := radius
	for node in DynamicGridBody.bodies_in_play(get_tree()):
		var body := node as DynamicGridBody
		if body == null or not is_instance_valid(body) or body.movement_type != DynamicGridBody.MovementType.BOAT:
			continue
		var hull := body.get_hull_center_world()
		var distance := hull.distance_to(global_position)
		if distance < nearest_distance and _prey_afloat(body) and marine.habitat_allowed(hull):
			nearest = body
			nearest_distance = distance
	return nearest


func _prey_afloat(body: DynamicGridBody) -> bool:
	var hull := body.get_hull_center_world()
	return _water.surface_radius(hull) - hull.distance_to(_water.center()) < SUNK_DEPTH


## Hull centre lowered to half the draft, so bites land below the waterline.
func _bite_aim(hull: Vector3) -> Vector3:
	var center := _water.center()
	var up := (hull - center).normalized()
	var surface := _water.surface_radius(hull)
	var bounds := _prey.get_hull_bounds()
	var half_height: float = (bounds["half"] as Vector3).y if bounds.has("half") else 1.0
	var draft := surface - (hull.distance_to(center) - half_height)
	return center + up * (surface - clampf(draft * 0.5, 0.8, 2.5))


func _set_destination(point: Vector3) -> void:
	_target_local = _water.terrain.to_local(point)
	_turn_timer = 1.0


func _bite(point: Vector3) -> void:
	var settings := (_water as MarineFaunaHabitat).settings
	var up := (point - _water.center()).normalized()
	var inward := (_prey.get_hull_center_world() - point).slide(up)
	inward = inward.normalized() if inward.length_squared() > 0.0001 else -global_basis.z
	var bite_point := point + inward * 0.5
	_prey.apply_damage_at(bite_point, settings.bite_energy, settings.bite_radius)
	var jolt := minf(_prey.mass, BITE_JOLT_MASS) * BITE_JOLT
	_prey.apply_impulse(inward * jolt, bite_point - _prey.global_position)
	_start_retreat()


func _start_retreat() -> void:
	_attack = Attack.RETREAT
	_attack_timer = RETREAT_TIME


func _end_attack() -> void:
	_attack = Attack.NONE
	_prey = null
	_speed = _cruise_speed
	_scan_timer = ATTACK_REST
	_pick_target()


## The attacker's own charge is no crash: only the hull's motion can kill it.
func _resolve_ship_hit(hit: KinematicCollision3D, incoming: Vector3) -> bool:
	if _attack != Attack.NONE and is_instance_valid(_prey):
		for index in hit.get_collision_count():
			if hit.get_collider(index) == _prey:
				incoming = Vector3.ZERO
				if _attack == Attack.CHARGE:
					_bite(hit.get_position(index))
				break
	return super._resolve_ship_hit(hit, incoming)


func _swim_basis(forward: Vector3, up: Vector3) -> Basis:
	# Keep the long body level while changing depth; the cylindrical habitat
	# envelope permits yaw, and must never pitch a 100 m whale vertically.
	var heading := forward.slide(up).normalized()
	if heading.length_squared() < 0.01:
		heading = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return Basis.looking_at(heading, up)
