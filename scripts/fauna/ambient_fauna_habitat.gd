class_name AmbientFaunaHabitat extends RefCounted

## A candidate is a world position, or null when the habitat is unavailable.
## Implement this for forest airspace, ground/biome sampling, etc.
func sample_spawn(_anchor: Vector3, _profile: AmbientFaunaProfile,
		_rng: RandomNumberGenerator) -> Variant:
	return null


func is_spawn_valid(_point: Vector3, _clearance: float) -> bool:
	return false
