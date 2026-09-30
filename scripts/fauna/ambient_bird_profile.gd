class_name AmbientBirdProfile extends AmbientFaunaProfile

@export_group("Flight")
## Cruise speed in metres per second, randomized for each activated bird.
@export_range(0.1, 40.0, 0.1, "suffix:m/s") var flight_speed_min: float = 8.0
@export_range(0.1, 40.0, 0.1, "suffix:m/s") var flight_speed_max: float = 12.0
## Flapping bursts alternate with glides (gulls, wings open) or bounds (small birds, wings shut).
## A zero glide flaps without pause, as ducks do. Climbs, takeoffs and landings always flap.
@export_range(0.05, 10.0, 0.05, "suffix:s") var flap_burst_min: float = 0.3
@export_range(0.05, 10.0, 0.05, "suffix:s") var flap_burst_max: float = 0.6
@export_range(0.0, 10.0, 0.05, "suffix:s") var glide_min: float = 0.15
@export_range(0.0, 10.0, 0.05, "suffix:s") var glide_max: float = 0.3

@export_group("Perching")
## Rest duration in seconds, randomized on each landing. Threats can end it early.
@export_range(0.0, 300.0, 0.1, "or_greater", "suffix:s") var perch_time_min: float = 5.0
@export_range(0.0, 300.0, 0.1, "or_greater", "suffix:s") var perch_time_max: float = 12.0
## Chance that a landing turns into a long rest, so the canopy is never all in the air at once.
@export_range(0.0, 1.0, 0.01) var long_rest_chance: float = 0.0
@export_range(0.0, 600.0, 0.5, "or_greater", "suffix:s") var long_rest_time_min: float = 15.0
@export_range(0.0, 600.0, 0.5, "or_greater", "suffix:s") var long_rest_time_max: float = 40.0
## Chance of foraging on open ground under the trees instead of landing on a branch.
@export_range(0.0, 1.0, 0.01) var ground_chance: float = 0.0
## Share of new birds that appear already resting (hidden among the branches or on the ground)
## instead of flying in. They are discovered in place rather than seen popping into the sky.
@export_range(0.0, 1.0, 0.01) var perched_spawn_chance: float = 0.0

@export_group("Wariness")
## Distance at which the observer flushes a resting bird: the minimum for someone standing
## still or walking slowly, the maximum for someone running. Each bird has its own boldness.
@export_range(0.0, 50.0, 0.1, "suffix:m") var flush_distance_min: float = 4.0
@export_range(0.0, 50.0, 0.1, "suffix:m") var flush_distance_max: float = 4.0
## Resting birds within this distance of a fleeing one follow it into the air a moment later.
@export_range(0.0, 50.0, 0.1, "suffix:m") var alarm_radius: float = 0.0

@export_group("Ambient Audio")
@export var ambient_audio_enabled: bool = true
## Expand to edit clips, volume, range, pitch and simultaneous voice limit.
@export var ambient_sound: SoundEvent
@export_range(0.1, 120.0, 0.1, "or_greater", "suffix:s") var ambient_interval_min: float = 1.0
@export_range(0.1, 120.0, 0.1, "or_greater", "suffix:s") var ambient_interval_max: float = 4.0
@export var ambient_only_perched: bool = false


static func span(a: float, b: float, rng: RandomNumberGenerator, floor_value: float = 0.0) -> float:
	var minimum := maxf(floor_value, minf(a, b))
	return rng.randf_range(minimum, maxf(minimum, maxf(a, b)))
