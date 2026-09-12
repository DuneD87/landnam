class_name SmallGroundFaunaProfile extends GroundFaunaProfile

@export_enum("Conejo:0", "Zorro:1", "Ratón:2") var species: int = 0
@export var walk_speed: float = 1.0
@export var flee_speed: float = 4.0
@export var flee_distance: float = 6.0
@export var wander_distance: float = 5.0
@export var max_slope_degrees: float = 40.0
