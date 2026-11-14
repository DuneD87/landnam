extends Node3D

## godot --headless --path . res://tests/building/test_rowing_benches.tscn
## Regresión con las colisiones y seis bancadas del barco de la partida, sin modificar el guardado.
var failures := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/building/fixtures/rowing_hull.json"))
	await _check_saved_hull(fixture)
	_check_seating(fixture)
	await get_tree().process_frame
	print("ROWING BENCHES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _check_saved_hull(fixture: Dictionary) -> void:
	var body := DynamicGridBody.new()
	body.freeze = true
	body.movement_type = DynamicGridBody.MovementType.BOAT
	for box: Array in fixture["boxes"]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(box[3], box[4], box[5]) * 2.0
		col.shape = shape
		col.position = Vector3(box[0], box[1], box[2])
		body.add_child(col)
	add_child(body)
	body.set_physics_process(false)
	body._is_being_controlled = true
	body.sailing.set_gear(1)
	var benches: Array[RowingBench] = []
	for data: Dictionary in fixture["benches"]:
		var bench := RowingBench.new()
		body.add_child(bench)
		bench.restore_save_data(data)
		bench.occupant = bench
		bench.seated = true
		benches.append(bench)
		var station := bench.oar_station()
		check(not station.is_empty(), "la bancada guardada en %s queda en el área de remo" % bench.position)
		if station.is_empty():
			continue
		var seat := bench.transform * RowingBench.SEAT
		var side: float = -1.0 if seat.x < 3.5 else 1.0
		check(station["side"] == side and absf((station["pivot"] as Vector3).x - seat.x) < station["inboard"],
			"remo en el costado cercano y mango hasta el remero")
	body._update_oars()
	check(body.sailing.rowers == 6 and body.oars() != null and body.oars().direction == 1,
		"las seis bancadas guardadas cuentan como remeros y activan sus remos")
	await _check_grip(body, benches, &"female")
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body.global_transform = Transform3D(Basis.from_euler(Vector3(0.08, 0.7, -0.06)), Vector3(50, 10, -30))
	body.reset_physics_interpolation()
	await get_tree().process_frame
	await _check_grip(body, benches, &"male")
	var previous := benches[0].position
	benches[0].position.z += 0.1
	body._update_oars()
	var drawn := body.oars()._oars[0]["node"] as Node3D
	check(drawn.transform.is_equal_approx(BoatOars.station_pose(benches[0].oar_station(), body.oars().phase())),
		"al mover una bancada se actualiza el remo aunque conserve remero y casco")
	benches[0].position = previous
	check(body.oar_station_at(Vector3(3.5, 3.54, 16.0)).is_empty(), "el centro de cubierta queda fuera del área")
	check(body.oar_station_at(Vector3(1.5, 3.54, 40.0)).is_empty(), "fuera de la eslora no se activa un remo")
	# Borde exacto e inmediatamente fuera, con una borda recta de referencia.
	var boxes := PackedVector3Array([Vector3.ZERO])
	var halves := PackedVector3Array([Vector3(4.0, 0.5, 10.0)])
	check(not BoatOars.station_at(Vector3(4.0 - BoatOars.ROW_REACH, 1.0, 0.0), boxes, halves).is_empty()
		and BoatOars.station_at(Vector3(4.0 - BoatOars.ROW_REACH - 0.01, 1.0, 0.0), boxes, halves).is_empty(),
		"el umbral incluye 2,4 m y excluye lo que queda más adentro")
	for bench in benches:
		bench.seated = false
	body._update_oars()
	check(body.sailing.rowers == 0 and not body.oars().visible, "las sillas vacías no aportan remos")
	body.queue_free()


func _check_grip(body: DynamicGridBody, benches: Array[RowingBench], sex: StringName) -> void:
	var terrain := Node3D.new()
	add_child(terrain)
	terrain.position.y = -10000.0
	var player := Node3D.new()
	add_child(player)
	var c := Companion.new()
	var who := {"id": "grip_test", "name": "Remero", "sex": sex, "look": 103 if sex == &"female" else 102}
	c.setup(who, 0, "Prueba", null, Villager.build_model(who, []), terrain, player, Vector3.ZERO)
	add_child(c)
	c.set_physics_process(false)
	body.oars().set_process(false)
	var measurements := (c._model.get_node("AppearanceRig") as CharacterAppearanceRig).measurements()
	for bench in benches:
		bench.occupant = null
		c.board(bench)
		c._sit(false)
		var errors := {"max": 0.0, "samples": 0, "clearance": INF, "hips": 0.0, "back": {}}
		var sample := func() -> void:
			var p := c._rowing_pose
			var station := bench.oar_station()
			var phase := body.oars().phase()
			var frame := body.get_global_transform_interpolated()
			var axis := (frame.basis * BoatOars.station_pose(station, phase).basis.y).normalized()
			var center := frame * BoatOars.grip_at(station, phase)
			var hips := p.bone_world(HumanRig.HIPS)
			errors["hips"] = maxf(errors["hips"], hips.distance_to(bench.get_global_transform_interpolated() * RowingBench.SEAT))
			var local_grip := c.global_transform.affine_inverse() * center
			var shoulders := (p.bone_world(HumanRig.LEFT_ARM) + p.bone_world(HumanRig.RIGHT_ARM)) * 0.5
			errors["back"][phase] = Vector2(local_grip.z, (c.global_transform.affine_inverse() * shoulders).z)
			var chest_base := p.bone_world(HumanRig.SPINE)
			var neck := p.bone_world(HumanRig.NECK)
			var chest_up := (neck - chest_base).normalized()
			var chest_left := (p.bone_world(HumanRig.LEFT_ARM) - p.bone_world(HumanRig.RIGHT_ARM)).normalized()
			var chest_forward := chest_left.cross(chest_up).normalized()
			var chest := (neck + chest_base) * 0.5
			# Costillas como elipsoide con las medidas del cuerpo, más el grosor del brazo.
			var radii := Vector3(float(measurements.summary[&"chest_width"]) * 0.5 + 0.025,
				neck.distance_to(chest_base) * 0.55, float(measurements.summary[&"chest_depth"]) * 0.5 + 0.025)
			for side in ["Left", "Right"]:
				var arm := [p.bone_world("mixamorig_%sArm" % side), p.bone_world("mixamorig_%sForeArm" % side),
					p.bone_world("mixamorig_%sHand" % side)]
				for segment in 2:
					for step in range(1, 10):
						var point: Vector3 = (arm[segment] as Vector3).lerp(arm[segment + 1], step / 10.0) - chest
						var unit_point := Vector3(point.dot(chest_left), point.dot(chest_up), point.dot(chest_forward)) / radii
						errors["clearance"] = minf(errors["clearance"], unit_point.length())
				var hand := p.hand_frame(side)
				var actual := p.to_world_point(p.bone_pos("mixamorig_%sHand" % side)
					+ (hand.x * CombatPose.FIST_HANDLE.x + hand.y * CombatPose.FIST_HANDLE.y) * p.unit())
				var along := signf(axis.dot(c.global_basis.x)) * (1.0 if side == "Left" else -1.0)
				var target := center + axis * along * BoatOars.HAND_SPACING * 0.5
				errors["max"] = maxf(errors["max"], actual.distance_to(target))
				errors["samples"] += 1
		c._rowing_pose.modification_processed.connect(sample)
		for step in 16:
			var phase := step / 16.0
			body.oars()._phase = phase
			body.oars()._pose()
			c._process(0.0)
			await get_tree().process_frame
			await get_tree().process_frame
		check(errors["samples"] >= 8 and errors["max"] < 0.04,
			"ambas manos siguen el mango durante toda la palada (error %.3f m)" % errors["max"])
		check(errors["clearance"] > 1.0,
			"brazos y antebrazos quedan fuera de las costillas (margen %.3f)" % errors["clearance"])
		check(errors["hips"] < 0.01, "la espalda se mueve con las caderas apoyadas en la bancada")
		var closest := Vector2(INF, 0.0)
		var farthest := Vector2(-INF, 0.0)
		for point: Vector2 in errors["back"].values():
			if point.x < closest.x:
				closest = point
			if point.x > farthest.x:
				farthest = point
		check(farthest.y - closest.y > 0.06,
			"la espalda avanza al alargar los brazos y se recoge al tirar (%.3f m)" % (farthest.y - closest.y))
		var station := bench.oar_station()
		var seat := bench.transform * RowingBench.SEAT
		var rest := BoatOars.grip_at(station, BoatOars.REST_PHASE)
		check(absf(rest.y - seat.y - BoatOars.HOLD_HEIGHT) < 0.001
			and (rest - seat).slide(Vector3.UP).length() < 0.4,
			"el mango descansa delante del cuerpo y por debajo de los hombros")
		c._rowing_pose.modification_processed.disconnect(sample)
		c.stand_up()
		check(not c._rowing_pose.active and c._rowing_pose.bench == null, "al levantarse suelta el remo")
		bench.occupant = bench
		bench.seated = true
	c.queue_free()
	terrain.queue_free()
	player.queue_free()


func _check_seating(fixture: Dictionary) -> void:
	var terrain := Node3D.new()
	add_child(terrain)
	terrain.position = Vector3(0.0, -10000.0, 0.0)
	var player := Node3D.new()
	add_child(player)
	var who := {"id": "rowing_test", "name": "Remero", "sex": &"male", "look": 102}
	var c := Companion.new()
	c.setup(who, 0, "Prueba", null, Villager.build_model(who, []), terrain, player, Vector3.ZERO)
	add_child(c)
	c.set_physics_process(false)
	for data: Dictionary in fixture["benches"]:
		var bench := RowingBench.new()
		add_child(bench)
		# El mismo camino que al cargar; conserva cada rotación de la partida.
		bench.restore_save_data(data)
		c.sit_on_load(bench.entity_id)
		check(c._shape.disabled, "esperando su bancada al cargar no choca (lanzaría el casco)")
		c._find_pending_bench(0.0)
		check(c.is_seated() and c.global_basis.z.dot(-bench.global_basis.z) > 0.99,
			"al cargar se sienta mirando al -Z de la bancada")
		check((c.global_transform * c._hips_in_body()).distance_to(bench.global_transform * RowingBench.SEAT) < 0.01,
			"las caderas siguen en el asiento tras invertir la orientación")
		c.stand_up()
		check(not c._shape.disabled, "de pie vuelve a chocar")
		check(c.global_position.distance_to(bench.global_transform * RowingBench.STAND) < 0.01
			and c._forward.dot(-bench.global_basis.z) > 0.99,
			"se levanta por delante y mantiene esa orientación")
		bench.queue_free()
	c.sit_on_load("bancada_que_no_existe")
	c.stand_up()
	check(not c._shape.disabled, "si deja de esperar una bancada vuelve a chocar")
	c.queue_free()
	terrain.queue_free()
	player.queue_free()
