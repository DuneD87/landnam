class_name DynamicGridBody
extends RigidBody3D

## RigidBody3D que aplica gravedad planetaria.
## Propiedad de DynamicPlanetGrid.

var planet_node: Node3D = null

func _is_ground_ready() -> bool:
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 5,
		planet_node.global_pos
	)
	
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	
	return not result.is_empty()
	
func _physics_process(_delta: float) -> void:
	while !_is_ground_ready():
		await get_tree().create_timer(.5).timeout
	if not planet_node or not is_inside_tree():
		return
	var dir: Vector3 = (planet_node.global_pos  - global_position).normalized()
	apply_central_force(dir * planet_node.gravity_strength * mass)
