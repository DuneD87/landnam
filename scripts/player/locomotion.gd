class_name Locomotion
extends Node

## Andar y correr en todas direcciones, y agacharse.
##
## El cuerpo mira hacia donde mira la cámara (PlayerController.rotate_toward_movement), así que andar
## y correr eligen el clip según hacia dónde va respecto a él: delante, atrás, izquierda y derecha,
## en un BlendSpace2D que mezcla las diagonales. Todas las direcciones llevan la cadencia de la de
## delante (línea de tiempo propia, con el pie izquierdo adelantado a la misma fase del ciclo) para
## que al mezclarse no se pisen los pies; por eso cada una avanza lo que da su zancada a esa
## cadencia, y Movement.gait_scale ajusta la velocidad a la dirección para que los pies no patinen.
##
## Agachado (acción "crouch", Ctrl, alterna agachado y de pie): quieto y andar, encima de la
## locomoción y debajo del salto y el agua,
## con la cápsula baja y la cámara más abajo. De andar agachado solo hay hacia delante (muestra
## gratuita de MoCap Online): agachado, el cuerpo mira hacia donde va. Saltar o esprintar lo
## levantan, si cabe de pie.

const LIBRARY := "res://models/player/locomotion_anims.tres"

## Por dirección (x a la derecha, y adelante): [clip, lo que avanza a ritmo 1 (m/s, el pie apoyado
## sobre el cuerpo del jugador, como RUN_CLIP_SPEED), pasos dobles que trae, cuándo lleva el pie
## izquierdo más adelantado hacia donde va (s)]. La primera, la de delante, marca la cadencia.
const WALK_CLIPS := [
	[Vector2(0, 1), &"combat/walk_relaxed", 0.50, 3, 1.267],
	[Vector2(0, -1), &"loco/walk_back", 1.06, 1, 0.200],
	[Vector2(-1, 0), &"loco/walk_left", 1.70, 1, 0.200],
	[Vector2(1, 0), &"loco/walk_right", 1.70, 1, 0.733],
]
const RUN_CLIPS := [
	[Vector2(0, 1), &"running", 4.3, 1, 0.233],
	[Vector2(0, -1), &"loco/run_back", 2.91, 1, 0.167],
	[Vector2(-1, 0), &"loco/run_left", 4.13, 1, 0.200],
	[Vector2(1, 0), &"loco/run_right", 4.13, 1, 0.500],
]

## Andar agachado: lo que avanza a ritmo 1 y a qué ritmo va.
const CROUCH_CLIP_SPEED := 0.97
const CROUCH_RATE := 1.0
## Cápsula agachado (m, de los pies arriba) y cuánto baja la cámara.
const CROUCH_HEIGHT := 1.2
const CROUCH_CAMERA_DROP := 0.55
## Fundido al agacharse y levantarse, y entre quieto y andar agachado (1/s).
const CROUCH_BLEND := 6.0
const CROUCH_MOVE_BLEND := 8.0
## Holgura con que se prueba si cabe de pie: la cápsula de pie, así de alta sobre el suelo.
const STAND_CLEARANCE := 0.1

var player: PlayerController
var crouching := false
## Pulsado "crouch": se aplica en el siguiente pre_update. Con Ctrl pulsado el jugador no pasa por
## la física (PlayerController._physics_step), así que se lee por evento y se aplica al soltarlo.
var _toggle_requested := false

## Velocidad de cada dirección respecto a la de delante: [delante, atrás, lado], andando y corriendo.
var _walk_gait := Vector3.ONE
var _run_gait := Vector3.ONE
var _crouch := 0.0
var _crouch_move := 0.0
var _stand_shape: CapsuleShape3D
var _stand_y := 0.0
var _crouch_shape: CapsuleShape3D
var _crouch_y := 0.0


## Cambia andar y correr del árbol del jugador por sus BlendSpace2D ("loco_walk", "loco_run") y
## mete el agachado ("crouch") debajo del salto. Antes de que el árbol se asigne (PlayerCombat).
static func build(tree_root: AnimationNodeBlendTree, animator: AnimationPlayer) -> void:
	if not animator.has_animation_library(&"loco"):
		animator.add_animation_library(&"loco", load(LIBRARY))
	_replace(tree_root, &"WALK", &"walk_scale", &"loco_walk", _space(WALK_CLIPS, animator))
	_replace(tree_root, &"Animation", &"run_scale", &"loco_run", _space(RUN_CLIPS, animator))
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"loco/crouch_idle"
	var walk := AnimationNodeAnimation.new()
	walk.animation = &"loco/crouch_walk"
	tree_root.add_node(&"crouch_idle", idle)
	tree_root.add_node(&"crouch_walk", walk)
	tree_root.add_node(&"crouch_walk_scale", AnimationNodeTimeScale.new())
	tree_root.connect_node(&"crouch_walk_scale", 0, &"crouch_walk")
	tree_root.add_node(&"crouch_move", AnimationNodeBlend2.new())
	tree_root.connect_node(&"crouch_move", 0, &"crouch_idle")
	tree_root.connect_node(&"crouch_move", 1, &"crouch_walk_scale")
	# Debajo del salto: lo que entraba en él pasa por el agachado.
	var below := _input_of(tree_root, &"bJumpStart", 0)
	tree_root.disconnect_node(&"bJumpStart", 0)
	tree_root.add_node(&"crouch", AnimationNodeBlend2.new())
	tree_root.connect_node(&"crouch", 0, below)
	tree_root.connect_node(&"crouch", 1, &"crouch_move")
	tree_root.connect_node(&"bJumpStart", 0, &"crouch")


static func _space(clips: Array, animator: AnimationPlayer) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	# Todas avanzan a la vez, aunque no pesen: así siguen a la misma fase.
	space.sync = true
	var front: Array = clips[0]
	var cycle: float = animator.get_animation(front[1]).length / float(front[3])
	var phase: float = float(front[4]) / cycle
	for clip in clips:
		var anim := AnimationNodeAnimation.new()
		anim.animation = clip[1]
		if clip != front:
			var length := animator.get_animation(clip[1]).length
			anim.use_custom_timeline = true
			anim.timeline_length = cycle * float(clip[3])
			anim.stretch_time_scale = true
			anim.loop_mode = Animation.LOOP_LINEAR
			anim.start_offset = fposmod(float(clip[4]) - phase * length / float(clip[3]), length)
		space.add_blend_point(anim, clip[0])
	return space


static func _replace(tree_root: AnimationNodeBlendTree, old: StringName, into: StringName, node_name: StringName,
		node: AnimationNode) -> void:
	tree_root.remove_node(old)
	tree_root.add_node(node_name, node)
	tree_root.connect_node(into, 0, node_name)


static func _input_of(tree_root: AnimationNodeBlendTree, node: StringName, port: int) -> StringName:
	var connections: Array = tree_root.get("node_connections")
	for i in range(0, connections.size(), 3):
		if connections[i] == node and int(connections[i + 1]) == port:
			return connections[i + 2]
	return StringName()


func setup(owner_player: PlayerController) -> void:
	player = owner_player
	var animator := player.animation_controller.animator
	_walk_gait = _gaits(WALK_CLIPS, animator)
	_run_gait = _gaits(RUN_CLIPS, animator)
	_stand_shape = player.collision_shape.shape as CapsuleShape3D
	_stand_y = player.collision_shape.position.y
	_crouch_shape = _stand_shape.duplicate() as CapsuleShape3D
	_crouch_shape.height = CROUCH_HEIGHT
	# Los pies, donde estaban.
	_crouch_y = _stand_y - (_stand_shape.height - CROUCH_HEIGHT) * 0.5


## Lo que avanza cada dirección respecto a la de delante, a la cadencia de esta.
static func _gaits(clips: Array, animator: AnimationPlayer) -> Vector3:
	var front: Array = clips[0]
	var cycle: float = animator.get_animation(front[1]).length / float(front[3])
	var stride := {}
	for clip in clips:
		var length := animator.get_animation(clip[1]).length
		# A la cadencia de delante, el clip va a length / (cycle * pasos) de su ritmo.
		stride[clip[0]] = float(clip[2]) * length / (cycle * float(clip[3]))
	var front_speed: float = stride[Vector2(0, 1)]
	return Vector3(1.0, stride[Vector2(0, -1)] / front_speed,
		(stride[Vector2(-1, 0)] + stride[Vector2(1, 0)]) * 0.5 / front_speed)


## Antes de leer el movimiento: agacharse o levantarse, y la velocidad según la dirección.
func pre_update() -> void:
	var movement := player.movement
	var combat := player.combat
	# En el aire, en el agua, trepando, lisiado o muerto, de pie aunque no quepa.
	var can_crouch := not movement.is_jumping and not movement.is_falling and not movement.is_swimming \
		and not player.climb.is_active() and not combat.cripple.active() and not combat.is_dead()
	# Golpear, esquivar o tambalearse lo levantan; apuntar y la guardia, no.
	var acting := combat.state in [PlayerCombat.State.ATTACK, PlayerCombat.State.DODGE, PlayerCombat.State.STAGGER]
	var toggle := _toggle_requested
	_toggle_requested = false
	if not can_crouch or acting:
		_set_crouching(false, not can_crouch)
	elif toggle:
		_set_crouching(not crouching)
	elif crouching and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("Sprint")):
		_set_crouching(false)
	# Agachado no se salta ni se esprinta: saltar o esprintar solo lo levantan.
	if crouching or (Input.is_action_just_pressed("jump") and _crouch > 0.0):
		movement.jump_blocked = true
	if crouching:
		movement.sprint_blocked = true
	movement.gait_scale = _gait_scale()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("crouch") and player != null and player.input_enabled \
			and player.is_mouse_captured():
		_toggle_requested = true


func _gait_scale() -> float:
	var movement := player.movement
	if crouching:
		return CROUCH_CLIP_SPEED * CROUCH_RATE / maxf(movement.walk_speed if movement.walking else movement.speed, 0.01)
	if player.combat.cripple.active():
		return 1.0
	var dir := _local_dir()
	var gait := _walk_gait if movement.walking else _run_gait
	var weight := absf(dir.x) + absf(dir.y)
	if weight < 1e-3:
		return 1.0
	# Como el BlendSpace2D en el borde del rombo: cada eje pesa lo que su parte de la dirección.
	return (absf(dir.y) * (gait.x if dir.y >= 0.0 else gait.y) + absf(dir.x) * gait.z) / weight


## Hacia dónde va respecto al cuerpo: x a su derecha, y adelante.
func _local_dir() -> Vector2:
	var dir := player.movement.direction
	var basis := player.global_basis
	return Vector2(-dir.dot(basis.x), dir.dot(basis.z))


## Después del combate: el árbol y la cámara.
func update(delta: float) -> void:
	var tree := player.animation_controller.animation_tree
	if tree == null:
		return
	var dir := _local_dir()
	var weight := absf(dir.x) + absf(dir.y)
	if weight > 1e-3:
		tree.set(&"parameters/loco_walk/blend_position", dir / weight)
		tree.set(&"parameters/loco_run/blend_position", dir / weight)
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, delta * CROUCH_BLEND)
	var up := -player.gravity_direction.normalized()
	var flat_v := player.velocity - up * player.velocity.dot(up)
	var crouch_speed := CROUCH_CLIP_SPEED * CROUCH_RATE
	var moving := clampf(flat_v.length() / crouch_speed, 0.0, 1.0)
	_crouch_move = move_toward(_crouch_move, 1.0 if moving > 0.2 else 0.0, delta * CROUCH_MOVE_BLEND)
	tree.set(&"parameters/crouch/blend_amount", smoothstep(0.0, 1.0, _crouch))
	tree.set(&"parameters/crouch_move/blend_amount", smoothstep(0.0, 1.0, _crouch_move))
	tree.set(&"parameters/crouch_walk_scale/scale", CROUCH_RATE * maxf(moving, 0.3))
	player.camera_controller.crouch_drop = CROUCH_CAMERA_DROP * smoothstep(0.0, 1.0, _crouch)


## [force] lo levanta aunque no quepa (al nadar, trepar, caer o morir).
func _set_crouching(value: bool, force: bool = false) -> void:
	if value == crouching:
		return
	if not value and not force and not _fits_standing():
		return
	crouching = value
	player.collision_shape.shape = _crouch_shape if value else _stand_shape
	player.collision_shape.position.y = _crouch_y if value else _stand_y


## Si la cápsula de pie cabe donde está, algo levantada para no tocar el suelo.
func _fits_standing() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_shape
	query.transform = player.global_transform * Transform3D(Basis.IDENTITY,
		Vector3(0.0, _stand_y + STAND_CLEARANCE, 0.0))
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Al reaparecer o cargar: de pie.
func reset() -> void:
	_set_crouching(false, true)
	_crouch = 0.0
	_crouch_move = 0.0
	if player.camera_controller != null:
		player.camera_controller.crouch_drop = 0.0
