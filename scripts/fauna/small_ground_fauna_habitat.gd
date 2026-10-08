class_name SmallGroundFaunaHabitat extends GroundFaunaHabitat

## Short probes during movement never bridge cliffs or unloaded voxel chunks.
var observer: Node3D
var sea_radius: float = 0.0


func sample_spawn(anchor: Vector3, settings: AmbientFaunaProfile,
		rng: RandomNumberGenerator) -> Variant:
	var candidate: Variant = super.sample_spawn(anchor, settings, rng)
	if not candidate is Vector3:
		return null
	var small := settings as SmallGroundFaunaProfile
	if small == null:
		return null
	var hit := ground_at(candidate, settings.clearance + GROUND_MARGIN + 0.5, small)
	if hit.is_empty():
		return null
	return candidate


func up_at(point: Vector3) -> Vector3:
	return (point - center()).normalized()


## Suelo donde se puede pisar bajo [point]: el terreno a menos de [depth] m, sin pasarse de
## max_slope_degrees y fuera del agua; {} si no.
func ground_at(point: Vector3, depth: float, settings: SmallGroundFaunaProfile) -> Dictionary:
	var hit := terrain_under(point, 0.3, depth)
	if hit.is_empty():
		return {}
	var up := up_at(point)
	var surface: Vector3 = hit.position
	if (hit.normal as Vector3).dot(up) < cos(deg_to_rad(settings.max_slope_degrees)):
		return {}
	if sea_radius > 0.0 and surface.distance_to(center()) < sea_radius + 0.25:
		return {}
	if world_map != null and world_map.is_ready() and world_map.is_water_at(surface):
		return {}
	return hit


## El terreno bajo [point], sea como sea (en cuesta, bajo el agua): la primera cara que mira hacia
## arriba bajando desde [above] m por encima hasta [depth] m por debajo, o {} si ahí no hay
## colisión cargada. Las caras de debajo de un saliente no cuentan.
func terrain_under(point: Vector3, above: float, depth: float) -> Dictionary:
	if not is_instance_valid(terrain) or not terrain.is_inside_tree():
		return {}
	var up := up_at(point)
	var query := PhysicsRayQueryParameters3D.create(point + up * above, point - up * depth, 1)
	query.hit_back_faces = false
	return terrain.get_world_3d().direct_space_state.intersect_ray(query)


func can_step(from: Vector3, to: Vector3, settings: SmallGroundFaunaProfile) -> bool:
	# Chest ray blocks walls; the foot probe rejects water, steep slopes and drops.
	var up := up_at(from)
	var query := PhysicsRayQueryParameters3D.create(from + up * 0.12, to + up * 0.12, 1)
	if not terrain.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	return not ground_at(to, 0.55, settings).is_empty()
