class_name AmbientBirdHabitat extends AmbientFaunaHabitat

var terrain: Node3D
var observer: Node3D
var _observer_local := Vector3.ZERO
var _observer_speed: float = 0.0
var _speed_frame: int = -1


func host() -> Node3D:
	return terrain


func up_at(point: Vector3) -> Vector3:
	return (point - terrain.global_position).normalized()


## Observer speed over the ground, shared by every bird in the frame. Measured in terrain space
## so a floating-origin rebase is not mistaken for a sprint.
func observer_speed() -> float:
	var frame := Engine.get_physics_frames()
	if frame == _speed_frame or not is_instance_valid(observer):
		return _observer_speed
	var local := terrain.to_local(observer.global_position)
	if _speed_frame >= 0:
		var elapsed := float(frame - _speed_frame) / Engine.physics_ticks_per_second
		_observer_speed = minf(local.distance_to(_observer_local) / maxf(elapsed, 0.001), 30.0)
	_observer_local = local
	_speed_frame = frame
	return _observer_speed


## First solid hit on a vertical ray through [point], from [above] metres over it down to
## [below] metres under it. Empty when nothing is there (unstreamed terrain, open air).
func ground_below(point: Vector3, above: float = 30.0, below: float = 60.0) -> Dictionary:
	var up := up_at(point)
	return terrain.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(point + up * above, point - up * below, 1))


func reserve(_owner_id: int, _near: Vector3, _rng: RandomNumberGenerator) -> Dictionary:
	return {}


## A resting place on open ground near [near]. Habitats without ground foraging have none.
func reserve_ground(_owner_id: int, _near: Vector3, _rng: RandomNumberGenerator) -> Dictionary:
	return {}


## The resting place sample_spawn offered at [point], now reserved for [owner_id]; empty when
## the spawn was a flying one or the place was taken meanwhile.
func claim_spawn_perch(_owner_id: int, _point: Vector3) -> Dictionary:
	return {}


## Moves a ground anchor by [offset] (a hop while foraging). Empty when there is no footing.
func hop(_anchor: Dictionary, _offset: Vector3) -> Dictionary:
	return {}


func resolve(_anchor: Dictionary) -> Dictionary:
	return {}


func release(_owner_id: int) -> void:
	pass


func flight_route(_from: Vector3, _perch: Dictionary) -> Array[Vector3]:
	return []


func path_clear(from: Vector3, to: Vector3, _check_foliage: bool = false) -> bool:
	return terrain.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()
