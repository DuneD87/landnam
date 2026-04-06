class_name DynamicGridBody
extends RigidBody3D

## RigidBody3D que aplica gravedad planetaria.
## Propiedad de DynamicPlanetGrid.

var planet_node: Node3D = null

func _physics_process(_delta: float) -> void:
	if not planet_node or not is_inside_tree():
		return
	var dir: Vector3 = (planet_node.global_pos  - global_position).normalized()
	apply_central_force(dir * planet_node.gravity_strength * mass)
