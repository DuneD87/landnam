class_name CombatStance
extends RefCounted

## Posturas de los packs debajo de las acciones. En cuerpo a cuerpo solo cambia el
## tronco: las piernas conservan su locomoción direccional, el salto y el agachado.
## El arquero lleva sus ciclos completos en las cuatro direcciones; el canal de
## apuntar pone encima el tensado, de modo que puede desplazarse con la flecha lista.
## Corriendo con armas cuerpo a cuerpo, solo se superponen los brazos: el tronco
## conserva el contrabalanceo del mismo ciclo que mueve la cadera y las piernas.
const STYLES := [&"greatsword", &"shield", &"archer"]
const BLEND_RATE := 7.0
## La carrera del escudo lleva un braceo ancho pensado para el cuerpo entero del
## actor original. Al superponer brazos se conserva solo un movimiento pequeño
## alrededor de su postura media de transporte, sin tocar los clips de ataque.
const SHIELD_RUN_MOTION := 0.15
## A dos manos se conserva más movimiento que con escudo, con la hoja más estable.
const GREATSWORD_RUN_MOTION := 0.45
const CARRY_LIBRARY := &"combat_carry"
static var _carry_library: AnimationLibrary
## Velocidad del pie en apoyo y fase del izquierdo, medidas en el rig destino.
const ARCHER_WALK := [
	[Vector2(0, 1), &"styles/archer_walk_forward", 1.08, 1, 0.267],
	[Vector2(0, -1), &"styles/archer_walk_back", 0.85, 1, 0.300],
	[Vector2(-1, 0), &"styles/archer_walk_left", 1.42, 1, 0.233],
	[Vector2(1, 0), &"styles/archer_walk_right", 1.58, 1, 0.300],
]
const ARCHER_RUN := [
	[Vector2(0, 1), &"styles/archer_run_forward", 3.51, 1, 0.233],
	[Vector2(0, -1), &"styles/archer_run_back", 2.62, 1, 0.167],
	[Vector2(-1, 0), &"styles/archer_run_left", 2.75, 1, 0.167],
	[Vector2(1, 0), &"styles/archer_run_right", 2.95, 1, 0.167],
]
var _weights := {&"greatsword": 0.0, &"shield": 0.0, &"archer": 0.0}
var _run_weight := 0.0


static func build(tree: AnimationNodeBlendTree, skeleton: Skeleton3D, animator: AnimationPlayer) -> void:
	_attach_carry(animator)
	var below := AnimGraph.input_of(tree, &"bJumpStart", 0)
	tree.disconnect_node(&"bJumpStart", 0)
	for style in STYLES:
		var prefix := "stance_" + String(style)
		var idle := AnimationNodeAnimation.new()
		idle.animation = StringName("styles/" + String(style) + ("_idle_01" if style == &"archer" else "_idle"))
		tree.add_node(StringName(prefix + "_idle"), idle)
		for gait in ["walk", "run"]:
			var node: AnimationNode
			if style == &"archer":
				node = Locomotion._space(ARCHER_WALK if gait == "walk" else ARCHER_RUN, animator)
			else:
				var clip := AnimationNodeAnimation.new()
				clip.animation = StringName("styles/" + String(style) + "_" + gait)
				node = clip
			tree.add_node(StringName(prefix + "_" + gait), node)
			tree.add_node(StringName(prefix + "_" + gait + "_speed"), AnimationNodeTimeScale.new())
			tree.connect_node(StringName(prefix + "_" + gait + "_speed"), 0, StringName(prefix + "_" + gait))
		tree.add_node(StringName(prefix + "_pace"), AnimationNodeBlend2.new())
		tree.connect_node(StringName(prefix + "_pace"), 0, StringName(prefix + "_walk_speed"))
		tree.connect_node(StringName(prefix + "_pace"), 1, StringName(prefix + "_run_speed"))
		tree.add_node(StringName(prefix + "_move"), AnimationNodeBlend2.new())
		tree.connect_node(StringName(prefix + "_move"), 0, StringName(prefix + "_idle"))
		tree.connect_node(StringName(prefix + "_move"), 1, StringName(prefix + "_pace"))
		var blend := AnimationNodeBlend2.new()
		if style != &"archer":
			AnimGraph.filter_branch(blend, skeleton, HumanRig.SPINE)
			var arms := AnimationNodeBlend2.new()
			AnimGraph.filter_branch(arms, skeleton, HumanRig.LEFT_SHOULDER)
			AnimGraph.filter_branch(arms, skeleton, HumanRig.RIGHT_SHOULDER)
			var run := AnimationNodeAnimation.new()
			run.animation = StringName("combat_carry/" + String(style) + "_run")
			var run_clip := AnimGraph.add_clip(tree, prefix + "_run_arms", run, false)
			tree.add_node(StringName(prefix + "_run_arms"), arms)
			tree.connect_node(StringName(prefix + "_run_arms"), 0, below)
			tree.connect_node(StringName(prefix + "_run_arms"), 1, run_clip)
			below = StringName(prefix + "_run_arms")
		tree.add_node(StringName(prefix), blend)
		tree.connect_node(StringName(prefix), 0, below)
		tree.connect_node(StringName(prefix), 1, StringName(prefix + "_move"))
		below = StringName(prefix)
	tree.connect_node(&"bJumpStart", 0, below)


static func _attach_carry(animator: AnimationPlayer) -> void:
	if animator.has_animation_library(CARRY_LIBRARY):
		return
	if _carry_library == null:
		_carry_library = AnimationLibrary.new()
		_carry_library.add_animation(&"shield_run", _steady_carry(animator.get_animation(&"styles/shield_run"), SHIELD_RUN_MOTION))
		_carry_library.add_animation(&"greatsword_run", _steady_carry(animator.get_animation(&"styles/greatsword_run"), GREATSWORD_RUN_MOTION))
	animator.add_animation_library(CARRY_LIBRARY, _carry_library)


## Reducir la oscilación alrededor de la media del ciclo conserva el movimiento
## continuo y el cierre del bucle; no congela los brazos en un fotograma arbitrario.
static func _steady_carry(source: Animation, motion: float) -> Animation:
	var result := source.duplicate(true) as Animation
	for track in result.get_track_count():
		if result.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var count := result.track_get_key_count(track)
		if count == 0:
			continue
		var reference: Quaternion = result.track_get_key_value(track, 0)
		var sum := Vector4.ZERO
		# El último fotograma cierra el ciclo: no se cuenta dos veces la misma pose.
		for key in maxi(count - 1, 1):
			var rotation: Quaternion = result.track_get_key_value(track, key)
			if reference.dot(rotation) < 0.0:
				rotation = -rotation
			sum += Vector4(rotation.x, rotation.y, rotation.z, rotation.w)
		var mean := Quaternion(sum.x, sum.y, sum.z, sum.w).normalized()
		for key in count:
			var rotation: Quaternion = result.track_get_key_value(track, key)
			result.track_set_key_value(track, key, mean.slerp(rotation, motion).normalized())
	return result


func update(combat: PlayerCombat, delta: float) -> void:
	var player := combat.player
	var tree := player.animation_controller.animation_tree
	if not combat._anims_ready:
		return
	var data := combat.weapon()
	var chosen: StringName = &""
	if data != null and not combat.cripple.active():
		if data.weapon_type == ItemData.WeaponType.BOW:
			chosen = &"archer"
		elif data.weapon_type in [ItemData.WeaponType.SWORD, ItemData.WeaponType.AXE, ItemData.WeaponType.MACE]:
			if data.two_handed:
				chosen = &"greatsword"
			elif combat._shield_data != null and combat._guard_item() == combat._shield_data:
				chosen = &"shield"
	var movement := player.movement
	if movement.is_swimming or movement.is_jumping or movement.is_falling or player.locomotion.crouching \
			or combat.state in [PlayerCombat.State.DODGE, PlayerCombat.State.STAGGER, PlayerCombat.State.DEAD] \
			or player.climb.is_active():
		chosen = &""
	var up := -player.gravity_direction.normalized()
	var velocity := player.velocity - up * player.velocity.dot(up)
	var speed := velocity.length()
	# Medido respecto al modelo (+X a la izquierda), igual que Locomotion._local_dir.
	var dir := Vector2(-velocity.dot(player.global_basis.x), velocity.dot(player.global_basis.z))
	var direction_weight := absf(dir.x) + absf(dir.y)
	if direction_weight > 0.001:
		dir /= direction_weight
	var running := not movement.walking or movement.is_brisk
	_run_weight = move_toward(_run_weight, 1.0 if not movement.walking and speed > 0.1 else 0.0,
		delta * BLEND_RATE)
	var run_blend := smoothstep(0.0, 1.0, _run_weight)
	for style in STYLES:
		var prefix := "parameters/stance_" + String(style)
		_weights[style] = move_toward(_weights[style], 1.0 if chosen == style else 0.0, delta * BLEND_RATE)
		var weight := smoothstep(0.0, 1.0, _weights[style])
		tree.set(prefix + "/blend_amount", weight if style == &"archer" else weight * (1.0 - run_blend))
		if style != &"archer":
			tree.set(prefix + "_run_arms/blend_amount", weight * run_blend)
		tree.set(prefix + "_move/blend_amount", smoothstep(0.05, 0.6, speed))
		tree.set(prefix + "_pace/blend_amount", 1.0 if style == &"archer" and running else 0.0)
		var walk_speed := _archer_speed(ARCHER_WALK, dir, player.animation_controller.animator) if style == &"archer" else 1.4
		var run_speed := _archer_speed(ARCHER_RUN, dir, player.animation_controller.animator) if style == &"archer" else 4.3
		tree.set(prefix + "_walk_speed/scale", clampf(speed / walk_speed, 0.4, 3.0))
		tree.set(prefix + "_run_speed/scale", clampf(speed / run_speed, 0.4, 3.0))
		if style != &"archer":
			tree.set(prefix + "_run_arms_speed/scale", clampf(speed / run_speed, 0.4, 3.0))
		if style == &"archer" and direction_weight > 0.001:
			tree.set(prefix + "_walk/blend_position", dir)
			tree.set(prefix + "_run/blend_position", dir)


func active(style: StringName) -> bool:
	return float(_weights.get(style, 0.0)) > 0.01


## Velocidad a la cadencia común, interpolada igual que el rombo del BlendSpace.
static func _archer_speed(clips: Array, dir: Vector2, animator: AnimationPlayer) -> float:
	var cycle := animator.get_animation(clips[0][1]).length
	var speed := 0.0
	for clip in clips:
		var direction: Vector2 = clip[0]
		var weight := maxf(dir.dot(direction), 0.0)
		speed += weight * float(clip[2]) * animator.get_animation(clip[1]).length / cycle
	return maxf(speed, 0.1)
