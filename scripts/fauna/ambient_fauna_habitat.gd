class_name AmbientFaunaHabitat extends RefCounted

var _blood_pool: Array[BloodCloud] = []
var _blood_cursor: int = 0
var _ship_frame: int = -1
var _ships: Array[Node] = []


## A candidate is a world position, or null when the habitat is unavailable.
## Implement this for forest airspace, ground/biome sampling, etc.
func sample_spawn(_anchor: Vector3, _profile: AmbientFaunaProfile,
		_rng: RandomNumberGenerator) -> Variant:
	return null


func is_spawn_valid(_point: Vector3, _clearance: float) -> bool:
	return false


## Scene node the habitat hangs from: parents its pooled effects and gives access to the tree.
func host() -> Node3D:
	return null


## Planet centre, for effects that need a gravity up.
func center() -> Vector3:
	var node := host()
	return Vector3.ZERO if node == null else node.global_position


## Distance from the centre to the sea surface above a point. Only underwater habitats
## have one; the rest never ask for it.
func surface_radius(_point: Vector3) -> float:
	return 0.0


func is_underwater() -> bool:
	return false


## Dynamic hulls near the population. One group lookup per physics frame for the whole
## population, shared by spawn checks and by the animals' own impact sweeps.
func nearby_ships() -> Array[Node]:
	var node := host()
	if node == null or not node.is_inside_tree():
		return []
	var frame := Engine.get_physics_frames()
	if frame != _ship_frame:
		_ship_frame = frame
		_ships = node.get_tree().get_nodes_in_group("dynamic_grid_body")
	return _ships


## Pooled blood puff at a lethal impact. Bounded: a crowded moment reuses the oldest cloud.
func burst_blood(point: Vector3) -> void:
	var node := host()
	if node == null or not node.is_inside_tree():
		return
	var cloud: BloodCloud
	for entry in _blood_pool:
		if is_instance_valid(entry) and not entry.active:
			cloud = entry
			break
	if cloud == null and _blood_pool.size() < 8:
		cloud = BloodCloud.new()
		node.add_child(cloud)
		_blood_pool.append(cloud)
	if cloud == null:
		cloud = _blood_pool[_blood_cursor]
		_blood_cursor = (_blood_cursor + 1) % _blood_pool.size()
	cloud.burst(point, self)
