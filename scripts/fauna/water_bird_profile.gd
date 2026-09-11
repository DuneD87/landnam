class_name WaterBirdProfile extends AmbientBirdProfile

@export_group("Sustained Flight")
## Time spent cruising before looking for water to land on, including after spawn.
@export_range(0.0, 180.0, 0.5, "suffix:s") var flight_time_min: float = 12.0
@export_range(0.0, 180.0, 0.5, "suffix:s") var flight_time_max: float = 25.0
## Actual distance flown before landing is allowed; obstacles do not reset it.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var flight_distance_min: float = 60.0

@export_group("Waterside Habitat")
## Maximum distance to land while over the ocean, in metres.
@export_range(0.0, 2000.0, 1.0, "suffix:m") var max_offshore_distance: float = 200.0
@export_range(0.0, 200.0, 1.0, "suffix:m") var coast_inland_distance: float = 40.0
@export_range(0.0, 200.0, 1.0, "suffix:m") var river_bank_distance: float = 35.0
@export_range(0.5, 50.0, 0.5, "suffix:m") var flight_height_min: float = 2.0
@export_range(0.5, 50.0, 0.5, "suffix:m") var flight_height_max: float = 10.0
@export_range(0.0, 5.0, 0.1, "suffix:m/s") var swim_speed: float = 1.0
