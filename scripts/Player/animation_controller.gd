extends Node
class_name AnimationController
const Config = preload("res://scripts/config.gd")

@onready var animator: AnimationPlayer = $"../PlayerModel/AnimationPlayer"
@onready var animation_tree: AnimationTree = $"../PlayerModel/AnimationTree"
@export var blend_speed: float = 15.0

var run_val = 0
var sprint_val = 0
var jump_start_val = 0
var jump_idle_val = 0
var jump_end_val = 0

func update_tree():
	animation_tree["parameters/bRun/blend_amount"] = run_val
	animation_tree["parameters/bSprint/blend_amount"] = sprint_val
	animation_tree["parameters/bJumpStart/blend_amount"] = jump_start_val
	animation_tree["parameters/bJumpIdle/blend_amount"] = jump_idle_val
	animation_tree["parameters/bJumpLand/blend_amount"] = jump_end_val

func handle_animations(delta: float, current_animation, free_flight_enabled):
	if free_flight_enabled:
		return

	match current_animation:
		Config.IDLE:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)	
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		Config.RUN:
			run_val = lerpf(run_val, 1, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)	
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		Config.SPRINT:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 1, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		Config.JUMP_START:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 1, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		Config.JUMP_IDLE:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 1, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		Config.JUMP_LAND:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 0, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 1, blend_speed*delta)
		Config.FALLING:
			run_val = lerpf(run_val, 0, blend_speed*delta)
			sprint_val = lerpf(sprint_val, 0, blend_speed*delta)
			jump_start_val = lerpf(jump_start_val, 0, blend_speed*delta)	
			jump_idle_val = lerpf(jump_idle_val, 1, blend_speed*delta)	
			jump_end_val = lerpf(jump_end_val, 0, blend_speed*delta)
		Config.ATTACK_1:
			animation_tree.set("parameters/oAttack_1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			
	update_tree()
