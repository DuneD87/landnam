class_name AmbientFaunaProfile extends Resource

## Population policy shared by fish, birds and small ground animals.
## Habitat selection and locomotion belong to separate strategies/animal scenes.
@export var animal_scene: PackedScene
@export_range(0, 200, 1) var population: int = 28
@export var spawn_min_distance: float = 12.0
@export var spawn_radius: float = 40.0
@export var recycle_distance: float = 60.0
@export var update_interval: float = 0.25
@export_range(1, 32, 1) var attempts_per_update: int = 6
@export_range(1, 10, 1) var activations_per_update: int = 2
## Enclosing radius of the largest animal, including its animation.
@export var clearance: float = 0.95
## Minimum distance from any other active animal of this profile when spawning.
## Zero allows spawns anywhere, as dense schools of fish want.
@export var min_spacing: float = 0.0
## Margin outside the camera frustum for new spawns. Negative uses clearance. Animals
## that fade in on activation can use a smaller margin than their full length.
@export var view_margin: float = -1.0


## Equal probability per unit area of the spawn annulus. Uniform radius would
## concentrate the population into its much smaller inner rings.
func sample_spawn_distance(rng: RandomNumberGenerator) -> float:
	var minimum := maxf(0.0, spawn_min_distance)
	var maximum := maxf(minimum, spawn_radius)
	return sqrt(rng.randf_range(minimum * minimum, maximum * maximum))
