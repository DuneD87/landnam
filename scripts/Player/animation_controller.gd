extends Node
class_name AnimationController

const Config = preload("res://scripts/config.gd")

@onready var animator: AnimationPlayer = $"../PlayerModel/AnimationPlayer"
@onready var animation_tree: AnimationTree = $"../PlayerModel/AnimationTree"
@export var blend_speed: float = 5.0

var animation_states = {
	Config.IDLE: {
	},
	Config.RUN: {
		"bRun": 1.0,
	},
	Config.SPRINT: {
		"bSprint": 1.0,
	},
	Config.JUMP_START: {
		"bJumpStart": 1.0,
	},
	Config.JUMP_IDLE: {
		"bJumpIdle": 1.0,
	},
	Config.JUMP_LAND: {
		"bJumpLand": 1.0
	},
	Config.FALLING: {
		"bJumpIdle": 1.0,
	},
	Config.SWIM: {
		"bSwim": 1.0
	},
	Config.SWIM_IDLE: {
		"bSwimIdle": 1.0
	}
}

var current_values = {
	"bRun": 0.0,
	"bSprint": 0.0,
	"bJumpStart": 0.0,
	"bJumpIdle": 0.0,
	"bJumpLand": 0.0,
	"bSwim": 0.0,
	"bSwimIdle": 0.0
}

func update_tree():
	for parameter in current_values:
		animation_tree["parameters/%s/blend_amount" % parameter] = current_values[parameter]

func handle_animations(delta: float, current_animation, free_flight_enabled):
	if free_flight_enabled:
		return

	if current_animation == Config.ATTACK_1:
		animation_tree.set("parameters/oAttack_1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return

	var target_value = animation_states.get(current_animation, {})
	
	for parameter in current_values:
		if target_value.has(parameter):
			current_values[parameter] = lerpf(current_values[parameter], target_value[parameter], blend_speed * delta)
		else:
			current_values[parameter] = lerpf(current_values[parameter], 0, blend_speed * delta)
	
	update_tree()

func add_animation_state(state_name, parameter_values: Dictionary):
	animation_states[state_name] = parameter_values

func add_animation_parameter(parameter_name, initial_value: float = 0.0):
	current_values[parameter_name] = initial_value
