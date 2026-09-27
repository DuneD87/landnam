extends "res://tests/lighting/lighting_capture.gd"

## Combate en el juego real (sun.tscn, jugador activo en PLAYING) contra un oso soltado delante.
## Un "bot" juega con entradas simuladas por el mismo camino que el teclado y el ratón
## (InputEventAction → _input del jugador → PlayerCombat), guarda fotogramas en build/combat/ y
## deja un registro de golpes, esquivas, muerte y reaparición.
##   godot --path . res://tests/combat/combat_capture.tscn -- --tag=x [--runs=melee,bow,death]
##
##   melee  espada, objetivo fijado: esquiva rodando los zarpazos y castiga en la recuperación
##   bow    arco: apunta, tensa y dispara al oso que se acerca
##   death  sin defenderse: el oso lo mata, sale "HAS MUERTO" y reaparece con la vida llena

const ItemConfig = preload("res://scripts/config.gd")
const OUT := "res://build/combat"
const SPOT := {"dir": Vector3(0.708411, 0.173648, -0.684105), "yaw": 180.0, "pitch": 0.0}
const FRAME_EVERY := 0.2

var _pc: PlayerController
var _log: Array[String] = []
var _frame := 0
var _next_frame := 0.0
var _clock := 0.0
var _run_name := ""
var _bear: NPCController
var _stats := {}
## Con --showcase los fotogramas salen de una cámara que sigue al jugador de cerca, de tres
## cuartos por delante a su derecha (la del juego sigue mandando en apuntar y moverse).
var _showcase: Camera3D = null


## Ventana discreta con --background: sin foco (no roba el teclado) y fuera de la pantalla,
## para lanzar la prueba mientras se usa el ordenador. Conviene añadir --audio-driver Dummy.
func _enter_tree() -> void:
	if "--background" in OS.get_cmdline_user_args():
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			only = arg.substr(7).split(",")
	_set_sun_elevation(SPOT, TIMES["afternoon"], false)
	await _place(SPOT)
	await _wait_streaming(90.0)
	await _place(SPOT)
	_pc = _player as PlayerController
	GameManager._change_state(GameManager.State.PLAYING)
	var waited := 0.0
	while not _pc.input_enabled and waited < 30.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_pc.camera.current = true
	_camera.current = false
	if "--showcase" in OS.get_cmdline_user_args():
		_showcase = Camera3D.new()
		_showcase.fov = 50
		get_tree().current_scene.add_child(_showcase)
		_showcase.current = true
	_pc.combat.hud.visible = true
	_pc.hotbar.visible = true
	_pc.health_component.invincible = false
	print("player active=%s pos=%s" % [_pc.input_enabled, _pc.global_position])
	await _settle(1.0)
	for run in ["roll", "melee", "bow", "throw", "death", "bowstill"]:
		if not only.is_empty() and run not in only:
			continue
		_run_name = run
		_frame = 0
		while _pc.combat.is_dead() or _pc.combat._respawning:
			await get_tree().create_timer(0.25).timeout
		_pc.health_component.revive()
		_pc.combat.stamina.refill()
		_stats = {"dealt": 0.0, "taken": 0.0, "dodges": 0, "attacks": 0, "hits_on_bear": 0,
			"bear_attacks": 0, "hits_on_player": 0}
		match run:
			"roll":
				await _rolls()
			"melee":
				await _melee()
			"bow":
				await _bow()
			"throw":
				await _throw()
			"death":
				await _death()
			"bowstill":
				await _bow_still()
		print("RUN %s %s" % [run, _stats])
	for line in _log:
		print(line)
	print("COMBAT CAPTURE COMPLETE")


# ---------------------------------------------------------------------------------------------
# Utilidades del bot


func _press(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tap(action: StringName) -> void:
	_press(action, true)
	await get_tree().physics_frame
	_press(action, false)


func _equip(item_id: StringName) -> void:
	var data := ItemConfig.get_item(item_id)
	if _pc.inventory.get_item_count(data) <= 0:
		_pc.inventory.add_item(data, 1)
	_pc._equip_from_hotbar(_pc.equiped_weapon if _pc.right_hand_equipped else null, data)
	await _settle(0.3)


func _spawn_bear(distance: float) -> void:
	for node in get_tree().get_nodes_in_group("npc"):
		if node is NPCController and node.npc_type == &"Bear" and node.get_parent() == get_tree().current_scene:
			node.queue_free()
	await get_tree().process_frame
	var before := get_tree().get_nodes_in_group("npc")
	var msg: String = Console._cmd_spawn(PackedStringArray(["oso", "1", str(distance)]))
	print(msg)
	_bear = null
	for node in get_tree().get_nodes_in_group("npc"):
		if node is NPCController and node not in before and node.npc_type == &"Bear":
			_bear = node
	if _bear != null:
		_bear.health_component.hit_received.connect(func(info, applied):
			_stats.dealt += applied
			_stats.hits_on_bear += 1
			_note("oso encaja %.0f (%s, de %s) → %.0f/%.0f" % [applied, _part(info), info.source.name if info.source else "?", _bear.health_component.health - applied, _bear.health_component.max_health]))
	if not _pc.health_component.hit_received.is_connected(_on_player_hit):
		_pc.health_component.hit_received.connect(_on_player_hit)


func _part(info: DamageInfo) -> String:
	return "cabeza" if info.part_multiplier > 1.0 else "cuerpo"


func _on_player_hit(info: DamageInfo, applied: float) -> void:
	_stats.taken += applied
	_stats.hits_on_player += 1
	_note("jugador encaja %.0f (poise %.0f) → %.0f" % [applied, info.poise, _pc.health_component.health])


func _note(text: String) -> void:
	var line := "[%s %.2fs] %s" % [_run_name, _clock, text]
	_log.append(line)
	print(line)


func _bear_state() -> CreatureMeleeState:
	if _bear == null or not is_instance_valid(_bear):
		return null
	return _bear.ai_controller.get_node_or_null("CombatState") as CreatureMeleeState


## Avanza un tick de física y guarda fotograma cuando toca.
func _tick() -> void:
	await get_tree().physics_frame
	var dt := 1.0 / Engine.physics_ticks_per_second
	_clock += dt
	if _showcase != null:
		var body := _pc.global_transform
		var up := -_pc.gravity_direction.normalized()
		var fwd := body.basis.z.normalized()
		var right := fwd.cross(up).normalized()
		var target := body.origin + up * 1.1
		_showcase.look_at_from_position(target + fwd * 2.2 + right * 2.2 + up * 0.5, target, up)
	if _clock >= _next_frame:
		_next_frame = _clock + (FRAME_EVERY_OVERRIDE if FRAME_EVERY_OVERRIDE > 0.0 else FRAME_EVERY)
		await RenderingServer.frame_post_draw
		var lt := _pc.combat.lock_target
		if lt != null and is_instance_valid(lt) and _frame % 10 == 0:
			var cam := _pc.camera
			print("LOCK %s lock_pt=%s screen=%s bear=%s bear_screen=%s cam=%s current=%s" % [lt.name, _pc.combat._lock_point(lt),
				cam.unproject_position(_pc.combat._lock_point(lt)), _bear.global_position if is_instance_valid(_bear) else Vector3.ZERO,
				cam.unproject_position(_bear.global_position) if is_instance_valid(_bear) else Vector2.ZERO, cam.global_position, cam.current])
		var path := "%s/%s_%s_%03d.png" % [OUT, _tag, _run_name, _frame]
		get_viewport().get_texture().get_image().save_png(path)
		_frame += 1


# ---------------------------------------------------------------------------------------------
# Escenarios


func _melee() -> void:
	await _equip(&"iron_sword")
	await _spawn_bear(11.0)
	if _bear == null:
		_note("no se pudo soltar el oso")
		return
	await _run_for(1.0, Callable())
	await _tap(&"lock_on")
	_note("fijado: %s" % (_pc.combat.lock_target != null))
	var dodged_attack := -1
	var elapsed := 0.0
	var dodge_side := &"move_left"
	var was_attacking := false
	while elapsed < 30.0 and _bear != null and is_instance_valid(_bear) and not _bear.is_dead \
			and not _pc.combat.is_dead():
		var st := _bear_state()
		var dist := _pc.global_position.distance_to(_bear.global_position)
		var attacking := st != null and st._phase == CreatureMeleeState.Phase.ATTACK and not st._attack.is_empty()
		if attacking and not was_attacking:
			_stats.bear_attacks += 1
			_note("oso ataca: %s a %.1f m" % [st._attack.name, dist])
		was_attacking = attacking
		if attacking and st._pre <= 0.0:
			var first := -1.0
			for hit in st._attack.hits:
				if hit.from > st._t:
					first = hit.from
					break
			if first > 0.0 and st._t > first - 0.30 and dodged_attack != int(first * 100):
				dodged_attack = int(first * 100)
				_press(dodge_side, true)
				for i in 3:
					await _tick()
				await _tap(&"dodge")
				_stats.dodges += 1
				_note("esquiva (%s) con el golpe a %.2f s" % [dodge_side, first - st._t])
				for i in 12:
					await _tick()
				_press(dodge_side, false)
				dodge_side = &"move_right" if dodge_side == &"move_left" else &"move_left"
				elapsed += 23.0 / 60.0
				continue
		var opening := st != null and st._phase in [CreatureMeleeState.Phase.RECOVER,
			CreatureMeleeState.Phase.STAGGER, CreatureMeleeState.Phase.CIRCLE, CreatureMeleeState.Phase.ROAR]
		if opening and dist < 2.9 and _pc.combat.state == PlayerCombat.State.IDLE and _pc.combat.stamina.stamina > 30.0:
			await _tap(&"attack_1")
			_stats.attacks += 1
			for i in 40:
				await _tick()
			await _tap(&"attack_1")
			_stats.attacks += 1
		elif opening and dist >= 2.9 and dist < 7.0:
			_press(&"move_forward", true)
			await _tick()
			_press(&"move_forward", false)
		await _tick()
		elapsed += 1.0 / 60.0
	_note("fin melee: oso %s, vida jugador %.0f" % ["muerto" if _bear != null and _bear.is_dead else "vivo", _pc.health_component.health])
	await _run_for(2.0, Callable())


## Volteretas sin enemigos, con capturas seguidas para ver la animación entera.
func _rolls() -> void:
	await _equip(&"iron_sword")
	for dir in [&"move_forward", &"move_left", &"move_right"]:
		_press(dir, true)
		await _run_for(0.4, Callable())
		FRAME_EVERY_OVERRIDE = 0.05
		await _tap(&"dodge")
		await _run_for(0.8, Callable())
		FRAME_EVERY_OVERRIDE = -1.0
		_press(dir, false)
		await _run_for(0.6, Callable())
		_note("voltereta %s: estado %s" % [dir, PlayerCombat.State.keys()[_pc.combat.state]])
	# Paso atrás: esquivar sin moverse.
	FRAME_EVERY_OVERRIDE = 0.05
	await _tap(&"dodge")
	await _run_for(0.7, Callable())
	FRAME_EVERY_OVERRIDE = -1.0
	_note("paso atrás: estado %s" % PlayerCombat.State.keys()[_pc.combat.state])


var FRAME_EVERY_OVERRIDE := -1.0


func _bow() -> void:
	_pc.health_component.revive()
	await _equip(&"hunting_bow")
	await _spawn_bear(15.0)
	if _bear == null:
		return
	# Que no se venga encima antes de probar: sordo y ciego un momento no, que ataque normal.
	await _run_for(0.5, Callable())
	if _pc.combat.lock_target == null:
		await _tap(&"lock_on")
	_note("fijado para disparar: %s" % (_pc.combat.lock_target != null))
	for shot in 4:
		# Los dos primeros sin apuntar fino (al objetivo fijado); los otros, apuntando.
		if shot >= 2:
			_press(&"attack_2", true)
		for i in 20:
			await _tick()
		_press(&"attack_1", true)
		for i in 70:
			await _tick()
		var before := _bear.health_component.health
		_press(&"attack_1", false)
		for i in 30:
			await _tick()
		_press(&"attack_2", false)
		_note("flecha %d: oso %.0f → %.0f, flechas quedan %d" % [shot, before, _bear.health_component.health, _pc.combat.ammo_count()])
		if _bear.is_dead:
			break
		for i in 10:
			await _tick()
	_bear.health_component.invincible = true
	await _run_for(1.0, Callable())


## Lanza: fija al oso, apunta, carga y suelta; comprueba el acierto y que empuña la siguiente.
func _throw() -> void:
	_pc.health_component.revive()
	await _equip(&"spear")
	await _spawn_bear(12.0)
	if _bear == null:
		return
	await _run_for(0.5, Callable())
	if _pc.combat.lock_target == null:
		await _tap(&"lock_on")
	for shot in 2:
		var before := _bear.health_component.health
		var spears := _pc.inventory.get_item_count(ItemConfig.get_item(&"spear"))
		_press(&"attack_2", true)
		for i in 15:
			await _tick()
		_press(&"attack_1", true)
		for i in 45:
			await _tick()
		_press(&"attack_1", false)
		for i in 50:
			await _tick()
		_press(&"attack_2", false)
		for i in 20:
			await _tick()
		_note("lanza %d: oso %.0f → %.0f, lanzas en inventario %d → %d, en mano: %s" % [shot, before,
			_bear.health_component.health, spears, _pc.inventory.get_item_count(ItemConfig.get_item(&"spear")),
			_pc.equiped_weapon.id if _pc.right_hand_equipped else "nada"])
	_bear.health_component.invincible = true
	await _run_for(1.0, Callable())


func _death() -> void:
	_pc.health_component.revive()
	var start := _pc.global_position
	await _equip(&"iron_mace")
	await _spawn_bear(7.0)
	var elapsed := 0.0
	while not _pc.combat.is_dead() and elapsed < 40.0:
		await _tick()
		elapsed += 1.0 / 60.0
	_note("muerto=%s tras %.1f s" % [_pc.combat.is_dead(), elapsed])
	var died_at := _pc.global_position
	elapsed = 0.0
	var next_log := 0.0
	while (_pc.combat.is_dead() or _pc.combat._respawning) and elapsed < 30.0:
		await _tick()
		elapsed += 1.0 / 60.0
		var rag := _pc.combat.ragdoll
		if rag.is_running() and elapsed >= next_log:
			next_log += 0.5
			var hips: RigidBody3D = rag.get_node_or_null("RagdollBodies/Hips")
			if hips:
				var up := -_pc.gravity_direction.normalized()
				var rel := hips.global_position - _pc.global_position
				_note("muñeco: cadera a %.2f m del cuerpo (altura %.2f), vel %.2f" % [rel.length(), rel.dot(up), hips.linear_velocity.length()])
	await _run_for(1.5, Callable())
	_note("reaparece: vida %.0f/%.0f, aguante %.0f, a %.1f m de donde murió, input=%s" % [
		_pc.health_component.health, _pc.health_component.max_health, _pc.combat.stamina.stamina,
		_pc.global_position.distance_to(died_at), _pc.input_enabled])
	if _bear != null and is_instance_valid(_bear):
		_note("oso tras reaparecer: objetivo=%s estado=%s" % [_bear.ai_controller.target, _bear.ai_controller.get_current_state()])


## Arco sin enemigos, quieto: apunta, tensa y sostiene. Registra en cada fotograma (dentro del
## modificador, que es cuando la pose es la de verdad) cuánto se mueven de un fotograma a otro
## la cabeza, las manos y el cuerpo, para ver temblores.
func _bow_still() -> void:
	await _equip(&"hunting_bow")
	await _run_for(0.5, Callable())
	var combat := _pc.combat
	var original: Callable = combat.pose.after_pose
	var samples: Array = []
	combat.pose.after_pose = func(p: CombatPose) -> void:
		original.call(p)
		var base := _pc.global_transform
		samples.append({"t": _clock, "head": base.affine_inverse() * p.bone_world("mixamorig_Head"),
			"lhand": base.affine_inverse() * p.bone_world("mixamorig_LeftHand"),
			"rhand": base.affine_inverse() * p.bone_world("mixamorig_RightHand"),
			"hips": base.affine_inverse() * p.bone_world("mixamorig_Hips"),
			"pos": _pc.global_position, "yaw": combat._stance_yaw,
			"aim": combat._aim_dir, "state": combat.state, "draw": combat._draw, "phase": combat._bow_phase})
	FRAME_EVERY_OVERRIDE = 1.0 / 30.0
	_press(&"attack_2", true)
	await _run_for(1.5, Callable())
	var up := -_pc.gravity_direction.normalized()
	var hv := _pc.velocity - up * _pc.velocity.dot(up)
	_note("postura: en suelo=%s pendiente=%.1f° vel horizontal=%.2f m/s giro=%.1f" % [_pc.is_on_floor(),
		rad_to_deg(_pc.get_floor_normal().angle_to(up)), hv.length(), combat._stance_yaw])
	_press(&"attack_1", true)
	await _run_for(3.0, Callable())
	_press(&"attack_1", false)
	await _run_for(1.0, Callable())
	_press(&"attack_2", false)
	FRAME_EVERY_OVERRIDE = -1.0
	combat.pose.after_pose = original
	await _run_for(0.5, Callable())
	# Temblor: diferencia de cada punto respecto a la media de sus vecinos (quita el movimiento
	# suave y deja el ruido de alta frecuencia), en mm, por tramos de medio segundo.
	var keys := ["head", "lhand", "rhand", "hips"]
	var t0: float = samples[0].t if not samples.is_empty() else 0.0
	var bucket := {}
	for i in range(1, samples.size() - 1):
		var s: Dictionary = samples[i]
		var slot := int((s.t - t0) / 0.5)
		if not bucket.has(slot):
			bucket[slot] = {"n": 0, "phase": s.phase, "draw": s.draw, "yaw": s.yaw}
			for k in keys:
				bucket[slot][k] = 0.0
		bucket[slot].n += 1
		for k in keys:
			var mid: Vector3 = (samples[i - 1][k] + samples[i + 1][k]) * 0.5
			bucket[slot][k] = maxf(bucket[slot][k], (s[k] as Vector3).distance_to(mid) * 1000.0)
	for slot in bucket:
		var b: Dictionary = bucket[slot]
		_note("t=%.1f fase=%s tensión=%.2f giro=%.1f | ruido máx (mm) cabeza %.1f  mano izq %.1f  mano der %.1f  cadera %.1f  (%d fot.)" % [
			slot * 0.5, b.phase, b.draw, b.yaw, b.head, b.lhand, b.rhand, b.hips, b.n])
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i]
		var da := rad_to_deg((a.aim as Vector3).angle_to(samples[i - 1].aim))
		var dp := (a.pos as Vector3).distance_to(samples[i - 1].pos) * 1000.0
		if a.t - t0 > 2.7 and a.t - t0 < 3.5:
			print("  f t=%.3f cabeza %s  mano_izq %s  mano_der %s  cadera %s" % [a.t - t0, (a.head as Vector3).snapped(Vector3.ONE * 0.001), (a.lhand as Vector3).snapped(Vector3.ONE * 0.001), (a.rhand as Vector3).snapped(Vector3.ONE * 0.001), (a.hips as Vector3).snapped(Vector3.ONE * 0.001)])
		if da > 2.0 or dp > 5.0:
			var cam := _pc.camera
			print("  salto t=%.3f dir %.1f° cuerpo %.1f mm fase %s aim=%s punto=%s" % [a.t - t0, da, dp, a.phase, a.aim, combat._aim_point])
	var moved := 0.0
	var aim_jit := 0.0
	for i in range(1, samples.size()):
		moved = maxf(moved, (samples[i].pos as Vector3).distance_to(samples[i - 1].pos) * 1000.0)
		aim_jit = maxf(aim_jit, rad_to_deg((samples[i].aim as Vector3).angle_to(samples[i - 1].aim)))
	_note("cuerpo: salto máx entre fotogramas %.1f mm; dirección de tiro: salto máx %.2f°" % [moved, aim_jit])


func _run_for(seconds: float, _each: Callable) -> void:
	var t := 0.0
	while t < seconds:
		await _tick()
		t += 1.0 / 60.0
