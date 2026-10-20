extends Node
class_name AnimationController

## Estados de locomoción del jugador y las criaturas: cada uno fija los pesos de las mezclas del
## árbol (animation_states).
enum Anim {IDLE, RUN, JUMP_START, JUMP_IDLE, JUMP_LAND, ATTACK_1,
ATTACK_2, SPRINT, FALLING, SWIM, SWIM_IDLE, DEATH, HIT, IDLE_TORCH, RUNNING_TORCH, TORCH_FOCUS,
WALK, WALK_TORCH, SPRINT_TORCH}

## Si no se asigna, busca la ruta por defecto del Player; los NPCs lo apuntan a su propio modelo.
@export var animator: AnimationPlayer
@export var animation_tree: AnimationTree
@export var blend_speed: float = 5.0

## Las criaturas lo encienden (NPCController): el árbol se avanza a mano, en cámara cada fotograma de
## cerca y uno de cada pocos de lejos (AnimationLod.CREATURE_STRIDES), uno de cada
## AnimationLod.HIDDEN_STRIDE fuera de ella, y oculto (en el pool) no se anima. El jugador lo deja
## apagado.
var throttled: bool = false: set = set_throttled
## Fuerza cada fotograma: un ataque mide sus golpes con los huesos.
var full_rate: bool = false
## Radio del cuerpo (m), para ver si asoma en cámara con el origen fuera.
var lod_radius: float = 0.0

var _valid_blend_paths: Array[String] = []
var _has_hit_anim: bool = false
## El árbol pasa la animación de muerte por un TimeSeek (death_seek): trigger_death la arranca.
var _has_death_seek: bool = false
var _accum: float = 0.0
var _frame: int = 0

func _ready() -> void:
	set_process(throttled)
	if not animator:
		animator = get_node_or_null("../PlayerModel/AnimationPlayer")
	if not animation_tree:
		animation_tree = get_node_or_null("../PlayerModel/AnimationTree")
	if not animator or not animation_tree:
		push_warning("AnimationController '%s': animator o animation_tree no encontrado." % name)
		return
	_cache_valid_paths()


func set_throttled(value: bool) -> void:
	throttled = value
	if is_instance_valid(animation_tree):
		animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if value \
			else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	# Repartidos: los que animan uno de cada pocos fotogramas no lo hacen todos en el mismo.
	_frame = randi() % 8
	_accum = 0.0
	set_process(value)


func _process(delta: float) -> void:
	if not is_instance_valid(animation_tree) or not animation_tree.active:
		return
	var body := get_parent() as Node3D
	if body == null or not body.is_visible_in_tree():
		_accum = 0.0
		return
	_accum += delta
	_frame += 1
	# Se mira en cada fotograma: al girar la cámara, el que entra en vista ya anima a su ritmo.
	var stride := 1 if full_rate else AnimationLod.stride_for(body, lod_radius, AnimationLod.CREATURE_STRIDES)
	if _frame % stride == 0:
		var start := Time.get_ticks_usec()
		animation_tree.advance(_accum)
		_accum = 0.0
		DebugStats.report_cost(&"npc:anim", Time.get_ticks_usec() - start)

var animation_states = {
	Anim.IDLE: {
	},
	Anim.WALK: {
		"bWalk": 1.0,
	},
	Anim.RUN: {
		"bRun": 1.0,
	},
	Anim.SPRINT: {
		"bSprint": 1.0,
	},
	Anim.JUMP_START: {
		"bJumpStart": 1.0,
	},
	Anim.JUMP_IDLE: {
		"bJumpIdle": 1.0,
	},
	Anim.JUMP_LAND: {
		"bJumpLand": 1.0
	},
	Anim.FALLING: {
		"bJumpIdle": 1.0,
	},
	Anim.SWIM: {
		"bSwim": 1.0
	},
	Anim.SWIM_IDLE: {
		"bSwimIdle": 1.0
	},
	Anim.ATTACK_1: {
		"attack_horizontal": 1.0
	},
	Anim.ATTACK_2: {
		"attack_vertical": 1.0
	},
	Anim.TORCH_FOCUS:
	{
		"bTorchFocus": 1.0
	},
	Anim.DEATH: {
		"death": 1.0
	},
	Anim.HIT: {
		"bHit": 1.0
	},
	# Los de la antorcha solo ponen el brazo derecho (Locomotion.build): el resto del cuerpo, el
	# de debajo.
	Anim.IDLE_TORCH: {
		"bIdleTorch": 1.0
	},
	Anim.RUNNING_TORCH: {
		"bRun": 1.0,
		"bRunningTorch": 1.0
	},
	Anim.WALK_TORCH: {
		"bWalk": 1.0,
		"bIdleTorch": 1.0
	},
	Anim.SPRINT_TORCH: {
		"bSprint": 1.0,
		"bRunningTorch": 1.0
	}
}

var current_values = {
	"bWalk": 0.0,
	"bRun": 0.0,
	"bSprint": 0.0,
	"bJumpStart": 0.0,
	"bJumpIdle": 0.0,
	"bJumpLand": 0.0,
	"bSwim": 0.0,
	"bSwimIdle": 0.0,
	"death": 0.0,
	"bIdleTorch": 0.0,
	"bRunningTorch": 0.0,
	"bTorchFocus": 0.0
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
	_has_death_seek = prop_names.has("parameters/death_seek/seek_request")

func update_tree() -> void:
	if not is_instance_valid(animation_tree):
		return
	for path in _valid_blend_paths:
		animation_tree[path] = current_values[path.get_slice("/", 1)]


func handle_animations(delta: float, current_animation, free_flight_enabled):
	if free_flight_enabled:
		return

	var target_value = animation_states.get(current_animation, {})

	for param in oneshot_params:
		if target_value.has(param):
			if not animation_tree["parameters/%s/active" % param]:
				animation_tree["parameters/%s/request" % param] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

	for parameter in current_values:
		if parameter in oneshot_params:
			continue
		if target_value.has(parameter):
			current_values[parameter] = lerpf(current_values[parameter], target_value[parameter], blend_speed * delta)
		else:
			current_values[parameter] = lerpf(current_values[parameter], 0, blend_speed * delta)

	update_tree()


## Pone [current_animation] de golpe, sin fundido: la criatura que se duerme lejos (o vuelve del
## pool) ya no pasa por handle_animations, y se quedaría con la zancada de antes.
func snap_to(current_animation) -> void:
	var target_value = animation_states.get(current_animation, {})
	for parameter in current_values:
		if parameter in oneshot_params:
			continue
		current_values[parameter] = target_value.get(parameter, 0.0)
	update_tree()

func trigger_hit() -> void:
	if not is_instance_valid(animation_tree) or not _has_hit_anim:
		return
	animation_tree["parameters/bHit/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


## Arranca la animación de muerte desde el principio, si el árbol la pasa por death_seek: si no,
## el clip, que suena desde que se creó el árbol, ya habría acabado y solo se fundiría su última
## pose.
func trigger_death() -> void:
	if is_instance_valid(animation_tree) and _has_death_seek:
		animation_tree["parameters/death_seek/seek_request"] = 0.0
