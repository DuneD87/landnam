extends Node
class_name AnimationController

const Config = preload("res://scripts/config.gd")

@onready var animator: AnimationPlayer = $"../PlayerModel/AnimationPlayer"
@onready var animation_tree: AnimationTree = $"../PlayerModel/AnimationTree"
@export var blend_speed: float = 5.0

var animation_states = {
	Config.ANIMATION.IDLE: {
	},
	Config.ANIMATION.RUN: {
		"bRun": 1.0,
	},
	Config.ANIMATION.SPRINT: {
		"bSprint": 1.0,
	},
	Config.ANIMATION.JUMP_START: {
		"bJumpStart": 1.0,
	},
	Config.ANIMATION.JUMP_IDLE: {
		"bJumpIdle": 1.0,
	},
	Config.ANIMATION.JUMP_LAND: {
		"bJumpLand": 1.0
	},
	Config.ANIMATION.FALLING: {
		"bJumpIdle": 1.0,
	},
	Config.ANIMATION.SWIM: {
		"bSwim": 1.0
	},
	Config.ANIMATION.SWIM_IDLE: {
		"bSwimIdle": 1.0
	},
	Config.ANIMATION.ATTACK_1: {
		"attack_horizontal": 1.0
	},
	Config.ANIMATION.ATTACK_2: {
		"attack_vertical": 1.0
	}
}

var current_values = {
	"bRun": 0.0,
	"bSprint": 0.0,
	"bJumpStart": 0.0,
	"bJumpIdle": 0.0,
	"bJumpLand": 0.0,
	"bSwim": 0.0,
	"bSwimIdle": 0.0,
}
var oneshot_params = ["attack_vertical", "attack_horizontal"]  # parámetros que son OneShot

func update_tree():
	for parameter in current_values:
		animation_tree["parameters/%s/blend_amount" % parameter] = current_values[parameter]


func handle_animations(delta: float, current_animation, free_flight_enabled):
	if free_flight_enabled:
		return
	
	var target_value = animation_states.get(current_animation, {})
	
	# Manejar OneShot (ataques)
	for param in oneshot_params:
		if target_value.has(param):
			# Disparar el OneShot si no está ya activo
			if not animation_tree["parameters/%s/active" % param]:
				animation_tree["parameters/%s/request" % param] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	
	# Manejar Blend2 (el resto)
	for parameter in current_values:
		if parameter in oneshot_params:
			continue  # Los OneShot no usan blend
		if target_value.has(parameter):
			current_values[parameter] = lerpf(current_values[parameter], target_value[parameter], blend_speed * delta)
		else:
			current_values[parameter] = lerpf(current_values[parameter], 0, blend_speed * delta)

	update_tree()

func add_animation_state(state_name, parameter_values: Dictionary):
	animation_states[state_name] = parameter_values

func add_animation_parameter(parameter_name, initial_value: float = 0.0):
	current_values[parameter_name] = initial_value
