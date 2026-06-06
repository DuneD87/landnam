extends AIState
class_name DeathState

func enter() -> void:
	controller.desired_direction = Vector3.ZERO
	controller.is_attacking = false
	if controller.npc.perception:
		controller.npc.perception.set_physics_process(false)


func update(_delta: float) -> StringName:
	return &""


func exit() -> void:
	pass
