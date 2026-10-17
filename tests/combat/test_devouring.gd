extends Node

## Devorado por una fiera (Devouring) sin el planeta: los restos del jugador (PlayerRemains) copian
## el cuerpo real en la pose en que ha caído el muñeco, se les arrancan los cuatro miembros (que
## caen y se quedan), sueltan las vísceras y dan tirones que vuelven a la pose; un lobo de verdad
## va a comérselos (FeedState) con su clip de comer y se va cuando están despiezados; y sellados se
## quedan quietos para siempre.
##   godot --headless --path . res://tests/combat/test_devouring.tscn

const MODEL := "res://scenes/character/character_model.tscn"
const GRAVITY := Vector3(0, -9.8, 0)

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_floor()
	var model: Node3D = load(MODEL).instantiate()
	add_child(model)
	(model.get_node("AppearanceRig") as CharacterAppearanceRig).apply(CharacterAppearance.new())
	var skel: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var hips := skel.find_bone(PlayerRemains.ROOT_BONE)
	var standing := (skel.global_transform * skel.get_bone_global_pose(hips).origin).y
	var ragdoll := Ragdoll.new()
	ragdoll.frame_node = model
	ragdoll.gravity = GRAVITY
	ragdoll.world_mask = 1
	skel.add_child(ragdoll)
	await get_tree().physics_frame
	ragdoll.start(Vector3.ZERO, Vector3(0, 0, -20))
	var remains := PlayerRemains.spawn(self, model.global_transform, ragdoll)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(remains.feed_point().distance_to(ragdoll.center()) < 0.01,
		"antes de montarse, los restos llevan a la fiera al muñeco")
	var frames := 0
	while not ragdoll.is_settled() and frames < 900:
		await get_tree().physics_frame
		frames += 1
	check(ragdoll.is_settled(), "el muñeco se asienta (%d fotogramas)" % frames)

	# La pose de verdad es la de dentro de la actualización del esqueleto (con el muñeco).
	var captured := {}
	var capture := func() -> void:
		var pose: Array[Transform3D] = []
		for b in skel.get_bone_count():
			pose.append(skel.get_bone_pose(b))
		captured.pose = pose
		captured.hips = skel.global_transform * skel.get_bone_global_pose(hips).origin
	skel.skeleton_updated.connect(capture, CONNECT_ONE_SHOT)
	while captured.is_empty() and frames < 1000:
		await get_tree().process_frame
		frames += 1
	check(not captured.is_empty() and (captured.hips as Vector3).y < standing - 0.4,
		"el cuerpo ha caído: la pelvis de %.2f m a %.2f m" % [standing, captured.get("hips", Vector3.ZERO).y])
	remains.build(skel, captured.pose, model, null, GRAVITY)
	model.visible = false
	ragdoll.stop()
	await get_tree().process_frame
	var copy := remains.skeleton
	var body := copy.get_node_or_null(^"Mesh_0") as MeshInstance3D
	var source := skel.get_node(^"Mesh_0") as MeshInstance3D
	check(copy.get_bone_count() == skel.get_bone_count() and body != null and body.mesh == source.mesh
		and body.skin == source.skin, "los restos copian el esqueleto y el cuerpo")
	var at := copy.global_transform * copy.get_bone_global_pose(hips).origin
	check(at.distance_to(captured.hips) < 0.01, "en la pose del muñeco (la pelvis a %.3f m)" % at.distance_to(captured.hips))
	check(remains.is_in_group(PlayerRemains.GROUP) and remains.is_in_group(&"floating_origin"),
		"van con el origen flotante")

	# Tirón de un bocado: se nota y vuelve a la pose.
	var spine := copy.find_bone(&"mixamorig_Spine2")
	var rest := copy.get_bone_pose_rotation(spine)
	remains.tug(&"mixamorig_Spine2", Vector3.RIGHT, 20.0, 0.05)
	await _wait(0.1)
	var pulled := rad_to_deg(copy.get_bone_pose_rotation(spine).angle_to(rest))
	await _wait(PlayerRemains.TUG_TIME)
	var back := rad_to_deg(copy.get_bone_pose_rotation(spine).angle_to(rest))
	check(pulled > 5.0 and back < 0.1, "un tirón de %.1f° que vuelve a la pose (%.2f°)" % [pulled, back])

	await _check_species(remains)

	# Un lobo se los come: la boca sobre lo que muerde, y el brazo que arranca, en la boca.
	var original := source.mesh
	var wolf := await _feeding_wolf(remains)

	# Los otros tres miembros: los cortes se aplican, lo arrancado cae y se queda.
	var torn := 0
	for zone in [&"right_arm", &"left_leg", &"right_leg"]:
		if remains.sever(zone, true, Vector3.RIGHT, Vector3(1.5, 1.5, 0)):
			torn += 1
	check(torn == 3 and not remains.sever(&"left_arm", true, Vector3.RIGHT, Vector3.ZERO),
		"se arrancan los demás miembros, y uno arrancado no se arranca otra vez")
	frames = 0
	while remains.dismemberment.is_busy() and frames < 600:
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame
	var caps := copy.find_children("*", "MeshInstance3D", true, false).filter(func(node: Node) -> bool:
		return node.has_meta(Dismemberment.CAP_META)).size()
	check(not remains.dismemberment.is_busy() and body.mesh != source.mesh and caps >= 4,
		"el cuerpo queda cortado, con %d muñones tapados" % caps)
	check(source.mesh == original, "sin tocar el cuerpo del jugador")
	var kept := remains.limbs.filter(func(limb: Node) -> bool:
		return is_instance_valid(limb) and limb is SeveredLimb and (limb as SeveredLimb)._kept).size()
	check(kept == 4, "los cuatro miembros caen y se quedan (%d)" % kept)

	remains.spill_guts(Vector3.RIGHT)
	check(remains.get_node_or_null(^"GutPile") != null, "las vísceras salen al suelo")
	await _check_open_torso(remains, skel, source)

	# Despiezado: el lobo come un rato más y se va.
	var state := wolf.ai_controller.get_node(^"FeedState") as FeedState
	state.profile = state.profile.duplicate()
	state.profile.feed_time = Vector2(0.3, 0.3)
	remains.devoured = true
	await _wait(0.8)
	check(wolf.ai_controller.get_current_state() != &"FeedState" and remains.eating().is_empty(),
		"despiezado, come un rato y se va (%s)" % wolf.ai_controller.get_current_state())
	wolf.queue_free()

	remains.seal()
	await _wait(0.2)
	var still := remains.limbs.filter(func(limb: Node) -> bool:
		return is_instance_valid(limb) and not (limb as SeveredLimb).ragdoll.is_running()).size()
	check(remains.dismemberment == null and remains.devoured and still == 4,
		"sellados: sin Dismemberment y lo arrancado quieto (%d)" % still)
	check(is_instance_valid(remains) and is_instance_valid(remains.skeleton), "y se quedan")
	await _check_save(remains)
	print("DEVOURING TESTS: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Cada especie que come carne va a los restos y come con la boca (la punta de la mandíbula, con el
## cuello ya girado) sobre el tronco, con sus clips de comer (también los prestados).
func _check_species(remains: PlayerRemains) -> void:
	var planet := _planet()
	for species in ["Wolf", "Bear", "Lion", "Lioness", "Puma", "Hyena", "Alligator"]:
		var npc := (load("res://scenes/animals/%s.tscn" % species) as PackedScene).instantiate() as NPCController
		add_child(npc)
		npc.apply_variant(null)
		npc.perception.set_physics_process(false)
		npc.planet = planet
		var torso := remains.torso_point()
		npc.global_position = Vector3(torso.x + 4.0, 0.05, torso.z + 1.0)
		npc.feed_on(remains)
		var state := npc.ai_controller.get_node(^"FeedState") as FeedState
		var waited := 0.0
		while not state.is_eating() and waited < 12.0:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
		# Fuera de la carne (en el aire) no; hundida un poco en ella, sí.
		var worst := 0.0
		var average := 0.0
		var deepest := 0.0
		for i in 60:
			await get_tree().process_frame
		for i in 90:
			await get_tree().process_frame
			var mouth := state.mouth_transform().origin
			var gap := remains.bite_gap(state, mouth)
			worst = maxf(worst, gap)
			average += maxf(gap, 0.0) / 90.0
			deepest = minf(deepest, gap)
		var playing := npc.get_action_channel() != null and npc.get_action_channel().is_playing()
		check(state.is_eating() and playing and average < 0.04 and worst < 0.1 and deepest > -0.1,
			"%s come con la boca en la carne del tronco (fuera %.2f m de media, %.2f como mucho; hundida %.2f; %s)" \
				% [species, average, worst, -deepest, state._anim])
		npc.queue_free()
		await get_tree().process_frame
	planet.queue_free()


## Abierto en canal: el hueco, a la medida del cuerpo, se vacía de la malla del cuerpo por delante
## (y no por detrás), dentro queda la cavidad con la columna y las costillas, y la canal no se pierde
## si luego se corta algo más.
func _check_open_torso(remains: PlayerRemains, skel: Skeleton3D, source: MeshInstance3D) -> void:
	var skin := source.skin
	var toe := -1
	var foot := -1
	for b in skin.get_bind_count():
		match String(skin.get_bind_name(b)):
			"mixamorig_LeftToeBase":
				toe = b
			"mixamorig_LeftFoot":
				foot = b
	check(toe >= 0 and foot >= 0 and skin.get_bind_pose(toe).affine_inverse().origin.z
		> skin.get_bind_pose(foot).affine_inverse().origin.z, "en la piel del cuerpo, +Z es delante (los dedos del pie)")
	var body := remains.skeleton.get_node(^"Mesh_0") as MeshInstance3D
	var before := _triangles(body.mesh)
	check(remains.open_torso() and not remains.open_torso(), "se abre en canal, una vez")
	var wound := remains.wound
	var radii: Vector3 = wound.radii
	check(radii.x > 0.05 and radii.x <= HumanCarcass.MAX_HALF_WIDTH and radii.y > 0.1 and radii.y < 0.35
		and wound.front - wound.back > 0.15 and wound.front - wound.back < 0.45,
		"el hueco, a la medida del cuerpo: %.2f × %.2f m, tronco de %.2f m de grueso" % [radii.x * 2.0, radii.y * 2.0, wound.front - wound.back])
	var frames := 0
	while remains.dismemberment.is_busy() and frames < 600:
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame
	var after := _triangles(body.mesh)
	var front := _in_wound(body.mesh, wound, 1.0)
	var behind := _in_wound(body.mesh, wound, -1.0)
	check(after < before and front == 0 and behind > 0,
		"se va la piel de delante (%d triángulos menos) y la de detrás se queda (%d)" % [before - after, behind])
	var cavity := remains.skeleton.get_node_or_null(^"TorsoCavity/Cavity") as MeshInstance3D
	check(cavity != null and cavity.mesh.get_surface_count() == 3, "dentro, la cavidad, la sangre y los huesos")
	# Al centro del hueco (mundo) le cae encima la cavidad.
	var center_world := remains.skeleton.global_transform \
		* (remains.skeleton.get_bone_global_pose(wound.bone) * (wound.body_bind as Transform3D) * (wound.center as Vector3))
	var aabb := cavity.global_transform * cavity.mesh.get_aabb()
	check(aabb.grow(0.02).has_point(center_world), "en su sitio, en el tronco")
	remains.sever(&"left_arm", false, Vector3.RIGHT, Vector3.ZERO)
	while remains.dismemberment.is_busy() and frames < 1200:
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame
	check(_in_wound(body.mesh, wound, 1.0) == 0, "y sigue abierto aunque se vuelva a cortar")


## Guardados y cargados (por JSON, como en la partida) se rehacen igual: el cuerpo cortado y abierto
## en canal, la cavidad, las vísceras y los miembros arrancados donde quedaron.
func _check_save(remains: PlayerRemains) -> void:
	var data: Variant = JSON.parse_string(JSON.stringify(remains.get_save_data()))
	check(data is Dictionary and not (data as Dictionary).is_empty() and remains.save_category == "remains"
		and remains.is_in_group(GameManager.SAVEABLE_GROUP), "se guardan en la partida")
	var copy := (load(PlayerRemains.SCENE_PATH) as PackedScene).instantiate() as PlayerRemains
	copy.entity_id = remains.entity_id
	add_child(copy)
	copy.restore_save_data(data)
	var waited := 0.0
	while (copy.dismemberment != null or not copy.built) and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(copy.built and copy.devoured and copy.dismemberment == null, "se rehacen al cargar (%.1f s)" % waited)
	var body := remains.skeleton.get_node(^"Mesh_0") as MeshInstance3D
	var rebuilt := copy.skeleton.get_node_or_null(^"Mesh_0") as MeshInstance3D
	check(rebuilt != null and _triangles(rebuilt.mesh) == _triangles(body.mesh),
		"con el cuerpo igual de cortado y abierto (%d triángulos, antes %d)" % [_triangles(rebuilt.mesh) if rebuilt else 0, _triangles(body.mesh)])
	var hips := copy.skeleton.find_bone(PlayerRemains.ROOT_BONE)
	var at := copy.skeleton.global_transform * copy.skeleton.get_bone_global_pose(hips).origin
	var was := remains.skeleton.global_transform * remains.skeleton.get_bone_global_pose(hips).origin
	check(at.distance_to(was) < 0.01, "en su sitio y su pose (la pelvis a %.3f m)" % at.distance_to(was))
	check(copy.skeleton.get_node_or_null(^"TorsoCavity/Cavity") != null and copy.get_node_or_null(^"GutPile") != null,
		"abierto en canal y con las vísceras al lado")
	var worst := 0.0
	var placed := 0
	for limb in copy.limbs:
		for old in remains.limbs:
			if (old as SeveredLimb).cut_bone == (limb as SeveredLimb).cut_bone:
				var a := (limb as SeveredLimb).skeleton
				var b := (old as SeveredLimb).skeleton
				var bone := a.find_bone((limb as SeveredLimb).cut_bone)
				var tip := (a.global_transform * a.get_bone_global_pose(bone + 1).origin).distance_to(
					b.global_transform * b.get_bone_global_pose(bone + 1).origin)
				worst = maxf(worst, tip)
				placed += 1
	check(placed == 4 and worst < 0.02, "y los cuatro miembros donde quedaron (a %.3f m como mucho)" % worst)
	copy.queue_free()


func _triangles(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		count += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return count


## Triángulos de [mesh] (en el espacio de la piel del cuerpo) con el centro en el hueco de [wound]:
## por delante ([side] 1) o por detrás (-1).
func _in_wound(mesh: Mesh, wound: Dictionary, side: float) -> int:
	var center: Vector3 = wound.center
	var radii: Vector3 = wound.radii
	var count := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var c := (verts[indices[t]] + verts[indices[t + 1]] + verts[indices[t + 2]]) / 3.0 - center
			var qx := c.x / radii.x
			var qy := c.y / radii.y
			if qx * qx + qy * qy <= 0.6 and c.z * side > radii.z * 0.5:
				count += 1
	return count


func _planet() -> Node3D:
	var planet_script := GDScript.new()
	planet_script.source_code = "extends Node3D\nvar planet = null\nvar gravity_strength := 9.8\n" \
		+ "func get_gravity_direction(_p: Vector3) -> Vector3:\n\treturn Vector3.DOWN\n"
	planet_script.reload()
	var planet := Node3D.new()
	planet.set_script(planet_script)
	add_child(planet)
	return planet


## Un lobo va a los restos y come con su clip, con la boca (la punta de la mandíbula, con el cuello
## ya girado) sobre lo que muerde; el brazo que arranca se lo lleva colgando de la boca y lo suelta.
func _feeding_wolf(remains: PlayerRemains) -> NPCController:
	var planet := _planet()
	var wolf := (load("res://scenes/animals/Wolf.tscn") as PackedScene).instantiate() as NPCController
	add_child(wolf)
	wolf.apply_variant(null)
	wolf.perception.set_physics_process(false)
	wolf.planet = planet
	var torso := remains.torso_point()
	wolf.global_position = Vector3(torso.x + 4.0, 0.05, torso.z + 1.0)
	check(wolf.feed_on(remains) and wolf.ai_controller.get_current_state() == &"FeedState",
		"el lobo va a comer")
	var state := wolf.ai_controller.get_node(^"FeedState") as FeedState
	var waited := 0.0
	while remains.eating().is_empty() and waited < 10.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check(not remains.eating().is_empty() and state._reach != null,
		"llega en %.1f s y se pone a comer" % waited)
	# Se coloca con la boca medida en el clip y la lleva al punto con el cuello.
	var worst := 0.0
	for i in 40:
		await get_tree().process_frame
	for i in 60:
		await get_tree().process_frame
		worst = maxf(worst, remains.bite_gap(state, state.mouth_transform().origin))
	check(state._mouth_local != Vector3.INF and worst < 0.1,
		"come con la boca en la carne (fuera %.2f m como mucho)" % worst)
	check(state._anim == &"Idle_Eating" and wolf.get_action_channel().is_playing(),
		"con su clip de comer (%s)" % state._anim)

	# Le arranca el brazo izquierdo y se lo lleva en la boca.
	var dropped := [null]
	remains.dismemberment.limb_dropped.connect(func(_cut: Dictionary, limb: Node3D) -> void: dropped[0] = limb,
		CONNECT_ONE_SHOT)
	remains.set_focus(&"left_arm", true)
	await _wait(0.6)
	var pull := (wolf.global_position - remains.limb_point(&"left_arm", true)).slide(Vector3.UP).normalized()
	check(remains.sever(&"left_arm", true, pull, pull * 0.5, false, state), "le arranca el brazo")
	var frames := 0
	while dropped[0] == null and frames < 300:
		await get_tree().process_frame
		frames += 1
	await _wait(0.4)
	var limb := dropped[0] as SeveredLimb
	var cut_gap := INF
	if limb != null and limb._cut_body != null:
		cut_gap = (limb._cut_body.global_transform * limb._cut_point).distance_to(state.mouth_transform().origin)
	check(limb != null and limb._holding and cut_gap < 0.08,
		"y se lo lleva en la boca por el corte (a %.2f m)" % cut_gap)
	await _wait(PlayerRemains.HOLD_TIME.y + 0.3)
	check(limb != null and not limb._holding and state.is_eating(), "luego lo suelta y sigue comiendo")
	return wolf


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(60, 1, 60)
	body.add_child(shape)
	add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
