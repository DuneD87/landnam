extends Node3D

## Repertorios nuevos: colisión real de la hoja, agarre y selección con el equipo.
## godot --headless --path . res://tests/combat/test_combat_styles.tscn
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var model: Node3D = load("res://scenes/character/character_model.tscn").instantiate()
	add_child(model)
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var animator: AnimationPlayer = model.get_node("AnimationPlayer")
	var library: AnimationLibrary = load(PlayerCombat.STYLE_LIBRARY)
	animator.add_animation_library(&"styles", library)
	var pose := CombatPose.new()
	pose.frame_node = model
	pose.grip_right = true
	pose.active = false
	skeleton.add_child(pose)
	var target := Node3D.new()
	add_child(target)
	var health := HealthComponent.new()
	target.add_child(health)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	Hurtbox.attach(target, target, shape, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 1.05)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for id in [&"greatsword", &"stone_maul", &"iron_sword"]:
		var data := ItemCatalog.get_item(id)
		target.position.z = 0.55 if id == &"stone_maul" else 0.0
		await get_tree().physics_frame
		var family := MeleeMoveset.family_for(data, id == &"iron_sword")
		pose.two_hand_grip = 1.0 if data.two_handed else 0.0
		for kind in ["light", "heavy", "dash"]:
			for index in (3 if kind == "light" else 1):
				# El mazo solo hiere con la cabeza: el salto y la entrada cubren más
				# distancia que los ligeros, y el mango cercano no causa daño.
				if id == &"stone_maul":
					target.position.z = {"light": 0.55, "heavy": 1.15, "dash": 1.35}[kind]
					await get_tree().physics_frame
				var move := MeleeMoveset.move(family, kind, index)
				var animation: Animation = library.get_animation(move.anim)
				var start := float(move.get("from", 0.0))
				var hit: Vector2 = move.hit
				check(animation != null and start < hit.x and hit.x < hit.y and hit.y <= float(move.commit)
					and float(move.commit) <= float(move.end) and float(move.end) <= animation.length + 0.01,
					"%s %s %d: ventanas dentro del clip" % [id, kind, index])
				if kind == "heavy":
					check(float(move.charge) >= start and float(move.charge) < hit.x,
						"%s: carga antes del impacto" % id)
				animator.play(StringName("styles/" + String(move.anim)))
				var sweep := MeleeSweep.new(data.blade_radius)
				var touched := false
				var max_grip_error := 0.0
				var lunge: Vector3 = move.get("lunge", Vector3.ZERO)
				for frame in range(int(start * 60), int(float(move.commit) * 60) + 1):
					var time := frame / 60.0
					var travel := clampf((time - lunge.x) / maxf(lunge.y - lunge.x, 0.001), 0.0, 1.0) * lunge.z
					model.position.z = travel
					animator.seek(time, true)
					skeleton.force_update_all_bone_transforms()
					pose._apply()
					var grip := pose.right_grip_xform
					if data.two_handed:
						var hand := pose.hand_frame("Left")
						var center := skeleton.global_transform * (pose.bone_pos(HumanRig.LEFT_HAND)
							+ (hand.x * CombatPose.FIST_HANDLE.x + hand.y * CombatPose.FIST_HANDLE.y) * pose.unit())
						max_grip_error = maxf(max_grip_error, center.distance_to(grip * Vector3(0, -0.18, 0)))
					if time >= hit.x and time <= hit.y:
						var hits := sweep.sweep(space, grip * Vector3(0, data.blade_start, 0), grip * Vector3(0, data.reach, 0))
						touched = touched or not hits.is_empty()
				check(touched, "%s %s %d: la hoja alcanza una cápsula delante" % [id, kind, index])
				if data.two_handed:
					check(max_grip_error < 0.12, "%s %s %d: apoyo en el mango (%.3f m)" % [id, kind, index, max_grip_error])
	model.position = Vector3.ZERO
	var sword := ItemCatalog.get_item(&"iron_sword")
	var pick := ItemCatalog.get_item(&"stone_pickaxe_01")
	check(MeleeMoveset.family_for(sword) == &"sword" and MeleeMoveset.family_for(sword, true) == &"shield",
		"poner o quitar escudo cambia el repertorio")
	check(MeleeMoveset.family_for(pick, true) == &"pickaxe", "el escudo conserva el gesto de picar")
	check(MeleeMoveset.family_for(ItemCatalog.get_item(&"greatsword"), true) == &"greatsword",
		"el escudo transportado no cambia las dos manos")
	for name in library.get_animation_list():
		if name.begins_with("archer_") or name.ends_with("_idle") or name.ends_with("_walk") or name.ends_with("_run"):
			check(library.get_animation(name).loop_mode == Animation.LOOP_LINEAR, "%s: locomoción en bucle" % name)
	await _check_runtime()
	model.queue_free()
	target.queue_free()
	print("COMBAT STYLES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


class GroundedPlayer extends PlayerController:
	func is_ground_ready() -> bool:
		return true

func _check_runtime() -> void:
	var menu := Control.new()
	add_child(menu)
	for button_name in ["btnSaveGame", "btnStartGame"]:
		var button := Button.new()
		button.name = button_name
		menu.add_child(button)
		button.owner = menu
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	add_child(spawn)
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.set_script(GroundedPlayer)
	player.main_menu = menu
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	GameManager.current_state = GameManager.State.PLAYING
	player.inventory.clear()
	var combat := player.combat
	var shield := ItemCatalog.get_item(&"heater_shield")
	player.movement.is_falling = false
	player.movement.is_jumping = false
	player.movement.is_swimming = false
	for index in 3:
		var previous := combat.detach_weapon()
		if previous != null:
			previous.free()
		var data := ItemCatalog.get_item([&"iron_sword", &"greatsword", &"hunting_bow"][index])
		player.equiped_weapon = data
		player.right_hand_equipped = true
		combat.attach_weapon(load(data.scene_path).instantiate(), data)
		if index == 0:
			combat.attach_shield(load(shield.scene_path).instantiate(), shield)
		combat.stance.update(combat, 1.0)
		var style: StringName = [&"shield", &"greatsword", &"archer"][index]
		check(combat.stance.active(style), "%s: postura al empuñar" % style)
		if index < 2:
			_check_running_posture(combat, style)
			combat._since_dodge = 999.0
			combat._start_attack(false)
			check(combat._move_family == style and combat._act[combat._attack_slot].active,
				"%s: ataque en el canal real del jugador" % style)
			combat._abort_attack()
			combat._set_state(PlayerCombat.State.IDLE)
			combat._since_dodge = 0.0
			combat._start_attack(false)
			check(combat._move_kind == "dash" and combat._move.anim == MeleeMoveset.move(style, "dash", 0).anim,
				"%s: ataque propio tras esquivar" % style)
			combat._abort_attack()
			combat._set_state(PlayerCombat.State.IDLE)
			combat.stamina.stamina = combat.stamina.max_stamina
			combat.stamina.exhausted = false
	combat.detach_weapon().free()
	player.equiped_weapon = null
	player.right_hand_equipped = false
	combat.stance.update(combat, 1.0)
	check(not combat.stance.active(&"archer"), "retirar el arco de la mano retira la postura")
	player.queue_free()
	menu.queue_free()
	spawn.queue_free()


func _check_running_posture(combat: PlayerCombat, style: StringName) -> void:
	var player := combat.player
	var tree := player.animation_controller.animation_tree
	var prefix := "parameters/stance_" + String(style)
	player.movement.walking = false
	player.velocity = player.global_basis.z * 4.0
	combat.stance.update(combat, 0.05)
	var transition: float = tree.get(prefix + "_run_arms/blend_amount")
	check(transition > 0.0 and transition < 1.0, "%s: la postura de carrera entra con fundido" % style)
	combat.stance.update(combat, 1.0)
	check(is_zero_approx(tree.get(prefix + "/blend_amount"))
		and is_equal_approx(tree.get(prefix + "_run_arms/blend_amount"), 1.0),
		"%s: corriendo el pack mueve brazos, la locomoción mueve el tronco" % style)
	player.velocity = player.global_basis.z * 6.0
	player.movement.is_sprinting = true
	combat.stance.update(combat, 1.0)
	check(is_zero_approx(tree.get(prefix + "/blend_amount")), "%s: esprintar conserva el tronco de la carrera" % style)
	player.movement.is_sprinting = false
	player.movement.walking = true
	player.velocity = player.global_basis.z * 0.6
	combat.stance.update(combat, 1.0)
	check(is_equal_approx(tree.get(prefix + "/blend_amount"), 1.0)
		and is_zero_approx(tree.get(prefix + "_run_arms/blend_amount")), "%s: andar recupera la postura completa" % style)
	player.velocity = Vector3.ZERO
	combat.stance.update(combat, 1.0)
	player.movement.walking = false
