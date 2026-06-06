extends Node
class_name AnimationController

const Config = preload("res://scripts/config.gd")

## Si no se asigna desde el editor, busca la ruta por defecto del Player.
## Los NPCs deben asignar estos exports apuntando a su propio modelo.
@export var animator: AnimationPlayer
@export var animation_tree: AnimationTree
@export var blend_speed: float = 5.0

var _valid_blend_paths: Array[String] = []
var _has_hit_anim: bool = false

func _ready() -> void:
	if not animator:
		animator = get_node_or_null("../PlayerModel/AnimationPlayer")
	if not animation_tree:
		animation_tree = get_node_or_null("../PlayerModel/AnimationTree")
	if not animator or not animation_tree:
		push_warning("AnimationController '%s': animator o animation_tree no encontrado." % name)
		return
	_cache_valid_paths()

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
	},
	Config.ANIMATION.DEATH: {
		"death": 1.0
	},
	Config.ANIMATION.HIT: {
		"bHit": 1.0
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
	"death": 0.0,
}
var oneshot_params = ["attack_vertical", "attack_horizontal", "bHit"]

func _cache_valid_paths() -> void:
	var prop_names := {}
	for prop in animation_tree.get_property_list():
		prop_names[prop["name"]] = true
	_valid_blend_paths.clear()
	for parameter in current_values:
		var path := "parameters/%s/blend_amount" % parameter
		if prop_names.has(path):
			_valid_blend_paths.append(path)
	_has_hit_anim = prop_names.has("parameters/bHit/request")

func update_tree() -> void:
	if not is_instance_valid(animation_tree):
		return
	for path in _valid_blend_paths:
		animation_tree[path] = current_values[path.get_slice("/", 1)]


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

func trigger_hit() -> void:
	if not is_instance_valid(animation_tree) or not _has_hit_anim:
		return
	animation_tree["parameters/bHit/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func trigger_death() -> void:
	for parameter in current_values:
		if parameter != "death":
			current_values[parameter] = 0.0
	update_tree()

func add_animation_state(state_name, parameter_values: Dictionary):
	animation_states[state_name] = parameter_values

func add_animation_parameter(parameter_name, initial_value: float = 0.0):
	current_values[parameter_name] = initial_value
	if is_instance_valid(animation_tree):
		_cache_valid_paths()
