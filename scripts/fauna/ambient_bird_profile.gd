class_name AmbientBirdProfile extends AmbientFaunaProfile

@export_group("Flight")
## Cruise speed in metres per second, randomized for each activated bird.
@export_range(0.1, 40.0, 0.1, "suffix:m/s") var flight_speed_min: float = 8.0
@export_range(0.1, 40.0, 0.1, "suffix:m/s") var flight_speed_max: float = 12.0

@export_group("Perching")
## Rest duration in seconds, randomized on each landing. Threats can end it early.
@export_range(0.0, 300.0, 0.1, "or_greater", "suffix:s") var perch_time_min: float = 5.0
@export_range(0.0, 300.0, 0.1, "or_greater", "suffix:s") var perch_time_max: float = 12.0

@export_group("Ambient Audio")
@export var ambient_audio_enabled: bool = true
## Expand to edit clips, volume, range, pitch and simultaneous voice limit.
@export var ambient_sound: SoundEvent
@export_range(0.1, 120.0, 0.1, "or_greater", "suffix:s") var ambient_interval_min: float = 1.0
@export_range(0.1, 120.0, 0.1, "or_greater", "suffix:s") var ambient_interval_max: float = 4.0
@export var ambient_only_perched: bool = false
