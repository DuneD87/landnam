class_name AmbientBirdHabitat extends AmbientFaunaHabitat

var terrain: Node3D
var observer: Node3D


func host() -> Node3D:
	return terrain


func up_at(point: Vector3) -> Vector3:
	return (point - terrain.global_position).normalized()


func reserve(_owner_id: int, _near: Vector3, _rng: RandomNumberGenerator) -> Dictionary:
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
