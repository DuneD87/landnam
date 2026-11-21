extends Node3D

## Carrera armada en el árbol real: el tronco debe conservar la locomoción base.
## godot --headless --path . res://tests/combat/test_combat_run.tscn
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _actor(style: StringName, gait: String, legacy: bool = false, unsteady_arms: bool = false) -> Dictionary:
	var model: Node3D = load("res://scenes/character/character_model.tscn").instantiate()
	add_child(model)
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var animator: AnimationPlayer = model.get_node("AnimationPlayer")
	animator.add_animation_library(&"combat", load(PlayerCombat.COMBAT_LIBRARY))
	animator.add_animation_library(&"styles", load(PlayerCombat.STYLE_LIBRARY))
	var graph: AnimationNodeBlendTree = load("res://data/resources/third_person_player._animation_treetres.tres").duplicate(true)
	Locomotion.build(graph, animator, skeleton)
	if unsteady_arms:
		(graph.get_node(StringName("stance_" + String(style) + "_run_arms_anim")) as AnimationNodeAnimation).animation = StringName("styles/" + String(style) + "_run")
	var tree := AnimationTree.new()
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(animator)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	tree.set("parameters/bRun/blend_amount", 1.0)
	tree.set("parameters/run_scale/scale", 4.0 / 4.3)
	tree.set("parameters/bSprint/blend_amount", 1.0 if gait == "sprint" else 0.0)
	tree.set("parameters/sprint_scale/scale", 6.0 / 4.4)
	if style != &"":
		var prefix := "parameters/stance_" + String(style)
		tree.set(prefix + "/blend_amount", 1.0 if legacy else 0.0)
		tree.set(prefix + "_run_arms/blend_amount", 0.0 if legacy else 1.0)
		tree.set(prefix + "_move/blend_amount", 1.0)
		tree.set(prefix + "_pace/blend_amount", 1.0 if legacy else 0.0)
		tree.set(prefix + "_run_speed/scale", (6.0 if gait == "sprint" else 4.0) / 4.3)
		tree.set(prefix + "_run_arms_speed/scale", (6.0 if gait == "sprint" else 4.0) / 4.3)
	var pose: CombatPose
	if style == &"greatsword":
		pose = CombatPose.new()
		pose.frame_node = model
		pose.grip_right = true
		pose.two_hand_grip = 1.0
		pose.active = false
		skeleton.add_child(pose)
	return {"model": model, "skeleton": skeleton, "tree": tree, "pose": pose, "grip_error": 0.0}

func _run() -> void:
	for gait in ["run", "sprint"]:
		for direction in [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1)]:
			for style in [&"greatsword", &"shield"]:
				var base := _actor(&"", gait)
				var armed := _actor(style, gait)
				var previous := _actor(style, gait, true)
				for actor in [base, armed, previous]:
					actor.tree.set("parameters/loco_run/blend_position", direction)
				var worst := 0.0
				var old_lean := Vector2(INF, -INF)
				var new_lean := Vector2(INF, -INF)
				for frame in 180:
					for actor in [base, armed, previous]:
						actor.tree.advance(1.0 / 60.0)
						actor.skeleton.force_update_all_bone_transforms()
					for bone in [HumanRig.HIPS, HumanRig.SPINE, HumanRig.SPINE1, HumanRig.SPINE2, HumanRig.NECK, HumanRig.HEAD]:
						var index: int = base.skeleton.find_bone(bone)
						worst = maxf(worst, base.skeleton.get_bone_pose_rotation(index).angle_to(armed.skeleton.get_bone_pose_rotation(index)))
					var before := _lean(previous.skeleton)
					var after := _lean(armed.skeleton)
					old_lean = Vector2(minf(old_lean.x, before), maxf(old_lean.y, before))
					new_lean = Vector2(minf(new_lean.x, after), maxf(new_lean.y, after))
				# También comprobar que el árbol está animando: una gráfica sin conectar
				# devolvería dos poses quietas idénticas y ocultaría el fallo.
				var ok := worst < 0.002 and new_lean.y - new_lean.x > 1.0
				if not ok:
					failures += 1
					push_error("FAIL: %s %s %s: tronco distinto de la locomoción (%.3f°)" % [style, gait, direction, rad_to_deg(worst)])
				else:
					print("PASS: %s %s %s: tronco acompasado; balanceo anterior %.1f°, actual %.1f°" %
						[style, gait, direction, old_lean.y - old_lean.x, new_lean.y - new_lean.x])
				for actor in [base, armed, previous]:
					actor.model.free()
	_check_arm_sway(&"shield")
	_check_arm_sway(&"greatsword")
	print("COMBAT RUN: 24 checks, %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _lean(skeleton: Skeleton3D) -> float:
	var up := skeleton.get_bone_global_pose(skeleton.find_bone(HumanRig.NECK)).origin \
		- skeleton.get_bone_global_pose(skeleton.find_bone(HumanRig.HIPS)).origin
	var model_up := skeleton.global_basis * up
	return rad_to_deg(atan2(model_up.x, model_up.y))


func _check_arm_sway(style: StringName) -> void:
	for gait in ["run", "sprint"]:
		for direction in [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1)]:
			var stable := _actor(style, gait)
			var previous := _actor(style, gait, false, true)
			var spans := [[Vector2(INF, -INF), Vector2(INF, -INF)], [Vector2(INF, -INF), Vector2(INF, -INF)]]
			var reference_rotations := [[Quaternion.IDENTITY, Quaternion.IDENTITY], [Quaternion.IDENTITY, Quaternion.IDENTITY]]
			var angles := [[0.0, 0.0], [0.0, 0.0]]
			for actor in [stable, previous]:
				actor.tree.set("parameters/loco_run/blend_position", direction)
			for frame in 120:
				for actor_index in 2:
					var actor: Dictionary = [stable, previous][actor_index]
					actor.tree.advance(1.0 / 60.0)
					actor.skeleton.force_update_all_bone_transforms()
					if actor.pose != null:
						var pose: CombatPose = actor.pose
						pose._apply()
						var hand := pose.hand_frame("Left")
						var center := pose.skeleton().global_transform * (pose.bone_pos(HumanRig.LEFT_HAND)
							+ (hand.x * CombatPose.FIST_HANDLE.x + hand.y * CombatPose.FIST_HANDLE.y) * pose.unit())
						actor.grip_error = maxf(actor.grip_error, center.distance_to(pose.right_grip_xform * Vector3(0, -0.18, 0)))
					for side in 2:
						var value := _hand_sideways(actor.skeleton, HumanRig.LEFT_HAND if side == 0 else HumanRig.RIGHT_HAND)
						var span: Vector2 = spans[actor_index][side]
						spans[actor_index][side] = Vector2(minf(span.x, value), maxf(span.y, value))
						# La muñeca podría agitar la hoja sin desplazar la mano: medir
						# también la orientación de la mano de espada y del antebrazo
						# que lleva el escudo, siempre respecto al pecho.
						var skeleton: Skeleton3D = actor.skeleton
						var chest := skeleton.get_bone_global_pose(skeleton.find_bone(HumanRig.SPINE2)).basis.orthonormalized()
						var bone := HumanRig.LEFT_FORE_ARM if side == 0 else HumanRig.RIGHT_HAND
						var basis := skeleton.get_bone_global_pose(skeleton.find_bone(bone)).basis.orthonormalized()
						var rotation := (chest.inverse() * basis).get_rotation_quaternion()
						if frame == 0:
							reference_rotations[actor_index][side] = rotation
						angles[actor_index][side] = maxf(angles[actor_index][side], rotation.angle_to(reference_rotations[actor_index][side]))
			var ok := float(stable.grip_error) < 0.06
			var sway_ratio := 0.7 if style == &"greatsword" else 0.35
			var angle_limit := deg_to_rad(35.0 if style == &"greatsword" else 20.0)
			var ranges: Array[float] = []
			for side in 2:
				var after: float = spans[0][side].y - spans[0][side].x
				var before: float = spans[1][side].y - spans[1][side].x
				ranges.append(after)
				# Limitar ambas manos respecto al pecho detecta el braceo horizontal
				# aunque la prueba del tronco dé bien. Exigir algo de movimiento evita
				# aceptar una animación detenida como solución.
				ok = ok and after < 0.12 and after < before * sway_ratio and after > 0.001
				ok = ok and angles[0][side] < angle_limit and angles[0][side] < angles[1][side] * sway_ratio
			if not ok:
				failures += 1
				push_error("FAIL: %s %s %s: braceo lateral %s; giros %s; agarre %.3f m" % [style, gait, direction, spans, angles, stable.grip_error])
			else:
				print("PASS: %s %s %s: desplazamiento lateral de manos %.1f / %.1f cm; agarre %.3f m" % [style, gait, direction, ranges[0] * 100.0, ranges[1] * 100.0, stable.grip_error])
			stable.model.free()
			previous.model.free()


func _hand_sideways(skeleton: Skeleton3D, hand: String) -> float:
	var left := skeleton.get_bone_global_pose(skeleton.find_bone(HumanRig.LEFT_ARM)).origin
	var right := skeleton.get_bone_global_pose(skeleton.find_bone(HumanRig.RIGHT_ARM)).origin
	var across := (skeleton.global_basis * (left - right)).normalized()
	var offset := skeleton.get_bone_global_pose(skeleton.find_bone(hand)).origin \
		- skeleton.get_bone_global_pose(skeleton.find_bone(HumanRig.SPINE2)).origin
	return (skeleton.global_basis * offset).dot(across)
