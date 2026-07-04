@tool
extends Node
class_name PlanetAtmosphereController

## Alimenta el PlanetAtmosphere (compute) cada frame con el centro del planeta y la dirección del sol.

enum SunSourceMode {
	DIRECTIONAL_LIGHT,
	NODE_POSITION,
	CUSTOM_DIRECTION,
}

@export var effect: PlanetAtmosphere
@export var planet_node: Node3D
@export var sun_node: Node3D

@export_group("Planet")
@export var planet_radius: float = 1000.0
@export var atmosphere_height: float = 80.0

@export_group("Sun")
@export var sun_source_mode: SunSourceMode = SunSourceMode.DIRECTIONAL_LIGHT
@export var custom_sun_direction: Vector3 = Vector3(1.0, 0.25, 0.1)
@export var invert_sun_direction: bool = false

@export_group("Editor")
@export var update_in_editor: bool = true


func _ready() -> void:
	_update_effect()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and not update_in_editor:
		return

	_update_effect()


func _update_effect() -> void:
	if effect == null:
		return

	var center := Vector3.ZERO
	if planet_node != null:
		center = planet_node.global_position

	var sun_dir := custom_sun_direction.normalized()

	if sun_node != null:
		match sun_source_mode:
			SunSourceMode.DIRECTIONAL_LIGHT:
				sun_dir = sun_node.global_transform.basis.z.normalized()

			SunSourceMode.NODE_POSITION:
				sun_dir = (sun_node.global_position - center).normalized()

			SunSourceMode.CUSTOM_DIRECTION:
				sun_dir = custom_sun_direction.normalized()

	if invert_sun_direction:
		sun_dir = -sun_dir

	var atmosphere_radius: float = planet_radius + max(atmosphere_height, 0.001)
	effect.set_planet_data(center, planet_radius, atmosphere_radius, sun_dir, _get_water_radius())


## Radio del océano del planeta (0 si no tiene agua); lo expone el PlanetLoader vecino.
func _get_water_radius() -> float:
	if planet_node == null:
		return 0.0
	var ocean: Variant = planet_node.get("water_sphere")
	if ocean == null or not is_instance_valid(ocean):
		return 0.0
	return ocean.radius
