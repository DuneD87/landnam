class_name FishingRodTrait
extends ItemTrait

## La caña carga el alcance mientras se mantiene ataque 1. Un cebo por lanzamiento;
## el anzuelo queda montado hasta recoger o cancelar, y entonces vuelve al inventario.
@export var min_distance := 3.0
@export var max_distance := 22.0
@export var charge_time := 1.5
@export var attraction_radius := 18.0
@export_range(0.0, 1.0) var hook_chance := 0.65
@export var bite_time := 1.2
@export var response_time := 5.0
@export var reel_speed := 3.0
@export var hook_id: StringName = &"fishing_hook"
@export var bait_id: StringName = &"fishing_bait"
@export var catch_id: StringName = &"raw_fish"


func distance_at(seconds: float) -> float:
	return lerpf(min_distance, max_distance, clampf(seconds / maxf(charge_time, 0.01), 0.0, 1.0))


func describe() -> Array:
	return [["FISH_RANGE", number(max_distance) + " m"],
		["FISH_CHANCE", "%d %%" % roundi(hook_chance * 100.0)]]
